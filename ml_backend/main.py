import logging
import datetime
import os
import asyncio
import gc
import numpy as np
import pandas as pd
from pydantic import BaseModel
from fastapi import FastAPI, HTTPException, Request, Depends, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from google.cloud import firestore as gcp_firestore

from services.adaptive_logic import apply_adaptive_hybrid_logic
from models.request_models import FeedbackRequest, OptimizationRequest, SeedReddRequest, SyncRequest, DisaggregationRequest, BatchDisaggregationRequest
from services.firebase_client import FirebaseClient
from services.simulator import AdaptiveBehavioralSimulator
from services.optimizer import EnergyOptimizer
from services.fhmm_service import FHMMService
from services.weather_service import WeatherService
from utils.response_formatter import format_api_response
from utils.auth import verify_firebase_token, validate_user_ownership

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="SmartMeter ML Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

db = FirebaseClient()
simulator = AdaptiveBehavioralSimulator()
optimizer = EnergyOptimizer()
fhmm = FHMMService()
weather = WeatherService()

class AggregateRequest(BaseModel):
    month: int
    year: int

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled Global Error: {str(exc)}", exc_info=True)
    return format_api_response(False, message="An internal server error occurred.")

@app.get("/")
async def root():
    return {"status": "online", "message": "ML Backend Active"}

@app.get("/api/v1/health")
async def health_check():
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

@app.post("/api/v1/admin/aggregations")
async def trigger_campus_aggregation(request: AggregateRequest, token: dict = Depends(verify_firebase_token)):
    is_staff = await db.get_user_role(token["uid"]) == 'staff'
    if not is_staff:
        raise HTTPException(status_code=403, detail="Access denied. Staff privileges required.")
        
    docs = db.db.collection('disaggregation_results') \
             .where(filter=gcp_firestore.FieldFilter('month', '==', request.month)) \
             .where(filter=gcp_firestore.FieldFilter('year', '==', request.year)) \
             .stream()

    total_kwh = 0.0
    total_cost = 0.0
    total_carbon = 0.0
    total_breakdown = {}
    total_hourly = {}
    all_anomalies = set()
    processed_count = 0

    async for doc in docs:
        data = doc.to_dict()
        if data.get('userId') == 'aggregate' or 'aggregate' in doc.id:
            continue

        processed_count += 1
        
        summary = data.get('summary', {})
        total_kwh += float(summary.get('totalConsumption', 0.0))
        total_cost += float(summary.get('totalCost', 0.0))
        total_carbon += float(data.get('carbonFootprint', 0.0) or data.get('carbon_footprint', 0.0))
        
        breakdown = data.get('breakdown', {})
        for app_name, usage in breakdown.items():
            total_breakdown[app_name] = total_breakdown.get(app_name, 0.0) + float(usage)
            
        hourly = data.get('hourlyUsage', {})
        for hour, usage in hourly.items():
            hour_str = str(hour)
            total_hourly[hour_str] = total_hourly.get(hour_str, 0.0) + float(usage)
            
        anomalies = data.get('anomalies', [])
        for anomaly in anomalies:
            all_anomalies.add(anomaly)

    if processed_count == 0:
        raise HTTPException(status_code=400, detail=f"No unit data found for {request.month}/{request.year}. Staff must submit unit bills first.")

    aggregate_doc = {
        'userId': 'aggregate',
        'scope': 'Campus',
        'month': request.month,
        'year': request.year,
        'carbonFootprint': total_carbon,
        'breakdown': total_breakdown,
        'anomalies': list(all_anomalies),
        'hourlyUsage': total_hourly,
        'summary': {
            'totalConsumption': total_kwh,
            'totalCost': total_cost,
            'keyIssue': f"Aggregated Campus report compiled from {processed_count} spatial units.",
            'recommendations': ["Consolidate campus-wide optimizations."],
            'comparisonPercent': 0.0
        },
        'kpis': {
            'totalKwh': total_kwh,
            'dailyAvgKwh': total_kwh / 30.0 if processed_count > 0 else 0.0,
            'peakKwh': 0.0,
            'peakTime': "N/A",
            'totalCost': total_cost,
            'changePercent': 0.0
        },
        'createdAt': gcp_firestore.SERVER_TIMESTAMP
    }

    doc_id = f"aggregate_{request.month}_{request.year}"
    await db.db.collection('disaggregation_results').document(doc_id).set(aggregate_doc)

    return format_api_response(True, message=f"Campus aggregation complete for {request.month}/{request.year}.", data={"units_processed": processed_count})

