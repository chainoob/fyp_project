# ml_backend/utils/data_quality.py

import pandas as pd
import numpy as np
from utils.logger import AppLog

MAX_FILL_SECONDS = 30

def repair_gaps(series: pd.Series, freq_seconds: int = 6):
    # High-level: Implements bounded forward/backward fill.
    limit = MAX_FILL_SECONDS // freq_seconds
    series = series.ffill(limit=limit).bfill(limit=limit)
    gap_mask = series.isnull()
    series = series.dropna()
    return series, gap_mask

def run_integrity_checks(df: pd.DataFrame) -> pd.DataFrame:
    # High-level: Enforces strictly increasing timestamps, duplicate removal, and index alignment.
    if not isinstance(df.index, pd.DatetimeIndex):
        raise ValueError("DataFrame index must be DatetimeIndex for time-series checks.")
    
    # Remove duplicate indices
    df = df[~df.index.duplicated(keep='first')]
    
    # Enforce strictly increasing timestamps
    df = df.sort_index()
    
    return df

def monitor_quality(agg_series: pd.Series, appliance_series_dict: dict) -> dict:
    # High-level: Computes rolling z-scores (drift detection) and per-appliance activation counts.
    # Rolling z-score as a drift proxy (window of 100 samples)
    rolling_mean = agg_series.rolling(window=100, min_periods=10).mean()
    rolling_std = agg_series.rolling(window=100, min_periods=10).std()
    
    # Calculate z-score with numerical stability epsilon
    z_score = (agg_series - rolling_mean) / (rolling_std + 1e-6)
    
    # If absolute z-score exceeds 5.0, flag as drift/anomaly
    drift_detected = bool(np.any(np.abs(z_score) > 5.0))
    
    # Zero-activity detection / activation counts
    activation_counts = {}
    for app_name, series in appliance_series_dict.items():
        active = (series > 5.0).astype(int)
        diff_active = np.diff(active, prepend=0)
        activations = int(np.sum(diff_active == 1))
        activation_counts[app_name] = activations
        
    missingness_ratio = float(agg_series.isnull().mean()) if len(agg_series) > 0 else 0.0
    
    quality_report = {
        "drift_detected": drift_detected,
        "missingness_ratio": missingness_ratio,
        "activation_counts": activation_counts
    }
    
    AppLog.info("DATA_QUALITY", f"Quality check results: drift={drift_detected}, missingness={missingness_ratio:.4f}")
    return quality_report
