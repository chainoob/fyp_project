# ml_backend/services/behavior/occupancy_model.py

import random

class OccupancyModel:
    # High-level: Models room occupancy and activity levels dynamically based on hostal schedules.

    @staticmethod
    def get_occupancy_state(hour: int, is_weekend: bool) -> bool:
        # Determine occupancy based on typical hostel schedules.
        if 9 <= hour <= 16 and not is_weekend:
            # Low occupancy during class hours
            return random.random() < 0.15
        elif hour < 6 or hour >= 23:
            # High occupancy at night
            return random.random() < 0.95
        else:
            # Standard occupancy during morning/evening
            return random.random() < 0.85

    @staticmethod
    def get_activity_level(hour: int, is_occupied: bool) -> str:
        # High-level: Resolves student activity level if occupied.
        if not is_occupied:
            return "UNOCCUPIED"
        if hour < 6 or hour >= 23:
            return "SLEEPING"
        elif 9 <= hour <= 16:
            return "STUDYING"
        else:
            return "ACTIVE"
