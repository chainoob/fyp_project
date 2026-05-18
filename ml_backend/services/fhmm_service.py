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
            if 'states' not in stats:
                AppLog.error("FHMM_INIT", f"Skipping {appliance}: Signature fields missing.")
                continue
                
            try:
                states_list = stats['states']
                n_states = len(states_list)
                std_dev = stats.get('std_dev', 1.0)
                
                # Developer Expectation: Instantiate GaussianHMM with N states defined by the signature.
                model = hmm.GaussianHMM(n_components=n_states, covariance_type="diag") 
                
                # Developer Expectation: Manually set HMM parameters for prediction-only mode.
                # Initialize start probabilities and transition matrices for a general N-state model.
                model.startprob_ = np.full(n_states, 1.0 / n_states)
                
                # Create a simple transition matrix: high probability of staying in the same state.
                trans_matrix = np.full((n_states, n_states), 0.1 / (n_states - 1))
                np.fill_diagonal(trans_matrix, 0.9)
                model.transmat_ = trans_matrix
                
                # Set means based on the signature states.
                model.means_ = np.array([[float(s)] for s in states_list])
                
                # Set covariances based on the signature std_dev.
                model.covars_ = np.array([[float(std_dev**2)] for _ in range(n_states)])
                
                models[appliance] = model
                AppLog.info("FHMM_INIT", f"Initialized {appliance} with {n_states} states (StdDev: {std_dev}W).")
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