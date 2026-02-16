#!/usr/bin/env python3
"""
Context-Aware Learning for Agent-Lightning

Learn different strategies for different contexts:
- Peak hours vs off-peak
- High load vs low load
- Complex queries vs simple queries
- Different user types
"""

import json
import numpy as np
from pathlib import Path
from typing import Dict, List
from datetime import datetime
from collections import defaultdict


class ContextDetector:
    """Detect current context from system state"""

    @staticmethod
    def detect(state: Dict) -> List[str]:
        """Detect all applicable contexts"""
        contexts = []

        # Time-based contexts
        hour = state.get('hour', datetime.now().hour)
        if 9 <= hour <= 17:
            contexts.append('peak_hours')
        elif 22 <= hour or hour <= 6:
            contexts.append('night')
        else:
            contexts.append('off_peak')

        # Day of week
        day = state.get('day_of_week', datetime.now().weekday())
        if day < 5:  # Monday-Friday
            contexts.append('weekday')
        else:
            contexts.append('weekend')

        # System load
        load = state.get('system_load', 0.5)
        if load > 0.8:
            contexts.append('high_load')
        elif load < 0.3:
            contexts.append('low_load')
        else:
            contexts.append('normal_load')

        # Query complexity
        complexity = state.get('query_complexity', 1)
        if complexity >= 3:
            contexts.append('complex_query')
        elif complexity <= 1:
            contexts.append('simple_query')
        else:
            contexts.append('medium_query')

        # User type
        user_type = state.get('user_type', 'standard')
        contexts.append(f'user_{user_type}')

        # Cache state
        cache_hit_rate = state.get('cache_hit_rate', 0.65)
        if cache_hit_rate < 0.50:
            contexts.append('cache_cold')
        elif cache_hit_rate > 0.80:
            contexts.append('cache_hot')
        else:
            contexts.append('cache_warm')

        return contexts


class ContextAwarePolicy:
    """Policy that adapts based on context"""

    def __init__(self):
        # Separate Q-tables for each context
        self.context_q_tables = defaultdict(lambda: defaultdict(float))
        self.context_counts = defaultdict(int)
        self.context_rewards = defaultdict(list)

    def get_q_value(self, contexts: List[str], state: str, action: str) -> float:
        """Get Q-value for state-action pair in given contexts"""

        # Combine Q-values from all applicable contexts
        q_values = []
        weights = []

        for context in contexts:
            q = self.context_q_tables[context].get((state, action), 0.0)
            count = self.context_counts[context]
            weight = np.sqrt(count + 1)  # More experience = higher weight

            q_values.append(q)
            weights.append(weight)

        # Weighted average
        if sum(weights) > 0:
            return np.average(q_values, weights=weights)
        else:
            return 0.0

    def update(self, contexts: List[str], state: str, action: str, reward: float):
        """Update Q-values for all applicable contexts"""

        learning_rate = 0.1
        discount = 0.95

        for context in contexts:
            # Standard Q-learning update
            current_q = self.context_q_tables[context].get((state, action), 0.0)

            # Simplified update (no next state for now)
            new_q = current_q + learning_rate * (reward - current_q)

            self.context_q_tables[context][(state, action)] = new_q

            # Track statistics
            self.context_counts[context] += 1
            self.context_rewards[context].append(reward)

    def select_action(self, contexts: List[str], state: str, actions: List[str]) -> str:
        """Select best action for current contexts"""

        # Get Q-values for all actions
        q_values = {
            action: self.get_q_value(contexts, state, action)
            for action in actions
        }

        # Epsilon-greedy selection
        epsilon = 0.1
        if np.random.random() < epsilon:
            # Explore
            return np.random.choice(actions)
        else:
            # Exploit
            return max(q_values, key=q_values.get)

    def get_context_performance(self) -> Dict:
        """Get performance statistics per context"""

        performance = {}
        for context, rewards in self.context_rewards.items():
            if rewards:
                performance[context] = {
                    'count': self.context_counts[context],
                    'avg_reward': np.mean(rewards),
                    'std_reward': np.std(rewards),
                    'total_reward': sum(rewards)
                }

        return performance


