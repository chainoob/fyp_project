import sys
import os
import argparse
import json
import pandas as pd
import numpy as np
from sklearn.metrics import f1_score
from typing import Dict, List, Any, Optional

# Align Python path to root directory
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from services.fhmm_service import FHMMService
from utils.logger import AppLog

class DataLoader:
    """Handles time-series telemetry ingestion, format parsing, and alignment."""
    
    def __init__(self, target_frequency: str = '6s'):
        self.target_frequency = target_frequency

    def load_file(self, file_path: str, is_dat: bool = False, col_name: str = 'power') -> pd.DataFrame:
        """Loads a CSV, space-separated DAT file, or HDF5 file with specified key mapping."""
        h5_key = None
        if '.h5:' in file_path:
            file_path, h5_key = file_path.split('.h5:', 1)
            file_path = file_path + '.h5'
            
        if not os.path.exists(file_path):
            raise FileNotFoundError(f"File not found: {file_path}")
            
        if h5_key is not None:
            import tables
            # Load HDF5 using PyTables directly to bypass version mismatch type errors in pandas.read_hdf
            AppLog.info("H5_LOAD", f"Reading node {h5_key} from {file_path} using PyTables")
            with tables.open_file(file_path, 'r') as f:
                node_path = h5_key.rstrip('/') + '/table' if not h5_key.endswith('/table') else h5_key
                node = f.get_node(node_path)
                data = node.read()
                
            power_data = data['values_block_0'].flatten()
            timestamps = pd.to_datetime(data['index'], unit='ns', utc=True)
            
            df = pd.DataFrame({col_name: power_data}, index=timestamps)
            df.index.name = 'timestamp'
            return df
            
        if is_dat:
            # Space-separated raw dat file: epoch_timestamp power_val
            df = pd.read_csv(
                file_path, 
                sep=r'\s+', 
                header=None, 
                names=['timestamp', col_name],
                dtype={'timestamp': float, col_name: float}
            )
            df['timestamp'] = pd.to_datetime(df['timestamp'], unit='s', utc=True)
            df.set_index('timestamp', inplace=True)
        else:
            # Standard CSV file
            df = pd.read_csv(file_path)
            df.columns = [col.lower() for col in df.columns]
            
            # Find the timestamp/time column dynamically to support standard formats and REFIT Time/Unix headers
            time_col = None
            for col in ['timestamp', 'time', 'datetime', 'unix']:
                if col in df.columns:
                    time_col = col
                    break
                    
            if time_col is None:
                raise ValueError(f"CSV file {file_path} must contain a 'timestamp', 'time', or 'datetime' column.")
                
            # Rename the selected column to 'timestamp'
            df = df.rename(columns={time_col: 'timestamp'})
            
            first_val = df['timestamp'].iloc[0] if len(df) > 0 else ""
            try:
                float(first_val)
                # Parse numeric unix epoch timestamps
                df['timestamp'] = pd.to_datetime(df['timestamp'].astype(float), unit='s', utc=True)
            except ValueError:
                df['timestamp'] = pd.to_datetime(df['timestamp'], utc=True)
                
            df.set_index('timestamp', inplace=True)
            
        return df

    def align_channels(self, aggregate_path: str, appliance_paths: Dict[str, str], is_dat: bool = True) -> pd.DataFrame:
        """Loads aggregate power and appliance ground truth signals, aligns and resamples them."""
        AppLog.info("ALIGN_CHANNELS", f"Loading aggregate power from {aggregate_path}")
        agg_is_h5 = '.h5:' in aggregate_path
        df_agg = self.load_file(aggregate_path, is_dat=(is_dat and not agg_is_h5), col_name='aggregate')
        
        # Resample aggregate individually first to limit memory consumption
        df_agg_resampled = df_agg.resample(self.target_frequency).mean().ffill().bfill()
        
        aligned_dfs = [df_agg_resampled]
        
        for appliance_name, path in appliance_paths.items():
            AppLog.info("ALIGN_CHANNELS", f"Loading {appliance_name} power from {path}")
            app_is_h5 = '.h5:' in path
            df_app = self.load_file(path, is_dat=(is_dat and not app_is_h5), col_name=appliance_name)
            df_app_resampled = df_app.resample(self.target_frequency).mean().ffill().bfill()
            aligned_dfs.append(df_app_resampled)
            
        # Join all channels on datetime index
        df_aligned = aligned_dfs[0]
        for df in aligned_dfs[1:]:
            df_aligned = df_aligned.join(df, how='inner')
            
        df_aligned = df_aligned.ffill().bfill()
        return df_aligned

