# ml_backend/services/fhmm_service.py

import numpy as np
import json
from hmmlearn import hmm

from ml_backend.utils.logger import AppLog

class FHMMService:
    # High-level: Implements additive disaggregation via parallel Viterbi path decoding.

    def __init__(self, signatures_path="data/signatures.json"):
        # Developer Expectation: Signatures must be pre-scaled to student wattages before init.
        try:
            with open(signatures_path, 'r') as f:
                self.signatures = json.load(f)
        except FileNotFoundError:
            AppLog.error("FHMM Init", "signatures.json missing")
            self.signatures = {}
            
        self.models = self._initialize_models()

    def _initialize_models(self):
        # High-level: Configures Gaussian HMM parameters for binary ON/OFF states.
        models = {}
        for name, stats in self.signatures.items():
            # Developer Expectation: Use diagonal covariance to simplify matrix operations.
            model = hmm.GaussianHMM(n_components=2, covariance_type="diag", n_iter=100)
            
            # Developer Expectation: Standardize 95/5 start probability for stable convergence.
            model.startprob_ = np.array([0.95, 0.05])
            model.transmat_ = np.array([[0.99, 0.01], [0.05, 0.95]])
            model.means_ = np.array([[0.0], [stats['mean']]])
            model.covars_ = np.array([[1.0], [stats['variance']]])
            
            models[name] = model
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
                states = model.predict(observations)
                disaggregated_data[name] = [float(model.means_[s][0]) for s in states]
            except Exception as e:
                AppLog.error(f"Disaggregation Failure: {name}", str(e))
                disaggregated_data[name] = [0.0] * len(aggregate_signal)

        return disaggregated_data