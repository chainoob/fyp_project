import numpy as np
import datetime

def log_manual_override(db, user_id: str, appliance: str, state: float):
    # High-level: Records user overrides into a dedicated collection for temporal learning.
    now = datetime.datetime.now(datetime.timezone.utc)
    db.db.collection('behavioral_logs').add({
        'userId': user_id,
        'appliance': appliance.lower(),
        'state': state,
        'hour': now.hour,
        'timestamp': now.isoformat()
    })

def get_tod_probability(db, user_id: str, appliance: str, current_hour: int) -> float:
    # High-level: Calculates the historical probability of an appliance being active at a given hour.
    try:
        docs = db.db.collection('behavioral_logs') \
            .where('userId', '==', user_id) \
            .where('appliance', '==', appliance.lower()) \
            .where('hour', '==', current_hour) \
            .stream()
            
        logs = [doc.to_dict() for doc in docs]
        if not logs:
            return 0.0
            
        on_count = sum(1 for log in logs if log.get('state') == 1.0)
        return on_count / len(logs)
    except Exception:
        return 0.0
    
def apply_adaptive_hybrid_logic(db, user_id, appliance_name, manual_overrides, network_states, fhmm_predictions, registered_types, current_hour):
    # High-level: Executes 3-Tier Hybrid Logic with dynamic adaptive ToD weighting.
    key = appliance_name.lower()
    final_state = None
    
    if key in manual_overrides:
        final_state = manual_overrides[key]
        log_manual_override(db, user_id, key, final_state)
    elif key in network_states:
        final_state = network_states[key]

    power_series = fhmm_predictions.get(key, [])
    instantaneous_wattage = float(np.mean(power_series)) if len(power_series) > 0 else 0.0
    kwh_value = round(sum(power_series) / 1000.0, 3)

    if final_state is not None:
        if final_state == 0.0:
            return 0.0
        elif final_state == 1.0 and instantaneous_wattage < 5.0:
            return round(45.0 / 1000.0, 3) if key == "laptop" else round(50.0 / 1000.0, 3)

    tod_prob = get_tod_probability(db, user_id, key, current_hour)
    
    # Developer Expectation: Lower detection threshold if historical ToD probability exceeds 60%.
    if tod_prob > 0.6 and key in registered_types:
        if kwh_value == 0.0:
             return round(45.0 / 1000.0, 3) if key == "laptop" else round(50.0 / 1000.0, 3)
        return kwh_value

    if key in registered_types or kwh_value > 0.0:
        return kwh_value
        
    return 0.0