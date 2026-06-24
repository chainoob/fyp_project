# ml_backend/services/simulator.py

import random
import numpy as np
from typing import Dict, Any

from services.behavior.occupancy_model import OccupancyModel
from services.behavior.state_machine import ApplianceStateMachine

class AdaptiveBehavioralSimulator:
    # High-level: Implements stateful Markov-chain simulation with occupancy and environmental layers.

    def _get_app_modifiers(self, app_type: str, activity: str, temp: float) -> float:
        # Determine probability scale modifier based on context
        factor = 1.0
        
        # Environmental modifiers
        if app_type == "Fan" and temp > 30.0:
            factor *= 1.5 + (temp - 30.0) * 0.1
            
        # Activity/occupancy modifiers
        if activity == "UNOCCUPIED":
            if app_type in ["Kettle", "Iron", "Lamp", "Laptop", "Printer"]:
                factor *= 0.0
            else:
                factor *= 0.1 # standby/residual
        elif activity == "SLEEPING":
            if app_type in ["Kettle", "Iron", "Laptop", "Printer"]:
                factor *= 0.01
            elif app_type == "Lamp":
                factor *= 0.05
            elif app_type == "Fan":
                factor *= 1.2 # fan ON during sleep
        elif activity == "STUDYING":
            if app_type == "Laptop":
                factor *= 2.0
            elif app_type == "Lamp":
                factor *= 1.5
                
        return factor

    def run_monte_carlo(self, dynamic_appliances: Dict[str, Any], context: Dict[str, Any], iterations: int = 100) -> Dict[str, Any]:
        # High-level: Runs minute-by-minute stochastic simulation using Markov State Machines.
        aggregated_forecast = {hour: 0.0 for hour in range(24)}
        appliance_wh_totals = {name: 0.0 for name in dynamic_appliances.keys()}
        
        sim_context = context.copy()
        manual_overrides = sim_context.get("manualOverrides", {}) or sim_context.get("manual_overrides", {}) or {}
        phantom_load = 45.0 # standby electronic baseline
        
        temp = sim_context.get("temperature", 28.0)
        is_weekend = sim_context.get("is_weekend", False)
        
        for _ in range(iterations):
            # Instantiate a state machine for each appliance
            state_machines = {}
            for name, profile in dynamic_appliances.items():
                app_type = profile.get('type', name).title()
                state_machines[name] = ApplianceStateMachine(appliance_type=app_type)
                
            for hour in range(24):
                is_occupied = OccupancyModel.get_occupancy_state(hour, is_weekend)
                activity = OccupancyModel.get_activity_level(hour, is_occupied)
                
                hour_watts = 0.0
                for minute in range(60):
                    current_min_w = phantom_load
                    
                    for name, profile in dynamic_appliances.items():
                        # Tier 1: Manual overrides
                        override_val = manual_overrides.get(name) or manual_overrides.get(name.lower())
                        if override_val is not None:
                            if override_val > 0:
                                current_min_w += override_val
                                appliance_wh_totals[name] += (override_val / 60.0)
                            continue
                            
                        sm = state_machines[name]
                        app_type = profile.get('type', name).title()
                        
                        # Apply context factor to the transition matrix
                        factor = self._get_app_modifiers(app_type, activity, temp)
                        
                        modified_trans = sm.trans_matrix.copy()
                        if factor != 1.0 and modified_trans.shape[0] > 1:
                            # Scale the transition probability out of OFF state
                            off_to_on = modified_trans[0, 1:] * factor
                            total_on = np.sum(off_to_on)
                            if total_on > 0.99:
                                off_to_on = (off_to_on / total_on) * 0.99
                            modified_trans[0, 1:] = off_to_on
                            modified_trans[0, 0] = 1.0 - np.sum(off_to_on)
                            
                        # Transition step
                        state = sm.transition(override_matrix=modified_trans)
                        
                        if state > 0:
                            nominal_w = float(profile.get("wattage", 100.0))
                            # Idle vs Active wattage scaling
                            wattage = nominal_w if state == 2 else nominal_w * 0.15
                            
                            # Duty cycling for burst/thermostat loads
                            duty_cycle = 1.0
                            if app_type == "Iron":
                                duty_cycle = 0.4
                            elif app_type == "Fridge":
                                duty_cycle = 0.25
                                
                            if random.random() < duty_cycle:
                                noise = random.gauss(0, 5.0)
                                load = max(0.0, wattage + noise)
                                current_min_w += load
                                appliance_wh_totals[name] += (load / 60.0)
                                
                    hour_watts += (current_min_w / 60.0)
                    
                aggregated_forecast[hour] += (hour_watts / 1000.0)
                
        # Constrain allocations
        from mcmc_pipeline import constrain_mcmc_allocation
        return {
            'hourly_profile': {h: round(v / iterations, 4) for h, v in aggregated_forecast.items()},
            'appliance_totals': {
                name: round(constrain_mcmc_allocation(name, total / (iterations * 1000.0)), 3)
                for name, total in appliance_wh_totals.items()
            }
        }

    def run_30_day_forecast(self, dynamic_appliances: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
        # High-level: Aggregates weekend vs weekday Monte Carlo simulations to predict 30-day loads.
        days_to_predict = context.get("days_to_predict", 30)
        
        weekday_context = context.copy()
        weekday_context["is_weekend"] = False
        weekday_results = self.run_monte_carlo(dynamic_appliances, weekday_context, iterations=100)
        
        weekend_context = context.copy()
        weekend_context["is_weekend"] = True
        weekend_results = self.run_monte_carlo(dynamic_appliances, weekend_context, iterations=100)
        
        total_days = days_to_predict
        weekend_days = (total_days // 7) * 2
        weekday_days = total_days - weekend_days
        
        forecasted_appliance_totals = {}
        for name in dynamic_appliances.keys():
            w_total = weekday_results['appliance_totals'].get(name, 0.0) * weekday_days
            we_total = weekend_results['appliance_totals'].get(name, 0.0) * weekend_days
            forecasted_appliance_totals[name] = round(w_total + we_total, 3)
            
        combined_hourly = {}
        for h in range(24):
            w_h = weekday_results['hourly_profile'].get(h, 0.0) * 5
            we_h = weekend_results['hourly_profile'].get(h, 0.0) * 2
            combined_hourly[h] = round((w_h + we_h) / 7.0, 4)

        return {
            'appliance_totals': forecasted_appliance_totals,
            'hourly_profile': combined_hourly,
            'method': 'mcmc_30day_differentiated'
        }