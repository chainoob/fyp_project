# ml_backend/utils/logger.py

import logging
import os

# High-level: Initialize structural logging engine for cloud runtime routing.
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("backend")

class AppLog:
    # High-level: Dispatches standardized diagnostic entries to system streams.

    @staticmethod
    def error(context: str, detail: str):
        # Developer Expectation: Emit to stderr channel to ensure Google Cloud captures appropriate ERROR metrics.
        logger.error(f"Context: {context} | Detail: {detail}")

    @staticmethod
    def info(context: str, detail: str):
        # Developer Expectation: Conditional logging check for verbose execution logs.
        if os.getenv("DEBUG", "true").lower() == "true":
            logger.info(f"Context: {context} | Detail: {detail}")