class AmplitudeNormalizer:
    """Handles voltage and power characteristic normalization adjustments."""
    
    @staticmethod
    def normalize(data: np.ndarray, method: str = 'zscore') -> np.ndarray:
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
    def calculate_f1(y_true: np.ndarray, y_pred: np.ndarray, threshold: float = 5.0) -> float:
        """Measures activation state classification accuracy (F1-score)."""
        true_on = (y_true > threshold).astype(int)
        pred_on = (y_pred > threshold).astype(int)
        return float(f1_score(true_on, pred_on, zero_division=0))

    @staticmethod
    def calculate_sae(y_true: np.ndarray, y_pred: np.ndarray) -> float:
        """Calculates Signal Aggregate Error (SAE)."""
        total_true = np.sum(y_true)
        total_pred = np.sum(y_pred)
        if total_true == 0.0:
            return 0.0 if total_pred == 0.0 else 1.0
        return float(np.abs(total_pred - total_true) / total_true)

    @staticmethod
    def calculate_mae(y_true: np.ndarray, y_pred: np.ndarray) -> float:
        """Calculates Mean Absolute Error (MAE) in Watts."""
        return float(np.mean(np.abs(y_true - y_pred)))

class CrossDatasetEvaluator:
    """Orchestrates the cross-dataset evaluation protocol."""
    
    def __init__(self, fhmm_service: FHMMService, target_frequency: str = '6s'):
        self.fhmm = fhmm_service
        self.data_loader = DataLoader(target_frequency=target_frequency)
        self.metrics = MetricsCalculator()

    def evaluate_consolidated(self, file_path: str, label_mapping: Dict[str, str]) -> Dict[str, Any]:
        """Runs evaluation using a single consolidated CSV file containing both aggregate and appliance signals."""
        AppLog.info("EVAL_START", f"Starting evaluation on consolidated file: {file_path}")
        df = self.data_loader.load_file(file_path, is_dat=False)
        
        normalized_mapping = {k.lower(): v for k, v in label_mapping.items()}
        df = df.rename(columns=normalized_mapping)
        
        df_resampled = df.resample(self.data_loader.target_frequency).mean().ffill().bfill()
        
        if 'aggregate' not in df_resampled.columns:
            agg_cols = [col for col in df_resampled.columns if col.lower() == 'aggregate']
            if agg_cols:
                df_resampled.rename(columns={agg_cols[0]: 'aggregate'}, inplace=True)
            else:
                raise ValueError("Dataset must contain an 'aggregate' column.")
                
        return self._run_disaggregation_and_metrics(df_resampled)

    def evaluate_raw_channels(self, aggregate_path: str, appliance_paths: Dict[str, str], is_dat: bool = True) -> Dict[str, Any]:
        """Runs evaluation using raw independent channel files (e.g. UK-DALE house channels)."""
        AppLog.info("EVAL_START", f"Starting evaluation aligning {len(appliance_paths)} channels with {aggregate_path}")
        df_aligned = self.data_loader.align_channels(aggregate_path, appliance_paths, is_dat=is_dat)
        return self._run_disaggregation_and_metrics(df_aligned)

    def _run_disaggregation_and_metrics(self, df: pd.DataFrame) -> Dict[str, Any]:
        aggregate_signal = df['aggregate'].values
        assert len(aggregate_signal) > 0, "Aggregate signal length must be greater than 0."
        
        results = self.fhmm.disaggregate(aggregate_signal.tolist())
        
        evaluation_results = {}
        for appliance, pred_trace in results.items():
            if appliance in df.columns:
                true_trace = df[appliance].values
                assert len(true_trace) == len(pred_trace), "True and predicted trace lengths must align."
                
                f1 = self.metrics.calculate_f1(true_trace, np.array(pred_trace))
                sae = self.metrics.calculate_sae(true_trace, np.array(pred_trace))
                mae = self.metrics.calculate_mae(true_trace, np.array(pred_trace))
                
                evaluation_results[appliance] = {
                    "F1-Score": round(f1, 4),
                    "SAE": round(sae, 4),
                    "MAE (W)": round(mae, 4)
                }
                
        AppLog.info("EVAL_COMPLETE", "Evaluation metrics generated successfully.")
        return evaluation_results

