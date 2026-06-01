import pandas as pd
import numpy as np
from sklearn.metrics import f1_score
from services.fhmm_service import FHMMService
from utils.logger import AppLog

class DataLoader:
    """Handles time-series telemetry ingestion and synchronization."""
    
    def __init__(self, target_frequency='1S'):
        self.target_frequency = target_frequency

    def load_and_sync(self, file_path, label_mapping):
        """Loads CSV and applies temporal synchronization and classification mapping."""
        df = pd.read_csv(file_path, parse_dates=['timestamp'], index_col='timestamp')
        
        # Temporal Synchronization: Resample to unified target resolution
        df_resampled = df.resample(self.target_frequency).mean().fillna(method='ffill')
        
        # Classification Mapping: Rename columns based on strict taxonomy
        df_mapped = df_resampled.rename(columns=label_mapping)
        
        return df_mapped

class AmplitudeNormalizer:
    """Handles voltage and power characteristic normalization across geographic hardware."""
    
    @staticmethod
    def normalize(data, method='zscore'):
        """Applies Min-Max or Z-score normalization per appliance category."""
        if method == 'zscore':
            return (data - data.mean()) / (data.std() + 1e-6)
        elif method == 'minmax':
            return (data - data.min()) / (data.max() - data.min() + 1e-6)
        else:
            raise ValueError(f"Normalization method {method} not supported.")

class MetricsCalculator:
    """Calculates NILM-specific performance metrics."""
    
    @staticmethod
    def calculate_f1(y_true, y_pred, threshold=5.0):
        """Measures activation state classification accuracy (F1-score)."""
        true_on = (y_true > threshold).astype(int)
        pred_on = (y_pred > threshold).astype(int)
        return f1_score(true_on, pred_on, zero_division=0)

    @staticmethod
    def calculate_sae(y_true, y_pred):
        """Calculates Signal Aggregate Error (SAE)."""
        total_true = np.sum(y_true)
        total_pred = np.sum(y_pred)
        if total_true == 0:
            return 0.0
        return np.abs(total_pred - total_true) / total_true

class CrossDatasetEvaluator:
    """Orchestrates the cross-dataset evaluation protocol."""
    
    def __init__(self, fhmm_service: FHMMService):
        self.fhmm = fhmm_service
        self.data_loader = DataLoader()
        self.metrics = MetricsCalculator()

    def evaluate(self, primary_file, secondary_file, label_mapping, voltage_factor=1.0):
        """
        Executes the evaluation protocol:
        1. Resample and sync secondary data.
        2. Normalize amplitude based on voltage_factor (e.g. 240V/120V).
        3. Run FHMM disaggregation.
        4. Compute F1 and SAE.
        """
        AppLog.info("EVAL_START", f"Starting evaluation on {secondary_file}")
        
        # 1. Load and Sync
        df_secondary = self.data_loader.load_and_sync(secondary_file, label_mapping)
        
        # Assume 'aggregate' is the main power signal column
        if 'aggregate' not in df_secondary.columns:
            raise ValueError("Secondary dataset must contain an 'aggregate' column.")
            
        aggregate_signal = df_secondary['aggregate'].values
        
        # 2. Amplitude Normalization (Geographic hardware adjustment)
        # Apply voltage factor if moving from US (120V) to UK (240V) or vice versa
        normalized_signal = aggregate_signal * voltage_factor
        
        # 3. Disaggregation
        results = self.fhmm.disaggregate(normalized_signal.tolist())
        
        # 4. Metrics Calculation
        evaluation_results = {}
        for appliance, pred_trace in results.items():
            if appliance in df_secondary.columns:
                true_trace = df_secondary[appliance].values
                f1 = self.metrics.calculate_f1(true_trace, pred_trace)
                sae = self.metrics.calculate_sae(true_trace, pred_trace)
                evaluation_results[appliance] = {
                    "F1-Score": round(f1, 4),
                    "SAE": round(sae, 4)
                }
                
        AppLog.info("EVAL_COMPLETE", "Evaluation metrics generated successfully.")
        return evaluation_results

if __name__ == "__main__":
    # Example usage / Mock test
    import os
    
    # Setup mock data paths
    mock_csv = "mock_secondary_data.csv"
    
    # Create mock data mimicking REDD (1Hz)
    timestamps = pd.date_range(start="2026-05-28", periods=100, freq="1S")
    mock_df = pd.DataFrame({
        "timestamp": timestamps,
        "aggregate": np.random.normal(500, 50, 100),
        "fridge": np.random.normal(150, 10, 100),
        "laptop": np.random.normal(50, 5, 100)
    })
    mock_df.to_csv(mock_csv, index=False)
    
    # Initialize components
    try:
        fhmm = FHMMService(signatures_path="../data/appliance_signatures.json")
        evaluator = CrossDatasetEvaluator(fhmm)
        
        # Mapping REDD labels to Project labels
        mapping = {
            "fridge": "Fridge",
            "laptop": "Laptop"
        }
        
        # Execute evaluation (assuming US to UK voltage shift factor of 2.0 for demo)
        report = evaluator.evaluate(None, mock_csv, mapping, voltage_factor=1.0)
        
        print("Cross-Dataset Evaluation Report:")
        for app, metrics in report.items():
            print(f"{app}: {metrics}")
            
    except Exception as e:
        print(f"Error during evaluation: {e}")
    finally:
        if os.path.exists(mock_csv):
            os.remove(mock_csv)
