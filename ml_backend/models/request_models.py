# ml_backend/models/request_models.py

from pydantic import BaseModel, Field
from typing import Dict, Any, List

class OptimizationRequest(BaseModel):
    # Expects userId for database lookup and actualBill for objective targeting.
    user_id: str
    actual_bill: float

class SyncRequest(BaseModel):
    # Expects userId and environmental/contextual keys like temperature.
    user_id: str
    context: Dict[str, Any]

class DisaggregationRequest(BaseModel):
    user_id: str = Field(..., alias="userId")
    # High-level: Enforce minimum item boundaries on time-series telemetry vectors.
    aggregate_readings: List[float] = Field(..., alias="aggregateReadings", min_length=1)

    class Config:
        populate_by_name = True

class BatchDisaggregationRequest(BaseModel):
    # High-level: Schema for triggering a full month disaggregation via historical telemetry lookup.
    user_id: str = Field(..., alias="userId")
    month: int
    year: int
    total_bill: float = Field(..., alias="totalBill")
    scope: str = "Unit"
    train_model: bool = Field(False, alias="trainModel")
    
    class Config:
        populate_by_name = True
    
class FeedbackRequest(BaseModel):
    # High-level: Schema for capturing student corrections of AI predictions.
    user_id: str
    appliance_name: str
    timestamp: str  
    actual_state: bool  
    predicted_state: bool

class SeedReddRequest(BaseModel):
    user_id: str
    month: int
    year: int