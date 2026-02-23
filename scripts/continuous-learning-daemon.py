#!/usr/bin/env python3
"""
Continuous Learning Daemon
Monitors vector search usage and automatically optimizes parameters
Part of Phase 3: Continuous Learning Loop
"""

import json
import time
import signal
import sys
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, Optional

class ContinuousLearningDaemon:
    """Background daemon for continuous learning and optimization"""

    def __init__(self, config_path: str, learning_data_path: str):
        """
        Initialize daemon

        Args:
            config_path: Path to configuration file
            learning_data_path: Path to learning data
        """
        self.config_path = Path(config_path)
        self.learning_data_path = Path(learning_data_path)
        self.running = False

        # Load configuration
        self._load_config()

        # Setup signal handlers
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)

    def _load_config(self):
        """Load daemon configuration"""
        if self.config_path.exists():
            with open(self.config_path, 'r') as f:
                self.config = json.load(f)
        else:
            self.config = self._default_config()
            self._save_config()

    def _default_config(self) -> Dict:
        """Default daemon configuration"""
        return {
            'enabled': True,
            'check_interval_seconds': 3600,  # 1 hour
            'optimization_interval_seconds': 21600,  # 6 hours
            'min_queries_for_optimization': 50,
            'auto_apply_optimizations': True,
            'optimization_aggressiveness': 0.2,  # 0.0 = conservative, 1.0 = aggressive
            'thresholds': {
                'min_success_rate': 0.75,
                'min_avg_confidence': 0.70,
                'min_token_savings': 0.60
            },
            'embeddings': {
                'auto_rebuild': False,
                'rebuild_interval_days': 30,
                'rebuild_on_usage_change': True,
                'usage_change_threshold': 0.3  # 30% shift in section usage
            }
        }

    def _save_config(self):
        """Save configuration"""
        with open(self.config_path, 'w') as f:
            json.dump(self.config, f, indent=2)

    def _signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        print(f"\n📡 Received signal {signum}, shutting down gracefully...")
        self.running = False

    def _load_learning_data(self) -> Optional[Dict]:
        """Load learning data"""
        if not self.learning_data_path.exists():
            return None

        with open(self.learning_data_path, 'r') as f:
            return json.load(f)

    def _save_learning_data(self, data: Dict):
        """Save learning data"""
        data['last_updated'] = datetime.now().isoformat()
        with open(self.learning_data_path, 'w') as f:
            json.dump(data, f, indent=2)

    def _analyze_performance(self, learning_data: Dict) -> Dict:
        """Analyze current performance metrics"""
        vs = learning_data.get('vector_search', {})

        total_queries = vs.get('total_queries', 0)
        if total_queries == 0:
            return {'status': 'insufficient_data', 'queries': 0}

        success_rate = vs.get('successful_retrievals', 0) / total_queries
        avg_confidence = vs.get('average_confidence', 0)
        avg_savings = vs.get('average_token_savings', 0)

        thresholds = self.config['thresholds']
        issues = []

        if success_rate < thresholds['min_success_rate']:
            issues.append({
                'metric': 'success_rate',
                'current': success_rate,
                'target': thresholds['min_success_rate'],
                'severity': 'high'
            })

        if avg_confidence < thresholds['min_avg_confidence']:
            issues.append({
                'metric': 'avg_confidence',
                'current': avg_confidence,
                'target': thresholds['min_avg_confidence'],
                'severity': 'medium'
            })

        if avg_savings < thresholds['min_token_savings']:
            issues.append({
                'metric': 'avg_token_savings',
                'current': avg_savings,
                'target': thresholds['min_token_savings'],
                'severity': 'low'
            })

        return {
            'status': 'healthy' if not issues else 'needs_optimization',
            'queries': total_queries,
            'success_rate': success_rate,
            'avg_confidence': avg_confidence,
            'avg_token_savings': avg_savings,
            'issues': issues
        }

    def _generate_optimizations(self, performance: Dict, learning_data: Dict) -> Dict:
        """Generate optimization recommendations"""
        if performance['status'] == 'insufficient_data':
            return {'optimizations': []}

        lp = learning_data.get('learned_patterns', {})
        optimizations = []

        aggressiveness = self.config['optimization_aggressiveness']

        # Issue-based optimizations
        for issue in performance.get('issues', []):
            if issue['metric'] == 'success_rate':
                # Lower similarity threshold to get more results
                current_threshold = lp.get('optimal_similarity_threshold', 0.3)
                adjustment = 0.05 * aggressiveness
                new_threshold = max(0.15, current_threshold - adjustment)

                optimizations.append({
                    'parameter': 'similarity_threshold',
                    'current': current_threshold,
                    'recommended': new_threshold,
                    'reason': f"Success rate {issue['current']:.2%} below target {issue['target']:.2%}",
                    'impact': 'high',
                    'confidence': 0.85
                })

            elif issue['metric'] == 'avg_confidence':
                # Increase top_k to get more options
                current_top_k = lp.get('optimal_top_k', 5)
                new_top_k = min(10, current_top_k + 2)

                optimizations.append({
                    'parameter': 'top_k',
                    'current': current_top_k,
                    'recommended': new_top_k,
                    'reason': f"Low confidence {issue['current']:.2%}, increase search breadth",
                    'impact': 'medium',
                    'confidence': 0.75
                })

            elif issue['metric'] == 'avg_token_savings':
                # Reduce top_k to load fewer sections
                current_top_k = lp.get('optimal_top_k', 5)
                new_top_k = max(3, current_top_k - 1)

                optimizations.append({
                    'parameter': 'top_k',
                    'current': current_top_k,
                    'recommended': new_top_k,
                    'reason': f"Token savings {issue['current']:.2%} below target, reduce sections",
                    'impact': 'medium',
                    'confidence': 0.70
                })

        # Usage pattern optimizations
        usage = lp.get('usage_frequency_by_section', {})
        if usage:
            total_usage = sum(usage.values())
            # Find sections with < 5% usage
            rarely_used = [
                section for section, count in usage.items()
                if count / total_usage < 0.05
            ]

            if rarely_used:
                optimizations.append({
                    'parameter': 'embedding_priorities',
                    'current': 'all_sections',
                    'recommended': f'deprioritize_{len(rarely_used)}_sections',
                    'reason': f"{len(rarely_used)} sections used < 5% of time",
                    'impact': 'low',
                    'confidence': 0.60,
                    'details': rarely_used[:5]  # Show first 5
                })

        return {
            'timestamp': datetime.now().isoformat(),
            'optimizations': optimizations,
            'total_recommendations': len(optimizations)
        }

    def _apply_optimizations(self, optimizations: Dict, learning_data: Dict) -> Dict:
        """Apply optimizations to learning data"""
        lp = learning_data.get('learned_patterns', {})
        applied = []

        for opt in optimizations.get('optimizations', []):
            # Only apply high-confidence optimizations
            if opt['confidence'] < 0.70:
                continue

            param = opt['parameter']
            if param == 'similarity_threshold':
                lp['optimal_similarity_threshold'] = opt['recommended']
                applied.append(param)
            elif param == 'top_k':
                lp['optimal_top_k'] = opt['recommended']
                applied.append(param)

        if applied:
            learning_data['learned_patterns'] = lp
            self._save_learning_data(learning_data)

        return {
            'applied': applied,
            'timestamp': datetime.now().isoformat()
        }

    def _check_embeddings_freshness(self, learning_data: Dict) -> bool:
        """Check if embeddings need rebuilding"""
        embeddings_config = self.config.get('embeddings', {})

        if not embeddings_config.get('auto_rebuild', False):
            return False

        # Check last rebuild date
        rl = learning_data.get('rl_training', {})
        last_rebuild = rl.get('last_embeddings_rebuild')

        if not last_rebuild:
            return True  # Never rebuilt

        last_rebuild_date = datetime.fromisoformat(last_rebuild)
        rebuild_interval = embeddings_config.get('rebuild_interval_days', 30)

        if datetime.now() - last_rebuild_date > timedelta(days=rebuild_interval):
            return True

        # Check usage pattern shift
        if embeddings_config.get('rebuild_on_usage_change', True):
            # Compare current usage with last rebuild usage
            current_usage = learning_data.get('learned_patterns', {}).get('usage_frequency_by_section', {})
            rebuild_usage = rl.get('usage_at_last_rebuild', {})

            if rebuild_usage:
                # Calculate shift in usage distribution
                shift = self._calculate_usage_shift(current_usage, rebuild_usage)
                threshold = embeddings_config.get('usage_change_threshold', 0.3)

                if shift > threshold:
                    return True

        return False

    def _calculate_usage_shift(self, current: Dict, previous: Dict) -> float:
        """Calculate shift in usage distribution (0-1)"""
        if not previous:
            return 0.0

        # Normalize both distributions
        current_total = sum(current.values()) or 1
        previous_total = sum(previous.values()) or 1

        current_norm = {k: v / current_total for k, v in current.items()}
        previous_norm = {k: v / previous_total for k, v in previous.items()}

        # Calculate total variation distance
        all_keys = set(current_norm.keys()) | set(previous_norm.keys())
        shift = sum(
            abs(current_norm.get(k, 0) - previous_norm.get(k, 0))
            for k in all_keys
        ) / 2

        return shift

    def run(self):
        """Main daemon loop"""
        print("🚀 Continuous Learning Daemon started")
        print(f"⚙️  Check interval: {self.config['check_interval_seconds']}s")
        print(f"⚙️  Optimization interval: {self.config['optimization_interval_seconds']}s")
        print(f"⚙️  Auto-apply: {self.config['auto_apply_optimizations']}")
        print(f"⚙️  Aggressiveness: {self.config['optimization_aggressiveness']}")
        print()

        self.running = True
        last_optimization = datetime.now()

        while self.running:
            try:
                # Load learning data
                learning_data = self._load_learning_data()

                if not learning_data:
                    print("⏳ Waiting for initial data...")
                    time.sleep(self.config['check_interval_seconds'])
                    continue

                # Check if optimization is due
                time_since_optimization = (datetime.now() - last_optimization).total_seconds()

                if time_since_optimization >= self.config['optimization_interval_seconds']:
                    print(f"\n📊 Running optimization cycle at {datetime.now().strftime('%H:%M:%S')}")

                    # Analyze performance
                    performance = self._analyze_performance(learning_data)
                    print(f"   Status: {performance['status']}")
                    print(f"   Queries: {performance['queries']}")

                    if performance['queries'] >= self.config['min_queries_for_optimization']:
                        print(f"   Success rate: {performance.get('success_rate', 0):.2%}")
                        print(f"   Avg confidence: {performance.get('avg_confidence', 0):.2%}")
                        print(f"   Avg savings: {performance.get('avg_token_savings', 0):.2%}")

                        # Generate optimizations
                        optimizations = self._generate_optimizations(performance, learning_data)

                        if optimizations['total_recommendations'] > 0:
                            print(f"\n💡 Generated {optimizations['total_recommendations']} recommendations:")
                            for opt in optimizations['optimizations']:
                                print(f"   • {opt['parameter']}: {opt['current']} → {opt['recommended']}")
                                print(f"     Reason: {opt['reason']}")
                                print(f"     Confidence: {opt['confidence']:.2%}")

                            # Apply if enabled
                            if self.config['auto_apply_optimizations']:
                                result = self._apply_optimizations(optimizations, learning_data)
                                if result['applied']:
                                    print(f"\n✅ Applied optimizations: {', '.join(result['applied'])}")
                                else:
                                    print("\n⚠️  No optimizations met confidence threshold (70%)")
                        else:
                            print("   ✅ Performance optimal, no changes needed")

                        # Check embeddings freshness
                        if self._check_embeddings_freshness(learning_data):
                            print("\n🔄 Embeddings rebuild recommended")
                            print("   Run: ~/.claude/scripts/vector-search-manager.sh rebuild")
                    else:
                        needed = self.config['min_queries_for_optimization'] - performance['queries']
                        print(f"   ⏳ Need {needed} more queries for optimization")

                    last_optimization = datetime.now()

                # Sleep until next check
                time.sleep(self.config['check_interval_seconds'])

            except KeyboardInterrupt:
                print("\n⏹️  Stopped by user")
                break
            except Exception as e:
                print(f"\n❌ Error: {e}")
                print("   Continuing...")
                time.sleep(self.config['check_interval_seconds'])

        print("\n👋 Continuous Learning Daemon stopped")

    def status(self) -> Dict:
        """Get daemon status"""
        learning_data = self._load_learning_data()

        if not learning_data:
            return {
                'status': 'no_data',
                'message': 'No learning data available yet'
            }

        performance = self._analyze_performance(learning_data)

        return {
            'status': 'running' if self.running else 'stopped',
            'config': self.config,
            'performance': performance,
            'learning_data_path': str(self.learning_data_path)
        }


