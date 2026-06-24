import os
import sys
import numpy as np
from typing import Dict, Any, List

# Align python path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from evaluation.metrics import calculate_mae, calculate_rmse, calculate_mape
from evaluation.experiment_tracker import ExperimentTracker

class ForecastEvaluator:
    """Evaluates the energy forecasting performance against ground truth consumption."""
    
    def __init__(self):
        self.tracker = ExperimentTracker()

    def evaluate(self, y_true: List[float], y_pred: List[float], experiment_name: str = "forecast_eval") -> Dict[str, float]:
        """Calculates forecasting metrics (MAE, RMSE, MAPE) and logs to experiment tracker."""
        arr_true = np.array(y_true)
        arr_pred = np.array(y_pred)
        
        metrics = {
            "MAE": round(calculate_mae(arr_true, arr_pred), 4),
            "RMSE": round(calculate_rmse(arr_true, arr_pred), 4),
            "MAPE": round(calculate_mape(arr_true, arr_pred), 4)
        }
        
        self.tracker.log_experiment(experiment_name, "Forecast", metrics)
        return metrics
