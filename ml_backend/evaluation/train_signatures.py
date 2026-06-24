import sys
import os
import json
import numpy as np
import pandas as pd
from sklearn.cluster import KMeans
from typing import Dict, List, Tuple

# Align Python path to root directory
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from utils.logger import AppLog

class SignatureTrainer:
    """Trains appliance disaggregation signature templates using K-Means and transition mapping."""
    
    def __init__(self, h5_path: str):
        self.h5_path = h5_path

    def load_sensor_power(self, key: str) -> np.ndarray:
        """Reads and flattens power measurements from the HDF5 file using PyTables."""
        import tables
        with tables.open_file(self.h5_path, 'r') as f:
            node_path = key.rstrip('/') + '/table' if not key.endswith('/table') else key
            node = f.get_node(node_path)
            data = node.read()
        
        power = data['values_block_0'].flatten()
        # Clean data: Clip negative values to zero
        power = np.clip(power, 0.0, None)
        return power

    def train_appliance(self, key: str, n_states: int, name: str, max_power: float = None) -> Tuple[List[float], float, List[List[float]], List[float]]:
        """Extracts states using KMeans and computes transition matrices and standard deviations using vectorized NumPy operations."""
        AppLog.info("TRAIN_START", f"Training signature for {name} on {key}")
        power = self.load_sensor_power(key)
        
        if max_power is not None:
            power = power[power <= max_power]
            
        # Reshape for clustering
        X = power.reshape(-1, 1)
        
        # Fit KMeans to identify discrete operational levels
        kmeans = KMeans(n_clusters=n_states, random_state=42, n_init=10)
        kmeans.fit(X)
        
        # Get raw cluster centers and sort them
        centers = kmeans.cluster_centers_.flatten()
        sort_idx = np.argsort(centers)
        means = centers[sort_idx].tolist()
        
        # Enforce the first state (OFF state) to be exactly 0.0
        if means[0] < 10.0:
            means[0] = 0.0
            
        # Predict states to obtain state sequence
        raw_state_seq = kmeans.predict(X)
        
        # Map raw state indices to sorted state indices to preserve ascending order
        rank_map = np.zeros(n_states, dtype=int)
        for rank, idx in enumerate(sort_idx):
            rank_map[idx] = rank
        state_seq = rank_map[raw_state_seq]
        
        # Vectorized residuals and standard deviation calculation
        predicted_means = np.array(means)[state_seq]
        residuals = power - predicted_means
        std_dev = float(np.std(residuals))
        
        # Vectorized transition probability matrix calculation
        s_curr = state_seq[:-1]
        s_next = state_seq[1:]
        pairs = s_curr * n_states + s_next
        unique, counts = np.unique(pairs, return_counts=True)
        
        transitions = np.zeros((n_states, n_states))
        for pair, count in zip(unique, counts):
            row = pair // n_states
            col = pair % n_states
            transitions[row, col] = count
            
        # Normalize transitions row-wise to get probabilities (applying Laplace smoothing)
        alpha = 0.1
        transition_matrix = []
        for row in transitions:
            smoothed_row = row + alpha
            total = np.sum(smoothed_row)
            normalized_row = (smoothed_row / total).tolist()
            transition_matrix.append(normalized_row)
            
        # Calculate initial state probabilities
        unique_states, state_counts = np.unique(state_seq, return_counts=True)
        counts_dict = dict(zip(unique_states, state_counts))
        start_prob = []
        total_samples = len(state_seq)
        for i in range(n_states):
            start_prob.append(float(counts_dict.get(i, 0) / total_samples))
            
        AppLog.info("TRAIN_COMPLETE", f"Signature generated for {name}. States: {means}, StdDev: {std_dev:.2f}")
        return means, std_dev, transition_matrix, start_prob

