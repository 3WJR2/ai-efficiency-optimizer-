#!/usr/bin/env python3
"""
Machine Learning-Based Parallel Execution Optimizer

Features:
1. Predict optimal concurrency using ML models
2. Task clustering for similar workloads
3. Anomaly detection for performance issues
4. Reinforcement learning for dynamic scheduling
5. Resource prediction and preemptive scaling
"""

import json
import numpy as np
from pathlib import Path
from typing import List, Dict, Tuple
from collections import defaultdict
from dataclasses import dataclass, asdict
import time


@dataclass
class TaskExecution:
    """Record of a task execution"""
    task_id: str
    duration: float
    cpu_usage: float
    memory_usage: float
    concurrency: int
    success: bool
    speedup: float
    timestamp: float


class TaskClusterer:
    """Cluster tasks by characteristics for better scheduling"""

    def __init__(self, n_clusters=5):
        self.n_clusters = n_clusters
        self.clusters = defaultdict(list)
        self.centroids = []

    def extract_features(self, task: TaskExecution) -> np.ndarray:
        """Extract features for clustering"""
        return np.array([
            task.duration,
            task.cpu_usage / 100.0,
            task.memory_usage / 100.0,
            task.concurrency,
            task.speedup
        ])

    def fit(self, executions: List[TaskExecution]):
        """Cluster task executions using k-means"""

        if not executions:
            return

        # Extract features
        features = np.array([self.extract_features(e) for e in executions])

        # Simple k-means implementation
        n_samples = len(features)
        n_features = features.shape[1]

        # Initialize centroids randomly
        indices = np.random.choice(n_samples, self.n_clusters, replace=False)
        self.centroids = features[indices].copy()

        # Iterate until convergence
        max_iterations = 100
        for iteration in range(max_iterations):
            # Assign points to nearest centroid
            self.clusters = defaultdict(list)

            for i, feature in enumerate(features):
                distances = [np.linalg.norm(feature - centroid) for centroid in self.centroids]
                cluster_id = np.argmin(distances)
                self.clusters[cluster_id].append(i)

            # Update centroids
            old_centroids = self.centroids.copy()
            for cluster_id in range(self.n_clusters):
                if self.clusters[cluster_id]:
                    cluster_features = features[self.clusters[cluster_id]]
                    self.centroids[cluster_id] = np.mean(cluster_features, axis=0)

            # Check convergence
            if np.allclose(old_centroids, self.centroids):
                break

    def predict_cluster(self, task_features: np.ndarray) -> int:
        """Predict cluster for new task"""
        distances = [np.linalg.norm(task_features - centroid) for centroid in self.centroids]
        return np.argmin(distances)

    def get_cluster_characteristics(self) -> Dict:
        """Get characteristics of each cluster"""
        characteristics = {}

        for cluster_id in range(self.n_clusters):
            if cluster_id < len(self.centroids):
                centroid = self.centroids[cluster_id]
                characteristics[cluster_id] = {
                    'avg_duration': float(centroid[0]),
                    'avg_cpu': float(centroid[1] * 100),
                    'avg_memory': float(centroid[2] * 100),
                    'avg_concurrency': float(centroid[3]),
                    'avg_speedup': float(centroid[4]),
                    'task_count': len(self.clusters.get(cluster_id, []))
                }

        return characteristics


