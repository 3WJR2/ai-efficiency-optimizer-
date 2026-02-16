#!/usr/bin/env python3
"""
Multi-Objective Optimization for Agent-Lightning

Instead of optimizing a single reward, optimize multiple objectives:
- Performance (speed, cache hits)
- Resource efficiency (memory, CPU)
- Reliability (success rate, error rate)
- Cost (API calls, compute time)

Uses Pareto optimization to find the best trade-offs.
"""

import json
import numpy as np
from pathlib import Path
from typing import List, Dict, Tuple
from dataclasses import dataclass


@dataclass
class Objective:
    """Represents one optimization objective"""
    name: str
    value: float
    weight: float
    minimize: bool  # True = lower is better, False = higher is better


@dataclass
class Solution:
    """Represents a configuration and its objectives"""
    config: Dict
    objectives: List[Objective]

    def dominates(self, other: 'Solution') -> bool:
        """Check if this solution dominates another (Pareto dominance)"""
        better_in_one = False
        for obj1, obj2 in zip(self.objectives, other.objectives):
            if obj1.minimize:
                if obj1.value > obj2.value:
                    return False
                if obj1.value < obj2.value:
                    better_in_one = True
            else:
                if obj1.value < obj2.value:
                    return False
                if obj1.value > obj2.value:
                    better_in_one = True
        return better_in_one

    def weighted_score(self) -> float:
        """Calculate weighted score across all objectives"""
        score = 0.0
        for obj in self.objectives:
            if obj.minimize:
                # Normalize: 0 = worst, 1 = best
                normalized = 1.0 - obj.value
            else:
                normalized = obj.value
            score += normalized * obj.weight
        return score


class MultiObjectiveOptimizer:
    """Optimize multiple objectives simultaneously"""

    def __init__(self, objectives_config: Dict):
        self.objectives_config = objectives_config
        self.solutions: List[Solution] = []
        self.pareto_front: List[Solution] = []

    def add_solution(self, config: Dict, metrics: Dict) -> Solution:
        """Add a solution (configuration + metrics) to the population"""
        objectives = []

        for obj_name, obj_config in self.objectives_config.items():
            value = metrics.get(obj_name, 0.0)
            weight = obj_config.get('weight', 1.0)
            minimize = obj_config.get('minimize', False)

            objectives.append(Objective(
                name=obj_name,
                value=value,
                weight=weight,
                minimize=minimize
            ))

        solution = Solution(config=config, objectives=objectives)
        self.solutions.append(solution)
        return solution

    def compute_pareto_front(self) -> List[Solution]:
        """Find all non-dominated solutions (Pareto front)"""
        self.pareto_front = []

        for solution in self.solutions:
            dominated = False
            for other in self.solutions:
                if other.dominates(solution):
                    dominated = True
                    break

            if not dominated:
                self.pareto_front.append(solution)

        return self.pareto_front

    def select_best(self, preferences: Dict[str, float] = None) -> Solution:
        """
        Select the best solution from Pareto front based on preferences

        preferences: Dict mapping objective name to importance (0-1)
        If None, uses weights from objectives_config
        """
        if not self.pareto_front:
            self.compute_pareto_front()

        if not self.pareto_front:
            return None

        # Apply preference weights
        if preferences:
            for solution in self.pareto_front:
                for obj in solution.objectives:
                    if obj.name in preferences:
                        obj.weight = preferences[obj.name]

        # Select solution with highest weighted score
        best = max(self.pareto_front, key=lambda s: s.weighted_score())
        return best

    def get_trade_offs(self) -> List[Dict]:
        """Get trade-off analysis of Pareto front"""
        if not self.pareto_front:
            self.compute_pareto_front()

        trade_offs = []
        for solution in self.pareto_front:
            trade_off = {
                'config': solution.config,
                'weighted_score': solution.weighted_score(),
                'objectives': {}
            }

            for obj in solution.objectives:
                trade_off['objectives'][obj.name] = {
                    'value': obj.value,
                    'weight': obj.weight
                }

            trade_offs.append(trade_off)

        # Sort by weighted score
        trade_offs.sort(key=lambda x: x['weighted_score'], reverse=True)
        return trade_offs


