MAX_KWH_LIMITS: dict[str, float] = {
    "Laptop": 1.5, 
    "Fan": 1.44, 
    "Charger": 0.2, 
    "Kettle": 1.0, 
    "Iron": 1.5, 
    "Lamp": 0.8, 
    "Printer": 0.3
}

def constrain_mcmc_allocation(appliance_name: str, calculated_kwh: float) -> float:
    max_limit: float = MAX_KWH_LIMITS.get(appliance_name, float('inf'))
    return min(calculated_kwh, max_limit)
