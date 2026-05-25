import logging
import datetime
import os
import numpy as np
import pandas as pd
from pydantic import BaseModel
from fastapi import FastAPI, HTTPException, Request, Depends
from ml_backend.services.adaptive_logic import apply_adaptive_hybrid_logic
from models.request_models import FeedbackRequest, OptimizationRequest, SeedReddRequest, SyncRequest, DisaggregationRequest, BatchDisaggregationRequest
from services.firebase_client import FirebaseClient
from services.simulator import AdaptiveBehavioralSimulator
from services.optimizer import EnergyOptimizer
from services.fhmm_service import FHMMService
from services.weather_service import WeatherService
from utils.response_formatter import format_api_response
from utils.auth import verify_firebase_token, validate_user_ownership

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
async def process_realtime_telemetry(request: DisaggregationRequest, token: dict = Depends(verify_firebase_token)):
    # High-level: Implements continuous-priority sliding window real-time disaggregation with adaptive feedback.
    try:
        is_staff = db.get_user_role(token["uid"]) == 'staff'
        validate_user_ownership(request.user_id, token["uid"], is_staff=is_staff)
        user_id = request.user_id

        registered_appliances = db.get_user_appliances(user_id)
        if not registered_appliances:
            return format_api_response(False, message="No active appliances registered.", status_code=400)

        raw_readings = request.aggregate_readings
        if len(raw_readings) < 3:
            return format_api_response(False, message="Insufficient real-time sequence frame window.", status_code=400)

        if len(raw_readings) > 5:
            raw_readings = raw_readings[-5:]

        series_readings = pd.Series(raw_readings).rolling(window=3, min_periods=1, center=True).median().dropna()
        smoothed_readings = [float(x) for x in series_readings.values]

        if len(smoothed_readings) < 1:
            return format_api_response(False, message="Filtered telemetry window contains no usable signal.", status_code=400)

        fhmm_results = fhmm.disaggregate(smoothed_readings)
        
        # Developer Expectation: request schema must include network_states and manual_overrides
        raw_network = request.network_states if hasattr(request, 'network_states') and request.network_states else {}
        network_constraints = {str(k).lower(): v for k, v in raw_network.items() if v is not None}
        
        raw_manual = request.manual_overrides if hasattr(request, 'manual_overrides') and request.manual_overrides else {}
        manual_constraints = {str(k).lower(): v for k, v in raw_manual.items() if v is not None}
        
        normalized_fhmm = {str(k).lower(): v for k, v in fhmm_results.items()}
        registered_types = {str(app.get('type')).lower() for app in registered_appliances.values() if isinstance(app, dict) and app.get('type')}

        now = datetime.datetime.now(datetime.timezone.utc)
        current_hour = now.hour

        fhmm_breakdown = {}
        target_appliances = ["Fan", "Laptop", "Charger", "Lamp", "Iron", "Kettle", "Printer"]

        for name in target_appliances:
            # Route evaluation through the adaptive 3-tier logic gate
            fhmm_breakdown[name] = apply_adaptive_hybrid_logic(
                db=db,
                user_id=user_id,
                appliance_name=name,
                manual_overrides=manual_constraints,
                network_states=network_constraints,
                fhmm_predictions=normalized_fhmm,
                registered_types=registered_types,
                current_hour=current_hour
            )

        user_data = db.get_user_data(user_id)
        energy_goal = user_data.get('energyGoal', 0) if user_data else 0

        if energy_goal > 0:
            try:
                docs = db.db.collection('disaggregation_results') \
                    .where('userId', '==', user_id) \
                    .where('month', '==', now.month) \
                    .where('year', '==', now.year) \
                    .stream()
                cumulative_historical_load = sum([float(doc.to_dict().get('estimated_load', 0.0)) for doc in docs])
            except Exception:
                cumulative_historical_load = 0.0
            
            current_window_load = sum(fhmm_breakdown.values())
            total_monthly_consumption = cumulative_historical_load + current_window_load

            if total_monthly_consumption > energy_goal:
                db.send_fcm_notification(
                    user_id,
                    "Energy Budget Exceeded",
                    f"Your monthly consumption ({total_monthly_consumption:.2f} kWh) has broken your budget goal of {energy_goal} kWh."
                )

        payload = {
            "userId": user_id,
            "month": now.month,
            "year": now.year,
            "estimated_load": round(sum(fhmm_breakdown.values()), 2),
            "breakdown": fhmm_breakdown,
            "anomalies": [],
            "timestamp": now.isoformat()
        }

        db.save_disaggregation_result(payload)
        return format_api_response(True, data=payload)

    except Exception as e:
        logger.error(f"Real-time pipeline failed: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal processing error on streaming window.")

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

