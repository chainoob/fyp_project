import logging
import datetime
import os
from fastapi import FastAPI, HTTPException, Request, Depends
from models.request_models import FeedbackRequest, OptimizationRequest, SyncRequest, DisaggregationRequest, BatchDisaggregationRequest
from services.firebase_client import FirebaseClient
from services.simulator import AdaptiveBehavioralSimulator
from services.optimizer import EnergyOptimizer
from services.fhmm_service import FHMMService
from services.weather_service import WeatherService
from utils.response_formatter import format_api_response
from utils.auth import verify_firebase_token, validate_user_ownership
from utils.math_helper import calculate_malaysian_tariff_a, calculate_carbon_footprint

# Initialize logging for backend observability.
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="SmartMeter ML Backend")

# Service singleton instances for pipeline orchestration.
db = FirebaseClient()
simulator = AdaptiveBehavioralSimulator()
optimizer = EnergyOptimizer()
fhmm = FHMMService()
weather = WeatherService()

# Global exception handler for consistent error reporting across all endpoints.
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled Global Error: {str(exc)}", exc_info=True)
    return format_api_response(False, message="An internal server error occurred.")

@app.get("/")
async def root():
    # Service availability check for root path resolution.
    return {"status": "online", "message": "ML Backend Active"}

@app.get("/api/v1/health")
async def health_check():
    # Diagnostic endpoint to verify secret resolution and service status.
    weather_key_resolved = bool(weather.api_key)
    
    return {
        "status": "healthy",
        "timestamp": datetime.datetime.now(datetime.timezone.utc),
        "integrations": {
            "weather_api": {
                "status": "connected" if weather_key_resolved else "missing_key",
                "source": getattr(weather, 'secret_source', 'none')
            },
            "firebase": {
                "status": "initialized" if db.db else "error",
                "source": getattr(db, 'credential_source', 'none')
            }
        },
        "environment": "production" if os.getenv("K_SERVICE") else "development"
    }

@app.post("/api/v1/optimize")
async def run_optimization(request: OptimizationRequest, token: dict = Depends(verify_firebase_token)):
    # Calibrates behavioral weights against ground-truth bill values.
    try:
        is_staff = db.get_user_role(token["uid"]) == 'staff'
        validate_user_ownership(request.user_id, token["uid"], is_staff=is_staff)
        logger.info(f"Optimizing weights for user: {request.user_id}")
        appliances = db.get_user_appliances(request.user_id)
        if not appliances:
            raise ValueError("No active appliances found for user.")
            
        new_weights = optimizer.refine(appliances, request.actual_bill)
        
        # Sync optimized weights (prob_day/prob_night) to user Firestore document.
        db.update_appliance_weights(request.user_id, appliances, new_weights)
        return format_api_response(True, message="Weights optimized successfully")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Optimization failed: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to optimize energy weights.")

