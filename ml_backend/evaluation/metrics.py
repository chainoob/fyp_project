import numpy as np
from sklearn.metrics import f1_score, precision_score, recall_score, accuracy_score
from typing import Union

def calculate_f1(y_true: np.ndarray, y_pred: np.ndarray, threshold: float = 5.0) -> float:
    """Measures activation state classification accuracy (F1-score)."""
    true_on = (y_true > threshold).astype(int)
    pred_on = (y_pred > threshold).astype(int)
    if np.sum(true_on) == 0 and np.sum(pred_on) == 0:
        return 1.0
    return float(f1_score(true_on, pred_on, zero_division=0))

def calculate_precision(y_true: np.ndarray, y_pred: np.ndarray, threshold: float = 5.0) -> float:
    """Measures activation state precision."""
    true_on = (y_true > threshold).astype(int)
    pred_on = (y_pred > threshold).astype(int)
    if np.sum(true_on) == 0 and np.sum(pred_on) == 0:
        return 1.0
    return float(precision_score(true_on, pred_on, zero_division=0))

def calculate_recall(y_true: np.ndarray, y_pred: np.ndarray, threshold: float = 5.0) -> float:
    """Measures activation state recall."""
    true_on = (y_true > threshold).astype(int)
    pred_on = (y_pred > threshold).astype(int)
    if np.sum(true_on) == 0 and np.sum(pred_on) == 0:
        return 1.0
    return float(recall_score(true_on, pred_on, zero_division=0))

def calculate_accuracy(y_true: np.ndarray, y_pred: np.ndarray, threshold: float = 5.0) -> float:
    """Measures activation state accuracy."""
    true_on = (y_true > threshold).astype(int)
    pred_on = (y_pred > threshold).astype(int)
    return float(accuracy_score(true_on, pred_on))

def calculate_mae(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    """Calculates Mean Absolute Error (MAE) in Watts."""
    return float(np.mean(np.abs(y_true - y_pred)))

def calculate_rmse(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    """Calculates Root Mean Squared Error (RMSE) in Watts."""
    return float(np.sqrt(np.mean((y_true - y_pred) ** 2)))

def calculate_sae(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    """Calculates Signal Aggregate Error (SAE)."""
    total_true = np.sum(y_true)
    total_pred = np.sum(y_pred)
    if total_true == 0.0:
        return 0.0 if total_pred == 0.0 else 1.0
    return float(np.abs(total_pred - total_true) / total_true)

def calculate_mape(y_true: np.ndarray, y_pred: np.ndarray) -> float:
    """Calculates Mean Absolute Percentage Error (MAPE)."""
    mask = y_true != 0.0
    if not np.any(mask):
        return 0.0 if np.all(y_pred == 0.0) else 1.0
    return float(np.mean(np.abs((y_true[mask] - y_pred[mask]) / y_true[mask])))
