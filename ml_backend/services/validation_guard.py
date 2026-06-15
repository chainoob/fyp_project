import datetime
import calendar
import os
import logging
import asyncio
from google.cloud import firestore as gcp_firestore

logger = logging.getLogger(__name__)

DEFAULT_MAX_DURATIONS = {
    "kettle": 0.5,
    "iron": 1.0,
    "laptop": 8.0,
    "charger": 8.0,
    "fan": 12.0,
    "lamp": 12.0,
    "light": 12.0,
    "printer": 1.0,
}

def to_datetime_utc(val):
    if val is None:
        return None
    if isinstance(val, datetime.datetime):
        if val.tzinfo is None:
            return val.replace(tzinfo=datetime.timezone.utc)
        return val.astimezone(datetime.timezone.utc)
    
    # Check for Firestore Timestamp
    if hasattr(val, 'to_pydatetime'):
        py_dt = val.to_pydatetime()
        if py_dt.tzinfo is None:
            return py_dt.replace(tzinfo=datetime.timezone.utc)
        return py_dt.astimezone(datetime.timezone.utc)

    # String conversion fallback
    try:
        dt = datetime.datetime.fromisoformat(str(val).replace('Z', '+00:00'))
        return dt.astimezone(datetime.timezone.utc)
    except Exception:
        return val

async def get_all_tod_probabilities(db, user_id: str, appliance: str) -> dict[int, float]:
    """
    Fetches all 24 hourly ToD probabilities for a given user and appliance in a single database sweep.
    """
    try:
        docs = await asyncio.to_thread(
            lambda: list(db.db.collection('behavioral_logs') \
                .where('userId', '==', user_id) \
                .where('appliance', '==', appliance.lower()) \
                .stream())
        )
        probs = {h: 0.0 for h in range(24)}
        if not docs:
            return probs
            
        logs = [doc.to_dict() for doc in docs]
        hour_counts = {}
        hour_ons = {}
        for log in logs:
            h = log.get('hour')
            if h is not None:
                h = int(h)
                hour_counts[h] = hour_counts.get(h, 0) + 1
                if log.get('state') == 1.0:
                    hour_ons[h] = hour_ons.get(h, 0) + 1
                    
        for h in range(24):
            if h in hour_counts and hour_counts[h] > 0:
                probs[h] = hour_ons.get(h, 0) / hour_counts[h]
        return probs
    except Exception as e:
        logger.error(f"Failed to fetch all ToD probabilities (Soft-fail isolated): {e}", exc_info=True)
        return {h: 0.0 for h in range(24)}

async def sweep_and_load_sessions(db, user_ids: list[str], month: int, year: int) -> list[dict]:
    """
    Streams usage sessions from Firestore and applies safety ceilings (Dead-man's switch).
    Returns a cleaned list of session dictionaries.
    """
    try:
        now = datetime.datetime.now(datetime.timezone.utc)
        start_date = datetime.datetime(year, month, 1, tzinfo=datetime.timezone.utc)
        _, last_day = calendar.monthrange(year, month)
        end_date = datetime.datetime(year, month, last_day, 23, 59, 59, tzinfo=datetime.timezone.utc)
        
        # Load system configuration dynamically to override default limits
        sys_config = await db.get_system_config()
        db_max_durations = sys_config.get("max_durations", {})
        
        max_durations = {k.lower().strip(): float(v) for k, v in DEFAULT_MAX_DURATIONS.items()}
        for k, v in db_max_durations.items():
            max_durations[k.lower().strip()] = float(v)
            
        valid_sessions = []
        
        for uid in user_ids:
            registered_appliances = await db.get_user_appliances(uid) or {}
            
            # Map custom names to generic types, wattages, and individual limits
            wattage_lookup = {}
            type_lookup = {}
            app_limit_lookup = {}
            for app_id, app_data in registered_appliances.items():
                name_key = app_data.get('name', '').lower().strip()
                wattage_lookup[name_key] = float(app_data.get('wattage', 0.0))
                type_lookup[name_key] = app_data.get('type', 'fan').lower().strip()
                
                # Check for dynamic appliance-specific limits
                if 'max_duration' in app_data:
                    app_limit_lookup[name_key] = float(app_data['max_duration'])
                elif 'ttl' in app_data:
                    app_limit_lookup[name_key] = float(app_data['ttl'])
                
            sessions_ref = db.db.collection('users').document(uid).collection('usage_sessions')
            query = sessions_ref.where(filter=gcp_firestore.FieldFilter('start_time', '>=', start_date)) \
                                .where(filter=gcp_firestore.FieldFilter('start_time', '<=', end_date))
            
            docs = await asyncio.to_thread(lambda: list(query.stream()))
            
            user_app_probs = {}
            
            for doc in docs:
                doc_id = doc.id
                session_data = doc.to_dict()
                
                appliance_name = session_data.get('appliance', '').lower().strip()
                app_type = type_lookup.get(appliance_name, session_data.get('type', 'fan').lower().strip())
                wattage = wattage_lookup.get(appliance_name, 0.0)
                
                start_time = to_datetime_utc(session_data.get('start_time'))
                end_time = to_datetime_utc(session_data.get('end_time'))
                auto_cutoff = session_data.get('auto_cutoff', False)
                
                if start_time is None:
                    continue

                # Fetch ToD probabilities
                cache_key = (uid, appliance_name)
                if cache_key not in user_app_probs:
                    user_app_probs[cache_key] = await get_all_tod_probabilities(db, uid, appliance_name)
                tod_probs = user_app_probs[cache_key]

                # Clamp open sessions violating generic runtime ceilings
                if end_time is None:
                    elapsed = (now - start_time).total_seconds() / 3600.0
                    base_ceiling = app_limit_lookup.get(appliance_name, max_durations.get(app_type, 12.0))
                    
                    tod_prob_now = tod_probs.get(now.hour, 0.0)
                    # Dynamically scale the ceiling based on ToD probability
                    ceiling = base_ceiling * (0.5 + tod_prob_now)
                    
                    if elapsed > ceiling:
                        end_time = start_time + datetime.timedelta(hours=ceiling)
                        auto_cutoff = True
                        
                        await asyncio.to_thread(
                            sessions_ref.document(doc_id).update,
                            {
                                'end_time': end_time,
                                'auto_cutoff': True
                            }
                        )
                        logger.warning(f"Validation Guard: Auto-cutoff activated for {doc_id} ({app_type}) - Capped at {ceiling} hrs.")
                    else:
                        end_time = now
                        
                valid_sessions.append({
                    'doc_id': doc_id,
                    'user_id': uid,
                    'appliance': appliance_name,
                    'type': app_type,
                    'wattage': wattage,
                    'start_time': start_time,
                    'end_time': end_time,
                    'auto_cutoff': auto_cutoff,
                    'tod_probs': tod_probs
                })
                
        return valid_sessions
    except Exception as e:
        logger.error(f"Validation Guard failure (Soft-fail isolated): {e}", exc_info=True)
        return []

