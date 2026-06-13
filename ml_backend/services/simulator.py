import random
import numpy as np

class AdaptiveBehavioralSimulator:
    # Model energy load forecasts using stochastic behavioral sampling.

    def _apply_context_modifiers(self, profile, app_name, context):
        # Adjust usage probabilities based on thermal, schedule, and lifestyle environmental context.
        modified = profile.copy()
        
        # Use appliance type for rule matching as app_name might be a Firestore ID
        app_type = profile.get('type', app_name).title()
        
        temp = context.get("temperature", 28.0)
        is_class = context.get("is_class_hours", False)
        is_raining = context.get("is_raining", False)
        humidity = context.get("humidity", 70.0)

        # Thermal Rules: Fan scaling factors for heat and humidity.
        if app_type == "Fan":
            if temp > 30:
                boost = 1.0 + (temp - 30) * 0.2
                modified["prob_day"] = min(0.99, float(modified.get("prob_day", 0.1)) * boost)
                modified["prob_night"] = min(0.99, float(modified.get("prob_night", 0.4)) * boost)
            if humidity > 85:
                modified["prob_night"] = max(float(modified.get("prob_night", 0.5)), 0.85)

        # Schedule Rules: Academic hours suppression for study-related appliances.
        if app_type == "Laptop" and is_class:
            modified["prob_day"] = float(modified.get("prob_day", 0.3)) * 0.2
            modified["prob_night"] = min(0.95, float(modified.get("prob_night", 0.4)) * 1.5)

        # Lifestyle Rules: Rainy weather amplification for indoor comfort devices.
        if is_raining:
            if app_type in ["Laptop", "Kettle"]:
                modified["prob_day"] = min(0.9, float(modified.get("prob_day", 0.2)) * 1.3)

        # Burst Appliance Fractional Scaling
        if app_type in ["Iron", "Kettle"]:
            modified["prob_day"] = min(float(modified.get("prob_day", 0.03)), 0.03)
            modified["prob_night"] = min(float(modified.get("prob_night", 0.03)), 0.03)

        return modified

    def run_monte_carlo(self, dynamic_appliances, context, iterations=100):
        # Execute minute-level stochastic simulation to capture cycling loads and phantom baselines.
        # Developer Note: Output units are strictly kWh.
        aggregated_forecast = {hour: 0.0 for hour in range(24)}
        appliance_wh_totals = {name: 0.0 for name in dynamic_appliances.keys()}
        
        sim_context = context.copy()
        manual_overrides = sim_context.get("manualOverrides", {}) or sim_context.get("manual_overrides", {})
        phantom_load = 45.0 # Watts: Baseline for standby electronics.
        
        for _ in range(iterations):
            active_streaks = {name: 0 for name in dynamic_appliances.keys()}
            for hour in range(24):
                is_night = hour < 7 or hour > 19
                sim_context["is_class_hours"] = 9 <= hour <= 16 and not sim_context.get("is_weekend", False)

                # High-resolution sampling (60 steps/hour) to resolve duty cycles.
                hour_watts = 0.0
                for minute in range(60):
                    current_min_w = phantom_load
                    
                    for app_name, profile in dynamic_appliances.items():
                        # Tier 1 Logic Gates: Map manualOverrides
                        override_val = manual_overrides.get(app_name) or manual_overrides.get(app_name.lower())
                        if override_val is not None:
                            if override_val > 0:
                                current_min_w += override_val
                                appliance_wh_totals[app_name] += (override_val / 60.0)
                            continue
                            
                        mod_profile = self._apply_context_modifiers(profile, app_name, sim_context)
                        
                        p_night = mod_profile.get("prob_night", 0.05)
                        p_day = mod_profile.get("prob_day", 0.1)
                        prob = p_night if is_night else p_day

                        # Hardware Sequence Interruption
                        max_duration_hr = profile.get("max_duration_hr", 12.0)
                        max_streak_mins = max_duration_hr * 60

                        if active_streaks[app_name] >= max_streak_mins:
                            is_active = False
                            active_streaks[app_name] = 0
                        else:
                            # Probabilistic state persistence within the simulation hour.
                            is_active = random.random() < prob
                        
                        if is_active:
                            active_streaks[app_name] += 1
                            # Apply duty cycling for inductive/thermal appliance signatures.
                            duty_cycle = 1.0
                            if app_name == "Iron": duty_cycle = 0.4
                            if app_name == "Fridge": duty_cycle = 0.25
                            
                            if random.random() < duty_cycle:
                                wattage = mod_profile.get("wattage") or 100.0
                                # Inject Gaussian noise to simulate sensor jitter.
                                noise = random.gauss(0, 5.0) 
                                load = max(0, wattage + noise)
                                current_min_w += load
                                appliance_wh_totals[app_name] += (load / 60.0)
                        else:
                            active_streaks[app_name] = 0

                    hour_watts += (current_min_w / 60.0)

                # Convert average hourly Watts to kWh for that specific hour bucket.
                aggregated_forecast[hour] += (hour_watts / 1000.0)

        from mcmc_pipeline import constrain_mcmc_allocation
        return {
            'hourly_profile': {h: round(v / iterations, 4) for h, v in aggregated_forecast.items()},
            'appliance_totals': {
                name: round(constrain_mcmc_allocation(name, total / (iterations * 1000.0)), 3)
                for name, total in appliance_wh_totals.items()
            }
        }

    def run_30_day_forecast(self, dynamic_appliances, context):
        # High-level: Projects a 30-day profile by differentiating between weekend and weekday usage patterns.
        days_to_predict = context.get("days_to_predict", 30)
        
        # We run two base simulations: Weekday and Weekend with optimized iteration counts to prevent timeouts.
        weekday_context = context.copy()
        weekday_context["is_weekend"] = False
        weekday_results = self.run_monte_carlo(dynamic_appliances, weekday_context, iterations=100)
        
        weekend_context = context.copy()
        weekend_context["is_weekend"] = True
        weekend_results = self.run_monte_carlo(dynamic_appliances, weekend_context, iterations=100)
        
        # Aggregate totals over the forecast window (assuming 5:2 ratio for standard months).
        total_days = days_to_predict
        weekend_days = (total_days // 7) * 2
        weekday_days = total_days - weekend_days
        
        forecasted_appliance_totals = {}
        for name in dynamic_appliances.keys():
            # Units: (kWh/day * days) = kWh for the period.
            w_total = weekday_results['appliance_totals'].get(name, 0.0) * weekday_days
            we_total = weekend_results['appliance_totals'].get(name, 0.0) * weekend_days
            forecasted_appliance_totals[name] = round(w_total + we_total, 3)
            
        # Aggregate hourly profile (weighted average per hour)
        combined_hourly = {}
        for h in range(24):
            w_h = weekday_results['hourly_profile'].get(h, 0.0) * 5 # weight 5
            we_h = weekend_results['hourly_profile'].get(h, 0.0) * 2 # weight 2
            combined_hourly[h] = round((w_h + we_h) / 7.0, 4)

        return {
            'appliance_totals': forecasted_appliance_totals,
            'hourly_profile': combined_hourly,
            'method': 'mcmc_30day_differentiated'
        }