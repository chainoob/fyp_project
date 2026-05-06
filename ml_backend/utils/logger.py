# ml_backend/utils/logger.py

import os

class AppLog:
    # High-level: Centralizes diagnostic output for the Python backend.

    @staticmethod
    def error(context: str, detail: str):
        # Developer Expectation: 
        # Limits output to environments where the DEBUG variable is 'true'.
        if os.getenv("DEBUG", "true").lower() == "true":
            print("--- BACKEND ERROR ---")
            print(f"Context: {context}")
            print(f"Detail: {detail}")
            print("----------------------")