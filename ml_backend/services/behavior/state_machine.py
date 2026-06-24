# ml_backend/services/behavior/state_machine.py

import random
import numpy as np
from typing import Dict

class ApplianceStateMachine:
    # High-level: Implements Markov-chain state transitions for an appliance.
    
    def __init__(self, appliance_type: str, initial_state: int = 0):
        self.appliance_type = appliance_type.title()
        self.state = initial_state
        self.trans_matrix = self._get_default_matrix()

    def _get_default_matrix(self) -> np.ndarray:
        # Default transitions for 3 states: OFF (0), IDLE (1), ACTIVE (2)
        if self.appliance_type == "Kettle":
            # Kettle has no IDLE state and is short burst
            return np.array([
                [0.999, 0.0, 0.001],
                [0.10, 0.8, 0.10],
                [0.30, 0.0, 0.70]
            ], dtype=np.float32)
        elif self.appliance_type == "Iron":
            # Iron cycles thermostat
            return np.array([
                [0.998, 0.0, 0.002],
                [0.10, 0.8, 0.10],
                [0.20, 0.0, 0.80]
            ], dtype=np.float32)
        elif self.appliance_type == "Laptop":
            return np.array([
                [0.995, 0.003, 0.002],
                [0.05,  0.90,  0.05],
                [0.02,  0.08,  0.90]
            ], dtype=np.float32)
        elif self.appliance_type == "Fan":
            return np.array([
                [0.997, 0.0, 0.003],
                [0.05, 0.85, 0.10],
                [0.01, 0.0, 0.99]
            ], dtype=np.float32)
        else:
            # Default generic transition matrix
            return np.array([
                [0.995, 0.003, 0.002],
                [0.08,  0.84,  0.08],
                [0.05,  0.10,  0.85]
            ], dtype=np.float32)

    def transition(self, override_matrix: np.ndarray = None) -> int:
        matrix = override_matrix if override_matrix is not None else self.trans_matrix
        probs = matrix[self.state]
        self.state = int(np.random.choice([0, 1, 2], p=probs))
        return self.state