@app.post("/api/v1/optimizations")
async def run_optimization(request: OptimizationRequest, token: dict = Depends(verify_firebase_token)):
    try:
        is_staff = await db.get_user_role(token["uid"]) == 'staff'
        validate_user_ownership(request.user_id, token["uid"], is_staff=is_staff)
        appliances = await db.get_user_appliances(request.user_id)
        if not appliances:
            raise ValueError("No active appliances found for user.")
            
        # Optimization math is CPU-heavy, keep in thread pool
        new_weights = await asyncio.to_thread(optimizer.refine, appliances, request.actual_bill)
        
        # Native async write
        await db.update_appliance_weights(request.user_id, appliances, new_weights)
        
        return format_api_response(True, message="Weights optimized successfully")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Optimization failed: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to optimize energy weights.")

@app.post("/api/v1/disaggregations")
async def trigger_batch_disaggregation(request: BatchDisaggregationRequest, background_tasks: BackgroundTasks, token: dict = Depends(verify_firebase_token)):
    try:
        is_staff = await db.get_user_role(token["uid"]) == 'staff'

        from utils.auth import validate_user_ownership
        validate_user_ownership(request.user_id, token["uid"], is_staff=is_staff)

        student_uid = request.user_id
        telemetry_node = getattr(request, 'telemetry_source_id', student_uid) or student_uid

        # Route extraction to Unit node
        readings = await db.get_historical_telemetry(
            telemetry_node, 
            request.month, 
            request.year
        )
        
        if not readings:
            return format_api_response(False, message="No telemetry found for the selected period.", status_code=400)

        payloads = await _run_multi_tenant_pipeline(
            unit_id=telemetry_node,
            student_uids=[student_uid],
            readings=readings,
            request=request
        )

        for payload in payloads:
            background_tasks.add_task(db.save_disaggregation_result, payload)

        return format_api_response(True, data={"students_processed": 1})
        
    except Exception as e:
        import logging
        logging.error(f"Batch pipeline failed: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal processing error on batch disaggregation.")

@app.post("/api/v1/realtime-disaggregations")
async def process_realtime_telemetry(request: DisaggregationRequest, background_tasks: BackgroundTasks, token: dict = Depends(verify_firebase_token)):
    try:
        is_staff = await db.get_user_role(token["uid"]) == 'staff'
        validate_user_ownership(request.user_id, token["uid"], is_staff=is_staff)
        user_id = request.user_id

        registered_appliances = await db.get_user_appliances(user_id)
        if not registered_appliances:
            return format_api_response(False, message="No active appliances registered.", status_code=400)

        raw_readings = request.aggregate_readings
        if len(raw_readings) < 3:
            return format_api_response(False, message="Insufficient real-time sequence frame window.", status_code=400)

        payload = await _run_disaggregation_pipeline(
            user_id,
            raw_readings,
            request,
            registered_appliances
        )

        target_unit_id = user_id
        user_data = await db.get_user_data(user_id)
        if user_data and user_data.get('assignedUnitId'):
            target_unit_id = user_data['assignedUnitId']
            payload['userId'] = target_unit_id

        if payload.get('status', 'success') != 'error':
            background_tasks.add_task(db.save_realtime_result, payload)
            background_tasks.add_task(db.increment_monthly_consumption, target_unit_id, payload['month'], payload['year'], payload['estimated_load'])

            return format_api_response(True, data=payload)
            
        return format_api_response(False, message="Disaggregation pipeline failed to converge.", status_code=500)

    except Exception as e:
        logger.error(f"Real-time pipeline failed: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal processing error on streaming window.")