class ConcurrencyPredictor:
    """Predict optimal concurrency using linear regression"""

    def __init__(self):
        self.weights = None
        self.bias = 0.0
        self.is_fitted = False

    def fit(self, executions: List[TaskExecution]):
        """Train predictor on historical executions"""

        if not executions:
            return

        # Prepare training data
        X = []  # Features
        y = []  # Target (success rate weighted by speedup)

        for exec in executions:
            features = [
                exec.duration,
                exec.cpu_usage / 100.0,
                exec.memory_usage / 100.0,
                exec.concurrency,
                1.0 if exec.success else 0.0
            ]

            # Target: speedup if successful, negative speedup if failed
            target = exec.speedup if exec.success else -exec.speedup

            X.append(features)
            y.append(target)

        X = np.array(X)
        y = np.array(y)

        # Simple linear regression: y = Xw + b
        # Use normal equation: w = (X^T X)^-1 X^T y

        # Add bias term
        X_with_bias = np.c_[X, np.ones(X.shape[0])]

        # Solve normal equation
        try:
            XtX_inv = np.linalg.inv(X_with_bias.T @ X_with_bias)
            weights_with_bias = XtX_inv @ X_with_bias.T @ y

            self.weights = weights_with_bias[:-1]
            self.bias = weights_with_bias[-1]
            self.is_fitted = True
        except np.linalg.LinAlgError:
            # Singular matrix, use default weights
            self.weights = np.ones(X.shape[1]) * 0.1
            self.bias = 0.0
            self.is_fitted = True

    def predict_speedup(self, duration: float, cpu: float, memory: float,
                       concurrency: int, success_rate: float = 0.9) -> float:
        """Predict expected speedup for given parameters"""

        if not self.is_fitted:
            # Default prediction
            return concurrency * 0.7  # Assume 70% parallel efficiency

        features = np.array([
            duration,
            cpu / 100.0,
            memory / 100.0,
            concurrency,
            success_rate
        ])

        prediction = np.dot(features, self.weights) + self.bias
        return max(1.0, prediction)  # Speedup at least 1x

    def suggest_concurrency(self, duration: float, cpu: float, memory: float,
                           target_speedup: float = 3.0) -> int:
        """Suggest optimal concurrency to achieve target speedup"""

        if not self.is_fitted:
            # Default suggestion based on CPU cores
            import os
            return min(os.cpu_count() or 4, 8)

        # Binary search for optimal concurrency
        low, high = 1, 20
        best_concurrency = 4

        while low <= high:
            mid = (low + high) // 2
            predicted_speedup = self.predict_speedup(duration, cpu, memory, mid)

            if abs(predicted_speedup - target_speedup) < 0.5:
                best_concurrency = mid
                break
            elif predicted_speedup < target_speedup:
                low = mid + 1
                best_concurrency = mid
            else:
                high = mid - 1

        return best_concurrency


class AnomalyDetector:
    """Detect anomalies in parallel execution performance"""

    def __init__(self, threshold=2.0):
        self.threshold = threshold  # Standard deviations
        self.baseline_metrics = {}

    def fit(self, executions: List[TaskExecution]):
        """Establish baseline metrics"""

        if not executions:
            return

        # Calculate mean and std for each metric
        durations = [e.duration for e in executions]
        cpu_usages = [e.cpu_usage for e in executions]
        memory_usages = [e.memory_usage for e in executions]
        speedups = [e.speedup for e in executions]

        self.baseline_metrics = {
            'duration': {
                'mean': np.mean(durations),
                'std': np.std(durations)
            },
            'cpu_usage': {
                'mean': np.mean(cpu_usages),
                'std': np.std(cpu_usages)
            },
            'memory_usage': {
                'mean': np.mean(memory_usages),
                'std': np.std(memory_usages)
            },
            'speedup': {
                'mean': np.mean(speedups),
                'std': np.std(speedups)
            }
        }

    def is_anomaly(self, execution: TaskExecution) -> Tuple[bool, List[str]]:
        """Check if execution is anomalous"""

        if not self.baseline_metrics:
            return False, []

        anomalies = []

        # Check each metric
        for metric_name, value in [
            ('duration', execution.duration),
            ('cpu_usage', execution.cpu_usage),
            ('memory_usage', execution.memory_usage),
            ('speedup', execution.speedup)
        ]:
            baseline = self.baseline_metrics[metric_name]
            z_score = abs((value - baseline['mean']) / (baseline['std'] + 1e-6))

            if z_score > self.threshold:
                anomalies.append(f"{metric_name} z-score={z_score:.2f}")

        return len(anomalies) > 0, anomalies


