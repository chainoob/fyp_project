import random
import numpy as np
from deap import base, creator, tools
from models.fhmm import FHMMModel

class DisaggregationEngine:
    def __init__(self, target_load, registered_appliances):
        self.target_load = target_load
        self.appliances = registered_appliances
        self.fhmm = FHMMModel()
        self.num_appliances = len(registered_appliances)
        
        self._setup_deap()

    def _setup_deap(self):
        # Objective: Minimize load difference (weight -1.0)
        # Note: Behavioral likelihood objective will be added later
        if not hasattr(creator, "FitnessMin"):
            creator.create("FitnessMin", base.Fitness, weights=(-1.0,))
        if not hasattr(creator, "Individual"):
            creator.create("Individual", list, fitness=creator.FitnessMin)

        self.toolbox = base.Toolbox()
        
        # Attribute generator: random state index per appliance
        self.toolbox.register("attr_state", self._generate_random_states)
        self.toolbox.register("individual", tools.initIterate, creator.Individual, self.toolbox.attr_state)
        self.toolbox.register("population", tools.initRepeat, list, self.toolbox.individual)

        self.toolbox.register("evaluate", self._evaluate_fitness)
        self.toolbox.register("mate", tools.cxTwoPoint)
        self.toolbox.register("mutate", tools.mutUniformInt, low=0, up=2, indpb=0.2) # 'up' will be dynamic later
        self.toolbox.register("select", tools.selTournament, tournsize=3)

    def _generate_random_states(self):
        return [random.randint(0, self.fhmm.get_max_state_index(app)) for app in self.appliances]

    def _evaluate_fitness(self, individual):
        total_power = 0
        for idx, state_index in enumerate(individual):
            app_name = self.appliances[idx]
            total_power += self.fhmm.get_power_for_state(app_name, state_index)
            
        load_difference = abs(self.target_load - total_power)
        return (load_difference,)

    def run(self, population_size=50, generations=40):
        pop = self.toolbox.population(n=population_size)
        
        # Simple evolutionary loop for initial testing
        for gen in range(generations):
            offspring = self.toolbox.select(pop, len(pop))
            offspring = list(map(self.toolbox.clone, offspring))

            for child1, child2 in zip(offspring[::2], offspring[1::2]):
                if random.random() < 0.7:
                    self.toolbox.mate(child1, child2)
                    del child1.fitness.values
                    del child2.fitness.values

            for mutant in offspring:
                if random.random() < 0.2:
                    self.toolbox.mutate(mutant)
                    del mutant.fitness.values

            invalid_ind = [ind for ind in offspring if not ind.fitness.valid]
            fitnesses = map(self.toolbox.evaluate, invalid_ind)
            for ind, fit in zip(invalid_ind, fitnesses):
                ind.fitness.values = fit

            pop[:] = offspring

        best_ind = tools.selBest(pop, 1)[0]
        return self._format_output(best_ind)

    def _format_output(self, individual):
        breakdown = {}
        total_estimated = 0
        for idx, state_index in enumerate(individual):
            app_name = self.appliances[idx]
            power = self.fhmm.get_power_for_state(app_name, state_index)
            breakdown[app_name] = power
            total_estimated += power
            
        return {
            "target_load": self.target_load,
            "estimated_load": total_estimated,
            "difference": abs(self.target_load - total_estimated),
            "breakdown": breakdown
        }