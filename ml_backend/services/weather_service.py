# ml_backend/services/weather_service.py

import os
import requests
from utils.logger import AppLog
from utils.secrets import get_secret

class WeatherService:
    # High-level: Provides real-time environmental data for behavioral adjustments.

    def __init__(self):
        # Developer Expectation: Fetch API key from Secret Manager (Production) or Env (Local).
        self.api_key, self.secret_source = get_secret("OPENWEATHER_API_KEY")
        self.base_url = "http://api.openweathermap.org/data/2.5/weather"

    def get_contextual_data(self, lat: float = 1.861706329851231, lon: float = 103.09867) -> dict:
        # High-level: Fetches temperature and humidity to drive appliance usage probabilities.
        # Defaults to local region (e.g., Singapore) if coordinates are missing.
        
        fallback = {"temperature": 28.0, "humidity": 80.0, "is_raining": False}
        
        if not self.api_key:
            AppLog.error("WEATHER", "OPENWEATHER_API_KEY missing. Using static fallback context.")
            return fallback

        try:
            params = {
                "lat": lat,
                "lon": lon,
                "appid": self.api_key,
                "units": "metric"
            }
            # Use a short timeout to prevent backend blocking on external API latency.
            response = requests.get(self.base_url, params=params, timeout=3)
            response.raise_for_status()
            data = response.json()
            
            result = {
                "temperature": float(data["main"]["temp"]),
                "humidity": float(data["main"]["humidity"]),
                "is_raining": "rain" in data.get("weather", [{}])[0].get("main", "").lower()
            }
            AppLog.info("WEATHER", f"Context synchronized: {result['temperature']}C")
            return result
        except Exception as e:
            AppLog.error("WEATHER", f"API Request Failed: {str(e)}")
            return fallback
