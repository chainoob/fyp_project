# ml_backend/services/fhmm_service.py

import os
import json
import numpy as np
from hmmlearn import hmm
from utils.logger import AppLog
from typing import Dict, List, Optional

class FHMMService:
    # High-level: Implements additive disaggregation via joint beam search decoding.

    def __init__(self, signatures_path: str = "data/appliance_signatures.json"):
        if not os.path.exists(signatures_path):
            raise FileNotFoundError(f"Signature resource blueprint missing at: {signatures_path}")
            
        self.signatures = self._load_signatures(signatures_path)
        self.models = self._initialize_models()

    def _load_signatures(self, path: str) -> Dict:
        # High-level: Parses pre-trained HMM signatures from JSON storage.
        try:
            with open(path, 'r') as f:
                return json.load(f)
        except Exception as e:
            AppLog.error("Signature Parser Structural Failure", str(e))
            raise RuntimeError(f"Failed to load required model payload templates: {str(e)}")

    def _initialize_models(self) -> Dict:
        models = {}
        target_appliances = ["Fan", "Laptop", "Charger", "Lamp", "Iron", "Kettle", "Printer"]
        
        for appliance in target_appliances:
            if appliance not in self.signatures:
                AppLog.warning(f"Signature configuration skipped: {appliance} not found in blueprint JSON file.")
                continue
                
            stats = self.signatures[appliance]
            if 'states' not in stats and 'means' not in stats:
                AppLog.error("FHMM_INIT", f"Skipping {appliance}: Signature matrix profiles missing.")
                continue
                
            try:
                means_source = stats.get('means', stats.get('states', []))
                n_states = len(means_source)
                
                model = hmm.GaussianHMM(n_components=n_states, covariance_type="diag") 
                model.n_features = 1
                
                if 'transition_matrix' in stats:
                    model.startprob_ = np.array(stats.get('start_probabilities', stats.get('start_probs')))
                    model.transmat_ = np.array(stats['transition_matrix'])
                    model.means_ = np.array(means_source).reshape(-1, 1)
                    # Enforce covariance bounds (225.0 min for state 0, [25.0, 2500.0] for active states)
                    covars_data = []
                    for state_idx, c in enumerate(stats['covariances']):
                        if state_idx == 0:
                            covars_data.append(max(float(c), 225.0))
                        else:
                            covars_data.append(min(max(float(c), 25.0), 2500.0))
                    model.covars_ = np.array(covars_data).reshape(-1, 1)
                else:
                    std_dev = stats.get('std_dev', 1.0)
                    model.startprob_ = np.full(n_states, 1.0 / n_states)
                    
                    max_dur = stats.get('max_duration_hr', 12.0)
                    trans_prob = min(0.9, 1.0 / max_dur) if max_dur > 0 else 0.9
                    stay_prob = 1.0 - trans_prob
                    
                    trans_matrix = np.full((n_states, n_states), trans_prob / (n_states - 1))
                    np.fill_diagonal(trans_matrix, stay_prob)
                    model.transmat_ = trans_matrix
                    
                    model.means_ = np.array([[float(s)] for s in means_source])
                    covars_data = []
                    for state_idx in range(n_states):
                        if state_idx == 0:
                            covars_data.append([max(float(std_dev**2), 225.0)])
                        else:
                            covars_data.append([min(max(float(std_dev**2), 25.0), 2500.0)])
                    model.covars_ = np.array(covars_data)
                
                models[appliance] = model
                AppLog.info("FHMM_INIT", f"Successfully bounded sequence model layer for: {appliance}")
                
            except Exception as e:
                AppLog.error("FHMM_INIT", f"Failed to compile model matrices for {appliance}: {str(e)}")
                
        try:
            sink_model = hmm.GaussianHMM(n_components=2, covariance_type="diag")
            sink_model.n_features = 1
            sink_model.startprob_ = np.array([0.999999, 0.000001])
            sink_model.transmat_ = np.array([
                [0.999999, 0.000001],
                [0.1, 0.9]
            ])
            sink_model.means_ = np.array([[0.0], [2000.0]])
            sink_model.covars_ = np.array([[1.0], [1440000.0]])
            models["BackgroundSink"] = sink_model
            AppLog.info("FHMM_INIT", "Successfully injected BackgroundSink model layer.")
        except Exception as e:
            AppLog.error("FHMM_INIT", f"Failed to initialize BackgroundSink: {str(e)}")
            
        return models    

    def get_transmat(self, appliance_name: str, hour: int) -> np.ndarray:
        # High-level: Returns a time-dependent transition matrix for the appliance.
        model = self.models[appliance_name]
        base_trans = model.transmat_.copy()
        stats = self.signatures.get(appliance_name, {})
        if not stats:
            return base_trans
            
        if 6 <= hour < 12:
            factor = 0.8
        elif 12 <= hour < 18:
            factor = 1.0
        elif 18 <= hour <= 23:
            factor = 1.4
        else:
            p_day = stats.get("prob_day", 0.5)
            p_night = stats.get("prob_night", 0.5)
            factor = p_night / p_day if p_day > 0 else 1.0
            
        n_components = base_trans.shape[0]
        if n_components > 1:
            off_to_on = base_trans[0, 1:] * factor
            total_on = np.sum(off_to_on)
            if total_on > 0.99:
                off_to_on = (off_to_on / total_on) * 0.99
            base_trans[0, 1:] = off_to_on
            base_trans[0, 0] = 1.0 - np.sum(off_to_on)
            
        return base_trans

    def disaggregate(self, aggregate_signal: List[float], hour: Optional[int] = None, user_id: Optional[str] = None, adapt_online: bool = True) -> Dict[str, List[float]]:
        # High-level: Decodes aggregate wattage into independent appliance traces using Joint Beam Search.
        if not aggregate_signal:
            return {}
            
        if hour is None:
            import datetime
            hour = datetime.datetime.now(datetime.timezone.utc).hour
            
        original_means = {name: model.means_.copy() for name, model in self.models.items()}
        original_covars = {name: model.covars_.copy() for name, model in self.models.items()}
        original_trans = {name: model.transmat_.copy() for name, model in self.models.items()}
        
        if user_id:
            try:
                from services.bayesian_adaptation import BayesianAdaptationService
                adaptation_service = BayesianAdaptationService()
                profile = adaptation_service.load_user_profile(user_id)
                for appliance, app_profile in profile.items():
                    if appliance in self.models:
                        model = self.models[appliance]
                        
                        # Load adapted means/variances
                        states_profile = app_profile.get("states", {})
                        for state_key, val in states_profile.items():
                            state_idx = int(state_key)
                            if state_idx < len(model.means_):
                                # BUG-02: Only adapt if we have enough observations (e.g. 100 frames)
                                if val.get("sample_count", 0) >= 100:
                                    model.means_[state_idx, 0] = val.get("adapted_mean")
                                    if state_idx == 0:
                                        adapted_var = max(val.get("adapted_variance", 225.0), 225.0)
                                    else:
                                        adapted_var = min(max(val.get("adapted_variance", 25.0), 25.0), 2500.0)
                                    if len(model.covars_.shape) == 3:
                                        model.covars_[state_idx, 0, 0] = adapted_var
                                    else:
                                        model.covars_[state_idx, 0] = adapted_var
                                    
                        # Stage 7: Load adapted transition matrix if available
                        if "transition_matrix" in app_profile:
                            model.transmat_ = np.array(app_profile["transition_matrix"])
            except Exception as e:
                AppLog.error("BAYESIAN_ADAPT_LOAD_FAILED", f"Failed to load/apply user profiles for {user_id}: {str(e)}")
            
        model_names = list(self.models.keys())
        num_models = len(model_names)
        
        import itertools
        state_ranges = [range(len(self.models[name].means_)) for name in model_names]
        joint_states = np.array(list(itertools.product(*state_ranges)), dtype=np.int32)
        
        joint_means = np.zeros(len(joint_states), dtype=np.float32)
        joint_variances = np.zeros(len(joint_states), dtype=np.float32)
        for m_idx, name in enumerate(model_names):
            model = self.models[name]
            joint_means += model.means_[joint_states[:, m_idx]].flatten()
            joint_variances += model.covars_[joint_states[:, m_idx]].flatten()
            
        log_start = np.zeros(len(joint_states), dtype=np.float32)
        for m_idx, name in enumerate(model_names):
            model = self.models[name]
            log_start += np.log(np.clip(model.startprob_, 1e-12, None))[joint_states[:, m_idx]]
            
        log_trans_matrices = []
        for name in model_names:
            trans = self.get_transmat(name, hour)
            log_trans_matrices.append(np.log(np.clip(trans, 1e-12, None)))
            
        # Precompute the joint transition matrix of shape (len(joint_states), len(joint_states))
        joint_log_trans = np.zeros((len(joint_states), len(joint_states)), dtype=np.float32)
        for m_idx in range(num_models):
            log_transmat = log_trans_matrices[m_idx]
            p_states = joint_states[:, m_idx]
            c_states = joint_states[:, m_idx]
            joint_log_trans += log_transmat[p_states[:, None], c_states[None, :]]
            
        beam_width = min(100, len(joint_states))
        T = len(aggregate_signal)
        
        x0 = aggregate_signal[0]
        log_emission = -0.5 * np.log(2.0 * np.pi * joint_variances) - 0.5 * ((x0 - joint_means) ** 2) / joint_variances
        log_likelihoods = log_start + log_emission
        
        top_indices = np.argsort(log_likelihoods)[-beam_width:][::-1]
        
        paths = np.zeros((beam_width, T), dtype=np.int32)
        paths[:, 0] = top_indices
        beam_likelihoods = log_likelihoods[top_indices]
        
        for t in range(1, T):
            xt = aggregate_signal[t]
            log_emission = -0.5 * np.log(2.0 * np.pi * joint_variances) - 0.5 * ((xt - joint_means) ** 2) / joint_variances
            
            num_parents = len(beam_likelihoods)
            parent_indices = paths[:num_parents, t-1]
            
            # Vectorized transition mapping to replace high-overhead loops
            log_trans = joint_log_trans[parent_indices]
                
            candidate_likelihoods = beam_likelihoods[:, None] + log_trans + log_emission[None, :]
            
            flat_candidate = candidate_likelihoods.ravel()
            n_candidates = len(flat_candidate)
            if n_candidates > beam_width:
                top_flat_indices = np.argpartition(flat_candidate, -beam_width)[-beam_width:]
                top_flat_indices = top_flat_indices[np.argsort(flat_candidate[top_flat_indices])[::-1]]
            else:
                top_flat_indices = np.argsort(flat_candidate)[::-1]
                
            parent_rows, child_cols = np.unravel_index(top_flat_indices, candidate_likelihoods.shape)
            
            # Avoid repeated dynamic memory allocation inside decoding loop
            paths[:len(top_flat_indices), :t] = paths[parent_rows, :t].copy()
            paths[:len(top_flat_indices), t] = child_cols
            beam_likelihoods = candidate_likelihoods[parent_rows, child_cols]
            
        best_path_idx = np.argmax(beam_likelihoods)
        best_joint_states_sequence = paths[best_path_idx]
        decoded_sequence = joint_states[best_joint_states_sequence]
        
        disaggregated_data = {}
        for m_idx, name in enumerate(model_names):
            if name == "BackgroundSink":
                continue
            model = self.models[name]
            trace = [float(model.means_[state][0]) for state in decoded_sequence[:, m_idx]]
            
            min_durations = {
                "Fan": 10,
                "Laptop": 10,
                "Charger": 10,
                "Lamp": 10,
                "Iron": 30,
                "Kettle": 1,
                "Printer": 2,
            }
            min_dur = min_durations.get(name, 1)
            
            n_samples = len(trace)
            i = 0
            while i < n_samples:
                if trace[i] > 5.0:
                    start = i
                    while i < n_samples and trace[i] > 5.0:
                        i += 1
                    end = i
                    duration = end - start
                    if name == "Kettle":
                        AppLog.info("KETTLE_DURATION_DETECTED", f"Detected Kettle event: start={start}, end={end}, duration={duration} frames")
                    if duration < min_dur:
                        AppLog.info("DURATION_SUPPRESS", f"Suppressed event for {name}: start={start}, end={end}, duration={duration} frames")
                        for j in range(start, end):
                            trace[j] = 0.0
                else:
                    i += 1
            disaggregated_data[name] = trace

        known_appliances = ["Fan", "Laptop", "Charger", "Lamp", "Iron", "Kettle", "Printer"]
        total_pred = np.zeros(len(aggregate_signal))
        for name in known_appliances:
            if name in disaggregated_data:
                total_pred += np.array(disaggregated_data[name])
        
        raw_arr = np.array(aggregate_signal)
        unassigned_residual = np.abs(raw_arr - total_pred)
        
        for name in known_appliances:
            if name in disaggregated_data and name in self.models:
                trace = np.array(disaggregated_data[name])
                model = self.models[name]
                active_mean = float(model.means_[-1][0])
                # Off-state standard deviation
                sigma_off = float(np.sqrt(float(model.covars_[0][0])))
                limit = max(0.2 * active_mean, 3.0 * sigma_off)
                
                for t in range(len(trace)):
                    if trace[t] > 5.0 and unassigned_residual[t] > limit:
                        trace[t] = 0.0
                disaggregated_data[name] = trace.tolist()

        if user_id and adapt_online:
            try:
                from services.bayesian_adaptation import BayesianAdaptationService
                adaptation_service = BayesianAdaptationService()
                for name in model_names:
                    if name in disaggregated_data and name != "BackgroundSink":
                        trace = disaggregated_data[name]
                        active_samples = [v for v in trace if v > 5.0]
                        if active_samples:
                            other_pred = np.zeros(len(aggregate_signal))
                            for other_name in disaggregated_data.keys():
                                if other_name != name:
                                    other_pred += np.array(disaggregated_data[other_name])
                            
                            actual_active_samples = []
                            for t, val in enumerate(trace):
                                if val > 5.0:
                                    act_val = max(0.0, aggregate_signal[t] - other_pred[t])
                                    act_val = min(act_val, aggregate_signal[t])
                                    actual_active_samples.append(act_val)
                            
                            if actual_active_samples:
                                observed_mean = float(np.mean(actual_active_samples))
                                observed_var = float(np.var(actual_active_samples)) if len(actual_active_samples) > 1 else 0.0
                                num_samples = len(actual_active_samples)
                                
                                model = self.models[name]
                                active_state_idx = len(model.means_) - 1
                                adaptation_service.update_appliance_state(
                                    user_id, name, active_state_idx, observed_mean, 
                                    observed_variance=observed_var, num_samples=num_samples
                                )
                                
                                sample_duration_hr = 24.0 / len(trace) if len(trace) > 0 else 1.0
                                daily_runtime = len(active_samples) * sample_duration_hr
                                adaptation_service.update_appliance_statistics(user_id, name, [hour], daily_runtime)
            except Exception as e:
                AppLog.error("BAYESIAN_ADAPT_UPDATE_FAILED", f"Failed to update user profiles for {user_id}: {str(e)}")

        for name, model in self.models.items():
            model.means_ = original_means[name]
            model.covars_ = original_covars[name].reshape(model.n_components, -1)
            model.transmat_ = original_trans[name]

        return disaggregated_data