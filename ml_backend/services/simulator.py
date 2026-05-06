import random
import numpy as np

class AdaptiveBehavioralSimulator:
    # Generates load forecasts using contextual behavioral overrides.

    def _apply_context_modifiers(self, profile, app_name, context):
        # Expects 'temperature' and 'is_class_hours' in context dictionary.
        modified = profile.copy()
        
        if app_name == "Fan" and context.get("temperature", 28) > 32:
            modified["prob_day"] = min(1.0, modified["prob_day"] * 1.5)
            modified["prob_night"] = 1.0

        if app_name in ["Laptop", "Kettle", "Iron"] and context.get("is_class_hours", False):
            modified["prob_day"] *= 0.1 

        return modified

    def run_monte_carlo(self, dynamic_appliances, context, iterations=1000):
        # Converges on average consumption via repeated stochastic sampling.
        aggregated_forecast = {hour: 0.0 for hour in range(24)}
        
        # Local copy to prevent side effects on the passed context object.
        sim_context = context.copy()
        
        for _ in range(iterations):
            for hour in range(24):
                is_night = hour < 7 or hour > 19
                sim_context["is_class_hours"] = 9 <= hour <= 16 and not sim_context.get("is_weekend", False)

                current_w = 0.0
                for app_name, profile in dynamic_appliances.items():
                    mod_profile = self._apply_context_modifiers(profile, app_name, sim_context)
                    prob = mod_profile["prob_night"] if is_night else mod_profile["prob_day"]

                    if random.random() < prob:
                        current_w += (mod_profile["wattage"] * mod_profile.get("max_duration_hr", 1.0))

                aggregated_forecast[hour] += (current_w / 1000.0)

        return {h: round(v / iterations, 3) for h, v in aggregated_forecast.items()}