import base64
import datetime
import json
import os
import firebase_admin
from firebase_admin import credentials, firestore
from utils.logger import AppLog
from utils.secrets import get_secret

class FirebaseClient:
    # High-level: Centralized Firestore client with Cloud Run and local credential support.

    def __init__(self):
        # High-level: Initialize the Firestore SDK and establish the database client.
        self.credential_source = "uninitialized"
        self._setup_credentials()
        self.db = firestore.client()

    def _setup_credentials(self):
        # High-level: Configures SDK using Secret Manager, ADC, or local JSON fallback.
        if firebase_admin._apps:
            # Developer Expectation: Prevent re-initialization if the app context is already active.
            return

        # Production Path 1: Google Cloud Secret Manager
        sa_json, source = get_secret("FIREBASE_SERVICE_ACCOUNT")
        if sa_json:
            try:
                # Payload can be raw JSON or Base64 (handle both for legacy compatibility)
                try:
                    cert_dict = json.loads(sa_json)
                except (json.JSONDecodeError, TypeError):
                    decoded_bytes = base64.b64decode(sa_json)
                    cert_dict = json.loads(decoded_bytes)
                
                cred = credentials.Certificate(cert_dict)
                self.credential_source = "secret_manager"
                AppLog.info("FIREBASE_INIT", "Credentials initialized via Secret Manager.")
            except Exception as e:
                AppLog.error("FIREBASE_INIT", f"Secret Manager credential parsing failed: {str(e)}")
                raise
        else:
            try:
                # Production Path 2: Application Default Credentials (ADC)
                cred = credentials.ApplicationDefault()
                self.credential_source = "adc"
                AppLog.info("FIREBASE_INIT", "Using Application Default Credentials (ADC).")
            except Exception:
                # Development Path: Local JSON Fallback (DEBUG mode only)
                if os.environ.get("DEBUG", "false").lower() == "true":
                    try:
                        cred = credentials.Certificate("serviceAccountKey.json")
                        self.credential_source = "local_file"
                        AppLog.info("FIREBASE_INIT", "Falling back to local serviceAccountKey.json.")
                    except Exception as e:
                        AppLog.error("FIREBASE_INIT", "Local fallback failed.")
                        raise FileNotFoundError("Local serviceAccountKey.json not found.")
                else:
                    AppLog.error("FIREBASE_INIT", "No valid credentials found. Deployment likely misconfigured.")
                    raise RuntimeError("No valid Firebase credentials found.")

        firebase_admin.initialize_app(cred)

    def get_user_appliances(self, user_id: str):
        # High-level: Stream active appliance documents with explicit gRPC error interception.
        try:
            AppLog.info("FIRESTORE_READ", f"Fetching active appliances for user: {user_id}")
            docs = self.db.collection('users').document(user_id).collection('appliances') \
                .where('status', '==', 'active').stream()
            
            result = {doc.id: doc.to_dict() for doc in docs}
            AppLog.info("FIRESTORE_READ", f"Retrieved {len(result)} active appliances.")
            return result
        except Exception as e:
            # Developer Expectation: Log full trace context for permission or connectivity failures.
            AppLog.error("FIRESTORE_READ", f"Read failure for user {user_id}: {str(e)}")
            raise e

    def update_appliance_weights(self, user_id: str, appliances: dict, new_weights: list):
        # High-level: Executes atomic batch update of appliance probability weights.
        try:
            batch = self.db.batch()
            for i, (app_id, _) in enumerate(appliances.items()):
                doc_ref = self.db.collection('users').document(user_id) \
                    .collection('appliances').document(app_id)
                batch.update(doc_ref, {
                    "prob_day": float(new_weights[i]),
                    "prob_night": float(new_weights[i])
                })
            batch.commit()
            AppLog.info("FIRESTORE_BATCH", f"Weights updated for {len(appliances)} appliances.")
        except Exception as e:
            AppLog.error("FIRESTORE_BATCH", f"Batch update failed: {str(e)}")
            raise e

    def save_disaggregation_result(self, payload: dict):
        # High-level: Persists disaggregation model output with explicit type-safety checks.
        try:
            # Developer Expectation: Deep inspection loop to catch non-serializable NumPy types before commit.
            for key, value in payload.items():
                if isinstance(value, dict):
                    for sub_key, sub_value in value.items():
                        if "numpy" in str(type(sub_value)):
                            AppLog.error("SERIALIZATION", f"Numpy contaminant found: payload['{key}']['{sub_key}']")
            
            self.db.collection('disaggregation_results').add(payload)
            AppLog.info("FIRESTORE_SAVE", f"Disaggregation result saved for user: {payload.get('userId')}")
        except Exception as e:
            AppLog.error("FIRESTORE_SAVE", f"Transaction aborted: {str(e)}")
            raise e

    def save_daily_usage(self, user_id: str, hourly_profile: dict):
        # High-level: Stores daily time-series breakdown for UI visualization.
        try:
            date_str = datetime.date.today().isoformat()
            doc_ref = self.db.collection('users').document(user_id) \
                .collection('daily_usage').document(date_str)
            
            # Developer Expectation: Use SERVER_TIMESTAMP to maintain consistency across global locations.
            doc_ref.set({
                "kwh": sum(hourly_profile.values()),
                "hourly_breakdown": hourly_profile,
                "timestamp": firestore.SERVER_TIMESTAMP
            })
            AppLog.info("FIRESTORE_DAILY", f"Daily usage synced for {user_id} on {date_str}")
        except Exception as e:
            AppLog.error("FIRESTORE_DAILY", f"Daily sync failed: {str(e)}")
            raise e

    def log_feedback(self, data: dict):
        # High-level: Archives user-submitted ground truth for future model retraining.
        try:
            feedback_ref = self.db.collection('users').document(data['user_id']).collection('feedback')
            feedback_ref.add({
                "appliance": data['appliance_name'],
                "was_correct": data['actual_state'] == data['predicted_state'],
                "actual_state": data['actual_state'],
                "timestamp": data['timestamp'],
                "logged_at": firestore.SERVER_TIMESTAMP
            })
            AppLog.info("FIRESTORE_FEEDBACK", f"Feedback logged for appliance: {data['appliance_name']}")
        except Exception as e:
            AppLog.error("FIRESTORE_FEEDBACK", f"Feedback logging failed: {str(e)}")

    def update_single_appliance_prob(self, user_id: str, app_name: str, new_prob: float):
        # High-level: Updates weight parameters for a single specific appliance.
        try:
            app_ref = self.db.collection('users').document(user_id) \
                .collection('appliances').document(app_name)
            app_ref.update({
                "prob_day": new_prob,
                "prob_night": new_prob
            })
            AppLog.info("FIRESTORE_UPDATE", f"Updated {app_name} probability to {new_prob}")
        except Exception as e:
            AppLog.error("FIRESTORE_UPDATE", f"Single update failed for {app_name}: {str(e)}")