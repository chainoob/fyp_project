import numpy as np

# High-level: Statistical functions for model performance validation.

def calculate_rmse(simulated, actual):
    # Expected: Input arrays of equal length representing kWh values.
    return np.sqrt(np.mean((np.array(simulated) - np.array(actual))**2))

def calculate_mae(simulated, actual):
    # Calculates the average absolute error across all time-series points.
    return np.mean(np.abs(np.array(simulated) - np.array(actual)))