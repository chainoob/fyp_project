import base64
import datetime
import json
import os
import asyncio

import firebase_admin
from firebase_admin import credentials, messaging, firestore
from google.cloud import firestore as gcp_firestore
from google.oauth2 import service_account
import google.auth

from utils.logger import AppLog
from utils.secrets import get_secret

class FirebaseClient:
    def __init__(self):
        if not firebase_admin._apps:
            if os.getenv("K_SERVICE"):
                firebase_admin.initialize_app() 
            elif os.path.exists("serviceAccountKey.json"):
                cred = credentials.Certificate("serviceAccountKey.json")
                firebase_admin.initialize_app(cred)
            else:
                try:
                    cred = credentials.ApplicationDefault()
                    firebase_admin.initialize_app(cred)
                except Exception:
                    firebase_admin.initialize_app()
                
        self.db = firestore.client()

    def _setup_credentials(self):
        sa_json, source = get_secret("FIREBASE_SERVICE_ACCOUNT")
        if sa_json:
            try:
                try:
                    cert_dict = json.loads(sa_json)
                except (json.JSONDecodeError, TypeError):
                    decoded_bytes = base64.b64decode(sa_json)
                    cert_dict = json.loads(decoded_bytes)
                
                if not firebase_admin._apps:
                    cred = credentials.Certificate(cert_dict)
                    firebase_admin.initialize_app(cred)

                self.gcp_creds = service_account.Credentials.from_service_account_info(cert_dict)
                self.credential_source = "secret_manager"
                AppLog.info("FIREBASE_INIT", "Credentials initialized via Secret Manager.")
            except Exception as e:
                AppLog.error("FIREBASE_INIT", f"Secret Manager credential parsing failed: {str(e)}")
                raise
        else:
            try:
                if not firebase_admin._apps:
                    cred = credentials.ApplicationDefault()
                    firebase_admin.initialize_app(cred)

                self.gcp_creds, _ = google.auth.default()
                self.credential_source = "adc"
                AppLog.info("FIREBASE_INIT", "Using Application Default Credentials (ADC).")
            except Exception:
                if os.environ.get("DEBUG", "false").lower() == "true":
                    try:
                        if not firebase_admin._apps:
                            cred = credentials.Certificate("serviceAccountKey.json")
                            firebase_admin.initialize_app(cred)

                        self.gcp_creds = service_account.Credentials.from_service_account_file("serviceAccountKey.json")
                        self.credential_source = "local_file"
                        AppLog.info("FIREBASE_INIT", "Falling back to local serviceAccountKey.json.")
                    except Exception as e:
                        AppLog.error("FIREBASE_INIT", "Local fallback failed.")
                        raise FileNotFoundError("Local serviceAccountKey.json not found.")
                else:
                    AppLog.error("FIREBASE_INIT", "No valid credentials found. Deployment likely misconfigured.")
                    raise RuntimeError("No valid Firebase credentials found.")

    async def get_system_config(self):
        try:
            AppLog.info("FIRESTORE_READ", "Fetching system_config document.")
            doc = self.db.collection('system').document('config').get()
            if doc.exists:
                return doc.to_dict()
            return {"mcmc_enabled": True}
        except Exception as e:
            AppLog.error("FIRESTORE_READ", f"Failed to fetch system config: {str(e)}")
            return {"mcmc_enabled": True}

    async def get_user_appliances(self, user_id: str):
        try:
            AppLog.info("FIRESTORE_READ", f"Fetching active appliances for user: {user_id}")
            docs = self.db.collection('users').document(user_id).collection('appliances') \
                .where(filter=gcp_firestore.FieldFilter('status', '==', 'active')).stream()
            
            result = {}
            for doc in docs:
                result[doc.id] = doc.to_dict()
                
            AppLog.info("FIRESTORE_READ", f"Retrieved {len(result)} active appliances.")
            return result
        except Exception as e:
            AppLog.error("FIRESTORE_READ", f"Read failure for user {user_id}: {str(e)}")
            raise e

    async def update_appliance_weights(self, user_id: str, appliances: dict, new_weights: list):
        try:
            batch = self.db.batch()
            for i, (app_id, _) in enumerate(appliances.items()):
                doc_ref = self.db.collection('users').document(user_id) \
                    .collection('appliances').document(app_id)
                batch.update(doc_ref, {
                    "prob_day": float(new_weights[i]),
                    "prob_night": float(new_weights[i])
                })
            await asyncio.to_thread(batch.commit)
            AppLog.info("FIRESTORE_BATCH", f"Weights updated for {len(appliances)} appliances.")
        except Exception as e:
            AppLog.error("FIRESTORE_BATCH", f"Batch update failed: {str(e)}")
            raise e

    def _clean_numpy(self, data):
        if isinstance(data, dict):
            return {k: self._clean_numpy(v) for k, v in data.items()}
        elif isinstance(data, list):
            return [self._clean_numpy(v) for v in data]
        elif "numpy" in str(type(data)):
            return data.item() if hasattr(data, 'item') else float(data)
        return data

    async def save_disaggregation_result(self, payload: dict) -> None:
        try:
            user_id = payload.get('userId')
            month = payload.get('month')
            year = payload.get('year')
            
            AppLog.info("FIRESTORE_SAVE", f"Attempting to save result for {user_id} ({month}/{year})")
            cleaned_payload = self._clean_numpy(payload)
            doc_id = f"{user_id}_{month}_{year}"
            
            if 'timestamp' in cleaned_payload and not isinstance(cleaned_payload['timestamp'], (datetime.datetime, str)):
                cleaned_payload['timestamp'] = gcp_firestore.SERVER_TIMESTAMP

            # Legacy Write
            self.db.collection('disaggregation_results').document(doc_id).set(cleaned_payload)
            AppLog.info("FIRESTORE_SAVE", f"SUCCESS: Legacy result persisted: {doc_id}")

            # Partitioned Hierarchical Write (Dual Write)
            month_id = f"{year}-{month:02d}"
            now = datetime.datetime.now(datetime.timezone.utc)
            day_id = now.strftime("%Y-%m-%d")
            
            user_ref = self.db.collection('users').document(user_id)
            
            # 1. Update User Metrics Domain (Segregated Schema)
            user_ref.set({
                "metrics": {
                    "lifetime_kwh": gcp_firestore.Increment(cleaned_payload.get('estimated_load', 0.0)),
                    "last_aggregate_update": gcp_firestore.SERVER_TIMESTAMP
                }
            }, merge=True)

            # 2. Update Monthly Summary Partition (1-Read Dashboard Optimization)
            month_ref = user_ref.collection('billing_cycles').document(month_id)
            month_ref.set({
                "total_consumption_kwh": cleaned_payload.get('estimated_load', 0.0),
                "last_updated": gcp_firestore.SERVER_TIMESTAMP,
                "scope": cleaned_payload.get('scope', 'Unit'),
                "month": month,
                "year": year,
                "recommendations": cleaned_payload.get('recommendations', []),
                "anomalies": cleaned_payload.get('anomalies', []),
                "benchmark_breakdown": cleaned_payload.get('benchmark_breakdown', {}),
                "appliance_breakdown": cleaned_payload.get('breakdown', {}),
                "hourly_usage": cleaned_payload.get('hourlyUsage', {}),
            })
            
            # 3. Insert Daily Granular Array
            daily_ref = month_ref.collection('daily_disaggregations').document(month_id)
            daily_ref.set({
                "timestamp": gcp_firestore.SERVER_TIMESTAMP,
                "hourly_usage": cleaned_payload.get('hourlyUsage', {}),
                "appliance_breakdown": cleaned_payload.get('breakdown', {}),
                "method": cleaned_payload.get('methodApplied', 'MCMC'),
                "confidence_scores": cleaned_payload.get('confidence_scores', {})
            })
            
            AppLog.info("FIRESTORE_SAVE", f"SUCCESS: Partitioned hierarchical dual-write completed for {user_id} ({month_id}/{day_id})")

            # Increment monthly total for the forecast currentConsumption tracker.
            await self.increment_monthly_consumption(
                user_id, 
                month, 
                year, 
                cleaned_payload.get('estimated_load', 0.0)
            )
        except Exception as e:
            AppLog.error("FIRESTORE_SAVE", f"CRITICAL PERSISTENCE FAILURE: {str(e)}")
            raise e

    async def save_realtime_result(self, payload: dict):
        try:
            user_id = payload.get('userId')
            cleaned_payload = self._clean_numpy(payload)
            
            await asyncio.to_thread(self.db.collection('realtime_results').document(user_id).set, cleaned_payload)
            AppLog.info("FIRESTORE_REALTIME", f"Real-time result cached for user: {user_id}")
        except Exception as e:
            AppLog.error("FIRESTORE_REALTIME", f"Real-time persistence failure: {str(e)}")

    async def save_daily_usage(self, user_id: str, hourly_profile: dict):
        try:
            date_str = datetime.date.today().isoformat()
            doc_ref = self.db.collection('users').document(user_id) \
                .collection('daily_usage').document(date_str)
            
            await asyncio.to_thread(doc_ref.set, {
                "kwh": sum(hourly_profile.values()),
                "hourly_breakdown": hourly_profile,
                "timestamp": gcp_firestore.SERVER_TIMESTAMP
            })
            AppLog.info("FIRESTORE_DAILY", f"Daily usage synced for {user_id} on {date_str}")
        except Exception as e:
            AppLog.error("FIRESTORE_DAILY", f"Daily sync failed: {str(e)}")
            raise e

    async def log_feedback(self, data: dict):
        try:
            feedback_ref = self.db.collection('users').document(data['user_id']).collection('feedback')
            await asyncio.to_thread(feedback_ref.add, {
                "appliance": data['appliance_name'],
                "was_correct": data['actual_state'] == data['predicted_state'],
                "actual_state": data['actual_state'],
                "timestamp": data['timestamp'],
                "logged_at": gcp_firestore.SERVER_TIMESTAMP
            })
            AppLog.info("FIRESTORE_FEEDBACK", f"Feedback logged for appliance: {data['appliance_name']}")
        except Exception as e:
            AppLog.error("FIRESTORE_FEEDBACK", f"Feedback logging failed: {str(e)}")

    async def update_single_appliance_prob(self, user_id: str, app_name: str, new_prob: float, is_night: bool = False):
        try:
            app_ref = self.db.collection('users').document(user_id).collection('appliances').document(app_name)
            field = "prob_night" if is_night else "prob_day"
            await asyncio.to_thread(app_ref.update, {field: new_prob})
            AppLog.info("FIRESTORE_UPDATE", f"Updated {app_name} probability (night={is_night}) to {new_prob}")
        except Exception as e:
            AppLog.error("FIRESTORE_UPDATE", f"Single update failed for {app_name}: {str(e)}")

    async def update_appliance_signature_meta(self, user_id: str, app_name: str, meta: dict):
        try:
            app_ref = self.db.collection('users').document(user_id).collection('appliances').document(app_name)
            await asyncio.to_thread(app_ref.update, meta)
            AppLog.info("FIRESTORE_META", f"Updated signature metadata for {app_name}: {meta}")
        except Exception as e:
            AppLog.error("FIRESTORE_META", f"Meta update failed for {app_name}: {str(e)}")

    async def get_historical_telemetry(self, unit_id: str, month: int, year: int, block_id: str = None):
        import calendar
        try:
            telemetry_ref = self.db.collection('users').document(unit_id).collection('telemetry')
            
            start_date = datetime.datetime(year, month, 1, tzinfo=datetime.timezone.utc)
            last_day = calendar.monthrange(year, month)[1]
            end_date = datetime.datetime(year, month, last_day, 23, 59, 59, tzinfo=datetime.timezone.utc)
            
            query = telemetry_ref.where(filter=gcp_firestore.FieldFilter('timestamp', '>=', start_date)) \
                                 .where(filter=gcp_firestore.FieldFilter('timestamp', '<=', end_date))
            
            docs_list = []
            docs_stream = await asyncio.to_thread(lambda: list(query.stream()))
            for doc in docs_stream:
                docs_list.append(doc.to_dict())
                
            if not docs_list:
                return []
                
            docs_list.sort(key=lambda x: x.get('timestamp', start_date))
            readings = [float(doc.get('wattage', 0.0)) for doc in docs_list if 'wattage' in doc]
            
            return readings
        except Exception as e:
            AppLog.error("FIRESTORE_READ", f"Telemetry fetch failed: {str(e)}")
            return []

    async def get_historical_telemetry_with_timestamps(self, unit_id: str, month: int, year: int, block_id: str = None):
        import calendar
        try:
            telemetry_ref = self.db.collection('users').document(unit_id).collection('telemetry')
            
            start_date = datetime.datetime(year, month, 1, tzinfo=datetime.timezone.utc)
            last_day = calendar.monthrange(year, month)[1]
            end_date = datetime.datetime(year, month, last_day, 23, 59, 59, tzinfo=datetime.timezone.utc)
            
            query = telemetry_ref.where(filter=gcp_firestore.FieldFilter('timestamp', '>=', start_date)) \
                                 .where(filter=gcp_firestore.FieldFilter('timestamp', '<=', end_date))
            
            docs_list = []
            docs_stream = await asyncio.to_thread(lambda: list(query.stream()))
            for doc in docs_stream:
                doc_data = doc.to_dict()
                if 'wattage' in doc_data and 'timestamp' in doc_data:
                    docs_list.append({
                        'wattage': float(doc_data['wattage']),
                        'timestamp': doc_data['timestamp']
                    })
                    
            if not docs_list:
                return []
                
            docs_list.sort(key=lambda x: x.get('timestamp', start_date))
            return docs_list
        except Exception as e:
            AppLog.error("FIRESTORE_READ", f"Telemetry fetch with timestamps failed: {str(e)}")
            return []

    async def get_user_data(self, user_id: str):
        try:
            doc_ref = self.db.collection('users').document(user_id)
            doc = await asyncio.to_thread(doc_ref.get)
            return doc.to_dict() if doc.exists else None
        except Exception as e:
            AppLog.error("FIRESTORE_READ", f"Failed to get user data for {user_id}: {str(e)}")
            return None

    async def get_user_role(self, user_id: str):
        try:
            doc_ref = self.db.collection('users').document(user_id)
            doc = await asyncio.to_thread(doc_ref.get)
            if doc.exists:
                role = doc.to_dict().get('role', 'student')
                AppLog.info("FIRESTORE_ROLE", f"User {user_id} has role: {role}")
                return role
            AppLog.warning("FIRESTORE_ROLE", f"User {user_id} not found in Firestore, defaulting to student.")
            return 'student'
        except Exception as e:
            AppLog.error("FIRESTORE_ROLE", f"Failed to fetch role for {user_id}: {str(e)}")
            return 'student'

    async def get_monthly_consumption(self, user_id: str, month: int, year: int) -> float:
        try:
            month_id = f"{year}-{month:02d}"
            billing_doc_ref = self.db.collection('users').document(user_id) \
                .collection('billing_cycles').document(month_id)
            billing_doc = await asyncio.to_thread(billing_doc_ref.get)
            
            if billing_doc.exists:
                data = billing_doc.to_dict()
                return float(data.get('total_consumption_kwh', 0.0))

            doc_id = f"{year}_{month}"
            doc_ref = self.db.collection('users').document(user_id) \
                .collection('stats').document(doc_id)
            doc = await asyncio.to_thread(doc_ref.get)
            
            if doc.exists:
                return float(doc.to_dict().get('total_kwh', 0.0))
                
            return 0.0
        except Exception as e:
            AppLog.error("FIRESTORE_READ", f"Failed to fetch monthly consumption: {str(e)}")
            return 0.0

    async def increment_monthly_consumption(self, user_id: str, month: int, year: int, amount: float):
        try:
            doc_id = f"{year}_{month}"
            doc_ref = self.db.collection('users').document(user_id).collection('stats').document(doc_id)
            
            await asyncio.to_thread(doc_ref.set, {
                "total_kwh": gcp_firestore.Increment(amount),
                "last_updated": gcp_firestore.SERVER_TIMESTAMP
            }, merge=True)
            AppLog.info("FIRESTORE_UPDATE", f"Incremented {user_id} monthly total by {amount}")
        except Exception as e:
            AppLog.error("FIRESTORE_UPDATE", f"Failed to increment monthly total: {str(e)}")

    async def send_fcm_notification(self, user_id: str, title: str, body: str):
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
            
            response = await asyncio.to_thread(messaging.send, message)
            AppLog.info("FCM_SEND", f"Notification sent successfully: {response}")
        except Exception as e:
            AppLog.error("FCM_SEND", f"Failed to dispatch FCM: {str(e)}")