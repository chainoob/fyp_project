# ml_backend/services/optimizer.py

import os
import json
import numpy as np
from scipy.optimize import minimize
from typing import Dict, List, Any

class EnergyOptimizer:
    # High-level: Calibrates daily runtimes using regularized SLSQP optimization.

    def __init__(self, signatures_path: str = None):
        if signatures_path is None:
            signatures_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "data", "appliance_signatures.json"))
        self.signatures_path = signatures_path
        self.signatures = self._load_signatures()

    def _load_signatures(self) -> Dict:
        if os.path.exists(self.signatures_path):
            try:
                with open(self.signatures_path, 'r') as f:
                    return json.load(f)
            except Exception:
                return {}
        return {}

    def refine(self, appliances: Dict[str, Any], actual_bill_monthly: float) -> List[float]:
        app_list = list(appliances.values())
        if not app_list:
            return []

        wattages = np.array([float(a.get('wattage', 100.0)) for a in app_list])
        
        # Historical runtimes in hours/day derived from initial average probabilities
        historical_runtimes = np.array([
            24.0 * (float(a.get('prob_day', 0.1)) + float(a.get('prob_night', 0.1))) / 2.0
            for a in app_list
        ])
        
        # Formulate bounds based on learned appliance signatures
        bounds = []
        for a in app_list:
            app_type = a.get('type', 'Unknown').capitalize()
            stats = self.signatures.get(app_type, {})
            # Fallback to 24.0 if signature limit is not defined
            limit = stats.get("max_duration_hr", 24.0)
            bounds.append((0.01, float(limit)))

        # SLSQP objective function: relative energy error + regularized runtime deviation
        def objective(x: np.ndarray) -> float:
            estimate_monthly = np.sum(x * wattages * 30) / 1000.0
            energy_error = ((estimate_monthly - actual_bill_monthly) / max(1.0, actual_bill_monthly)) ** 2
            
            # Runtime deviation regularization (scale-invariant)
            lambda_reg = 0.1
            runtime_dev = lambda_reg * np.sum(((x - historical_runtimes) / (historical_runtimes + 0.1)) ** 2)
            
            return float(energy_error + runtime_dev)

        res = minimize(
            objective,
            x0=historical_runtimes,
            bounds=bounds,
            method='SLSQP',
            options={'ftol': 1e-6}
        )
        
        # Map optimized daily runtime hours back to average probabilities
        optimized_runtimes = res.x
        optimized_probs = optimized_runtimes / 24.0
        
        # Clip to ensure valid probability bounds
        clipped_probs = np.clip(optimized_probs, 0.01, 0.99)
        return clipped_probs.tolist()