class RLScheduler:
    """Reinforcement Learning-based task scheduler"""

    def __init__(self, learning_rate=0.1, discount=0.95, epsilon=0.1):
        self.lr = learning_rate
        self.gamma = discount
        self.epsilon = epsilon
        self.q_table = defaultdict(lambda: defaultdict(float))
        self.episode_rewards = []

    def get_state_key(self, cpu: float, memory: float, active_tasks: int) -> str:
        """Convert state to discrete key"""
        cpu_bin = int(cpu / 25)  # 0-3 (0-25%, 25-50%, 50-75%, 75-100%)
        mem_bin = int(memory / 25)
        task_bin = min(active_tasks // 2, 5)  # 0-5+
        return f"{cpu_bin}_{mem_bin}_{task_bin}"

    def select_action(self, state_key: str, available_actions: List[int]) -> int:
        """Select action using epsilon-greedy"""

        if np.random.random() < self.epsilon:
            # Explore
            return np.random.choice(available_actions)
        else:
            # Exploit
            q_values = [self.q_table[state_key][a] for a in available_actions]
            if max(q_values) == 0:
                return np.random.choice(available_actions)
            return available_actions[np.argmax(q_values)]

    def update(self, state: str, action: int, reward: float, next_state: str):
        """Q-learning update"""

        # Get max Q-value for next state
        next_q_values = list(self.q_table[next_state].values())
        max_next_q = max(next_q_values) if next_q_values else 0.0

        # Update Q-value
        current_q = self.q_table[state][action]
        new_q = current_q + self.lr * (reward + self.gamma * max_next_q - current_q)
        self.q_table[state][action] = new_q

        # Track episode reward
        if not hasattr(self, 'current_episode_reward'):
            self.current_episode_reward = 0.0
        self.current_episode_reward += reward

    def end_episode(self):
        """Mark end of episode and record reward"""
        if hasattr(self, 'current_episode_reward'):
            self.episode_rewards.append(self.current_episode_reward)
            self.current_episode_reward = 0.0

    def get_policy(self) -> Dict:
        """Get learned policy"""
        policy = {}
        for state, actions in self.q_table.items():
            if actions:
                best_action = max(actions.items(), key=lambda x: x[1])
                policy[state] = {
                    'action': best_action[0],
                    'q_value': best_action[1]
                }
        return policy


class MLParallelOptimizer:
    """Complete ML-based parallel execution optimizer"""

    def __init__(self):
        self.clusterer = TaskClusterer(n_clusters=5)
        self.predictor = ConcurrencyPredictor()
        self.anomaly_detector = AnomalyDetector(threshold=2.5)
        self.scheduler = RLScheduler(learning_rate=0.1, epsilon=0.15)
        self.executions = []

    def load_data(self):
        """Load execution history"""

        history_path = Path.home() / ".claude/data/parallel-history.jsonl"

        if not history_path.exists():
            print("No execution history found")
            return

        with open(history_path) as f:
            for line in f:
                if not line.strip():
                    continue

                entry = json.loads(line)

                # Create TaskExecution from history
                execution = TaskExecution(
                    task_id=f"batch_{entry['batch']}",
                    duration=entry['duration'],
                    cpu_usage=entry.get('cpu_usage', 50.0),
                    memory_usage=entry.get('memory_usage', 50.0),
                    concurrency=entry['concurrency'],
                    success=entry['success'] > 0,
                    speedup=entry.get('speedup', entry['concurrency'] * 0.7),
                    timestamp=time.time()
                )

                self.executions.append(execution)

    def train_models(self):
        """Train all ML models"""

        if not self.executions:
            print("No data to train on")
            return

        print(f"Training models on {len(self.executions)} executions...")

        # Train clusterer
        self.clusterer.fit(self.executions)
        print(f"✓ Clusterer trained ({self.clusterer.n_clusters} clusters)")

        # Train predictor
        self.predictor.fit(self.executions)
        print(f"✓ Concurrency predictor trained")

        # Train anomaly detector
        self.anomaly_detector.fit(self.executions)
        print(f"✓ Anomaly detector trained")

        # Train RL scheduler
        for exec in self.executions:
            state = self.scheduler.get_state_key(
                exec.cpu_usage, exec.memory_usage, exec.concurrency
            )
            action = exec.concurrency
            reward = exec.speedup if exec.success else -1.0
            next_state = state  # Simplified

            self.scheduler.update(state, action, reward, next_state)

        self.scheduler.end_episode()
        print(f"✓ RL scheduler trained ({len(self.scheduler.q_table)} states)")

    def analyze_clusters(self):
        """Analyze task clusters"""

        print("\n=== Task Cluster Analysis ===\n")

        characteristics = self.clusterer.get_cluster_characteristics()

        for cluster_id, chars in sorted(characteristics.items()):
            print(f"Cluster {cluster_id}:")
            print(f"  Tasks: {chars['task_count']}")
            print(f"  Avg Duration: {chars['avg_duration']:.2f}s")
            print(f"  Avg CPU: {chars['avg_cpu']:.1f}%")
            print(f"  Avg Memory: {chars['avg_memory']:.1f}%")
            print(f"  Avg Concurrency: {chars['avg_concurrency']:.1f}")
            print(f"  Avg Speedup: {chars['avg_speedup']:.2f}x")

            # Classify cluster type
            if chars['avg_duration'] < 1.0:
                cluster_type = "Quick tasks"
            elif chars['avg_cpu'] > 70:
                cluster_type = "CPU-intensive tasks"
            elif chars['avg_memory'] > 70:
                cluster_type = "Memory-intensive tasks"
            elif chars['avg_speedup'] > 2.5:
                cluster_type = "Highly parallelizable tasks"
            else:
                cluster_type = "Mixed workload"

            print(f"  Type: {cluster_type}")
            print()

    def optimize_concurrency(self, duration: float, cpu: float, memory: float):
        """Suggest optimal concurrency"""

        print(f"\n=== Concurrency Optimization ===\n")
        print(f"Input:")
        print(f"  Expected Duration: {duration}s")
        print(f"  Current CPU: {cpu}%")
        print(f"  Current Memory: {memory}%")
        print()

        # Multiple approaches
        approaches = {}

        # 1. ML Predictor
        if self.predictor.is_fitted:
            for target_speedup in [2.0, 3.0, 4.0]:
                concurrency = self.predictor.suggest_concurrency(
                    duration, cpu, memory, target_speedup
                )
                predicted_speedup = self.predictor.predict_speedup(
                    duration, cpu, memory, concurrency
                )
                approaches[f"ML (target {target_speedup}x)"] = {
                    'concurrency': concurrency,
                    'predicted_speedup': predicted_speedup
                }

        # 2. RL Scheduler
        state = self.scheduler.get_state_key(cpu, memory, 0)
        available_actions = list(range(2, 11))
        rl_action = self.scheduler.select_action(state, available_actions)
        approaches["RL Scheduler"] = {
            'concurrency': rl_action,
            'q_value': self.scheduler.q_table[state][rl_action]
        }

        # 3. Rule-based
        import os
        cpu_cores = os.cpu_count() or 4

        if cpu > 80 or memory > 80:
            rule_based = max(2, cpu_cores // 2)
        elif cpu > 60 or memory > 60:
            rule_based = cpu_cores
        else:
            rule_based = min(cpu_cores * 2, 10)

        approaches["Rule-based"] = {
            'concurrency': rule_based,
            'reasoning': 'Based on current resource usage'
        }

        # Display recommendations
        print("Recommendations:")
        for approach, result in approaches.items():
            print(f"\n  {approach}:")
            print(f"    Concurrency: {result['concurrency']}")
            if 'predicted_speedup' in result:
                print(f"    Predicted Speedup: {result['predicted_speedup']:.2f}x")
            if 'q_value' in result:
                print(f"    Q-value: {result['q_value']:.3f}")
            if 'reasoning' in result:
                print(f"    Reasoning: {result['reasoning']}")

        # Consensus recommendation
        concurrencies = [r['concurrency'] for r in approaches.values()]
        consensus = int(np.median(concurrencies))

        print(f"\n  Consensus Recommendation: {consensus}")
        print()

        return consensus

    def detect_anomalies(self):
        """Detect anomalous executions"""

        print("\n=== Anomaly Detection ===\n")

        anomalies_found = []

        for exec in self.executions[-20:]:  # Last 20 executions
            is_anomaly, reasons = self.anomaly_detector.is_anomaly(exec)

            if is_anomaly:
                anomalies_found.append({
                    'execution': exec,
                    'reasons': reasons
                })

        if anomalies_found:
            print(f"Found {len(anomalies_found)} anomalies in last 20 executions:\n")

            for anomaly in anomalies_found:
                exec = anomaly['execution']
                print(f"  Task {exec.task_id}:")
                print(f"    Duration: {exec.duration:.2f}s")
                print(f"    Speedup: {exec.speedup:.2f}x")
                print(f"    Success: {exec.success}")
                print(f"    Anomalies: {', '.join(anomaly['reasons'])}")
                print()
        else:
            print("No anomalies detected in recent executions")

        print()

    def save_models(self):
        """Save trained models"""

        output_path = Path.home() / ".claude/data/agent-lightning/ml-parallel-models.json"

        models_data = {
            'timestamp': time.time(),
            'n_executions': len(self.executions),
            'clusterer': {
                'n_clusters': self.clusterer.n_clusters,
                'centroids': [c.tolist() for c in self.clusterer.centroids],
                'characteristics': self.clusterer.get_cluster_characteristics()
            },
            'predictor': {
                'is_fitted': self.predictor.is_fitted,
                'weights': self.predictor.weights.tolist() if self.predictor.weights is not None else None,
                'bias': float(self.predictor.bias)
            },
            'anomaly_detector': {
                'threshold': self.anomaly_detector.threshold,
                'baseline_metrics': self.anomaly_detector.baseline_metrics
            },
            'rl_scheduler': {
                'policy': self.scheduler.get_policy(),
                'episode_rewards': self.scheduler.episode_rewards[-100:]  # Last 100
            }
        }

        with open(output_path, 'w') as f:
            json.dump(models_data, f, indent=2)

        print(f"✓ Models saved to: {output_path}")


def main():
    """Main optimization workflow"""

    print("=== ML-Based Parallel Execution Optimizer ===\n")

    optimizer = MLParallelOptimizer()

    # Load data
    print("Loading execution history...")
    optimizer.load_data()

    if not optimizer.executions:
        print("\nNo execution history found.")
        print("Run some parallel tasks first:")
        print("  bash ~/.claude/enhancements/advanced-parallel-execution.sh demo")
        return

    print(f"Loaded {len(optimizer.executions)} executions\n")

    # Train models
    optimizer.train_models()

    # Analyze clusters
    optimizer.analyze_clusters()

    # Suggest optimal concurrency for different scenarios
    print("\n=== Scenario Analysis ===\n")

    scenarios = [
        ("Light load, short tasks", 0.5, 30.0, 40.0),
        ("Normal load, medium tasks", 2.0, 50.0, 50.0),
        ("Heavy load, long tasks", 5.0, 75.0, 70.0),
        ("Peak hours, complex tasks", 3.0, 80.0, 65.0)
    ]

    for name, duration, cpu, memory in scenarios:
        print(f"Scenario: {name}")
        optimizer.optimize_concurrency(duration, cpu, memory)

    # Detect anomalies
    optimizer.detect_anomalies()

    # Save models
    optimizer.save_models()

    print("\n=== Summary ===\n")
    print("ML models trained and ready for use!")
    print("\nNext steps:")
    print("  1. Integrate with agent-lightning bridge")
    print("  2. Use ML predictions for dynamic scheduling")
    print("  3. Monitor anomalies in real-time")
    print("  4. Retrain periodically as more data accumulates")


if __name__ == '__main__':
    main()