class ContextAwareAgent:
    """Complete context-aware learning agent"""

    def __init__(self):
        self.detector = ContextDetector()
        self.policy = ContextAwarePolicy()
        self.history = []

    def step(self, state: Dict, available_actions: List[str]) -> str:
        """Take one step in the environment"""

        # Detect current contexts
        contexts = self.detector.detect(state)

        # Convert state to string key
        state_key = self._state_to_key(state)

        # Select action based on contexts
        action = self.policy.select_action(contexts, state_key, available_actions)

        # Store for learning
        self.history.append({
            'contexts': contexts,
            'state': state_key,
            'action': action,
            'timestamp': datetime.now().isoformat()
        })

        return action

    def learn(self, reward: float):
        """Learn from most recent action"""

        if not self.history:
            return

        # Get most recent experience
        experience = self.history[-1]

        # Update policy for all contexts
        self.policy.update(
            experience['contexts'],
            experience['state'],
            experience['action'],
            reward
        )

    def _state_to_key(self, state: Dict) -> str:
        """Convert state dict to hashable key"""

        # Use relevant features
        features = [
            f"cache_{state.get('cache_hit_rate', 0):.2f}",
            f"load_{state.get('system_load', 0):.2f}",
            f"parallel_{state.get('parallel_success', 0):.2f}"
        ]

        return "_".join(features)

    def save(self, path: Path):
        """Save agent state"""

        data = {
            'q_tables': {
                context: dict(q_table)
                for context, q_table in self.policy.context_q_tables.items()
            },
            'counts': dict(self.policy.context_counts),
            'rewards': {
                context: rewards
                for context, rewards in self.policy.context_rewards.items()
            }
        }

        with open(path, 'w') as f:
            json.dump(data, f, indent=2)

    def load(self, path: Path):
        """Load agent state"""

        with open(path) as f:
            data = json.load(f)

        self.policy.context_q_tables = defaultdict(
            lambda: defaultdict(float),
            {
                context: defaultdict(float, q_table)
                for context, q_table in data['q_tables'].items()
            }
        )

        self.policy.context_counts = defaultdict(int, data['counts'])

        self.policy.context_rewards = defaultdict(
            list,
            data['rewards']
        )

    def analyze_contexts(self) -> Dict:
        """Analyze performance across contexts"""

        performance = self.policy.get_context_performance()

        # Find best and worst contexts
        if performance:
            sorted_contexts = sorted(
                performance.items(),
                key=lambda x: x[1]['avg_reward'],
                reverse=True
            )

            best_context = sorted_contexts[0]
            worst_context = sorted_contexts[-1]

            return {
                'performance': performance,
                'best_context': {
                    'name': best_context[0],
                    'avg_reward': best_context[1]['avg_reward']
                },
                'worst_context': {
                    'name': worst_context[0],
                    'avg_reward': worst_context[1]['avg_reward']
                },
                'improvement_opportunity': worst_context[1]['avg_reward'] / best_context[1]['avg_reward']
            }
        else:
            return {'performance': {}}


def integrate_with_agent_lightning():
    """Integrate context-aware learning with existing system"""

    agent = ContextAwareAgent()

    # Load spans from LightningStore
    spans_path = Path.home() / ".claude/data/agent-lightning/lightning-store/spans.jsonl"

    if not spans_path.exists():
        print(f"No spans found at {spans_path}")
        return

    print("Loading spans and training context-aware agent...")

    with open(spans_path) as f:
        for line in f:
            if not line.strip():
                continue

            span = json.loads(line)
            metadata = span.get('metadata', {})
            reward = span.get('reward', 0.0)

            # Build state from metadata
            state = {
                'hour': datetime.fromisoformat(span['timestamp'].replace('Z', '+00:00')).hour,
                'system_load': metadata.get('system_load', 0.5),
                'query_complexity': metadata.get('query_complexity', 1),
                'cache_hit_rate': metadata.get('hit_rate', 0.65),
                'parallel_success': metadata.get('success_rate', 0.90)
            }

            # Determine available actions (from metadata)
            # For now, use dummy actions
            available_actions = ['maintain', 'increase', 'decrease']

            # Agent takes action
            action = agent.step(state, available_actions)

            # Agent learns from reward
            agent.learn(reward)

    # Analyze results
    print("\n=== Context-Aware Learning Analysis ===\n")

    analysis = agent.analyze_contexts()

    if 'best_context' in analysis:
        print(f"Best performing context: {analysis['best_context']['name']}")
        print(f"  Average reward: {analysis['best_context']['avg_reward']:.3f}")
        print()

        print(f"Worst performing context: {analysis['worst_context']['name']}")
        print(f"  Average reward: {analysis['worst_context']['avg_reward']:.3f}")
        print()

        print(f"Improvement opportunity: {analysis['improvement_opportunity']:.1%}")
        print()

    print("Context Performance:")
    for context, perf in sorted(
        analysis['performance'].items(),
        key=lambda x: x[1]['avg_reward'],
        reverse=True
    ):
        print(f"  {context:20s}: {perf['avg_reward']:+.3f} (n={perf['count']:3d})")

    # Save agent
    output_path = Path.home() / ".claude/data/agent-lightning/context-aware-agent.json"
    agent.save(output_path)
    print(f"\n✓ Context-aware agent saved to: {output_path}")

    # Generate recommendations
    recommendations = generate_context_recommendations(analysis)

    rec_path = Path.home() / ".claude/data/agent-lightning/context-recommendations.json"
    with open(rec_path, 'w') as f:
        json.dump(recommendations, f, indent=2)

    print(f"✓ Recommendations saved to: {rec_path}")


def generate_context_recommendations(analysis: Dict) -> Dict:
    """Generate recommendations based on context analysis"""

    recommendations = {
        'timestamp': datetime.now().isoformat(),
        'recommendations': []
    }

    performance = analysis.get('performance', {})

    # Find contexts that need improvement
    if performance:
        avg_reward = np.mean([p['avg_reward'] for p in performance.values()])

        for context, perf in performance.items():
            if perf['avg_reward'] < avg_reward * 0.8:  # 20% below average
                recommendations['recommendations'].append({
                    'context': context,
                    'issue': 'underperforming',
                    'current_reward': perf['avg_reward'],
                    'target_reward': avg_reward,
                    'action': 'investigate and optimize configurations for this context'
                })

    return recommendations


if __name__ == '__main__':
    integrate_with_agent_lightning()
