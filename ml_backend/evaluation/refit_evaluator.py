import os
import sys
from typing import Dict, Any

# Align python path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from services.fhmm_service import FHMMService
from evaluation.cross_dataset import CrossDatasetEvaluator
from evaluation.experiment_tracker import ExperimentTracker

class REFITEvaluator:
    """Specialized evaluation runner for the REFIT dataset structure."""
    
    def __init__(self, fhmm_service: FHMMService, target_frequency: str = '6s'):
        self.evaluator = CrossDatasetEvaluator(fhmm_service, target_frequency=target_frequency)
        self.tracker = ExperimentTracker()

    def evaluate(self, csv_path: str, label_mapping: Dict[str, str], experiment_name: str = "refit_eval") -> Dict[str, Any]:
        """Runs evaluation using a consolidated CSV file."""
        results = self.evaluator.evaluate_consolidated(csv_path, label_mapping)
        
        # Flatten metrics for logging
        flat_metrics = {}
        for app, metrics in results.items():
            for metric_name, val in metrics.items():
                flat_metrics[f"{app}_{metric_name}"] = val
                
        self.tracker.log_experiment(experiment_name, "REFIT", flat_metrics)
        return results
