import numpy as np

# High-level: Statistical and conversion functions for energy analysis.

# Regional Grid Baseline (kg CO2e per kWh)
CARBON_INTENSITY = 0.478 

def calculate_malaysian_tariff_a(kwh: float) -> float:
    """
    Implements TNB Tariff A - Domestic tiered pricing:
    1-200 kWh: 21.80 sen
    201-300 kWh: 33.40 sen
    301-600 kWh: 51.60 sen
    601-900 kWh: 54.60 sen
    >900 kWh: 57.10 sen
    """
    total_sen = 0.0
    remaining = kwh

    # Tier 1: First 200 kWh
    tier1 = min(remaining, 200)
    total_sen += tier1 * 21.80
    remaining -= tier1

    # Tier 2: Next 100 kWh (201-300)
    if remaining > 0:
        tier2 = min(remaining, 100)
        total_sen += tier2 * 33.40
        remaining -= tier2

    # Tier 3: Next 300 kWh (301-600)
    if remaining > 0:
        tier3 = min(remaining, 300)
        total_sen += tier3 * 51.60
        remaining -= tier3

    # Tier 4: Next 300 kWh (601-900)
    if remaining > 0:
        tier4 = min(remaining, 300)
        total_sen += tier4 * 54.60
        remaining -= tier4

    # Tier 5: > 900 kWh
    if remaining > 0:
        total_sen += remaining * 57.10

    # Convert sen to MYR (100 sen = 1 MYR)
    return round(total_sen / 100.0, 2)

def calculate_carbon_footprint(kwh: float) -> float:
    return round(kwh * CARBON_INTENSITY, 2)

def calculate_rmse(simulated, actual):
    # Expected: Input arrays of equal length representing kWh values.
    return np.sqrt(np.mean((np.array(simulated) - np.array(actual))**2))

def calculate_mae(simulated, actual):
    # Calculates the average absolute error across all time-series points.
    return np.mean(np.abs(np.array(simulated) - np.array(actual)))