@app.post("/api/v1/disaggregate")
async def process_telemetry(request: DisaggregationRequest, token: dict = Depends(verify_firebase_token)):
    # Run disaggregation pipeline and persist results.
    try:
        is_staff = db.get_user_role(token["uid"]) == 'staff'
        validate_user_ownership(request.user_id, token["uid"], is_staff=is_staff)
        user_id = request.user_id
        logger.info(f"Running disaggregation for user: {user_id}")
        
        # Verify appliance registry exists for the target UID.
        registered_appliances = db.get_user_appliances(user_id) 
        if not registered_appliances:
            logger.warning(f"Aborting: No active appliances for user {user_id}")
            return format_api_response(False, message="No active appliances found. Add appliances to proceed.")

        # Resolve environmental context via Weather API.
        context = weather.get_contextual_data()
        context["is_weekend"] = datetime.datetime.now().weekday() >= 5
        context["poll_iron_used_today"] = False
        
        # NILM Hybrid Logic: FHMM signal decoding + Monte Carlo behavioral benchmarking.
        fhmm_results = fhmm.disaggregate(request.aggregate_readings)
        simulation_results = simulator.run_monte_carlo(registered_appliances, context)
        
        # Validate simulation output integrity before payload construction.
        if 'hourly_profile' not in simulation_results or 'appliance_totals' not in simulation_results:
            logger.error(f"Simulator output missing keys for {user_id}: {simulation_results}")
            raise KeyError("Simulator failed to return 'hourly_profile' or 'appliance_totals'.")

        # Map FHMM traces to registered appliance types.
        registered_types = {app['type'] for app in registered_appliances.values()}
        fhmm_breakdown = {
            name: round(sum(power_series) / 1000.0, 3) 
            for name, power_series in fhmm_results.items()
            if name in registered_types
        }

        # Detect high-load unregistered signatures (>500W).
        anomalies = [
            name for name, power_series in fhmm_results.items()
            if name not in registered_types and sum(power_series) > 500 
        ]
        
        # Trigger real-time alerts for anomalies.
        if anomalies:
            db.send_fcm_notification(
                user_id, 
                "High-Load Anomaly Detected", 
                f"We detected an unregistered high-load appliance: {', '.join(anomalies)}. Please register it for safety compliance."
            )

        safe_hourly_usage = {str(k): float(v) for k, v in simulation_results['hourly_profile'].items()}
        estimated_load = sum(fhmm_breakdown.values())

        # Trigger budget threshold alerts.
        user_data = db.get_user_data(user_id)
        if user_data:
            energy_goal = user_data.get('energyGoal', 0)
            if energy_goal > 0 and estimated_load > energy_goal:
                db.send_fcm_notification(
                    user_id,
                    "Energy Budget Exceeded",
                    f"Your monthly consumption ({estimated_load:.2f} kWh) has exceeded your goal of {energy_goal} kWh."
                )

        now = datetime.datetime.now(datetime.timezone.utc)
        payload = {
            "userId": user_id, 
            "month": now.month,
            "year": now.year,
            "estimated_load": estimated_load,
            "estimated_cost": calculate_malaysian_tariff_a(estimated_load),
            "carbon_footprint": calculate_carbon_footprint(estimated_load),
            "breakdown": fhmm_breakdown,
            "benchmark_breakdown": simulation_results['appliance_totals'],
            "anomalies": anomalies,
            "recommendations": generate_recommendations(fhmm_breakdown),
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

@app.post("/api/v1/trigger-disaggregation")
async def trigger_batch_disaggregation(request: BatchDisaggregationRequest, token: dict = Depends(verify_firebase_token)):
    try:
        staff_uid = token["uid"]
        user_id = request.user_id
        is_staff = db.get_user_role(staff_uid) == 'staff'
        
        validate_user_ownership(user_id, staff_uid, is_staff=is_staff)
        
        readings = db.get_historical_telemetry(user_id, request.month, request.year)
        if not readings:
            return format_api_response(False, message="No historical telemetry found for this period.", status_code=404)

        fhmm_results = fhmm.disaggregate(readings)
        
        # FIXED: Injected safety guard to prevent NoneType execution crashes
        registered_appliances = db.get_user_appliances(user_id)
        if not registered_appliances:
            logger.warning(f"Aborting batch trigger: No active appliances for user {user_id}")
            return format_api_response(False, message="No active appliances found for this user.")

        # FIXED: Added safe dictionary key lookup for 'type'
        registered_types = {
            app.get('type') for app in registered_appliances.values() if isinstance(app, dict) and app.get('type')
        }
        
        fhmm_breakdown = {
            name: round(sum(power_series) / 1000.0, 3) 
            for name, power_series in fhmm_results.items()
            if name in registered_types
        }

        estimated_load = sum(fhmm_breakdown.values())
        
        now = datetime.datetime.now(datetime.timezone.utc)
        payload = {
            "userId": user_id,
            "month": request.month,
            "year": request.year,
            "estimated_load": estimated_load,
            "estimated_cost": calculate_malaysian_tariff_a(estimated_load),
            "carbon_footprint": calculate_carbon_footprint(estimated_load),
            "breakdown": fhmm_breakdown,
            "benchmark_breakdown": {}, 
            "anomalies": [],
            "recommendations": ["Monthly report generated via batch trigger."],
            "hourlyUsage": {}, 
            "timestamp": now.isoformat()
        }

        db.save_disaggregation_result(payload)
        return format_api_response(True, message="Batch disaggregation triggered successfully.", data=payload)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Batch disaggregation failed for {request.user_id}: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Pipeline error: {str(e)}")

@app.post("/api/v1/sync-daily")
async def sync_daily_usage(request: SyncRequest, token: dict = Depends(verify_firebase_token)):
    # Synchronize 24-hour time-series data to Firestore.
    try:
        is_staff = db.get_user_role(token["uid"]) == 'staff'
        validate_user_ownership(request.user_id, token["uid"], is_staff=is_staff)
        appliances = db.get_user_appliances(request.user_id)
        results = simulator.run_monte_carlo(appliances, request.context)
        
        # Update daily_usage subcollection for frontend rendering.
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
        is_staff = db.get_user_role(token["uid"]) == 'staff'
        validate_user_ownership(request.user_id, token["uid"], is_staff=is_staff)
        db.log_feedback(request)
        user_apps = db.get_user_appliances(request.user_id)
        app_data = user_apps.get(request.appliance_name)

        if not app_data:
            return format_api_response(False, message=f"Appliance '{request.appliance_name}' not found.", status_code=404)

        is_false_positive = (request.predicted_state and not request.actual_state)
        learning_rate = 0.05
        current_p = app_data.get('prob_day', 0.5)

        # Behavioral adjustment: Tune usage probabilities
        new_p = max(0.01, current_p - learning_rate) if is_false_positive else min(0.99, current_p + learning_rate)
        db.update_single_appliance_prob(request.user_id, request.appliance_name, new_p)

        # Signature adjustment: Tune FHMM emission parameters (Advanced Loop)
        if is_false_positive:
            # If the AI over-predicted, slightly increase the variance (std_dev) 
            # to make the model more 'skeptical' of noisy signals for this appliance.
            current_std = app_data.get('std_dev', 1.0)
            db.update_appliance_signature_meta(request.user_id, request.appliance_name, {
                "std_dev": current_std * 1.05
            })

        return format_api_response(True, data={"new_probability": new_p})    
    except Exception as e:
        return format_api_response(False, message=str(e))
