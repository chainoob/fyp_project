import logging
import datetime
from fastapi import FastAPI, HTTPException, Request
from models.request_model import FeedbackRequest, OptimizationRequest, SyncRequest, DisaggregationRequest
from services.firebase_client import FirebaseClient
from services.simulator import AdaptiveBehavioralSimulator
from services.optimizer import EnergyOptimizer
from services.fhmm_service import FHMMService
from utils.response_formatter import format_api_response

# Initialize logging for backend observability.
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="SmartMeter ML Backend")

# High-level: Service singleton instances for pipeline orchestration.
db = FirebaseClient()
simulator = AdaptiveBehavioralSimulator()
optimizer = EnergyOptimizer()
fhmm = FHMMService()

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled Global Error: {str(exc)}", exc_info=True)
    return format_api_response(False, message="An internal server error occurred.")

@app.post("/api/v1/optimize")
async def run_optimization(request: OptimizationRequest):
    # Calibrates behavioral weights against ground-truth bill values.
    try:
        logger.info(f"Optimizing weights for user: {request.user_id}")
        appliances = db.get_user_appliances(request.user_id)
        if not appliances:
            raise ValueError("No active appliances found for user.")
            
        new_weights = optimizer.refine(appliances, request.actual_bill)
        
        # Expected: Update Firestore with optimized prob_day/prob_night values.
        db.update_appliance_weights(request.user_id, appliances, new_weights)
        return format_api_response(True, message="Weights optimized successfully")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Optimization failed: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to optimize energy weights.")

@app.post("/api/v1/disaggregate")
async def process_telemetry(request: DisaggregationRequest):
    # Executes simulation and derives appliance breakdown from results.
    try:
        user_id = request.user_id # Corrected attribute access
        logger.info(f"Running disaggregation for user: {user_id}")
        
        registered_appliances = db.get_user_appliances(user_id) 
        
        # Injected default context if missing in request to ensure simulation stability.
        context = {
            "temperature": 28,
            "is_weekend": False,
            "poll_iron_used_today": False
        }
        
        # Returns structured simulation data containing hourly load and appliance-specific totals.
        simulation_results = simulator.run_monte_carlo(registered_appliances, context)
        
        # Map simulator output to Firestore-compatible string keys.
        safe_hourly_usage = {str(k): float(v) for k, v in simulation_results['hourly_profile'].items()}
        dynamic_breakdown = {name: float(val) for name, val in simulation_results['appliance_totals'].items()}

        now = datetime.datetime.now(datetime.timezone.utc)
        parsed_year, parsed_month = now.year, now.month

        payload = {
            "userId": user_id, 
            "month": parsed_month,
            "year": parsed_year,
            "estimated_load": sum(dynamic_breakdown.values()),
            "breakdown": dynamic_breakdown,
            "recommendations": generate_recommendations(dynamic_breakdown),
            "hourlyUsage": safe_hourly_usage,
            "timestamp": datetime.datetime.now(datetime.timezone.utc) 
        }
        
        db.save_disaggregation_result(payload)
        return format_api_response(True, data=payload)
    except Exception as e:
        logger.error(f"Disaggregation failed: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal disaggregation error.")

@app.post("/api/v1/sync-daily")
async def sync_daily_usage(request: SyncRequest):
    # Expected: Generate and persist high-fidelity 24-hour time-series data.
    try:
        appliances = db.get_user_appliances(request.user_id)
        results = simulator.run_monte_carlo(appliances, request.context)
        
        # Persists to the daily_usage subcollection for frontend charting.
        db.save_daily_usage(request.user_id, results['hourly_profile'])
        return format_api_response(True, message="Daily sync complete")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

def generate_recommendations(breakdown: dict) -> list:
    # Generates advice by comparing appliance usage against dynamic thresholds.
    advice = []
    total = sum(breakdown.values())
    if total == 0: return ["No usage detected."]
    
    for app, val in breakdown.items():
        percentage = (val / total) * 100
        if percentage > 40:
            advice.append(f"High Consumption: {app} accounts for {percentage:.1f}% of usage. Check efficiency settings.")
            
    if not advice:
        advice.append("Usage patterns are within optimal ranges.")
    return advice

@app.post("/api/v1/feedback")
async def handle_feedback(request: FeedbackRequest):
    # High-level: Processes corrections and applies a reinforcement learning nudge.
    try:
        # 1. Record the event for future training sessions.
        db.log_feedback(request)

        # 2. Get current state to calculate the adjustment.
        user_apps = db.get_user_appliances(request.user_id)
        app_data = user_apps.get(request.appliance_name)

        if app_data:
            # 3. Calculate the new probability based on the error.
            # If AI guessed 'ON' (True) but student was 'OFF' (False), it's a False Positive.
            is_false_positive = (request.predicted_state and not request.actual_state)
            
            # Developer Expectation: Use a 5% shift as the default learning rate.
            learning_rate = 0.05
            current_p = app_data.get('prob_day', 0.5)
            
            if is_false_positive:
                new_p = max(0.01, current_p - learning_rate)
            else:
                new_p = min(0.99, current_p + learning_rate)

            db.update_single_appliance_prob(request.user_id, request.appliance_name, new_p)

        return {"status": "success", "new_probability": new_p}
    except Exception as e:
        return {"status": "error", "message": str(e)}