@app.post("/api/v1/dev/seed-synthetic-redd")
async def seed_exact_synthetic_redd(request: SeedReddRequest, token: dict = Depends(verify_firebase_token)):
    try:
        staff_uid = token["uid"]
        is_staff = db.get_user_role(staff_uid) == 'staff'
        validate_user_ownership(request.user_id, staff_uid, is_staff=is_staff)

        h5_file_path = "/mnt/datasets/redd.h5" 
        
        columns_to_read = {
            'Lamp': '/building1/elec/meter9',
            'Fan': '/building1/elec/meter17',
            'Laptop': '/building1/elec/meter15',
            'Charger': '/building1/elec/meter16',
            'Kettle': '/building1/elec/meter11',
            'Iron': '/building1/elec/meter13',
            'Printer': '/building1/elec/meter8'
        }

        resampled_series = {}
        
        try:
            with pd.HDFStore(h5_file_path, mode='r') as store:
                for col_name, h5_path in columns_to_read.items():
                    table_path = f"{h5_path}/table"
                    
                    if table_path in store:
                        df_meter = store.get(table_path)
                        
                        # Check common column names for timestamps in structural HDF5 exports
                        if 'index' in df_meter.columns:
                            df_meter.index = pd.to_datetime(df_meter['index'])
                        elif 'timestamp' in df_meter.columns:
                            df_meter.index = pd.to_datetime(df_meter['timestamp'])
                        elif 'time' in df_meter.columns:
                            df_meter.index = pd.to_datetime(df_meter['time'])
                        elif isinstance(df_meter.index, pd.RangeIndex) and df_meter.iloc[:, 0].name == 'index':
                            df_meter.index = pd.to_datetime(df_meter.iloc[:, 0])
                        
                        if 'active' in df_meter.columns:
                            raw_series = df_meter['active']
                        elif 'values' in df_meter.columns:
                            raw_series = df_meter['values']
                        else:
                            # Use the last column if the first column was the timestamp index
                            raw_series = df_meter.iloc[:, -1]
                        
                        if not isinstance(raw_series.index, pd.DatetimeIndex):
                            raise ValueError(f"Could not convert HDF5 index to DatetimeIndex for {col_name}. Current columns: {list(df_meter.columns)}")

                        # Resample down to 1-hour chunks safely
                        resampled_series[col_name] = raw_series.resample('1h').mean().dropna()
                        del df_meter, raw_series
                    else:
                        logger.warning(f"Expected data table missing at path: {table_path}")
                        resampled_series[col_name] = pd.Series(dtype='float64')
        except Exception as e:
            logger.error(f"HDF5 Critical Ingestion Failure: {str(e)}")
            raise HTTPException(status_code=500, detail=f"Data storage read failure: {str(e)}")

        # High-level: Re-baselines static HDF5 time-series indices to fit within the dynamically requested billing month.
        df = pd.DataFrame(resampled_series)
        df = df.ffill().fillna(0)
        df['synthetic_mains'] = df.sum(axis=1)

        # Developer Expectation: Calculate the offset delta between the raw dataset index and the target year/month parameters.
        target_start = datetime.datetime(request.year, request.month, 1, tzinfo=datetime.timezone.utc)
        raw_start = df.index[0].tz_localize(datetime.timezone.utc) if df.index[0].tzinfo is None else df.index[0]
        time_delta_offset = target_start - raw_start

        # Developer Expectation: Shift the dataframe index vector so all generated records match the request boundary context.
        df.index = df.index + time_delta_offset

        # Clear secondary dictionary tracking structures from heap memory
        del resampled_series

        batch = db.db.batch()
        write_count = 0

        for timestamp, row in df.iterrows():
            doc_ref = db.db.collection('users').document(request.user_id).collection('telemetry').document()
            native_timestamp = timestamp.to_pydatetime()

            batch.set(doc_ref, {
                "wattage": float(row['synthetic_mains']),
                "timestamp": native_timestamp,
                "is_synthetic_redd": True,
                "ground_truth": {
                    "Fan": float(row['Fan']),
                    "Laptop": float(row['Laptop']),
                    "Charger": float(row['Charger']),
                    "Lamp": float(row['Lamp']),
                    "Iron": float(row['Iron']),
                    "Kettle": float(row['Kettle']),
                    "Printer": float(row['Printer'])
                }
            })
            
            write_count += 1
            if write_count >= 400:  
                batch.commit()
                batch = db.db.batch()
                write_count = 0
                
        if write_count > 0:
            batch.commit()

        del df
        return format_api_response(True, message=f"Seeded REDD data for {request.user_id}.")
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Seeding failed: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))