def generate_mock_uk_dale_dir(base_dir: str):
    """Generates a mock directory mimicking raw UK-DALE house structure with dat files."""
    os.makedirs(base_dir, exist_ok=True)
    
    start_time = 1775000000
    timestamps = np.array([start_time + i * 6 for i in range(100)])
    
    laptop_power = np.zeros(100)
    laptop_power[20:60] = 65.0
    
    fan_power = np.zeros(100)
    fan_power[40:80] = 40.0
    
    baseline = np.random.normal(15.0, 1.0, 100)
    aggregate_power = laptop_power + fan_power + baseline
    
    df_agg = pd.DataFrame({'timestamp': timestamps, 'power': aggregate_power})
    df_agg.to_csv(os.path.join(base_dir, 'channel_1.dat'), sep=' ', header=False, index=False)
    
    df_laptop = pd.DataFrame({'timestamp': timestamps, 'power': laptop_power})
    df_laptop.to_csv(os.path.join(base_dir, 'channel_2.dat'), sep=' ', header=False, index=False)
    
    df_fan = pd.DataFrame({'timestamp': timestamps, 'power': fan_power})
    df_fan.to_csv(os.path.join(base_dir, 'channel_3.dat'), sep=' ', header=False, index=False)
    
    AppLog.info("MOCK_GENERATE", f"Generated mock UK-DALE directory at {base_dir}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="UK-DALE / REDD / REFIT Cross-Dataset NILM Evaluator")
    parser.add_argument('--consolidated-csv', type=str, help="Path to single aligned CSV file")
    parser.add_argument('--appliance-map', nargs='+', help="Appliance column mapping for consolidated CSV (e.g. Laptop=Appliance7 Kettle=Appliance9)")
    parser.add_argument('--aggregate-dat', type=str, help="Path to aggregate power DAT/CSV/H5 file")
    parser.add_argument('--appliance-dat', nargs='+', action='append', help="Appliance channel files as ApplianceName=path pairs (e.g. Laptop=channel_2.dat or Laptop=ukdale.h5:/building1/elec/meter2)")
    parser.add_argument('--resample-freq', type=str, default='6s', help="Target resample frequency (e.g., 6s, 8s, 1min)")
    parser.add_argument('--signatures-path', type=str, default=None, help="Path to appliance signatures JSON file")
    parser.add_argument('--output-report', type=str, help="Path to save evaluation JSON report")
    parser.add_argument('--generate-mock-dir', type=str, help="Path to generate mock UK-DALE directory for testing")
    
    args = parser.parse_args()
    
    sig_path = args.signatures_path
    if sig_path is None:
        sig_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'data', 'appliance_signatures.json'))
        
    if args.generate_mock_dir:
        generate_mock_uk_dale_dir(args.generate_mock_dir)
        print(f"Mock UK-DALE data generated at: {args.generate_mock_dir}")
        sys.exit(0)
        
    try:
        fhmm = FHMMService(signatures_path=sig_path)
        evaluator = CrossDatasetEvaluator(fhmm, target_frequency=args.resample_freq)
        
        report = {}
        if args.consolidated_csv:
            # Build label mapping
            label_mapping = {}
            if args.appliance_map:
                for mapping_pair in args.appliance_map:
                    if '=' in mapping_pair:
                        target, source = mapping_pair.split('=', 1)
                        # Map source (e.g. Appliance7) to target (e.g. Laptop)
                        label_mapping[source] = target
                    else:
                        print(f"Skipping invalid mapping pair: {mapping_pair}. Must be Target=Source")
            else:
                # Default fallback mappings
                label_mapping = {
                    "laptop": "Laptop",
                    "fan": "Fan",
                    "charger": "Charger",
                    "lamp": "Lamp",
                    "iron": "Iron",
                    "kettle": "Kettle",
                    "printer": "Printer"
                }
            report = evaluator.evaluate_consolidated(args.consolidated_csv, label_mapping)
        elif args.aggregate_dat and args.appliance_dat:
            appliance_paths = {}
            for app_list in args.appliance_dat:
                for app_pair in app_list:
                    if '=' in app_pair:
                        name, path = app_pair.split('=', 1)
                        appliance_paths[name] = path
                    else:
                        print(f"Skipping invalid appliance-dat pair: {app_pair}. Must be Name=Path")
            
            report = evaluator.evaluate_raw_channels(
                args.aggregate_dat, 
                appliance_paths, 
                is_dat=args.aggregate_dat.endswith('.dat') or '.dat' in args.aggregate_dat
            )
        else:
            parser.print_help()
            print("\nError: Please provide either --consolidated-csv OR both --aggregate-dat and --appliance-dat.")
            sys.exit(1)
            
        print("\nCross-Dataset Evaluation Report:")
        print(json.dumps(report, indent=4))
        
        if args.output_report:
            with open(args.output_report, 'w') as f:
                json.dump(report, f, indent=4)
            AppLog.info("REPORT_SAVED", f"Saved report to {args.output_report}")
            
    except Exception as e:
        AppLog.error("CLI_EXECUTION_FAILURE", str(e))
        import traceback
        traceback.print_exc()
        sys.exit(1)
