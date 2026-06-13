import numpy as np
from scipy.optimize import minimize

class EnergyOptimizer:
    # Calibrates usage probabilities to align with billing ground truth.
    
    def _objective(self, weights, wattages, actual_total):
        # Expected: inputs are numpy arrays of equal length.
        estimate = np.sum(weights * wattages * 24) / 1000.0
        return np.abs(estimate - actual_total)

    def refine(self, appliances, actual_bill_monthly):
        # Optimization constrained to realistic probability bounds (0.01 - 0.99).
        app_list = list(appliances.values())
        if not app_list:
            return []

        # We are optimizing for a 30-day billing period.
        # Estimate = (Prob * Wattage * 24h * 30 days) / 1000
        wattages = np.array([float(a.get('wattage', 100.0)) for a in app_list])
        initial_weights = np.array([
            (float(a.get('prob_day', 0.1)) + float(a.get('prob_night', 0.1))) / 2 
            for a in app_list
        ])
        
        def objective(weights):
            # Monthly kWh estimate based on average daily probability
            estimate_monthly = np.sum(weights * wattages * 24 * 30) / 1000.0
            return np.abs(estimate_monthly - actual_bill_monthly)

        res = minimize(
            objective,
            x0=initial_weights,
            bounds=[(0.01, 0.95) for _ in app_list],
            method='SLSQP',
            options={'ftol': 1e-6}
        )
        
        return res.x.tolist()