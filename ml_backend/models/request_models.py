# ml_backend/models/request_models.py

from pydantic import BaseModel, Field
from typing import Dict, Any, List, Optional

class OptimizationRequest(BaseModel):
    user_id: str
    actual_bill: float

class SyncRequest(BaseModel):
    user_id: str
    context: Dict[str, Any]

class DisaggregationRequest(BaseModel):
    user_id: str = Field(..., alias="userId")
    aggregate_readings: List[float] = Field(..., alias="aggregateReadings", min_length=1)
    device_states: Dict[str, Optional[float]] = Field(default_factory=dict, alias="deviceStates")

    class Config:
        populate_by_name = True

class BatchDisaggregationRequest(BaseModel):
    user_id: str = Field(..., alias="userId")
    month: int
    year: int
    total_bill: float = Field(..., alias="totalBill")
    scope: str = "Unit"
    train_model: bool = Field(False, alias="trainModel")
    
    class Config:
        populate_by_name = True
    
class FeedbackRequest(BaseModel):
    user_id: str
    appliance_name: str
    timestamp: str  
    actual_state: bool  
    predicted_state: bool

class SeedReddRequest(BaseModel):
    user_id: str
    month: int
    year: int