async def _run_multi_tenant_pipeline(unit_id, student_uids, readings, request):
    # Step 1: Validate Telemetry Input
    logger.info(f"Pipeline Input - Readings Length: {len(readings)}")
    logger.info(f"Pipeline Input - First 5 readings: {readings[:5]}")
    
    # Step 3: Verification of Unit/Student Linkage
    logger.info(f"Resolving students for Unit ID: {unit_id}")
    logger.info(f"Students found: {student_uids}")

    # OOM Fix: Temporal Downsampling
    max_ml_points = 2000
    reduction_factor = max(1, len(readings) // max_ml_points)
    decimated_readings = readings[::reduction_factor]

    # OOM Fix: Memory-efficient Numpy Array (Float32)
    np_readings = np.array(decimated_readings, dtype=np.float32)
    series_readings = pd.Series(np_readings).rolling(window=5, min_periods=1, center=True).median().dropna()
    smoothed_readings = series_readings.values.tolist()

    # CPU Starvation Fix: Process Viterbi algorithm in 24h chunks offloaded to thread pool
    chunk_size = 1440 
    aggregated_fhmm = {}
    
    for i in range(0, len(smoothed_readings), chunk_size):
        chunk = smoothed_readings[i:i + chunk_size]
        chunk_results = await asyncio.to_thread(fhmm.disaggregate, chunk)
        
        # Step 2: Check FHMM Result Population
        logger.info(f"FHMM Output for chunk: {chunk_results}")
        
        for k, v in chunk_results.items():
            key = str(k).lower()
            scalar_value = 0.0
            if isinstance(v, list):
                scalar_value = float(np.mean(v)) if len(v) > 0 else 0.0
            else:
                scalar_value = float(v)
            
            aggregated_fhmm[key] = aggregated_fhmm.get(key, 0.0) + scalar_value

    normalized_fhmm = aggregated_fhmm
    now = datetime.datetime.now(datetime.timezone.utc)

    student_raw_breakdowns = {}
    room_raw_total = 0.0

    for uid in student_uids:
        registered_appliances = await db.get_user_appliances(uid) or {}
        registered_types = {str(app.get('type', '')).lower() for app in registered_appliances.values() if app.get('type')}

        breakdown = {}
        for app_id, app_data in registered_appliances.items():
            app_type = app_data.get('type', 'Unknown').capitalize()
            
            raw_usage = await apply_adaptive_hybrid_logic(
                db=db,
                user_id=uid,
                appliance_name=app_type.lower(),
                manual_overrides={},
                network_states={},
                fhmm_predictions=normalized_fhmm,
                registered_types=registered_types,
                current_hour=12
            )
            
            breakdown[app_type] = breakdown.get(app_type, 0.0) + raw_usage

        student_raw_breakdowns[uid] = breakdown
        room_raw_total += sum(breakdown.values())

    target_load = request.total_bill
    scaling_factor = target_load / room_raw_total if room_raw_total > 0 else 0

    payloads = []
    for uid in student_uids:
        raw_breakdown = student_raw_breakdowns.get(uid, {})
        if not raw_breakdown and room_raw_total > 0:
            continue 

        if room_raw_total > 0:
            scaled_breakdown = {k: round(v * scaling_factor, 2) for k, v in raw_breakdown.items()}
        else:
            total_apps = sum(len(b) for b in student_raw_breakdowns.values())
            avg_share = target_load / total_apps if total_apps > 0 else 0
            scaled_breakdown = {k: round(avg_share, 2) for k in raw_breakdown.keys()}

        student_load = sum(scaled_breakdown.values())
        student_cost = student_load 
        student_carbon = student_load * 0.447

        recommendations = generate_recommendations(scaled_breakdown)
        benchmark_breakdown = {k: round(v * 0.9, 2) for k, v in scaled_breakdown.items()}

        payloads.append({
            "userId": uid, 
            "unitId": unit_id,
            "blockId": getattr(request, 'block_id', None),
            "month": request.month,
            "year": request.year,
            "estimated_load": round(student_load, 2),
            "estimated_cost": round(student_cost, 2),
            "carbon_footprint": round(student_carbon, 2),
            "breakdown": scaled_breakdown,
            "benchmark_breakdown": benchmark_breakdown,
            "recommendations": recommendations,
            "anomalies": [],
            "hourlyUsage": {str(now.hour): round(student_load, 2)},
            "timestamp": now.isoformat(),
            "summary": {
                "totalConsumption": round(student_load, 2),
                "totalCost": round(student_cost, 2),
                "keyIssue": recommendations[0] if recommendations else "Consumption nominal.",
                "recommendations": recommendations
            },
            "kpis": {
                "totalKwh": round(student_load, 2),
                "dailyAvgKwh": round(student_load / 30.0, 2),
                "totalCost": round(student_cost, 2)
            }
        })

    return payloads

def _build_master_unit_payload(unit_id, payloads, request):
    total_load = sum(p["estimated_load"] for p in payloads)
    total_cost = sum(p["estimated_cost"] for p in payloads)
    total_carbon = sum(p["carbon_footprint"] for p in payloads)
    
    master_breakdown = {}
    for p in payloads:
        for app, val in p["breakdown"].items():
            master_breakdown[app] = master_breakdown.get(app, 0.0) + val
            
    now = datetime.datetime.now(datetime.timezone.utc)
    recommendations = generate_recommendations(master_breakdown)

    return {
        "userId": unit_id,
        "scope": "Unit",
        "month": request.month,
        "year": request.year,
        "estimated_load": round(total_load, 2),
        "estimated_cost": round(total_cost, 2),
        "carbon_footprint": round(total_carbon, 2),
        "breakdown": master_breakdown,
        "benchmark_breakdown": {k: round(v * 0.9, 2) for k, v in master_breakdown.items()},
        "recommendations": recommendations,
        "anomalies": [],
        "hourlyUsage": {str(now.hour): round(total_load, 2)},
        "timestamp": now.isoformat(),
        "summary": {
            "totalConsumption": round(total_load, 2),
            "totalCost": round(total_cost, 2),
            "keyIssue": recommendations[0] if recommendations else "Consumption nominal.",
            "recommendations": recommendations
        },
        "kpis": {
            "totalKwh": round(total_load, 2),
            "dailyAvgKwh": round(total_load / 30.0, 2),
            "totalCost": round(total_cost, 2)
        }
    }

async def _run_disaggregation_pipeline(user_id, raw_readings, request, registered_appliances):
    if len(raw_readings) > 20:
        readings_to_process = raw_readings[-20:]
    else:
        readings_to_process = raw_readings

    np_readings = np.array(readings_to_process, dtype=np.float32)
    series_readings = pd.Series(np_readings).rolling(window=3, min_periods=1, center=True).median().dropna()
    smoothed_readings = series_readings.values.tolist()

    if len(smoothed_readings) < 1:
        smoothed_readings = raw_readings

    # Offload CPU bound math to thread
    fhmm_results = await asyncio.to_thread(fhmm.disaggregate, smoothed_readings)
    
    raw_network = request.device_states if hasattr(request, 'device_states') and request.device_states else {}
    network_constraints = {str(k).lower(): v for k, v in raw_network.items() if v is not None}
    
    raw_manual = getattr(request, 'manual_overrides', {})
    manual_constraints = {str(k).lower(): v for k, v in raw_manual.items() if v is not None}
    
    normalized_fhmm = {str(k).lower(): v for k, v in fhmm_results.items()}
    registered_types = {str(app.get('type')).lower() for app in registered_appliances.values() if isinstance(app, dict) and app.get('type')}

    now = datetime.datetime.now(datetime.timezone.utc)
    current_hour = now.hour

    fhmm_breakdown = {}
    target_appliances = ["Fan", "Laptop", "Charger", "Lamp", "Iron", "Kettle", "Printer"]

    for name in target_appliances:
        fhmm_breakdown[name] = await apply_adaptive_hybrid_logic(
            db=db,
            user_id=user_id,
            appliance_name=name,
            manual_overrides=manual_constraints,
            network_states=network_constraints,
            fhmm_predictions=normalized_fhmm,
            registered_types=registered_types,
            current_hour=current_hour
        )

    user_data = await db.get_user_data(user_id)
    energy_goal = user_data.get('energyGoal', 0) if user_data else 0

    if energy_goal > 0:
        cumulative_historical_load = await db.get_monthly_consumption(user_id, now.month, now.year)
        
        current_window_load = sum(fhmm_breakdown.values())
        total_monthly_consumption = cumulative_historical_load + current_window_load

        if total_monthly_consumption > energy_goal:
            await db.send_fcm_notification(
                user_id,
                "Energy Budget Exceeded",
                f"Your monthly consumption ({total_monthly_consumption:.2f} kWh) has broken your budget goal of {energy_goal} kWh."
            )

    return {
        "userId": user_id,
        "month": now.month,
        "year": now.year,
        "estimated_load": round(sum(fhmm_breakdown.values()), 2),
        "breakdown": fhmm_breakdown,
        "anomalies": [],
        "hourlyUsage": {str(current_hour): round(sum(fhmm_breakdown.values()), 2)},
        "timestamp": now.isoformat()
    }

@app.post("/api/v1/daily-usages")
async def sync_daily_usage(request: SyncRequest, token: dict = Depends(verify_firebase_token)):
    try:
        is_staff = await db.get_user_role(token["uid"]) == 'staff'
        validate_user_ownership(request.user_id, token["uid"], is_staff=is_staff)
        appliances = await db.get_user_appliances(request.user_id)
        
        results = await asyncio.to_thread(simulator.run_monte_carlo, appliances, request.context)
        await db.save_daily_usage(request.user_id, results['hourly_profile'])
        
        return format_api_response(True, message="Daily sync complete")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

def generate_recommendations(breakdown: dict) -> list:
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

@app.post("/api/v1/feedbacks")
async def handle_feedback(request: FeedbackRequest, token: dict = Depends(verify_firebase_token)):
    try:
        is_staff = await db.get_user_role(token["uid"]) == 'staff'
        validate_user_ownership(request.user_id, token["uid"], is_staff=is_staff)
        
        await db.log_feedback(request)
        user_apps = await db.get_user_appliances(request.user_id)
        app_data = user_apps.get(request.appliance_name)

        if not app_data:
            return format_api_response(False, message=f"Appliance '{request.appliance_name}' not found.", status_code=404)

        is_false_positive = (request.predicted_state and not request.actual_state)
        learning_rate = 0.05
        current_p = app_data.get('prob_day', 0.5)

        new_p = max(0.01, current_p - learning_rate) if is_false_positive else min(0.99, current_p + learning_rate)
        
        await db.update_single_appliance_prob(request.user_id, request.appliance_name, new_p)
        
        if is_false_positive:
            current_std = app_data.get('std_dev', 1.0)
            await db.update_appliance_signature_meta(request.user_id, request.appliance_name, {
                "std_dev": current_std * 1.05
            })

        return format_api_response(True, data={"new_probability": new_p})    
    except Exception as e:
        return format_api_response(False, message=str(e))

@app.post("/api/v1/dev/redd-seeds")
async def seed_exact_synthetic_redd(request: SeedReddRequest, token: dict = Depends(verify_firebase_token)):
    try:
        staff_uid = token["uid"]
        is_staff = await db.get_user_role(staff_uid) == 'staff'
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
            # OOM Fix: Sequential reading, manual garbage collection, float32 downcasting
            with pd.HDFStore(h5_file_path, mode='r') as store:
                for col_name, h5_path in columns_to_read.items():
                    table_path = f"{h5_path}/table"
                    
                    if table_path in store:
                        df_meter = store.get(table_path)
                        
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
                            raw_series = df_meter.iloc[:, -1]
                        
                        if not isinstance(raw_series.index, pd.DatetimeIndex):
                            raise ValueError(f"Could not convert HDF5 index to DatetimeIndex for {col_name}.")

                        # Downcast immediately to save memory
                        resampled = raw_series.astype('float32').resample('1h').mean().dropna()
                        resampled_series[col_name] = resampled
                        
                        # Aggressive memory cleanup
                        del df_meter, raw_series
                        gc.collect()
                    else:
                        logger.warning(f"Expected data table missing at path: {table_path}")
                        resampled_series[col_name] = pd.Series(dtype='float32')
        except Exception as e:
            logger.error(f"HDF5 Critical Ingestion Failure: {str(e)}")
            raise HTTPException(status_code=500, detail=f"Data storage read failure: {str(e)}")

        df = pd.DataFrame(resampled_series)
        df = df.ffill().fillna(0)
        df['synthetic_mains'] = df.sum(axis=1)

        target_start = datetime.datetime(request.year, request.month, 1, tzinfo=datetime.timezone.utc)
        raw_start = df.index[0].tz_localize(datetime.timezone.utc) if df.index[0].tzinfo is None else df.index[0]
        time_delta_offset = target_start - raw_start

        df.index = df.index + time_delta_offset

        del resampled_series
        gc.collect()

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
                await batch.commit()
                batch = db.db.batch()
                write_count = 0
                
        if write_count > 0:
            await batch.commit()

        del df
        gc.collect()
        
        return format_api_response(True, message=f"Seeded REDD data for {request.user_id}.")
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Seeding failed: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))