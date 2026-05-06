# ml_backend/services/firebase_client.py

import datetime
import firebase_admin
from firebase_admin import credentials, firestore

class FirebaseClient:
    # High-level: Handles authenticated Firestore I/O for the ML pipeline.

    def __init__(self):
        # Developer Expectation: 
        # serviceAccountKey.json must be present in root for local/docker execution.
        if not firebase_admin._apps:
            cred = credentials.Certificate("serviceAccountKey.json")
            firebase_admin.initialize_app(cred)
        self.db = firestore.client()

    def get_user_appliances(self, user_id: str):
        # High-level: Fetches current active appliance configurations for a user.
        docs = self.db.collection('users').document(user_id).collection('appliances').where('status', '==', 'active').stream()
        return {doc.id: doc.to_dict() for doc in docs}

    def update_appliance_weights(self, user_id: str, appliances: dict, new_weights: list):
        # High-level: Batch updates usage probabilities derived from SLSQP optimization.
        # Use a write batch for atomic updates to ensure data consistency.
        batch = self.db.batch()
        for i, (app_id, _) in enumerate(appliances.items()):
            doc_ref = self.db.collection('users').document(user_id).collection('appliances').document(app_id)
            batch.update(doc_ref, {
                "prob_day": float(new_weights[i]),
                "prob_night": float(new_weights[i])
            })
        batch.commit()

    def save_disaggregation_result(self, payload: dict):
        # High-level: Archives monthly disaggregation stats for historical analysis.
        self.db.collection('disaggregation_results').add(payload)

    def save_daily_usage(self, user_id: str, hourly_profile: dict):
        # High-level: Persists 24-hour time-series data for frontend charting.
        date_str = datetime.date.today().isoformat()
        doc_ref = self.db.collection('users').document(user_id).collection('daily_usage').document(date_str)
        doc_ref.set({
            "kwh": sum(hourly_profile.values()),
            "hourly_breakdown": hourly_profile,
            "timestamp": firestore.SERVER_TIMESTAMP
        })

    def log_feedback(self, data: dict):
        # High-level: Logs user corrections to a subcollection. 
        # Decoupled from FeedbackRequest model to prevent circular imports.
        feedback_ref = self.db.collection('users').document(data['user_id']).collection('feedback')
        feedback_ref.add({
            "appliance": data['appliance_name'],
            "was_correct": data['actual_state'] == data['predicted_state'],
            "actual_state": data['actual_state'],
            "timestamp": data['timestamp'],
            "logged_at": firestore.SERVER_TIMESTAMP
        })

    def update_single_appliance_prob(self, user_id: str, app_name: str, new_prob: float):
        # High-level: Performs a micro-adjustment to a single appliance's weight.
        app_ref = self.db.collection('users').document(user_id).collection('appliances').document(app_name)
        app_ref.update({
            "prob_day": new_prob,
            "prob_night": new_prob
        })