from datetime import datetime
from typing import Any, Dict

# High-level: Standardizes API output schemas for frontend consumption.

def format_api_response(success: bool, data: Any = None, message: str = "") -> Dict[str, Any]:
    # Returns a consistent wrapper for success and error states.
    return {
        "status": "success" if success else "error",
        "data": data,
        "message": message,
        "timestamp": datetime.now().isoformat()
    }