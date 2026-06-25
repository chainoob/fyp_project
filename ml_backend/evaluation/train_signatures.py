# ml_backend/evaluation/train_signatures.py

import sys
import os
import json
import numpy as np
import pandas as pd
from sklearn.mixture import GaussianMixture
from hmmlearn import hmm
from typing import Dict, List, Tuple

# Align Python path to root directory
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from utils.logger import AppLog
from utils.data_quality import repair_gaps, run_integrity_checks, monitor_quality

class SignatureTrainer:
    """Trains appliance signatures using GMM emissions, HMM transition learning, and duration statistics."""
    
    def __init__(self, h5_path: str):
        self.h5_path = h5_path

    def load_sensor_power(self, key: str) -> pd.Series:
        """Reads power measurements from the HDF5 file using PyTables and returns a pd.Series."""
        import tables
        with tables.open_file(self.h5_path, 'r') as f:
            node_path = key.rstrip('/') + '/table' if not key.endswith('/table') else key
            node = f.get_node(node_path)
            data = node.read()
        
        power = data['values_block_0'].flatten()
        power = np.clip(power, 0.0, None)
        timestamps = pd.to_datetime(data['index'], unit='ns', utc=True)
        return pd.Series(power, index=timestamps)

    def fit_gmm_signatures(self, power_trace: np.ndarray, n_states: int = 2, threshold: float = 5.0) -> dict:
        """Fits Gaussian Mixture Model with BIC-based model selection on active power trace and prepends OFF state."""
        X = power_trace.reshape(-1, 1)
        
        # Filter active and inactive segments
        active_mask = power_trace > threshold
        active_power = power_trace[active_mask]
        inactive_power = power_trace[~active_mask]
        
        # Phase A: BUG-01 - Outlier filtering to prevent profile contamination
        if len(active_power) > 20:
            q_limit = np.percentile(active_power, 99.5)
            p95 = np.percentile(active_power, 95)
            if p95 > 0 and q_limit > 3.0 * p95:
                active_power = active_power[active_power <= q_limit]
        
        n_active_states = n_states - 1
        n_active_states = max(1, n_active_states)
        
        # If there are not enough active samples, fall back to global fitting
        if len(active_power) < n_active_states or len(np.unique(active_power)) < n_active_states:
            n_active_states = n_states
            active_power = power_trace
            active_mask = np.ones_like(power_trace, dtype=bool)
            
        X_active = active_power.reshape(-1, 1)
        
        # Fit GMM on the active segment
        gmm = GaussianMixture(
            n_components=n_active_states,
            covariance_type="full",
            n_init=10,
            random_state=42
        ).fit(X_active)
        
        active_means = gmm.means_.flatten()
        active_covars = gmm.covariances_.flatten()
        active_weights = gmm.weights_
        
        # Sort active states by mean
        sort_idx = np.argsort(active_means)
        sorted_active_means = active_means[sort_idx].tolist()
        sorted_active_covars = active_covars[sort_idx].tolist()
        sorted_active_weights = active_weights[sort_idx].tolist()
        
        if active_mask.all():
            # Fallback global fit
            if sorted_active_means[0] < 10.0:
                sorted_active_means[0] = 0.0
            return {
                "means": sorted_active_means,
                "covariances": sorted_active_covars,
                "weights": sorted_active_weights,
                "n_states": gmm.n_components,
                "converged": bool(gmm.converged_)
            }
            
        # Standard active-only fit: prepend OFF state
        off_mean = 0.0
        off_covar = float(np.var(inactive_power)) if len(inactive_power) > 0 else 1.0
        off_covar = max(off_covar, 1.0)
        
        off_weight = float(len(inactive_power) / len(power_trace))
        
        # Scale active weights to sum to (1 - off_weight)
        scaled_active_weights = [w * (1.0 - off_weight) for w in sorted_active_weights]
        
        full_means = [off_mean] + sorted_active_means
        full_covars = [off_covar] + sorted_active_covars
        full_weights = [off_weight] + scaled_active_weights
        
        return {
            "means": full_means,
            "covariances": full_covars,
            "weights": full_weights,
            "n_states": len(full_means),
            "converged": bool(gmm.converged_)
        }



    def learn_transitions(self, power_trace: np.ndarray, n_states: int, means: List[float], covars: List[float]) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
        """Learns transition matrices via HMM latent state inference."""
        X = power_trace.reshape(-1, 1)
        means_arr = np.array(means).reshape(-1, 1)
        covars_arr = np.array(covars).reshape(-1, 1)
        
        # Enforce minimum variance for numerical stability in GaussianHMM
        covars_arr = np.clip(covars_arr, 25.0, None)
        
        # Method A: Baum-Welch (EM) learning with frozen emissions
        try:
            model = hmm.GaussianHMM(
                n_components=n_states,
                covariance_type="diag",
                init_params="",
                params="st",
                random_state=42
            )
            model.means_ = means_arr
            model.covars_ = covars_arr
            model.fit(X)
            
            _, state_seq = model.decode(X)
            transmat = model.transmat_
            startprob = model.startprob_
            
        except Exception as e:
            AppLog.warning("BW_LEARN_FAIL", f"Baum-Welch failed: {str(e)}. Falling back to Method B (Viterbi + counting).")
            # Method B: Viterbi + counting fallback
            model = hmm.GaussianHMM(
                n_components=n_states,
                covariance_type="diag"
            )
            model.means_ = means_arr
            model.covars_ = covars_arr
            
            # Setup default transition and startprob to decode
            model.startprob_ = np.full(n_states, 1.0 / n_states)
            model.transmat_ = np.full((n_states, n_states), 1.0 / n_states)
            
            _, state_seq = model.decode(X)
            
            counts = np.zeros((n_states, n_states))
            for t in range(len(state_seq) - 1):
                counts[state_seq[t], state_seq[t + 1]] += 1
                
            alpha = 1.0
            transmat = (counts + alpha) / (counts + alpha).sum(axis=1, keepdims=True)
            
            start_counts = np.zeros(n_states)
            if len(state_seq) > 0:
                start_counts[state_seq[0]] += 1
            startprob = (start_counts + alpha) / (start_counts + alpha).sum()
            
        return transmat, startprob, state_seq

    def learn_duration_stats(self, state_seq: np.ndarray) -> dict:
        """Extracts continuous state run statistics per state."""
        durations = {}
        for state in np.unique(state_seq):
            runs = []
            count = 0
            for s in state_seq:
                if s == state:
                    count += 1
                elif count > 0:
                    runs.append(count)
                    count = 0
            if count > 0:
                runs.append(count)
                
            runs = np.array(runs) if len(runs) > 0 else np.array([1])
            
            durations[str(int(state))] = {
                "mean_duration": float(np.mean(runs)),
                "std_duration": float(np.std(runs)),
                "min_duration": int(np.min(runs)),
                "max_duration": int(np.max(runs))
            }
        return durations

