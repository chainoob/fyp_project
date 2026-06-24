import os
import json
from typing import Dict, Any

class ExperimentTracker:
    """Manages recording and persistence of model evaluation experiments."""
    
    def __init__(self, filepath: str = None):
        if filepath is None:
            filepath = os.path.abspath(os.path.join(os.path.dirname(__file__), 'experiments.json'))
        self.filepath = filepath

    def log_experiment(self, experiment: str, dataset: str, metrics: Dict[str, Any]) -> None:
        """Appends an experiment record to the JSON log file."""
        record = {
            "experiment": experiment,
            "dataset": dataset,
            **metrics
        }
        
        records = []
        if os.path.exists(self.filepath):
            try:
                with open(self.filepath, 'r') as f:
                    records = json.load(f)
                    if not isinstance(records, list):
                        records = []
            except Exception:
                records = []
                
        records.append(record)
        
        with open(self.filepath, 'w') as f:
            json.dump(records, f, indent=2)
