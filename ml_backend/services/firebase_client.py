import firebase_admin
from firebase_admin import credentials, firestore

class FirebaseDatabase:
    def __init__(self):
        # Prevent duplicate initialization during hot-reloads
        if not firebase_admin._apps:
            cred = credentials.Certificate("serviceAccountKey.json")
            firebase_admin.initialize_app(cred)
        self.db = firestore.client()

    def get_user_appliances(self, user_id: str) -> dict:
        doc_ref = self.db.collection("users").doc(user_id)
        doc = doc_ref.get()
        if doc.exists:
            # Assumes appliances are stored in a map/dictionary field named 'appliances'
            data = doc.to_dict()
            return data.get("appliances", {})
        return {}

    def save_disaggregation_result(self, user_id: str, payload: dict):
        # Write the unified simulation output
        self.db.collection("users").doc(user_id).collection("disaggregation_results").add(payload)
        
    def update_user_appliance_profiles(self, user_id: str, updated_appliances: dict):
        # Write adapted Bayesian weights back to the user document
        self.db.collection("users").doc(user_id).set(
            {"appliances": updated_appliances}, 
            merge=True
        )