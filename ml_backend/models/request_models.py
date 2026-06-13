from pydantic import BaseModel, Field
from typing import Dict, Any, List, Optional

class OptimizationRequest(BaseModel):
    user_id: str = Field(..., alias="userId")
    actual_bill: float = Field(..., alias="actualBill")
    
    class Config:
        populate_by_name = True

class SyncRequest(BaseModel):
    user_id: str = Field(..., alias="userId")
    context: Dict[str, Any]
    
    class Config:
        populate_by_name = True

class DisaggregationRequest(BaseModel):
    user_id: str = Field(..., alias="userId")
    aggregate_readings: List[float] = Field(..., alias="aggregateReadings", min_length=1)
    device_states: Dict[str, Optional[float]] = Field(default_factory=dict, alias="networkStates")
    manual_overrides: Dict[str, Optional[float]] = Field(default_factory=dict, alias="manualOverrides")

    class Config:
        populate_by_name = True

class BatchDisaggregationRequest(BaseModel):
    user_id: str = Field(..., alias="userId")
    month: int
    year: int
    total_bill: float = Field(..., alias="totalBill")
    scope: str = "Unit"
    train_model: bool = Field(False, alias="trainModel")
    telemetry_source_id: Optional[str] = Field(None, alias="telemetrySourceId")
    block_id: Optional[str] = Field(None, alias="blockId")
    
    class Config:
        populate_by_name = True
    
class FeedbackRequest(BaseModel):
    user_id: str = Field(..., alias="userId")
    appliance_name: str = Field(..., alias="applianceName")
    timestamp: Optional[str] = None
    actual_state: bool = Field(..., alias="actualState")
    predicted_state: bool = Field(..., alias="predictedState")
    
    class Config:
        populate_by_name = True

class SeedReddRequest(BaseModel):
    user_id: str = Field(..., alias="userId")
    month: int
    year: int
    
    class Config:
        populate_by_name = True

class AggregationRequest(BaseModel):
    month: int
    year: int
    block_id: Optional[str] = Field(None, alias="blockId")

    class Config:
        populate_by_name = True

class ForecastRequest(BaseModel):
    user_id: str
    target_month: int
    target_year: int
    days_to_predict: int = 30
    manual_overrides: Dict[str, float] = Field(default_factory=dict)
    
    class Config:
        populate_by_name = True