def load_spans_and_optimize():
    """Load spans from LightningStore and perform multi-objective optimization"""

    # Configuration: Define objectives
    objectives_config = {
        'cache_hit_rate': {
            'weight': 0.35,
            'minimize': False  # Higher is better
        },
        'latency_ms': {
            'weight': 0.25,
            'minimize': True  # Lower is better
        },
        'parallel_success_rate': {
            'weight': 0.25,
            'minimize': False  # Higher is better
        },
        'resource_usage': {
            'weight': 0.10,
            'minimize': True  # Lower is better
        },
        'cost_per_operation': {
            'weight': 0.05,
            'minimize': True  # Lower is better
        }
    }

    optimizer = MultiObjectiveOptimizer(objectives_config)

    # Load spans from LightningStore
    spans_path = Path.home() / ".claude/data/agent-lightning/lightning-store/spans.jsonl"

    if not spans_path.exists():
        print(f"No spans found at {spans_path}")
        return

    # Group spans by configuration hash
    configs_metrics = {}

    with open(spans_path) as f:
        for line in f:
            if not line.strip():
                continue

            span = json.loads(line)
            metadata = span.get('metadata', {})

            # Create config hash (unique identifier for configuration)
            config_key = f"{metadata.get('cache_threshold', 0.85)}_{metadata.get('max_concurrent', 5)}"

            if config_key not in configs_metrics:
                configs_metrics[config_key] = {
                    'config': {
                        'cache_threshold': metadata.get('cache_threshold', 0.85),
                        'max_concurrent': metadata.get('max_concurrent', 5)
                    },
                    'metrics': {
                        'cache_hit_rate': [],
                        'latency_ms': [],
                        'parallel_success_rate': [],
                        'resource_usage': [],
                        'cost_per_operation': []
                    }
                }

            # Accumulate metrics
            metrics = configs_metrics[config_key]['metrics']

            if metadata.get('type') == 'cache':
                metrics['cache_hit_rate'].append(metadata.get('hit_rate', 0))
                metrics['latency_ms'].append(metadata.get('latency_ms', 0))

            if metadata.get('type') == 'parallel':
                metrics['parallel_success_rate'].append(metadata.get('success_rate', 0))
                metrics['resource_usage'].append(metadata.get('resource_usage', 0.5))

            metrics['cost_per_operation'].append(metadata.get('cost', 0.0))

    # Calculate averages and add to optimizer
    for config_key, data in configs_metrics.items():
        config = data['config']
        raw_metrics = data['metrics']

        # Average metrics
        avg_metrics = {}
        for metric_name, values in raw_metrics.items():
            if values:
                avg_metrics[metric_name] = np.mean(values)
            else:
                avg_metrics[metric_name] = 0.0

        optimizer.add_solution(config, avg_metrics)

    # Compute Pareto front
    print("Computing Pareto front...")
    pareto_front = optimizer.compute_pareto_front()
    print(f"Found {len(pareto_front)} non-dominated solutions")
    print()

    # Get trade-off analysis
    print("=== Trade-Off Analysis ===")
    trade_offs = optimizer.get_trade_offs()

    for i, trade_off in enumerate(trade_offs[:5], 1):  # Top 5
        print(f"\nSolution {i}:")
        print(f"  Config: {trade_off['config']}")
        print(f"  Weighted Score: {trade_off['weighted_score']:.3f}")
        print(f"  Objectives:")
        for obj_name, obj_data in trade_off['objectives'].items():
            print(f"    {obj_name}: {obj_data['value']:.3f} (weight: {obj_data['weight']})")

    # Select best with different preferences
    print("\n=== Preference-Based Selection ===")

    # Scenario 1: Prioritize speed
    print("\nScenario 1: Speed Priority")
    speed_prefs = {
        'cache_hit_rate': 0.3,
        'latency_ms': 0.5,  # High priority
        'parallel_success_rate': 0.15,
        'resource_usage': 0.03,
        'cost_per_operation': 0.02
    }
    best_speed = optimizer.select_best(speed_prefs)
    print(f"  Best config: {best_speed.config}")
    print(f"  Score: {best_speed.weighted_score():.3f}")

    # Scenario 2: Prioritize reliability
    print("\nScenario 2: Reliability Priority")
    reliability_prefs = {
        'cache_hit_rate': 0.25,
        'latency_ms': 0.15,
        'parallel_success_rate': 0.5,  # High priority
        'resource_usage': 0.05,
        'cost_per_operation': 0.05
    }
    best_reliability = optimizer.select_best(reliability_prefs)
    print(f"  Best config: {best_reliability.config}")
    print(f"  Score: {best_reliability.weighted_score():.3f}")

    # Scenario 3: Balanced
    print("\nScenario 3: Balanced")
    best_balanced = optimizer.select_best()  # Use default weights
    print(f"  Best config: {best_balanced.config}")
    print(f"  Score: {best_balanced.weighted_score():.3f}")

    # Save recommendations
    recommendations = {
        'pareto_front_size': len(pareto_front),
        'trade_offs': trade_offs,
        'recommended_configs': {
            'speed_optimized': {
                'config': best_speed.config,
                'score': best_speed.weighted_score(),
                'use_case': 'Prioritize low latency and fast responses'
            },
            'reliability_optimized': {
                'config': best_reliability.config,
                'score': best_reliability.weighted_score(),
                'use_case': 'Prioritize high success rates and stability'
            },
            'balanced': {
                'config': best_balanced.config,
                'score': best_balanced.weighted_score(),
                'use_case': 'Good all-around performance'
            }
        }
    }

    output_path = Path.home() / ".claude/data/agent-lightning/multi-objective-recommendations.json"
    with open(output_path, 'w') as f:
        json.dump(recommendations, f, indent=2)

    print(f"\n✓ Recommendations saved to: {output_path}")


if __name__ == '__main__':
    load_spans_and_optimize()