def compute_deterministic_load_matrix(sessions: list[dict], month: int, year: int) -> dict:
    """
    Converts session periods to hourly kWh loads with Cm confidence decay.
    """
    try:
        _, last_day = calendar.monthrange(year, month)
        total_hours = last_day * 24
        
        target_types = ["fan", "laptop", "charger", "lamp", "iron", "kettle", "printer"]
        matrix = {t: [0.0] * total_hours for t in target_types}
        
        start_month_dt = datetime.datetime(year, month, 1, tzinfo=datetime.timezone.utc)
        
        for session in sessions:
            app_type = session['type'].lower()
            if app_type not in matrix:
                matrix[app_type] = [0.0] * total_hours
                
            wattage = session['wattage']
            start_time = to_datetime_utc(session['start_time'])
            end_time = to_datetime_utc(session['end_time'])
            
            for hour_idx in range(total_hours):
                hour_start = start_month_dt + datetime.timedelta(hours=hour_idx)
                hour_end = hour_start + datetime.timedelta(hours=1)
                
                overlap_start = max(start_time, hour_start)
                overlap_end = min(end_time, hour_end)
                
                if overlap_start < overlap_end:
                    overlap_duration_hr = (overlap_end - overlap_start).total_seconds() / 3600.0
                    
                    elapsed_hours = max(0.0, (hour_start - start_time).total_seconds() / 3600.0)
                    hour_of_day = hour_start.hour
                    tod_prob = session.get('tod_probs', {}).get(hour_of_day, 0.0)
                    
                    decay_factor = 0.1 * (1.0 - tod_prob)
                    C_m = max(0.0, 0.95 - decay_factor * elapsed_hours)
                    
                    kwh = (wattage * overlap_duration_hr * C_m) / 1000.0
                    matrix[app_type][hour_idx] += kwh
                    
        return matrix
    except Exception as e:
        logger.error(f"Load matrix calculation failed (Soft-fail isolated): {e}", exc_info=True)
        return {}

def get_active_manual_wattage(sessions: list[dict], t: datetime.datetime) -> float:
    """
    Calculates active manual override load at timestamp t with Cm confidence decay.
    """
    try:
        t_utc = to_datetime_utc(t)
        total_w = 0.0
        for s in sessions:
            s_start = to_datetime_utc(s['start_time'])
            s_end = to_datetime_utc(s['end_time'])
            if s_start <= t_utc <= s_end:
                elapsed_hours = max(0.0, (t_utc - s_start).total_seconds() / 3600.0)
                hour_of_day = t_utc.hour
                tod_prob = s.get('tod_probs', {}).get(hour_of_day, 0.0)
                
                decay_factor = 0.1 * (1.0 - tod_prob)
                C_m = max(0.0, 0.95 - decay_factor * elapsed_hours)
                
                total_w += s['wattage'] * C_m
        return total_w
    except Exception as e:
        logger.error(f"Active manual wattage calculation failed (Soft-fail isolated): {e}", exc_info=True)
        return 0.0
