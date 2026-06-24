# ml_backend/services/behavior/transition_estimator.py

import numpy as np
from typing import List

class TransitionEstimator:
    # High-level: Estimates state transition matrices from historical state sequences.

    @staticmethod
    def estimate_transition_matrix(state_sequence: List[int], n_states: int = 3, alpha: float = 0.1) -> np.ndarray:
        # High-level: Computes P(i->j) = count(i->j) / count(i) with Laplace smoothing.
        transitions = np.zeros((n_states, n_states), dtype=np.float32)
        
        for t in range(len(state_sequence) - 1):
            i = state_sequence[t]
            j = state_sequence[t+1]
            if 0 <= i < n_states and 0 <= j < n_states:
                transitions[i, j] += 1.0
                
        # Normalize rows with Laplace smoothing
        transition_matrix = np.zeros((n_states, n_states), dtype=np.float32)
        for i in range(n_states):
            row_sum = np.sum(transitions[i])
            if row_sum > 0:
                transition_matrix[i] = (transitions[i] + alpha) / (row_sum + n_states * alpha)
            else:
                # Default fallback: high stay probability
                transition_matrix[i, i] = 0.9
                other_prob = 0.1 / (n_states - 1)
                for j in range(n_states):
                    if j != i:
                        transition_matrix[i, j] = other_prob
                        
        return transition_matrix
