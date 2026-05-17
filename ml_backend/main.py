import logging
import datetime
from fastapi import FastAPI, HTTPException, Request, Depends
from models.request_models import FeedbackRequest, OptimizationRequest, SyncRequest, DisaggregationRequest
from services.firebase_client import FirebaseClient
from services.simulator import AdaptiveBehavioralSimulator
from services.optimizer import EnergyOptimizer
from services.fhmm_service import FHMMService
from utils.response_formatter import format_api_response
from utils.auth import verify_firebase_token, validate_user_ownership
import traceback

# Initialize logging for backend observability.
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="SmartMeter ML Backend")

# Service singleton instances for pipeline orchestration.
db = FirebaseClient()
simulator = AdaptiveBehavioralSimulator()
optimizer = EnergyOptimizer()
fhmm = FHMMService()

# Global exception handler for consistent error reporting across all endpoints.
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled Global Error: {str(exc)}", exc_info=True)
    return format_api_response(False, message="An internal server error occurred.")

@app.get("/")
async def root():
    # Service availability check for root path resolution.
    return {"status": "online", "message": "ML Backend Active"}

@app.post("/api/v1/optimize")
async def run_optimization(request: OptimizationRequest, token: dict = Depends(verify_firebase_token)):
    # Calibrates behavioral weights against ground-truth bill values.
    try:
        validate_user_ownership(request.user_id, token["uid"])
        logger.info(f"Optimizing weights for user: {request.user_id}")
        appliances = db.get_user_appliances(request.user_id)
        if not appliances:
            raise ValueError("No active appliances found for user.")
            
        new_weights = optimizer.refine(appliances, request.actual_bill)
        
        # Developer Expectation: Update Firestore with optimized prob_day/prob_night values.
        db.update_appliance_weights(request.user_id, appliances, new_weights)
        return format_api_response(True, message="Weights optimized successfully")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Optimization failed: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to optimize energy weights.")

@app.post("/api/v1/disaggregate")
async def process_telemetry(request: DisaggregationRequest, token: dict = Depends(verify_firebase_token)):
    # Executes disaggregation pipeline and persists results to Firestore.
    try:
        validate_user_ownership(request.user_id, token["uid"])
        user_id = request.user_id
        logger.info(f"Running disaggregation for user: {user_id}")
        
        # Validation for user appliance data existence in Firestore.
        registered_appliances = db.get_user_appliances(user_id) 
        if not registered_appliances:
            logger.warning(f"Aborting: No active appliances for user {user_id}")
            return format_api_response(False, message="No active appliances found. Add appliances to proceed.")

        # TODO: Replace static context with dynamic data (Weather API/System Clock) for production.
        # This is currently a testing placeholder to ensure simulator stability.
        context = {
            "temperature": 28,
            "is_weekend": False,
            "poll_iron_used_today": False
        }
        
        simulation_results = simulator.run_monte_carlo(registered_appliances, context)
        
        # Guard clause for simulator dictionary key integrity to prevent KeyError.
        if 'hourly_profile' not in simulation_results or 'appliance_totals' not in simulation_results:
            logger.error(f"Simulator output missing keys for {user_id}: {simulation_results}")
            raise KeyError("Simulator failed to return 'hourly_profile' or 'appliance_totals'.")
        
        safe_hourly_usage = {str(k): float(v) for k, v in simulation_results['hourly_profile'].items()}
        dynamic_breakdown = {name: float(val) for name, val in simulation_results['appliance_totals'].items()}

        now = datetime.datetime.now(datetime.timezone.utc)
        payload = {
            "userId": user_id, 
            "month": now.month,
            "year": now.year,
            "estimated_load": sum(dynamic_breakdown.values()),
            "breakdown": dynamic_breakdown,
            "recommendations": generate_recommendations(dynamic_breakdown),
            "hourlyUsage": safe_hourly_usage,
            "timestamp": now 
        }
        
        db.save_disaggregation_result(payload)
        return format_api_response(True, data=payload)
    except Exception as e:
        logger.error(f"Disaggregation failed for user {request.user_id}: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500, 
            detail="An internal error occurred during disaggregation."
        )

@app.post("/api/v1/sync-daily")
async def sync_daily_usage(request: SyncRequest, token: dict = Depends(verify_firebase_token)):
    # Generates and persists high-fidelity 24-hour time-series data.
    try:
        validate_user_ownership(request.user_id, token["uid"])
        appliances = db.get_user_appliances(request.user_id)
        results = simulator.run_monte_carlo(appliances, request.context)
        
        # Persists to the daily_usage subcollection for frontend charting.
        db.save_daily_usage(request.user_id, results['hourly_profile'])
        return format_api_response(True, message="Daily sync complete")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

def generate_recommendations(breakdown: dict) -> list:
    # Generates advice by comparing appliance usage against thresholds.
    advice = []
    total = sum(breakdown.values())
    if total == 0: return ["No usage detected."]
    
    for app, val in breakdown.items():
        percentage = (val / total) * 100
        if percentage > 40:
            advice.append(f"High Consumption: {app} accounts for {percentage:.1f}% of usage.")
            
    if not advice:
        advice.append("Usage patterns are within optimal ranges.")
    return advice

@app.post("/api/v1/feedback")
async def handle_feedback(request: FeedbackRequest, token: dict = Depends(verify_firebase_token)):
    # Processes corrections and applies reinforcement learning adjustments.
    try:
        validate_user_ownership(request.user_id, token["uid"])
        db.log_feedback(request)
        user_apps = db.get_user_appliances(request.user_id)
        app_data = user_apps.get(request.appliance_name)

        if not app_data:
            return {"status": "error", "message": f"Appliance '{request.appliance_name}' not found."}

        is_false_positive = (request.predicted_state and not request.actual_state)
        learning_rate = 0.05
        current_p = app_data.get('prob_day', 0.5)
        
        new_p = max(0.01, current_p - learning_rate) if is_false_positive else min(0.99, current_p + learning_rate)
        db.update_single_appliance_prob(request.user_id, request.appliance_name, new_p)

        return {"status": "success", "new_probability": new_p}
    except Exception as e:
        return {"status": "error", "message": str(e)}