import random

class AdaptiveBehavioralSimulator:
    def __init__(self, iterations: int = 1000):
        self.iterations = iterations

    def _apply_context_modifiers(self, profile: dict, app_name: str, context: dict) -> dict:
        modified = profile.copy()
        
        if app_name == "Fan" and context.get("temperature", 28) > 32:
            modified["prob_day"] = min(1.0, modified["prob_day"] * 1.5)
            modified["prob_night"] = 1.0

        if app_name in ["Laptop", "Kettle", "Iron"] and context.get("is_class_hours", False):
            modified["prob_day"] *= 0.1 

        return modified

    def run_monte_carlo(self, dynamic_appliances: dict, context: dict) -> dict:
        """
        dynamic_appliances format:
        {
            "Fan": {"wattage": 50, "prob_day": 0.45, "prob_night": 0.92, "max_duration_hr": 1.0},
            "Iron": {"wattage": 1000, "prob_day": 0.12, "prob_night": 0.02, "max_duration_hr": 0.25}
        }
        These values are fetched from the user's Firestore profile, not hardcoded.
        """
        aggregated_forecast = {hour: 0.0 for hour in range(24)}
        
        for _ in range(self.iterations):
            for hour in range(24):
                is_night = hour < 7 or hour > 19
                context["is_class_hours"] = 9 <= hour <= 16 and not context.get("is_weekend", False)

                current_w = 0.0
                for app_name, profile in dynamic_appliances.items():
                    mod_profile = self._apply_context_modifiers(profile, app_name, context)
                    prob = mod_profile["prob_night"] if is_night else mod_profile["prob_day"]

                    if random.random() < prob:
                        duration = mod_profile.get("max_duration_hr", 1.0)
                        current_w += (mod_profile["wattage"] * duration)

                aggregated_forecast[hour] += (current_w / 1000.0)

        for hour in aggregated_forecast:
            aggregated_forecast[hour] = round(aggregated_forecast[hour] / self.iterations, 3)

        return aggregated_forecast

    def adapt_user_weights(self, db_client, user_id: str, actual_bill: float, simulated_total: float, current_appliances: dict):
        """
        Executes after the monthly bill is submitted to adapt next month's probabilities.
        """
        if simulated_total <= 0:
            return

        # Calculate error ratio
        error_ratio = actual_bill / simulated_total
        
        # Apply bounds to prevent wild swings (max 20% adjustment per month)
        adjustment_factor = max(0.8, min(1.2, error_ratio))

        updated_appliances = {}
        for app_name, profile in current_appliances.items():
            updated_profile = profile.copy()
            # Adjust probabilities based on historical error
            updated_profile["prob_day"] = min(0.99, profile["prob_day"] * adjustment_factor)
            updated_profile["prob_night"] = min(0.99, profile["prob_night"] * adjustment_factor)
            updated_appliances[app_name] = updated_profile

        # Write adapted weights back to Firestore
        db_client.update_user_appliance_profiles(user_id, updated_appliances)