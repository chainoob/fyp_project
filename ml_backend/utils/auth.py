# utils/auth.py

from fastapi import Header, HTTPException
from firebase_admin import auth
import logging

logger = logging.getLogger(__name__)

async def verify_firebase_token(authorization: str = Header(None)):
    """
    High-level: Parse and validate inbound bearer tokens via Firebase Admin SDK.
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
        decoded_token = auth.verify_id_token(id_token, check_revoked=True)
        return decoded_token
    except auth.ExpiredIdTokenError:
        raise HTTPException(status_code=401, detail="Token has expired.")
    except auth.InvalidIdTokenError:
        raise HTTPException(status_code=401, detail="Token is invalid.")
    except Exception as e:
        logger.error(f"Auth verification failed: {str(e)}")
        raise HTTPException(status_code=401, detail="Authentication failed.")

def validate_user_ownership(request_user_id: str, token_uid: str):
    """
    High-level: Assert cross-resource identity matches the token context.
    """
    if request_user_id != token_uid:
        logger.warning(f"Security Alert: User {token_uid} attempted to access data for {request_user_id}")
        raise HTTPException(
            status_code=403, 
            detail="Forbidden: You do not have permission to access this resource."
        )