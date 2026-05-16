# ml_backend/services/fhmm_service.py

import numpy as np
import json
from hmmlearn import hmm
from utils.logger import AppLog

class FHMMService:
    # High-level: Implements additive disaggregation via parallel Viterbi path decoding.

    def __init__(self, signatures_path="data/appliance_signatures.json"):
        # High-level: Load device signatures and bootstrap the HMM models.
        self.signatures = self._load_signatures(signatures_path)
        self.models = self._initialize_models()

    def _load_signatures(self, path: str) -> dict:
        # High-level: Reads the appliance signature JSON file from disk.
        try:
            with open(path, 'r') as f:
                data = json.load(f)
                AppLog.info("FHMM_INIT", f"Successfully loaded signatures from {path}")
                return data
        except FileNotFoundError:
            AppLog.error("FHMM_INIT", f"Signature file not found at path: {path}")
            return {}
        except json.JSONDecodeError:
            AppLog.error("FHMM_INIT", f"Malformed JSON in signature file: {path}")
            return {}

    def _initialize_models(self):
        models = {}
        # High-level: Parse signature configurations to initialize underlying FHMM components.
        for appliance, stats in self.signatures.items():
            if 'states' not in stats or 'max_state_index' not in stats:
                AppLog.error("FHMM_INIT", f"Skipping {appliance}: Signature fields missing.")
                continue
                
            try:
                states_list = stats['states']
                max_idx = stats['max_state_index']
                operational_mean = states_list[max_idx]
                
                # Developer Expectation: Instantiate GaussianHMM with 2 states (OFF/ON).
                model = hmm.GaussianHMM(n_components=2, covariance_type="diag") 
                
                # Developer Expectation: Manually set HMM parameters for prediction-only mode.
                model.startprob_ = np.array([0.5, 0.5])
                model.transmat_ = np.array([[0.9, 0.1], [0.1, 0.9]])
                model.means_ = np.array([[0.0], [float(operational_mean)]])
                model.covars_ = np.array([[1.0], [1.0]]) # Small variance for stable decoding.
                
                models[appliance] = model
                AppLog.info("FHMM_INIT", f"Initialized {appliance} at {operational_mean}W.")
            except Exception as e:
                AppLog.error("FHMM_INIT", f"Failed to compile model matrices for {appliance}: {str(e)}")
                
        return models    
    
    def disaggregate(self, aggregate_signal):
        # High-level: Decodes aggregate wattage into independent appliance power traces.
        if not aggregate_signal:
            return {}

        # Developer Expectation: Input must be a 1D list of floating point values.
        observations = np.array(aggregate_signal).reshape(-1, 1)
        disaggregated_data = {}

        for name, model in self.models.items():
            try:
                # Developer Expectation: Viterbi decoding to find the most likely state sequence.
                states = model.predict(observations)
                disaggregated_data[name] = [float(model.means_[s][0]) for s in states]
            except Exception as e:
                AppLog.error(f"Disaggregation Failure: {name}", str(e))
                disaggregated_data[name] = [0.0] * len(aggregate_signal)

        return disaggregated_data