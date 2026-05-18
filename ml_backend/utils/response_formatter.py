from datetime import datetime
from typing import Any
from fastapi.responses import JSONResponse
from fastapi.encoders import jsonable_encoder

# Standardize API output schemas for frontend consumption.

def format_api_response(success: bool, data: Any = None, message: str = "", status_code: int = None) -> JSONResponse:
    # High-level: Returns a FastAPI Response object for consistent schema and status code handling.
    content = {
        "status": "success" if success else "error",
        "data": data,
        "message": message,
        "timestamp": datetime.now().isoformat()
    }
    
    # Default to 200 for success, 500 for generic failure if not specified.
    if status_code is None:
        status_code = 200 if success else 500
        
    # Developer Expectation: jsonable_encoder automatically converts nested datetime structures into ISO strings.
    return JSONResponse(content=jsonable_encoder(content), status_code=status_code)