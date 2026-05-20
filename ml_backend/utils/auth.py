# utils/auth.py

from fastapi import Header, HTTPException
from firebase_admin import auth
import logging

logger = logging.getLogger(__name__)

async def verify_firebase_token(authorization: str = Header(None)):
    """
    High-level: Parse and validate inbound bearer tokens via Firebase Admin SDK.
    Hardened with audience (Project ID) validation.
    """
    if not authorization or not authorization.startswith("Bearer "):
        logger.warning("Missing or malformed Authorization header")
        raise HTTPException(
            status_code=401, 
            detail="Authorization header missing or invalid. Use 'Bearer <token>'."
        )
    
    id_token = authorization.split("Bearer ")[1]
    try:
        # Developer Expectation: Live network revocation check is active.
        # Audience check is implicitly handled by the Admin SDK using the initialized app context,
        # but we can explicitly verify if needed for multi-tenant setups.
        decoded_token = auth.verify_id_token(id_token, check_revoked=True)
        
        # Point 4: Hardening - Ingress control check (mock for demonstration)
        # In a real GCP environment, you would check for the 'X-Cloud-Trace-Context' 
        # or specific Gateway headers here to ensure requests come through the API Gateway.
        
        return decoded_token
    except auth.ExpiredIdTokenError:
        raise HTTPException(status_code=401, detail="Token has expired. Please refresh on client.")
    except auth.InvalidIdTokenError:
        raise HTTPException(status_code=401, detail="Token is invalid.")
    except Exception as e:
        logger.error(f"Auth verification failed: {str(e)}")
        raise HTTPException(status_code=401, detail="Authentication failed.")

def validate_user_ownership(request_user_id: str, token_uid: str, is_staff: bool = False):
    """
    High-level: Assert cross-resource identity matches the token context.
    Staff members bypass the ownership check to allow administrative access.
    """
    if is_staff:
        # Developer Expectation: Staff can access any resource (e.g., Campus overview).
        return

    if request_user_id != token_uid:
        logger.warning(f"Security Alert: User {token_uid} attempted to access data for {request_user_id}")
        raise HTTPException(
            status_code=403, 
            detail="Forbidden: You do not have permission to access this resource."
        )