# ml_backend/services/bayesian_adaptation.py

import os
import json
import numpy as np
from typing import Dict, Any, Tuple, List, Optional

def update_transitions(prior_matrix, observed_counts, alpha=5.0):
    # Stage 7 Dirichlet transition posterior update
    prior_counts = prior_matrix * alpha
    posterior = prior_counts + observed_counts
    return posterior / posterior.sum(axis=1, keepdims=True)

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

    def update_appliance_state(self, user_id: str, appliance_name: str, state_idx: int, observed_value: float, observed_variance: Optional[float] = None, num_samples: int = 1) -> Tuple[float, float]:
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
                "observed_variance": prior_variance,
                "sample_count": 0,
                "adapted_mean": prior_mean,
                "adapted_variance": prior_variance
            }
            
        entry = profile[appliance_name]["states"][state_key]
        n_prev = entry["sample_count"]
        n_new = num_samples
        n_total = n_prev + n_new
        
        if n_total > 0:
            old_mean = entry["observed_mean"]
            new_mean = (old_mean * n_prev + observed_value * n_new) / n_total
            
            if observed_variance is None:
                # Fallback to run-mean variance tracking
                if "observed_m2" not in entry:
                    entry["observed_m2"] = 0.0
                delta = observed_value - old_mean
                new_m2 = entry["observed_m2"] + delta * (observed_value - new_mean)
                entry["observed_m2"] = new_m2
                run_variance = new_m2 / n_total if n_total > 1 else 0.0
                obs_variance = max(run_variance, 25.0)
            else:
                if n_prev > 0:
                    prev_var = entry.get("observed_variance", prior_variance)
                    ss_prev = prev_var * n_prev
                    ss_new = observed_variance * n_new
                    group_delta = observed_value - old_mean
                    ss_between = (group_delta ** 2) * (n_prev * n_new) / n_total
                    obs_variance = (ss_prev + ss_new + ss_between) / n_total
                else:
                    obs_variance = observed_variance
        else:
            new_mean = prior_mean
            obs_variance = prior_variance
            
        obs_variance = max(obs_variance, 25.0)
        
        entry["sample_count"] = n_total
        entry["observed_mean"] = new_mean
        entry["observed_variance"] = obs_variance
        
        # Bayesian Conjugate update using equivalent sample size scaling
        kappa_0 = 50.0  # prior mean confidence weight
        nu_0 = 50.0     # prior variance confidence weight
        
        adapted_mean = (kappa_0 * prior_mean + n_total * new_mean) / (kappa_0 + n_total)
        adapted_variance = (nu_0 * prior_variance + n_total * obs_variance) / (nu_0 + n_total)
        
        # Phase 4 Variance Guardrail: prevent collapse below 25% prior or 25.0 absolute limit
        adapted_variance = max(adapted_variance, prior_variance * 0.25, 25.0)
        
        entry["adapted_mean"] = adapted_mean
        entry["adapted_variance"] = adapted_variance
        
        self.save_user_profile(user_id, profile)
        return adapted_mean, adapted_variance

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

    def update_appliance_transitions(self, user_id: str, appliance_name: str, observed_counts: np.ndarray, alpha: float = 5.0) -> np.ndarray:
        # Stage 7: Dirichlet transition posterior update
        profile = self.load_user_profile(user_id)
        signatures = self._load_signatures()
        
        if appliance_name not in signatures:
            raise ValueError(f"Unknown appliance: {appliance_name}")
            
        sig = signatures[appliance_name]
        prior_matrix = np.array(sig["transition_matrix"])
        
        observed_counts = np.array(observed_counts)
        if observed_counts.shape != prior_matrix.shape:
            raise ValueError(f"Observed counts shape {observed_counts.shape} does not match prior shape {prior_matrix.shape}")
            
        adapted_matrix = update_transitions(prior_matrix, observed_counts, alpha)
        
        if appliance_name not in profile:
            profile[appliance_name] = {}
            
        profile[appliance_name]["transition_matrix"] = adapted_matrix.tolist()
        self.save_user_profile(user_id, profile)
        return adapted_matrix