if __name__ == "__main__":
    h5_file = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'data', 'ukdale.h5'))
    signatures_file = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'data', 'appliance_signatures.json'))
    
    if not os.path.exists(h5_file):
        print(f"Error: HDF5 database not found at {h5_file}. Please place the file and try again.")
        sys.exit(1)
        
    trainer = SignatureTrainer(h5_file)
    
    # Target UK-DALE House 1 appliance settings and metadata configuration
    targets = {
        "Lamp": {
            "key": "/building1/elec/meter42",
            "n_states": 2,
            "max_power": 100.0,
            "type": "resistive",
            "description": "UK-DALE-distilled: LED/Fluorescent states",
            "prob_day": 0.1,
            "prob_night": 0.7,
            "max_duration_hr": 10.0
        },
        "Fan": {
            "key": "/building1/elec/meter7",
            "n_states": 2,
            "max_power": 150.0,
            "type": "resistive",
            "description": "UK-DALE-distilled: Low/High fan states",
            "prob_day": 0.35,
            "prob_night": 0.4,
            "max_duration_hr": 24.0
        },
        "Laptop": {
            "key": "/building1/elec/meter24",
            "n_states": 3,
            "max_power": 150.0,
            "type": "smps",
            "description": "UK-DALE-distilled: Idle/Standard/Heavy-Load laptop states",
            "prob_day": 0.6,
            "prob_night": 0.4,
            "max_duration_hr": 12.0
        },
        "Charger": {
            "key": "/building1/elec/meter26",
            "n_states": 2,
            "max_power": 30.0,
            "type": "smps",
            "description": "Mobile/Tablet Charger: Low-power consumption",
            "prob_day": 0.8,
            "prob_night": 0.9,
            "max_duration_hr": 8.0
        },
        "Kettle": {
            "key": "/building1/elec/meter11",
            "n_states": 2,
            "max_power": 3500.0,
            "type": "heating",
            "description": "UK-DALE-distilled: High-power thermal signature",
            "prob_day": 0.1,
            "prob_night": 0.05,
            "max_duration_hr": 0.5
        },
        "Iron": {
            "key": "/building1/elec/meter37",
            "n_states": 3,
            "max_power": 2500.0,
            "type": "thermal_cycling",
            "description": "UK-DALE-distilled: Cycling thermostat states",
            "prob_day": 0.05,
            "prob_night": 0.02,
            "max_duration_hr": 1.0
        },
        "Printer": {
            "key": "/building1/elec/meter36",
            "n_states": 2,
            "max_power": 2000.0,
            "type": "intermittent_high_load",
            "description": "Desk Printer: Standby/Warming/Printing",
            "prob_day": 0.15,
            "prob_night": 0.05,
            "max_duration_hr": 2.0
        }
    }
    
    # Load existing signatures if present
    signatures = {}
    try:
        if os.path.exists(signatures_file):
            with open(signatures_file, 'r') as f:
                signatures = json.load(f)
    except Exception as e:
        AppLog.warning("LOAD_SIGNATURES", f"Could not load existing signatures: {e}.")
        
    # Run training and update signature blocks
    updated_any = False
    for name, config in targets.items():
        try:
            means, std_dev, trans_matrix, start_prob = trainer.train_appliance(
                config["key"], config["n_states"], name, max_power=config["max_power"]
            )
            
            signatures[name] = {
                "states": [round(m, 2) for m in means],
                "max_state_index": config["n_states"] - 1,
                "std_dev": round(std_dev, 2),
                "type": config["type"],
                "description": config["description"],
                "prob_day": config["prob_day"],
                "prob_night": config["prob_night"],
                "max_duration_hr": config["max_duration_hr"],
                "default_wattage": round(means[-1], 2),
                "transition_matrix": [[round(val, 4) for val in row] for row in trans_matrix],
                "start_probabilities": [round(val, 4) for val in start_prob],
                "means": [round(m, 2) for m in means],
                "covariances": [round(std_dev**2, 4) for _ in range(config["n_states"])]
            }
            updated_any = True
            
        except Exception as e:
            AppLog.error("TRAINING_FAILURE", f"Failed to train signature for {name}: {str(e)}")
            
    if updated_any:
        # Write back updated profiles
        with open(signatures_file, 'w') as f:
            json.dump(signatures, f, indent=2)
        print(f"\nSuccessfully trained and updated UK-DALE signatures in: {signatures_file}")
    else:
        print("\nNo signatures were updated.")
