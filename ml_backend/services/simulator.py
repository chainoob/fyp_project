import random
import numpy as np

class AdaptiveBehavioralSimulator:
    # Model energy load forecasts using stochastic behavioral sampling.

    def _apply_context_modifiers(self, profile, app_name, context):
        # Adjust usage probabilities based on thermal, schedule, and lifestyle environmental context.
        modified = profile.copy()
        
        temp = context.get("temperature", 28.0)
        is_class = context.get("is_class_hours", False)
        is_raining = context.get("is_raining", False)
        humidity = context.get("humidity", 70.0)

        # Thermal Rules: Fan/AC scaling factors for heat and humidity.
        if app_name in ["Fan", "AC"]:
            if temp > 30:
                # Linear boost factor for thermal stress.
                boost = 1.0 + (temp - 30) * 0.2
                modified["prob_day"] = min(0.99, modified.get("prob_day", 0.1) * boost)
                modified["prob_night"] = min(0.99, modified.get("prob_night", 0.4) * boost)
            if humidity > 85:
                # Night-time fan usage saturation for high humidity.
                modified["prob_night"] = max(modified.get("prob_night", 0.5), 0.85)

        # Schedule Rules: Academic hours suppression for study-related appliances.
        if app_name in ["Laptop", "Monitor", "Desk Lamp"] and is_class:
            modified["prob_day"] = modified.get("prob_day", 0.3) * 0.2
            modified["prob_night"] = min(0.95, modified.get("prob_night", 0.4) * 1.5)

        # Lifestyle Rules: Rainy weather amplification for indoor comfort devices.
        if is_raining:
            if app_name in ["Laptop", "Kettle"]:
                modified["prob_day"] = min(0.9, modified.get("prob_day", 0.2) * 1.3)

        return modified

    def run_monte_carlo(self, dynamic_appliances, context, iterations=500):
        # Execute minute-level stochastic simulation to capture cycling loads and phantom baselines.
        aggregated_forecast = {hour: 0.0 for hour in range(24)}
        appliance_totals = {name: 0.0 for name in dynamic_appliances.keys()}
        
        sim_context = context.copy()
        phantom_load = 45.0 # Watts: Baseline for standby electronics.
        
        for _ in range(iterations):
            for hour in range(24):
                is_night = hour < 7 or hour > 19
                sim_context["is_class_hours"] = 9 <= hour <= 16 and not sim_context.get("is_weekend", False)

                # High-resolution sampling (60 steps/hour) to resolve duty cycles.
                hour_watts = 0.0
                for minute in range(60):
                    current_min_w = phantom_load
                    
                    for app_name, profile in dynamic_appliances.items():
                        mod_profile = self._apply_context_modifiers(profile, app_name, sim_context)
                        
                        p_night = mod_profile.get("prob_night", 0.05)
                        p_day = mod_profile.get("prob_day", 0.1)
                        prob = p_night if is_night else p_day

                        # Probabilistic state persistence within the simulation hour.
                        is_active = random.random() < prob
                        
                        if is_active:
                            # Apply duty cycling for inductive/thermal appliance signatures.
                            duty_cycle = 1.0
                            if app_name == "Iron": duty_cycle = 0.4
                            if app_name == "Fridge": duty_cycle = 0.25
                            
                            if random.random() < duty_cycle:
                                wattage = mod_profile.get("wattage") or 100.0
                                # Inject Gaussian noise to simulate sensor jitter.
                                noise = random.gauss(0, 5.0) 
                                load = wattage + noise
                                current_min_w += load
                                appliance_totals[app_name] += (load / 60.0)

                    hour_watts += (current_min_w / 60.0)

                aggregated_forecast[hour] += (hour_watts / 1000.0)

        return {
            'hourly_profile': {h: round(v / iterations, 3) for h, v in aggregated_forecast.items()},
            'appliance_totals': {name: round(total / (iterations * 24), 3) for name, total in appliance_totals.items()}
        }