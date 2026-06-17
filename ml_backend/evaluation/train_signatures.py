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

    def train_appliance(self, key: str, n_states: int, name: str) -> Tuple[List[float], float, List[List[float]], List[float]]:
        """Extracts states using KMeans and computes transition matrices and standard deviations using vectorized NumPy operations."""
        AppLog.info("TRAIN_START", f"Training signature for {name} on {key}")
        power = self.load_sensor_power(key)
        
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
            
        # Normalize transitions row-wise to get probabilities
        transition_matrix = []
        for row in transitions:
            total = np.sum(row)
            if total > 0:
                normalized_row = (row / total).tolist()
            else:
                normalized_row = [1.0 / n_states] * n_states
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
    
    # Target UK-DALE House 1 appliance settings
    # Format: ApplianceName: (HDF5_key, target_states_count)
    targets = {
        "Lamp": ("/building1/elec/meter42", 2),
        "Fan": ("/building1/elec/meter7", 2),
        "Laptop": ("/building1/elec/meter24", 3),
        "Charger": ("/building1/elec/meter26", 2),
        "Kettle": ("/building1/elec/meter11", 2),
        "Iron": ("/building1/elec/meter37", 3),
        "Printer": ("/building1/elec/meter36", 2)
    }
    
    # Load existing signatures
    try:
        with open(signatures_file, 'r') as f:
            signatures = json.load(f)
    except Exception as e:
        AppLog.warning("LOAD_SIGNATURES", f"Could not load existing signatures: {e}. Starting fresh.")
        signatures = {}
        
    # Run training and update signature blocks
    updated_any = False
    for name, (key, n_states) in targets.items():
        try:
            means, std_dev, trans_matrix, start_prob = trainer.train_appliance(key, n_states, name)
            
            # Update values in-place
            if name not in signatures:
                signatures[name] = {}
                
            signatures[name]["states"] = [round(m, 2) for m in means]
            signatures[name]["means"] = [round(m, 2) for m in means]
            signatures[name]["max_state_index"] = n_states - 1
            signatures[name]["std_dev"] = round(std_dev, 2)
            signatures[name]["covariances"] = [round(std_dev**2, 4) for _ in range(n_states)]
            signatures[name]["transition_matrix"] = [[round(val, 4) for val in row] for row in trans_matrix]
            signatures[name]["start_probabilities"] = [round(val, 4) for val in start_prob]
            signatures[name]["default_wattage"] = round(means[-1], 2)
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
