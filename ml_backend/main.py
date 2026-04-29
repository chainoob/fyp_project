from fastapi import FastAPI
from pydantic import BaseModel
from utils.behavioral_simulator import AdaptiveBehavioralSimulator
from services.firebase_client import FirebaseDatabase
import datetime

app = FastAPI()
db = FirebaseDatabase()
simulator = AdaptiveBehavioralSimulator(iterations=2000)

class DisaggregateRequest(BaseModel):
    userId: str
    blockId: str
    billTotal: float
    month: str
    temperature: float = 30.0 # Default fallback
    isWeekend: bool = False
    pollIronUsed: bool = True # Extracted from Firestore user doc

@app.post("/api/v1/disaggregate")
async def process_telemetry(request: DisaggregateRequest):
    # Fetch registered appliances from Firebase
    registered_appliances = db.get_user_appliances(request.userId) 
    
    # 1. Execute Monte Carlo Forecast
    context = {
        "temperature": request.temperature,
        "is_weekend": request.isWeekend,
        "poll_iron_used_today": request.pollIronUsed
    }
    forecast_array = simulator.run_monte_carlo(registered_appliances, context)

    # 2. Execute CMOEA Disaggregation (Constraint Solver)
    # engine.run(request.billTotal, registered_appliances)
    # mock_breakdown = ...

    # 3. Write Unified Payload to Firestore
    payload = {
        "estimated_load": request.billTotal,
        "breakdown": {"Fan": 150.0, "Laptop": 50.0}, # Output from CMOEA
        "hourlyUsage": forecast_array,               # Output from Monte Carlo
        "difference": 12.5,
        "timestamp": datetime.datetime.now()
    }
    db.save_disaggregation_result(request.userId, payload)
    
    return {"status": "success"}