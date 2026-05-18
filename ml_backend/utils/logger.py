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
        # Developer Expectation: Emit to stderr channel for Cloud logging detection.
        logger.error(f"Context: {context} | Detail: {detail}")

    @staticmethod
    def warning(context: str, detail: str):
        # Developer Expectation: Flag non-critical issues or configuration fallbacks.
        logger.warning(f"Context: {context} | Detail: {detail}")

    @staticmethod
    def info(context: str, detail: str):
        # Developer Expectation: Standard operational logging.
        logger.info(f"Context: {context} | Detail: {detail}")

    @staticmethod
    def debug(context: str, detail: str):
        # Developer Expectation: High-verbosity diagnostic logs.
        logger.debug(f"Context: {context} | Detail: {detail}")