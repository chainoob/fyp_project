import json
import os

class FHMMModel:
    def __init__(self, signature_file="data/appliance_signatures.json"):
        if not os.path.exists(signature_file):
            raise FileNotFoundError(f"Signature file missing: {signature_file}")
            
        with open(signature_file, 'r') as f:
            self.signatures = json.load(f)

    def get_power_for_state(self, appliance_name, state_index):
        if appliance_name not in self.signatures:
            return 0
        states = self.signatures[appliance_name]["states"]
        # Fallback to max state if index exceeds bounds
        safe_index = min(state_index, len(states) - 1)
        return states[safe_index]

    def get_max_state_index(self, appliance_name):
        if appliance_name not in self.signatures:
            return 0
        return self.signatures[appliance_name]["max_state_index"]