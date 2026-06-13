# ml_backend/services/fhmm_service.py

import os
import json
import numpy as np
from hmmlearn import hmm
from utils.logger import AppLog

class FHMMService:
    # High-level: Implements additive disaggregation via sequential subtractive Viterbi decoding.

    def __init__(self, signatures_path="data/appliance_signatures.json"):
        if not os.path.exists(signatures_path):
            raise FileNotFoundError(f"Signature resource blueprint missing at: {signatures_path}")
            
        self.signatures = self._load_signatures(signatures_path)
        
        # High-level: Routes execution path to parse structural states and instantiate model boundaries.
        self.models = self._initialize_models()

    def _load_signatures(self, path):
        # High-level: Parses pre-trained Gaussian Mixture HMM signatures from JSON storage blocks.
        try:
            with open(path, 'r') as f:
                return json.load(f)
        except Exception as e:
            AppLog.error("Signature Parser Structural Failure", str(e))
            raise RuntimeError(f"Failed to load required model payload templates: {str(e)}")

    def _initialize_models(self):
        models = {}
        target_appliances = ["Fan", "Laptop", "Charger", "Lamp", "Iron", "Kettle", "Printer"]
        
        # High-level: Parse signature configurations to initialize underlying FHMM components.
        for appliance in target_appliances:
            if appliance not in self.signatures:
                AppLog.warning(f"Signature configuration skipped: {appliance} not found in blueprint JSON file.")
                continue
                
            stats = self.signatures[appliance]
            if 'states' not in stats and 'means' not in stats:
                AppLog.error("FHMM_INIT", f"Skipping {appliance}: Signature matrix profiles missing.")
                continue
                
            try:
                # Developer Expectation: Pull state keys from pre-trained tracking blocks or fall back to signature definitions.
                means_source = stats.get('means', stats.get('states', []))
                n_states = len(means_source)
                
                # Developer Expectation: Instantiate GaussianHMM with N states using diagonal matrices to prevent execution skew.
                model = hmm.GaussianHMM(n_components=n_states, covariance_type="diag") 
                
                # Developer Expectation: Explicitly map trained emission values, transition matrices, and initial distributions.
                if 'transition_matrix' in stats:
                    model.startprob_ = np.array(stats['start_probabilities'])
                    model.transmat_ = np.array(stats['transition_matrix'])
                    model.means_ = np.array(means_source).reshape(-1, 1)
                    model.covars_ = np.array(stats['covariances']).reshape(-1, 1)
                else:
                    # Developer Expectation: ck heuristic structural generation block for simplified signatures.
                    std_dev = stats.get('std_dev', 1.0)
                    model.startprob_ = np.full(n_states, 1.0 / n_states)
                    
                    max_dur = stats.get('max_duration_hr', 12.0)
                    trans_prob = min(0.9, 1.0 / max_dur) if max_dur > 0 else 0.9
                    stay_prob = 1.0 - trans_prob
                    
                    trans_matrix = np.full((n_states, n_states), trans_prob / (n_states - 1))
                    np.fill_diagonal(trans_matrix, stay_prob)
                    model.transmat_ = trans_matrix
                    
                    model.means_ = np.array([[float(s)] for s in means_source])
                    model.covars_ = np.array([[float(std_dev**2)] for _ in range(n_states)])
                
                models[appliance] = model
                AppLog.info("FHMM_INIT", f"Successfully bounded sequence model layer for: {appliance}")
                
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
        residual_signal = observations.copy()

        # Developer Expectation: Sort appliances descending by typical power variance to decode large loads first.
        sorted_appliances = sorted(
            self.models.items(), 
            key=lambda x: float(np.max(x[1].means_)) if hasattr(x[1], 'means_') else 0, 
            reverse=True
        )

        for name, model in sorted_appliances:
            try:
                # Developer Expectation: Run Viterbi decoding against the remaining signal fraction to enforce model separation.
                states = model.predict(residual_signal)
                predicted_trace = [float(model.means_[s][0]) for s in states]
                
                disaggregated_data[name] = predicted_trace
                
                # Developer Expectation: Strip decoded active work from the residual matrix before the next iteration.
                predicted_vector = np.array(predicted_trace).reshape(-1, 1)
                residual_signal = np.clip(residual_signal - predicted_vector, a_min=0.0, a_max=None)
                
            except Exception as e:
                AppLog.error(f"Disaggregation Failure: {name}", str(e))
                disaggregated_data[name] = [0.0] * len(aggregate_signal)

        return disaggregated_data