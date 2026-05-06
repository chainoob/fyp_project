import numpy as np
from scipy.optimize import minimize

class EnergyOptimizer:
    # Calibrates usage probabilities to align with billing ground truth.
    
    def _objective(self, weights, wattages, actual_total):
        # Expected: inputs are numpy arrays of equal length.
        estimate = np.sum(weights * wattages * 24) / 1000.0
        return np.abs(estimate - actual_total)

    def refine(self, appliances, actual_bill):
        # Optimization constrained to realistic probability bounds (0.01 - 0.99).
        wattages = np.array([a['wattage'] for a in appliances])
        initial_weights = np.array([(a['prob_day'] + a['prob_night']) / 2 for a in appliances])
        
        res = minimize(
            self._objective,
            x0=initial_weights,
            args=(wattages, actual_bill),
            bounds=[(0.01, 0.99) for _ in appliances],
            method='SLSQP'
        )
        return res.x