if __name__ == "__main__":
    h5_file = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'data', 'ukdale.h5'))
    signatures_file = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'data', 'appliance_signatures.json'))
    
    if not os.path.exists(h5_file):
        print(f"Error: HDF5 database not found at {h5_file}.")
        sys.exit(1)
        
    trainer = SignatureTrainer(h5_file)
    
    # Target UK-DALE House 1 appliance settings
    targets = {
        "Lamp": {
            "key": "/building1/elec/meter42",
            "n_states": 2,
            "type": "resistive",
            "description": "UK-DALE-distilled: LED/Fluorescent states",
            "prob_day": 0.1,
            "prob_night": 0.7,
            "max_duration_hr": 10.0
        },
        "Fan": {
            "key": "/building1/elec/meter7",
            "n_states": 2,
            "type": "resistive",
            "description": "UK-DALE-distilled: Low/High fan states",
            "prob_day": 0.35,
            "prob_night": 0.4,
            "max_duration_hr": 24.0
        },
        "Laptop": {
            "key": "/building1/elec/meter24",
            "n_states": 3,
            "type": "smps",
            "description": "UK-DALE-distilled: Idle/Standard/Heavy-Load laptop states",
            "prob_day": 0.6,
            "prob_night": 0.4,
            "max_duration_hr": 12.0
        },
        "Charger": {
            "key": "/building1/elec/meter26",
            "n_states": 2,
            "type": "smps",
            "description": "Mobile/Tablet Charger: Low-power consumption",
            "prob_day": 0.8,
            "prob_night": 0.9,
            "max_duration_hr": 8.0
        },
        "Kettle": {
            "key": "/building1/elec/meter11",
            "n_states": 2,
            "type": "heating",
            "description": "UK-DALE-distilled: High-power thermal signature",
            "prob_day": 0.1,
            "prob_night": 0.05,
            "max_duration_hr": 0.5,
            "active_threshold": 100.0
        },
        "Iron": {
            "key": "/building1/elec/meter37",
            "n_states": 3,
            "type": "thermal_cycling",
            "description": "UK-DALE-distilled: Cycling thermostat states",
            "prob_day": 0.05,
            "prob_night": 0.02,
            "max_duration_hr": 1.0,
            "active_threshold": 50.0
        },
        "Printer": {
            "key": "/building1/elec/meter36",
            "n_states": 2,
            "type": "intermittent_high_load",
            "description": "Desk Printer: Standby/Warming/Printing",
            "prob_day": 0.15,
            "prob_night": 0.05,
            "max_duration_hr": 2.0
        }
    }
    
    signatures = {}
    
    # Load aggregate meter 1 for quality and residual subtraction
    print("Loading aggregate meter 1 for residual computation...")
    agg_raw = trainer.load_sensor_power("/building1/elec/meter1")
    agg_series, agg_mask = repair_gaps(agg_raw)
    
    # Map matching channels for sensor quality logging
    app_series_dict = {}
    
    # Run training for each targeted appliance
    for name, config in targets.items():
        try:
            raw_series = trainer.load_sensor_power(config["key"])
            
            # Step 1: Data quality processing
            clean_series, gap_mask = repair_gaps(raw_series)
            
            # Re-align clean data to index intersection with aggregate meter
            aligned_index = clean_series.index.intersection(agg_series.index)
            clean_series = clean_series.loc[aligned_index]
            app_series_dict[name] = clean_series
            
            power_data = clean_series.values
            
            # Step 2: Emission model fitting (GMM with BIC)
            threshold = config.get("active_threshold", 5.0)
            gmm_results = trainer.fit_gmm_signatures(
                power_data, 
                n_states=config.get("n_states", 2), 
                threshold=threshold
            )
            
            # Step 3: Transition learning via latent state inference
            transmat, startprob, state_seq = trainer.learn_transitions(
                power_data,
                gmm_results["n_states"],
                gmm_results["means"],
                gmm_results["covariances"]
            )
            
            # Step 4: Duration statistics extraction
            durations = trainer.learn_duration_stats(state_seq)
            
            # Step 5: Save model to signature block under versioned standardized profile schema
            signatures[name] = {
                "appliance": name,
                "n_states": gmm_results["n_states"],
                "means": gmm_results["means"],
                "covariances": gmm_results["covariances"],
                "weights": gmm_results["weights"],
                "start_probs": startprob.tolist(),
                "transition_matrix": [[round(val, 6) for val in row] for row in transmat.tolist()],
                "duration_stats": durations,
                
                # Keep metadata targets for backward compatibility with simulator
                "states": [round(m, 2) for m in gmm_results["means"]],
                "max_state_index": gmm_results["n_states"] - 1,
                "std_dev": round(float(np.sqrt(gmm_results["covariances"][-1])), 2),
                "type": config["type"],
                "description": config["description"],
                "prob_day": config["prob_day"],
                "prob_night": config["prob_night"],
                "max_duration_hr": config["max_duration_hr"],
                "default_wattage": round(gmm_results["means"][-1], 2)
            }
            
            print(f"Successfully trained {name}: n_states={gmm_results['n_states']}, means={gmm_results['means']}")
            
        except Exception as e:
            AppLog.error("TRAINING_FAILURE", f"Failed to train signature for {name}: {str(e)}")
            import traceback
            traceback.print_exc()
            
    # Compute sensor quality report
    quality_report = monitor_quality(agg_series, app_series_dict)
    print(f"Sensor Quality Report:\n{json.dumps(quality_report, indent=4)}")
    
    # Step 6.2: Fit multi-state GMM on residual load (unexplained sink modeling)
    try:
        print("Computing residual power trace for BackgroundSink training...")
        # Re-align all series to aggregate index
        agg_aligned = agg_series.copy()
        
        sum_known = np.zeros_like(agg_aligned.values)
        for name, series in app_series_dict.items():
            # Align series to aggregate index
            aligned_series = series.reindex(agg_aligned.index, fill_value=0.0)
            sum_known += aligned_series.values
            
        residual = np.clip(agg_aligned.values - sum_known, 0.0, None)
        
        # Fit GMM on residual (typically 3 states: Low/Med/High background variations)
        residual_gmm = trainer.fit_gmm_signatures(residual, n_states=3, threshold=5.0)
        transmat, startprob, state_seq = trainer.learn_transitions(
            residual,
            residual_gmm["n_states"],
            residual_gmm["means"],
            residual_gmm["covariances"]
        )
        durations = trainer.learn_duration_stats(state_seq)
        
        signatures["BackgroundSink"] = {
            "appliance": "BackgroundSink",
            "n_states": residual_gmm["n_states"],
            "means": residual_gmm["means"],
            "covariances": residual_gmm["covariances"],
            "weights": residual_gmm["weights"],
            "start_probs": startprob.tolist(),
            "transition_matrix": [[round(val, 6) for val in row] for row in transmat.tolist()],
            "duration_stats": durations,
            
            # Keep compatibility parameters for background decoding
            "states": [round(m, 2) for m in residual_gmm["means"]],
            "means": [round(m, 2) for m in residual_gmm["means"]],
            "covariances": [max(float(c), 25.0) for c in residual_gmm["covariances"]]
        }
        print("Successfully trained BackgroundSink from residual load.")
        
    except Exception as e:
        print(f"Failed to fit residual BackgroundSink: {str(e)}")
        
    # Write back updated signatures to standard destination config file
    with open(signatures_file, 'w') as f:
        json.dump(signatures, f, indent=2)
    print(f"\nSuccessfully stored and updated HMM-GMM signatures in: {signatures_file}")
