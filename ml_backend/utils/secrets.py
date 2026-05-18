# ml_backend/utils/secrets.py

import os
from google.cloud import secretmanager
from utils.logger import AppLog

def get_secret(secret_id: str, version_id: str = "latest") -> tuple[str, str]:
    """
    Fetch secret payload from Google Cloud Secret Manager.
    Returns: (secret_value, source_label)
    """
    # Check Environment First (Fastest Fallback)
    env_val = os.environ.get(secret_id.upper())
    if env_val:
        AppLog.info("SECRETS", f"Resolved {secret_id} from Environment Variable.")
        return env_val, "environment"

    try:
        client = secretmanager.SecretManagerServiceClient()
        # Fallback to local project ID if not set
        project_id = os.environ.get("GOOGLE_CLOUD_PROJECT") or os.environ.get("PROJECT_ID")
        
        if not project_id:
            AppLog.warning("SECRETS", f"Cannot fetch {secret_id}: GOOGLE_CLOUD_PROJECT not set.")
            return "", "none"

        name = f"projects/{project_id}/secrets/{secret_id}/versions/{version_id}"
        response = client.access_secret_version(request={"name": name})
        val = response.payload.data.decode("UTF-8")
        
        AppLog.info("SECRETS", f"Resolved {secret_id} from Secret Manager.")
        return val, "secret_manager"
    except Exception as e:
        AppLog.debug("SECRETS", f"Secret Manager fetch failed for {secret_id}: {str(e)}")
        return "", "none"
