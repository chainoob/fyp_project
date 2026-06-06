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
    
import numpy as np

async def apply_adaptive_hybrid_logic(db, user_id, appliance_name, manual_overrides, network_states, fhmm_predictions, registered_types, current_hour):
    # High-level: Executes 3-Tier Hybrid Logic with dynamic adaptive ToD weighting.
    key = appliance_name.lower()
    final_state = None
    
    if key in manual_overrides:
        final_state = manual_overrides[key]
        # Ensure log_manual_override is either awaited if async, or executed synchronously if not
        log_manual_override(db, user_id, key, final_state) 
    elif key in network_states:
        final_state = network_states[key]

    # Extract raw predictions, defaulting to an empty list
    power_series_raw = fhmm_predictions.get(key, [])
    
    # Normalize inputs to a 1D array to prevent scalar float iteration crashes
    power_series = np.atleast_1d(power_series_raw)
    
    # Execute extraction using array properties
    instantaneous_wattage = float(np.mean(power_series)) if power_series.size > 0 else 0.0
    kwh_value = round(float(np.sum(power_series)) / 1000.0, 3)

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

def run_30_day_forecast(self, appliances: dict, request_data: dict) -> dict:
        """
        Executes a localized Markov Chain Monte Carlo (MCMC) forecast utilizing 
        temporal probability profiles (prob_day, prob_night) over a 30-day projection matrix.
        """
        days_to_predict = request_data.get('days_to_predict', 30)
        total_projected_kwh = 0.0

        for _ in range(days_to_predict):
            for hour in range(24):
                for app_id, app_data in appliances.items():
                    # Apply temporal bounding matrix
                    is_daytime = 6 <= hour <= 18
                    base_prob = float(app_data.get('prob_day', 0.2)) if is_daytime else float(app_data.get('prob_night', 0.05))
                    
                    # Execute stochastic state transition
                    if random.random() < base_prob:
                        wattage = float(app_data.get('wattage', 0))
                        total_projected_kwh += (wattage / 1000.0)

        return {"total_projected_kwh": round(total_projected_kwh, 2)}