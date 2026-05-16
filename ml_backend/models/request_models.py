# ml_backend/models/request_models.py

from pydantic import BaseModel
from typing import Dict, Any

class OptimizationRequest(BaseModel):
    # Expects userId for database lookup and actualBill for objective targeting.
    user_id: str
    actual_bill: float

class SyncRequest(BaseModel):
    # Expects userId and environmental/contextual keys like temperature.
    user_id: str
    context: Dict[str, Any]

class DisaggregationRequest(BaseModel):
    # Expects a list of aggregate power readings to be separated.
    user_id: str
    aggregate_readings: list[float]
    
class FeedbackRequest(BaseModel):
    # High-level: Schema for capturing student corrections of AI predictions.
    user_id: str
    appliance_name: str
    timestamp: str  
    actual_state: bool  
    predicted_state: bool