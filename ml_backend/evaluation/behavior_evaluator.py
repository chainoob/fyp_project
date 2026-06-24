import os
import sys
import numpy as np
from typing import Dict, Any, List

# Align python path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from evaluation.experiment_tracker import ExperimentTracker

class BehaviorEvaluator:
    """Evaluates behavioral simulation models, tracking predicted runtime errors."""
    
    def __init__(self):
        self.tracker = ExperimentTracker()

    def evaluate(self, actual_runtimes: Dict[str, float], simulated_runtimes: Dict[str, float], experiment_name: str = "behavior_eval") -> Dict[str, Any]:
        """Calculates runtime error per appliance and overall, then logs the experiment."""
        errors = {}
        total_actual = 0.0
        total_error = 0.0
        
        for app, actual in actual_runtimes.items():
            simulated = simulated_runtimes.get(app, 0.0)
            diff = abs(simulated - actual)
            rel_error = diff / actual if actual > 0.0 else (0.0 if simulated == 0.0 else 1.0)
            errors[f"{app}_runtime_error"] = round(rel_error, 4)
            
            total_actual += actual
            total_error += diff
            
        overall_error = total_error / total_actual if total_actual > 0.0 else 0.0
        errors["overall_runtime_error"] = round(overall_error, 4)
        
        self.tracker.log_experiment(experiment_name, "Behavioral_Simulation", errors)
        return errors
