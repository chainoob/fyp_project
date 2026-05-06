from google.cloud import firestore

# High-level: Type mapping between Firestore documents and ML processing logic.

def to_python_datetime(firestore_val):
    # Expected: Handles both native datetime and Google Timestamp objects.
    if isinstance(firestore_val, firestore.Timestamp):
        return firestore_val.to_datetime()
    return firestore_val

def cast_to_float(value, default=0.0):
    # Ensures numeric data is cast to float64 for scipy.optimize compatibility.
    try:
        return float(value)
    except (TypeError, ValueError):
        return default