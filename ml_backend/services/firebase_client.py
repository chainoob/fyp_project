import base64
import datetime
import json
import os
import firebase_admin
from firebase_admin import credentials, firestore, messaging
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

        #Google Cloud Secret Manager
        sa_json, source = get_secret("FIREBASE_SERVICE_ACCOUNT")
        if sa_json:
            try:
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

    def _clean_numpy(self, data):
        # High-level: Recursively converts NumPy types to native Python types for Firestore serialization.
        if isinstance(data, dict):
            return {k: self._clean_numpy(v) for k, v in data.items()}
        elif isinstance(data, list):
            return [self._clean_numpy(v) for v in data]
        elif "numpy" in str(type(data)):
            return data.item() if hasattr(data, 'item') else float(data)
        return data

    def save_disaggregation_result(self, payload: dict):
        # High-level: Persists disaggregation model output with strict type-safety and logging.
        try:
            AppLog.info("FIRESTORE_SAVE", f"Attempting to save result for {payload.get('userId')} ({payload.get('month')}/{payload.get('year')})")
            
            # Developer Expectation: Deep-clean the payload to prevent gRPC serialization errors.
            cleaned_payload = self._clean_numpy(payload)
            
            # Explicitly ensure timestamp is a native DateTime or SERVER_TIMESTAMP
            if 'timestamp' in cleaned_payload and not isinstance(cleaned_payload['timestamp'], (datetime.datetime, str)):
                cleaned_payload['timestamp'] = firestore.SERVER_TIMESTAMP

            doc_ref = self.db.collection('disaggregation_results').add(cleaned_payload)
            AppLog.info("FIRESTORE_SAVE", f"SUCCESS: Result persisted with ID: {doc_ref[1].id}")
        except Exception as e:
            AppLog.error("FIRESTORE_SAVE", f"CRITICAL PERSISTENCE FAILURE: {str(e)}")
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

    def update_appliance_signature_meta(self, user_id: str, app_name: str, meta: dict):
        # High-level: Persists tuned FHMM emission parameters (std_dev, etc.) to Firestore.
        try:
            app_ref = self.db.collection('users').document(user_id) \
                .collection('appliances').document(app_name)
            app_ref.update(meta)
            AppLog.info("FIRESTORE_META", f"Updated signature metadata for {app_name}: {meta}")
        except Exception as e:
            AppLog.error("FIRESTORE_META", f"Meta update failed for {app_name}: {str(e)}")

    def get_historical_telemetry(self, user_id: str, month: int, year: int):
        # High-level: Fetches historical wattage readings for a specific billing period.
        try:
            # Developer Expectation: Query telemetry collection with timestamp bounds.
            # For simplicity, we fetch the last 1000 readings for that user.
            # Real-world would use start/end date filters.
            docs = self.db.collection('users').document(user_id).collection('telemetry') \
                .order_by('timestamp', direction=firestore.Query.DESCENDING).limit(1000).stream()
            
            readings = [float(doc.to_dict().get('wattage', 0)) for doc in docs]
            AppLog.info("FIRESTORE_READ", f"Fetched {len(readings)} historical readings for user: {user_id}")
            return readings
        except Exception as e:
            AppLog.error("FIRESTORE_READ", f"Failed to fetch historical telemetry: {str(e)}")
            return []

    def get_user_data(self, user_id: str):
        # High-level: Retrieves the base user document for configuration and goals.
        try:
            doc = self.db.collection('users').document(user_id).get()
            return doc.to_dict() if doc.exists else None
        except Exception as e:
            AppLog.error("FIRESTORE_READ", f"Failed to get user data for {user_id}: {str(e)}")
            return None

    def get_user_role(self, user_id: str):
        # High-level: Retrieves the role claim from the Firestore user document.
        try:
            doc = self.db.collection('users').document(user_id).get()
            if doc.exists:
                role = doc.to_dict().get('role', 'student')
                AppLog.info("FIRESTORE_ROLE", f"User {user_id} has role: {role}")
                return role
            AppLog.warning("FIRESTORE_ROLE", f"User {user_id} not found in Firestore, defaulting to student.")
            return 'student'
        except Exception as e:
            AppLog.error("FIRESTORE_ROLE", f"Failed to fetch role for {user_id}: {str(e)}")
            return 'student'

    def get_monthly_consumption(self, user_id: str, month: int, year: int) -> float:
        # High-level: Retrieves aggregated monthly consumption from the user's statistics subcollection.
        try:
            doc_id = f"{year}_{month}"
            doc = self.db.collection('users').document(user_id) \
                .collection('stats').document(doc_id).get()
            
            if doc.exists:
                return float(doc.to_dict().get('total_kwh', 0.0))
            return 0.0
        except Exception as e:
            AppLog.error("FIRESTORE_READ", f"Failed to fetch monthly consumption: {str(e)}")
            return 0.0

    def increment_monthly_consumption(self, user_id: str, month: int, year: int, amount: float):
        # High-level: Atomically increments the monthly consumption counter using Firestore increments.
        try:
            doc_id = f"{year}_{month}"
            doc_ref = self.db.collection('users').document(user_id) \
                .collection('stats').document(doc_id)
            
            doc_ref.set({
                "total_kwh": firestore.Increment(amount),
                "last_updated": firestore.SERVER_TIMESTAMP
            }, merge=True)
            AppLog.info("FIRESTORE_UPDATE", f"Incremented {user_id} monthly total by {amount}")
        except Exception as e:
            AppLog.error("FIRESTORE_UPDATE", f"Failed to increment monthly total: {str(e)}")

    def send_fcm_notification(self, user_id: str, title: str, body: str):
        # High-level: Dispatches push notifications to the student's mobile device.
        try:
            user_doc = self.db.collection('users').document(user_id).get()
            if not user_doc.exists:
                AppLog.warning("FCM_SEND", f"User {user_id} not found.")
                return

            token = user_doc.to_dict().get('fcmToken')
            if not token:
                AppLog.warning("FCM_SEND", f"No FCM token registered for user: {user_id}")
                return

            message = messaging.Message(
                notification=messaging.Notification(
                    title=title,
                    body=body
                ),
                token=token
            )
            
            response = messaging.send(message)
            AppLog.info("FCM_SEND", f"Notification sent successfully: {response}")
        except Exception as e:
            AppLog.error("FCM_SEND", f"Failed to dispatch FCM: {str(e)}")