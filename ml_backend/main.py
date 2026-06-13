from collections import defaultdict
import logging
import datetime
import calendar
import os
import asyncio
import gc
import numpy as np
import pandas as pd
from fastapi import FastAPI, HTTPException, Request, Depends, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from google.cloud import firestore as gcp_firestore

from services.adaptive_logic import apply_adaptive_hybrid_logic
from models.request_models import FeedbackRequest, ForecastRequest, SeedReddRequest, SyncRequest, DisaggregationRequest, BatchDisaggregationRequest, AggregationRequest
from services.firebase_client import FirebaseClient
from services.simulator import AdaptiveBehavioralSimulator
from services.optimizer import EnergyOptimizer
from services.fhmm_service import FHMMService
from services.weather_service import WeatherService
from utils.response_formatter import format_api_response
from utils.auth import verify_firebase_token, validate_user_ownership

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

from router.vision import router as vision_router

app = FastAPI(title="SmartMeter ML Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(vision_router)

db = FirebaseClient()
simulator = AdaptiveBehavioralSimulator()
optimizer = EnergyOptimizer()
fhmm = FHMMService()
weather = WeatherService()

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

async def resolve_block_id(identifier: str) -> str:
    # Resolves a block identifier (Name or ID) to a definitive Document ID.
    if not identifier or len(identifier) > 25: # Heuristic: IDs are usually shorter/fixed length
         return identifier
         
    # Check if it's already a valid ID by checking for existence.
    doc = db.db.collection('blocks').document(identifier).get()
    if doc.exists:
        return identifier
        
    # Otherwise, search by name.
    blocks = db.db.collection('blocks').where(filter=gcp_firestore.FieldFilter('name', '==', identifier)).limit(1).stream()
    for b in blocks:
        return b.id
        
    return identifier

@app.post("/api/v1/admin/aggregations")
async def trigger_aggregation_endpoint(request: AggregationRequest, token: dict = Depends(verify_firebase_token)):
    is_staff = await db.get_user_role(token["uid"]) == 'staff'
    if not is_staff:
        raise HTTPException(status_code=403, detail="Access denied. Staff privileges required.")
    
    # Normalize block_id to ensure we query with the Doc ID.
    resolved_id = await resolve_block_id(request.block_id) if request.block_id else None
        
    result = await asyncio.to_thread(run_aggregation, request.month, request.year, resolved_id)
    
    if result.get("status") == "no_data":
         raise HTTPException(status_code=400, detail=f"No unit data found for the selected period. Staff must submit unit bills first.")
         
    return format_api_response(True, message=f"Aggregation complete.", data=result)

def _create_empty_bucket() -> dict:
    return {
        "processed_count": 0,
        "total_kwh": 0.0,
        "breakdown": defaultdict(float),
        "hourly": defaultdict(float),
        "anomalies": set()
    }

def run_aggregation(month: int, year: int, target_id: str | None = None) -> dict:
    """Single-pass O(N) aggregation for Campus, Block, and Unit scopes."""
    logger.info(f"EX_AGG: Executing Universal Multi-Tier Aggregation for {year}-{month:02d}")
    
    month_id = f"{year}-{month:02d}"
    user_docs = db.db.collection('users').stream()

    # Memory Buckets
    campus_bucket = _create_empty_bucket()
    block_buckets = defaultdict(_create_empty_bucket)
    unit_buckets = defaultdict(_create_empty_bucket)

    for user_doc in user_docs:
        user_data = user_doc.to_dict() or {}
        
        profile = user_data.get('profile', {})
        role = profile.get('role', user_data.get('role', 'student'))
        if role == 'system_aggregate' or 'aggregate' in user_doc.id:
            continue

        loc = user_data.get('location', {})
        u_id = loc.get('unit_id', user_data.get('assignedUnitId'))
        b_id = loc.get('block_id', user_data.get('dormBlock', user_data.get('blockId')))

        if not u_id and not b_id:
            continue

        # Fetch monthly data
        cycle_ref = user_doc.reference.collection('billing_cycles').document(month_id)
        cycle_doc = cycle_ref.get()
        if not cycle_doc.exists:
            continue

        data = cycle_doc.to_dict() or {}
        
        # Accumulate Metrics
        kwh = float(data.get('total_consumption_kwh', 0.0))
        breakdown = data.get('monthly_appliance_breakdown', data.get('appliance_breakdown', {}))
        hourly = data.get('monthly_hourly_usage', data.get('hourly_usage', {}))
        anomalies = data.get('anomalies', [])

        campus_bucket["processed_count"] += 1
        campus_bucket["total_kwh"] += kwh
        for k, v in breakdown.items(): campus_bucket["breakdown"][k] += float(v)
        for k, v in hourly.items(): campus_bucket["hourly"][str(k)] += float(v)
        for a in anomalies: campus_bucket["anomalies"].add(a)

        if b_id:
            block_buckets[b_id]["processed_count"] += 1
            block_buckets[b_id]["total_kwh"] += kwh
            for k, v in breakdown.items(): block_buckets[b_id]["breakdown"][k] += float(v)
            for k, v in hourly.items(): block_buckets[b_id]["hourly"][str(k)] += float(v)
            for a in anomalies: block_buckets[b_id]["anomalies"].add(a)

        if u_id:
            unit_buckets[u_id]["processed_count"] += 1
            unit_buckets[u_id]["total_kwh"] += kwh
            for k, v in breakdown.items(): unit_buckets[u_id]["breakdown"][k] += float(v)
            for k, v in hourly.items(): unit_buckets[u_id]["hourly"][str(k)] += float(v)
            for a in anomalies: unit_buckets[u_id]["anomalies"].add(a)

    if campus_bucket["processed_count"] == 0:
        logger.warning("EX_AGG: Zero units processed. Database empty for this billing cycle.")
        return {"status": "no_data"}

    now = datetime.datetime.now(datetime.timezone.utc)
    day_id = now.strftime("%Y-%m-%d")
    batch = db.db.batch()
    write_count = 0

    def _prepare_write(entity_id: str, scope: str, bucket: dict):
        nonlocal write_count
        
        peak_val = max(bucket["hourly"].values(), default=0.0)
        peak_hour = next((k for k, v in bucket["hourly"].items() if v == peak_val), "0")

        doc_payload = {
            "summary": {
                "totalConsumption": round(bucket["total_kwh"], 2),
                "keyIssue": f"Aggregated {scope} report compiled from {bucket['processed_count']} active records.",
                "recommendations": [f"Review {scope.lower()} efficiency targets."]
            },
            "kpis": {
                "totalKwh": round(bucket["total_kwh"], 2),
                "dailyAvgKwh": round(bucket["total_kwh"] / 30.0, 2),
                "peakKwh": round(peak_val, 2),
                "peakTime": f"{peak_hour}:00"
            },
            "breakdown": {k: round(v, 2) for k, v in bucket["breakdown"].items()},
            "hourly": {k: round(v, 3) for k, v in bucket["hourly"].items()},
            "anomalies": list(bucket["anomalies"])
        }

        user_ref = db.db.collection('users').document(entity_id)
        month_ref = user_ref.collection('billing_cycles').document(month_id)
        daily_ref = month_ref.collection('daily_disaggregations').document(day_id)

        batch.set(user_ref, {
            "profile": {"role": "system_aggregate"},
            "metrics": {
                "lifetime_kwh": gcp_firestore.Increment(doc_payload["summary"]["totalConsumption"]),
                "last_aggregate_update": gcp_firestore.SERVER_TIMESTAMP
            }
        }, merge=True)

        batch.set(month_ref, {
            "total_consumption_kwh": doc_payload["summary"]["totalConsumption"],
            "last_updated": gcp_firestore.SERVER_TIMESTAMP,
            "scope": scope,
            "month": month,
            "year": year,
            "recommendations": doc_payload["summary"]["recommendations"],
            "anomalies": doc_payload["anomalies"],
            "benchmark_breakdown": doc_payload["breakdown"],
            "monthly_appliance_breakdown": doc_payload["breakdown"],
            "monthly_hourly_usage": doc_payload["hourly"]
        }, merge=True)

        # 3. Daily Entry
        batch.set(daily_ref, {
            "timestamp": gcp_firestore.SERVER_TIMESTAMP,
            "method": "Aggregation",
            "appliance_breakdown": doc_payload["breakdown"],
            "hourly_usage": doc_payload["hourly"],
            "kpis": doc_payload["kpis"],
            "summary": doc_payload["summary"],
            "scope": scope
        }, merge=True)
        
        write_count += 3

        if write_count >= 490:
            batch.commit()
            write_count = 0

    _prepare_write('aggregate', 'Campus', campus_bucket)
    
    for b_id, bucket in block_buckets.items():
        _prepare_write(b_id, 'Block', bucket)
        
    for u_id, bucket in unit_buckets.items():
        _prepare_write(u_id, 'Unit', bucket)

    if write_count > 0:
        batch.commit()

    # Update campus/config totalUsage for GoalProvider
    try:
        db.db.collection('campus').document('config').set({
            "totalUsage": round(campus_bucket["total_kwh"], 2)
        }, merge=True)
        logger.info(f"EX_AGG: Updated campus/config with totalUsage: {round(campus_bucket['total_kwh'], 2)}")
    except Exception as e:
        logger.error(f"EX_AGG: Failed to update campus/config: {e}")

    logger.info(f"EX_AGG: Success. Generated Campus, {len(block_buckets)} Blocks, and {len(unit_buckets)} Units.")
    return {"status": "success", "campus_kwh": campus_bucket["total_kwh"]}

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

        # Always provide a behavioral template for temporal distribution
        mcmc_result = await asyncio.to_thread(simulator.run_monte_carlo, registered_appliances, {})
        hourly_profile_template = mcmc_result.get('hourly_profile', {})

        payload = await _run_disaggregation_pipeline(
            user_id,
            raw_readings,
            request,
            registered_appliances,
            hourly_context=hourly_profile_template
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

@app.post("/api/v1/disaggregations")
async def trigger_batch_disaggregation(request: BatchDisaggregationRequest, background_tasks: BackgroundTasks, token: dict = Depends(verify_firebase_token)):
    try:
        is_staff = await db.get_user_role(token["uid"]) == 'staff'
        validate_user_ownership(request.user_id, token["uid"], is_staff=is_staff)
        
        # Fetch historical telemetry for the specified window
        source_id = request.telemetry_source_id or request.user_id
        readings = await db.get_historical_telemetry(source_id, request.month, request.year, block_id=request.block_id)
        
        if not readings or len(readings) < 5:
             return format_api_response(False, message="Insufficient historical telemetry for disaggregation.", status_code=400)

        student_docs = db.db.collection('users').where(filter=gcp_firestore.FieldFilter('assignedUnitId', '==', source_id)).stream()
        student_uids = [doc.id for doc in student_docs]
        
        if not student_uids:
            logger.warning(f"No students resolved for unit {source_id}. Defaulting to request user.")
            student_uids = [request.user_id]

        # Aggregate unit appliance pool for MCMC behavioral baseline
        all_appliances = {}
        for uid in student_uids:
            apps = await db.get_user_appliances(uid) or {}
            for k, v in apps.items():
                all_appliances[f"{uid}_{k}"] = v
        
        mcmc_result = await asyncio.to_thread(simulator.run_monte_carlo, all_appliances, {})
        hourly_profile = mcmc_result.get('hourly_profile', {})
        
        # Enforce default 24-hour distribution to prevent frontend serialization failure
        if not hourly_profile or sum(hourly_profile.values()) == 0:
            hourly_profile = {str(i): 1.0 for i in range(24)}

        # Execute primary disaggregation pipeline
        payloads = await _run_multi_tenant_pipeline(
            unit_id=source_id,
            student_uids=student_uids,
            readings=readings,
            request=request,
            block_id_override=request.block_id,
            hourly_context=hourly_profile
        )

        # Persist student-level disaggregation results
        for p in payloads:
            background_tasks.add_task(db.save_disaggregation_result, p)

        # Trigger multi-tier aggregation background task
        background_tasks.add_task(run_aggregation, request.month, request.year)
            
        return format_api_response(True, message=f"Disaggregation triggered for {len(student_uids)} students.", data={"student_count": len(student_uids)})

    except Exception as e:
        logger.error(f"Batch disaggregation failed: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

async def _run_multi_tenant_pipeline(unit_id, student_uids, readings, request, block_id_override=None, hourly_context=None):
    logger.info(f"Pipeline Input - Readings Length: {len(readings)}")
    
    max_ml_points = 2000
    reduction_factor = max(1, len(readings) // max_ml_points)
    decimated_readings = readings[::reduction_factor]

    np_readings = np.array(decimated_readings, dtype=np.float32)
    series_readings = pd.Series(np_readings).rolling(window=5, min_periods=1, center=True).median().dropna()
    smoothed_readings = series_readings.values.tolist()

    chunk_size = 1440 
    aggregated_fhmm = {}
    
    for i in range(0, len(smoothed_readings), chunk_size):
        chunk = smoothed_readings[i:i + chunk_size]
        chunk_results = await asyncio.to_thread(fhmm.disaggregate, chunk)
        
        for k, v in chunk_results.items():
            key = str(k).lower()
            scalar_value = float(np.mean(v)) if isinstance(v, list) and len(v) > 0 else float(v) if not isinstance(v, list) else 0.0
            aggregated_fhmm[key] = aggregated_fhmm.get(key, 0.0) + scalar_value

    now = datetime.datetime.now(datetime.timezone.utc)
    student_raw_breakdowns = {}
    room_raw_total = 0.0

    for uid in student_uids:
        registered_appliances = await db.get_user_appliances(uid) or {}
        registered_types = {str(app.get('type', '')).lower() for app in registered_appliances.values() if app.get('type')}
        
        user_doc = await db.get_user_data(uid)
        manual_overrides = user_doc.get('manualOverrides', {}) if user_doc else {}

        breakdown = {}
        for app_id, app_data in registered_appliances.items():
            app_type = app_data.get('type', 'Unknown').capitalize()
            
            raw_usage = await apply_adaptive_hybrid_logic(
                db=db,
                user_id=uid,
                appliance_name=app_type.lower(),
                manual_overrides=manual_overrides,
                network_states={},
                fhmm_predictions=aggregated_fhmm,
                registered_types=registered_types,
                current_hour=12
            )
            
            # Enforce minimum appliance baseline to prevent zero-value scaling
            raw_usage = max(raw_usage, 0.05)
            breakdown[app_type] = breakdown.get(app_type, 0.0) + raw_usage

        # Fallback to standard baseline if tenant has no registered appliances
        if not breakdown:
            breakdown = {
                "Lamp": 0.05,
                "Charger": 0.05,
                "Fan": 0.05
            }

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
        recommendations = generate_recommendations(scaled_breakdown)
        benchmark_breakdown = {k: round(v * 0.9, 2) for k, v in scaled_breakdown.items()}

        final_hourly = {}
        peak_hour = "0"
        peak_val = 0.0
        
        if hourly_context:
            profile_total = sum(hourly_context.values())
            scale = (student_load / profile_total) if profile_total > 0 else 0
            for h, v in hourly_context.items():
                h_str = str(h)
                h_val = round(v * scale, 3)
                final_hourly[h_str] = h_val
                if h_val > peak_val:
                    peak_val = h_val
                    peak_hour = h_str
        else:
            final_hourly = {str(h): round(student_load / 24, 3) for h in range(24)}

        payloads.append({
            "userId": uid, 
            "unitId": unit_id,
            "blockId": block_id_override,
            "scope": "Unit",
            "month": request.month,
            "year": request.year,
            "estimated_load": round(student_load, 2),
            "breakdown": scaled_breakdown,
            "benchmark_breakdown": benchmark_breakdown,
            "recommendations": recommendations,
            "anomalies": [],
            "hourlyUsage": final_hourly,
            "timestamp": now.isoformat(),
            "summary": {
                "totalConsumption": round(student_load, 2),
                "keyIssue": recommendations[0] if recommendations else "Consumption nominal.",
                "recommendations": recommendations
            },
            "kpis": {
                "totalKwh": round(student_load, 2),
                "dailyAvgKwh": round(student_load / 30.0, 2),
                "peakKwh": round(peak_val, 2),
                "peakTime": f"{peak_hour}:00"
            }
        })

    return payloads

async def _run_disaggregation_pipeline(user_id, raw_readings, request, registered_appliances, hourly_context=None):
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
    estimated_load = sum(fhmm_breakdown.values())

    if energy_goal > 0:
        cumulative_historical_load = await db.get_monthly_consumption(user_id, now.month, now.year)
        total_monthly_consumption = cumulative_historical_load + estimated_load

        if total_monthly_consumption > energy_goal:
            await db.send_fcm_notification(
                user_id,
                "Energy Budget Exceeded",
                f"Your monthly consumption ({total_monthly_consumption:.2f} kWh) has broken your budget goal of {energy_goal} kWh."
            )

    # Align peak usage with MCMC profile or decimated telemetry
    final_hourly = {}
    if hourly_context:
        # Scale the context profile to the current window load
        profile_total = sum(hourly_context.values())
        scale = (estimated_load / profile_total) if profile_total > 0 else 0
        final_hourly = {str(h): round(v * scale, 3) for h, v in hourly_context.items()}
    else:
        final_hourly = {str(current_hour): round(estimated_load, 2)}

    return {
        "userId": user_id,
        "month": now.month,
        "year": now.year,
        "estimated_load": round(estimated_load, 2),
        "breakdown": fhmm_breakdown,
        "anomalies": [],
        "hourlyUsage": final_hourly,
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
        
        return format_api_response(True, message="Daily sync complete", data=results['hourly_profile'])
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

@app.post("/api/v1/forecasts")
async def generate_energy_forecast(request: ForecastRequest, token: dict = Depends(verify_firebase_token)):
    is_staff = await db.get_user_role(token["uid"]) == 'staff'
    validate_user_ownership(request.user_id, token["uid"], is_staff=is_staff)

    user_id = request.user_id
    appliances = await db.get_user_appliances(user_id)
    
    logger.info(f"TRACE: Appliance count: {len(appliances) if appliances else 0}")

    if not appliances:
        raise HTTPException(status_code=400, detail="No active appliances registered for forecasting.")

    current_consumption = await db.get_monthly_consumption(user_id, request.target_month, request.target_year)
    logger.info(f"TRACE: Current consumption: {current_consumption}")

    try:
        sys_config = await db.get_system_config()
        if not sys_config.get("mcmc_enabled", True):
            raise Exception("MCMC disabled by feature flag")

        # Environmental Modulation
        env_context = await weather.get_contextual_data_async()
        sim_payload = request.model_dump()
        sim_payload.update(env_context) # Merge thermal data

        base_temp = 27.0
        temp_scalar = max(1.0, 1.0 + (env_context["temperature"] - base_temp) * 0.1)
        for app_id, profile in appliances.items():
            if str(profile.get('type', '')).title() == "Fan":
                profile["prob_day"] = min(0.99, float(profile.get("prob_day", 0.5)) * temp_scalar)
                profile["prob_night"] = min(0.99, float(profile.get("prob_night", 0.5)) * temp_scalar)

        forecast_result = await asyncio.wait_for(
            asyncio.to_thread(getattr(simulator, 'run_30_day_forecast', simulator.run_monte_carlo), appliances, sim_payload),
            timeout=8.0
        )
        logger.info(f"TRACE: MCMC raw output: {forecast_result}")
        
        projected_load = sum(float(val) for val in forecast_result.get('appliance_totals', {}).values())
        method_used = "mcmc_stochastic"

    except (asyncio.TimeoutError, Exception) as e:
        logger.warning(f"TRACE: MCMC aborted: {str(e)}")
        
        if current_consumption > 0:
            current_day = datetime.datetime.now(datetime.timezone.utc).day
            daily_average = current_consumption / max(1, current_day)
            projected_load = daily_average * request.days_to_predict
        else:
            projected_load = sum(float(app.get('wattage', 0)) / 1000.0 * 4.0 for app in appliances.values()) * request.days_to_predict

        method_used = "linear_heuristic"

    total_predicted = current_consumption + projected_load

    # Calculate remaining days in the month to prevent double counting
    now = datetime.datetime.now(datetime.timezone.utc)
    _, last_day = calendar.monthrange(request.target_year, request.target_month)
    remaining_days = max(0, last_day - now.day)
    
    # If we are in the target month, only predict for remaining days
    if now.month == request.target_month and now.year == request.target_year:
        scaling_ratio = remaining_days / request.days_to_predict
        projected_load = projected_load * scaling_ratio
        total_predicted = current_consumption + projected_load

    payload = {
        "userId": user_id,
        "targetMonth": request.target_month,
        "targetYear": request.target_year,
        "currentConsumption": round(current_consumption, 2),
        "projectedAddition": round(projected_load, 2),
        "estimatedEndOfMonthTotal": round(total_predicted, 2),
        "methodApplied": method_used,
        "timestamp": now.isoformat(),
        "mcmc_hourly_profile": forecast_result.get('hourly_profile', {}),
        "remaining_days": remaining_days
    }
    
    logger.info(f"TRACE: Final Payload: {payload}")

    return format_api_response(True, data=payload)

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
        
        # Determine temporal window
        is_night = False
        if request.timestamp:
            try:
                dt = datetime.datetime.fromisoformat(request.timestamp.replace('Z', '+00:00'))
                hour = dt.hour
                is_night = hour < 7 or hour > 19
            except ValueError:
                pass
                
        current_p = app_data.get('prob_night' if is_night else 'prob_day', 0.5)

        new_p = max(0.01, current_p - learning_rate) if is_false_positive else min(0.99, current_p + learning_rate)
        
        await db.update_single_appliance_prob(request.user_id, request.appliance_name, new_p, is_night)
        
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
                await asyncio.to_thread(batch.commit)
                batch = db.db.batch()
                write_count = 0
                
        if write_count > 0:
            await asyncio.to_thread(batch.commit)

        del df
        gc.collect()
        
        return format_api_response(True, message=f"Seeded REDD data for {request.user_id}.")
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Seeding failed: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))
    