def main():
    """CLI interface"""
    import argparse

    parser = argparse.ArgumentParser(description='Continuous Learning Daemon')
    parser.add_argument('command', choices=['start', 'status', 'config'],
                        help='Command to execute')
    parser.add_argument('--enable-auto-apply', action='store_true',
                        help='Enable automatic optimization application')
    parser.add_argument('--disable-auto-apply', action='store_true',
                        help='Disable automatic optimization application')
    parser.add_argument('--aggressiveness', type=float,
                        help='Set optimization aggressiveness (0.0-1.0)')

    args = parser.parse_args()

    # Paths
    claude_dir = Path.home() / '.claude'
    config_path = claude_dir / 'data' / 'continuous-learning-config.json'
    learning_data = claude_dir / 'data' / 'vector-search-learning.json'

    daemon = ContinuousLearningDaemon(str(config_path), str(learning_data))

    if args.command == 'start':
        # Apply config changes if requested
        if args.enable_auto_apply:
            daemon.config['auto_apply_optimizations'] = True
            daemon._save_config()
            print("✅ Auto-apply enabled")

        if args.disable_auto_apply:
            daemon.config['auto_apply_optimizations'] = False
            daemon._save_config()
            print("⚠️  Auto-apply disabled")

        if args.aggressiveness is not None:
            if 0.0 <= args.aggressiveness <= 1.0:
                daemon.config['optimization_aggressiveness'] = args.aggressiveness
                daemon._save_config()
                print(f"✅ Aggressiveness set to {args.aggressiveness}")
            else:
                print("Error: Aggressiveness must be between 0.0 and 1.0", file=sys.stderr)
                sys.exit(1)

        daemon.run()

    elif args.command == 'status':
        status = daemon.status()
        print(json.dumps(status, indent=2))

    elif args.command == 'config':
        print(json.dumps(daemon.config, indent=2))


if __name__ == '__main__':
    main()
