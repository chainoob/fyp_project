import random
import numpy as np

class AdaptiveBehavioralSimulator:
    # High-level: Generates energy load forecasts using stochastic behavioral modeling.

    def _apply_context_modifiers(self, profile, app_name, context):
        # Applies environmental adjustments to appliance probability profiles.
        modified = profile.copy()
        
        # TODO: Replace static rule logic with a dynamic rules engine or external weather API integration.
        # Developer Expectation: Production must fetch real-time temperature based on user geolocation.
        temp = context.get("temperature", 28)
        is_class = context.get("is_class_hours", False)

        if app_name == "Fan" and temp > 32:
            modified["prob_day"] = min(1.0, modified.get("prob_day", 0.1) * 1.5)
            modified["prob_night"] = 1.0

        if app_name in ["Laptop", "Kettle", "Iron"] and is_class:
            modified["prob_day"] = modified.get("prob_day", 0.1) * 0.1 

        return modified

    def run_monte_carlo(self, dynamic_appliances, context, iterations=1000):
        # Converges on average consumption via repeated stochastic sampling.
        aggregated_forecast = {hour: 0.0 for hour in range(24)}
        appliance_totals = {name: 0.0 for name in dynamic_appliances.keys()}
        
        sim_context = context.copy()
        
        # TODO: Implement dynamic iteration scaling based on required confidence intervals or latency constraints.
        # Developer Expectation: Default probabilities should be derived from global device profiles or historical user behavior.
        for _ in range(iterations):
            for hour in range(24):
                is_night = hour < 7 or hour > 19
                sim_context["is_class_hours"] = 9 <= hour <= 16 and not sim_context.get("is_weekend", False)

                current_w = 0.0
                for app_name, profile in dynamic_appliances.items():
                    mod_profile = self._apply_context_modifiers(profile, app_name, sim_context)
                    
                    p_night = mod_profile.get("prob_night", 0.05)
                    p_day = mod_profile.get("prob_day", 0.1)
                    wattage = mod_profile.get("wattage") or mod_profile.get("power_rating", 0.5)
                    
                    prob = p_night if is_night else p_day

                    if random.random() < prob:
                        load = (wattage * mod_profile.get("max_duration_hr", 1.0))
                        current_w += load
                        appliance_totals[app_name] += load

                aggregated_forecast[hour] += (current_w / 1000.0)

        # Developer Expectation: Structure must remain compatible with main.py disaggregation payload.
        return {
            'hourly_profile': {h: round(v / iterations, 3) for h, v in aggregated_forecast.items()},
            'appliance_totals': {name: round(total / (iterations * 24), 3) for name, total in appliance_totals.items()}
        }