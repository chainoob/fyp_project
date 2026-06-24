# ml_backend/services/bayesian_adaptation.py

import os
import json
import numpy as np
from typing import Dict, Any, Tuple, List

class BayesianAdaptationService:
    # High-level: Manages Bayesian signature adaptation for user appliance profiles.
    
    def __init__(self, profiles_dir: str = None, signatures_path: str = None):
        if profiles_dir is None:
            profiles_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "data", "user_profiles"))
        if signatures_path is None:
            signatures_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "data", "appliance_signatures.json"))
            
        self.profiles_dir = profiles_dir
        self.signatures_path = signatures_path
        os.makedirs(profiles_dir, exist_ok=True)
        
    def _load_signatures(self) -> Dict[str, Any]:
        with open(self.signatures_path, 'r') as f:
            return json.load(f)

    def load_user_profile(self, user_id: str) -> Dict[str, Any]:
        path = os.path.join(self.profiles_dir, f"{user_id}.json")
        if os.path.exists(path):
            try:
                with open(path, 'r') as f:
                    return json.load(f)
            except Exception:
                return {}
        return {}

    def save_user_profile(self, user_id: str, profile: Dict[str, Any]) -> None:
        path = os.path.join(self.profiles_dir, f"{user_id}.json")
        with open(path, 'w') as f:
            json.dump(profile, f, indent=2)

    def update_appliance_state(self, user_id: str, appliance_name: str, state_idx: int, observed_value: float) -> Tuple[float, float]:
        profile = self.load_user_profile(user_id)
        signatures = self._load_signatures()
        
        if appliance_name not in signatures:
            raise ValueError(f"Unknown appliance: {appliance_name}")
            
        sig = signatures[appliance_name]
        means = sig.get("means", sig.get("states", []))
        covars = sig.get("covariances", [sig.get("std_dev", 1.0)**2] * len(means))
        
        if state_idx >= len(means):
            raise ValueError(f"State index {state_idx} out of bounds for {appliance_name}")
            
        prior_mean = float(means[state_idx])
        prior_variance = float(covars[state_idx])
        
        if appliance_name not in profile:
            profile[appliance_name] = {}
        if "states" not in profile[appliance_name]:
            profile[appliance_name]["states"] = {}
            
        state_key = str(state_idx)
        if state_key not in profile[appliance_name]["states"]:
            profile[appliance_name]["states"][state_key] = {
                "prior_mean": prior_mean,
                "prior_variance": prior_variance,
                "observed_mean": 0.0,
                "observed_m2": 0.0,
                "sample_count": 0,
                "adapted_mean": prior_mean,
                "adapted_variance": prior_variance
            }
            
        entry = profile[appliance_name]["states"][state_key]
        n = entry["sample_count"] + 1
        old_mean = entry["observed_mean"]
        
        delta = observed_value - old_mean
        new_mean = old_mean + delta / n
        delta2 = observed_value - new_mean
        new_m2 = entry["observed_m2"] + delta * delta2
        
        observed_variance = new_m2 / n if n > 0 else 0.0
        observed_variance = max(observed_variance, 0.1)
        
        prior_precision = 1.0 / prior_variance
        observed_precision = 1.0 / observed_variance
        
        post_precision = prior_precision + n * observed_precision
        post_variance = 1.0 / post_precision
        post_mean = (prior_mean * prior_precision + n * new_mean * observed_precision) / post_precision
        
        entry["sample_count"] = n
        entry["observed_mean"] = new_mean
        entry["observed_m2"] = new_m2
        entry["observed_variance"] = observed_variance
        entry["adapted_mean"] = post_mean
        entry["adapted_variance"] = post_variance
        
        self.save_user_profile(user_id, profile)
        return post_mean, post_variance

    def update_appliance_statistics(self, user_id: str, appliance_name: str, active_hours: List[int], daily_runtime: float) -> None:
        # High-level: Updates user-specific usage statistics (mean_power, variance, runtime_distribution, activation_hours).
        profile = self.load_user_profile(user_id)
        
        if appliance_name not in profile:
            profile[appliance_name] = {}
            
        if "statistics" not in profile[appliance_name]:
            profile[appliance_name]["statistics"] = {
                "mean_power": 0.0,
                "variance": 0.0,
                "runtime_distribution": {},
                "activation_hours": []
            }
            
        stats = profile[appliance_name]["statistics"]
        
        states_profile = profile[appliance_name].get("states", {})
        highest_state_key = max(states_profile.keys(), key=int, default="0")
        if highest_state_key != "0":
            state_data = states_profile[highest_state_key]
            stats["mean_power"] = round(state_data.get("adapted_mean", 0.0), 2)
            stats["variance"] = round(state_data.get("adapted_variance", 0.0), 2)
            
        bucket = str(round(daily_runtime * 2) / 2)
        dist = stats["runtime_distribution"]
        dist[bucket] = dist.get(bucket, 0) + 1
        
        existing_hours = set(stats["activation_hours"])
        existing_hours.update(active_hours)
        stats["activation_hours"] = sorted(list(existing_hours))
        
        self.save_user_profile(user_id, profile)
