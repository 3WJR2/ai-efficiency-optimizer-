#!/usr/bin/env python3
"""
Vector Search RL Bridge
Integrates vector search with Agent-Lightning for continuous learning
Part of Phase 3: Real-time RL Integration
"""

import json
import time
import hashlib
from pathlib import Path
from typing import Dict, List, Optional
from datetime import datetime

class VectorSearchRLBridge:
    """Bridge between vector search and Agent-Lightning RL system"""

    def __init__(self, learning_data_path: str, rl_spans_path: str):
        """
        Initialize RL bridge

        Args:
            learning_data_path: Path to learning-data.json
            rl_spans_path: Path to agent-lightning spans storage
        """
        self.learning_data_path = Path(learning_data_path)
        self.rl_spans_path = Path(rl_spans_path)

        # Load or initialize learning data
        if self.learning_data_path.exists():
            with open(self.learning_data_path, 'r') as f:
                self.learning_data = json.load(f)
        else:
            self.learning_data = self._init_learning_data()

    def _init_learning_data(self) -> Dict:
        """Initialize empty learning data structure"""
        return {
            'version': '2.0',
            'last_updated': datetime.now().isoformat(),
            'vector_search': {
                'total_queries': 0,
                'successful_retrievals': 0,
                'failed_retrievals': 0,
                'average_confidence': 0.0,
                'average_token_savings': 0.0,
                'query_history': []
            },
            'learned_patterns': {
                'optimal_similarity_threshold': 0.3,
                'optimal_top_k': 5,
                'optimal_chunk_size': 500,
                'confidence_by_section': {},
                'usage_frequency_by_section': {}
            },
            'rl_training': {
                'total_spans_emitted': 0,
                'last_training_run': None,
                'training_count': 0,
                'learned_policies': {}
            }
        }

    def track_query(self, query: str, result: Dict, user_feedback: Optional[str] = None):
        """
        Track a vector search query and its outcome

        Args:
            query: User's query
            result: Result from smart-context-loader-v2
            user_feedback: Optional explicit feedback ('helpful', 'not_helpful')
        """
        # Extract metrics
        confidence = result.get('confidence', 0.0)
        token_savings = self._parse_token_savings(result.get('token_savings', '0%'))
        method = result.get('method', 'unknown')
        sections_loaded = result.get('sections_loaded', [])

        # Update statistics
        vs = self.learning_data['vector_search']
        vs['total_queries'] += 1

        if confidence > 0.5:
            vs['successful_retrievals'] += 1
        else:
            vs['failed_retrievals'] += 1

        # Update rolling averages
        n = vs['total_queries']
        vs['average_confidence'] = (
            (vs['average_confidence'] * (n - 1) + confidence) / n
        )
        vs['average_token_savings'] = (
            (vs['average_token_savings'] * (n - 1) + token_savings) / n
        )

        # Track section usage
        lp = self.learning_data['learned_patterns']
        for section in sections_loaded:
            if section not in lp['usage_frequency_by_section']:
                lp['usage_frequency_by_section'][section] = 0
            lp['usage_frequency_by_section'][section] += 1

            # Update confidence tracking
            if section not in lp['confidence_by_section']:
                lp['confidence_by_section'][section] = {
                    'count': 0,
                    'total_confidence': 0.0,
                    'avg_confidence': 0.0
                }

            sec_conf = lp['confidence_by_section'][section]
            sec_conf['count'] += 1
            sec_conf['total_confidence'] += confidence
            sec_conf['avg_confidence'] = sec_conf['total_confidence'] / sec_conf['count']

        # Add to query history (keep last 100)
        query_record = {
            'timestamp': datetime.now().isoformat(),
            'query': query,
            'confidence': confidence,
            'token_savings': token_savings,
            'method': method,
            'sections': sections_loaded,
            'user_feedback': user_feedback
        }
        vs['query_history'].append(query_record)
        vs['query_history'] = vs['query_history'][-100:]  # Keep last 100

        # Save immediately
        self._save_learning_data()

        # Emit RL span
        self._emit_rl_span(query_record)

    def _parse_token_savings(self, savings_str: str) -> float:
        """Parse token savings string like '92%' to float 0.92"""
        try:
            return float(savings_str.rstrip('%')) / 100.0
        except (ValueError, AttributeError):
            return 0.0

    def _emit_rl_span(self, query_record: Dict):
        """
        Emit RL span for Agent-Lightning training

        Span format:
        {
            "span_id": "unique_id",
            "parent_span_id": null,
            "type": "vector_search",
            "timestamp": "2026-02-17T...",
            "input": {"query": "..."},
            "output": {"confidence": 0.89, "sections": [...]},
            "reward": 4.5,  # Calculated from multiple factors
            "metadata": {...}
        }
        """
        # Calculate multi-dimensional reward
        reward = self._calculate_reward(query_record)

        span = {
            'span_id': hashlib.md5(
                f"{query_record['timestamp']}{query_record['query']}".encode()
            ).hexdigest(),
            'parent_span_id': None,
            'type': 'vector_search',
            'timestamp': query_record['timestamp'],
            'input': {
                'query': query_record['query']
            },
            'output': {
                'confidence': query_record['confidence'],
                'token_savings': query_record['token_savings'],
                'method': query_record['method'],
                'sections': query_record['sections']
            },
            'reward': reward,
            'metadata': {
                'user_feedback': query_record.get('user_feedback'),
                'query_length': len(query_record['query']),
                'sections_count': len(query_record['sections'])
            }
        }

        # Save span to RL storage
        self._save_rl_span(span)

        # Update count
        self.learning_data['rl_training']['total_spans_emitted'] += 1
        self._save_learning_data()

    def _calculate_reward(self, query_record: Dict) -> float:
        """
        Calculate multi-dimensional reward for RL training

        Factors:
        1. Confidence (0-1): Weight 35%
        2. Token savings (0-1): Weight 30%
        3. Section relevance (0-1): Weight 20%
        4. User feedback (0-1): Weight 15%

        Returns:
            Reward score 0-10 (higher is better)
        """
        # Factor 1: Confidence
        confidence_score = query_record['confidence']

        # Factor 2: Token savings
        savings_score = query_record['token_savings']

        # Factor 3: Section relevance (fewer sections = more focused)
        sections_count = len(query_record['sections'])
        relevance_score = max(0, 1 - (sections_count - 2) / 5)  # Optimal: 2-3 sections

        # Factor 4: User feedback
        feedback = query_record.get('user_feedback')
        if feedback == 'helpful':
            feedback_score = 1.0
        elif feedback == 'not_helpful':
            feedback_score = 0.0
        else:
            feedback_score = 0.5  # Neutral if no feedback

        # Weighted sum
        reward = (
            confidence_score * 3.5 +
            savings_score * 3.0 +
            relevance_score * 2.0 +
            feedback_score * 1.5
        )

        return round(reward, 2)

    def _save_rl_span(self, span: Dict):
        """Save RL span to agent-lightning storage"""
        # Create directory if needed
        self.rl_spans_path.mkdir(parents=True, exist_ok=True)

        # Save span
        span_file = self.rl_spans_path / f"span_{span['span_id']}.json"
        with open(span_file, 'w') as f:
            json.dump(span, f, indent=2)

    def _save_learning_data(self):
        """Save learning data to disk"""
        self.learning_data['last_updated'] = datetime.now().isoformat()

        with open(self.learning_data_path, 'w') as f:
            json.dump(self.learning_data, f, indent=2)

    def analyze_patterns(self) -> Dict:
        """
        Analyze learned patterns and recommend optimizations

        Returns:
            Dictionary with recommendations
        """
        vs = self.learning_data['vector_search']
        lp = self.learning_data['learned_patterns']

        # Calculate success rate
        total = vs['total_queries']
        if total == 0:
            return {'error': 'No queries tracked yet'}

        success_rate = vs['successful_retrievals'] / total

        # Find most/least used sections
        usage = lp['usage_frequency_by_section']
        sorted_usage = sorted(usage.items(), key=lambda x: x[1], reverse=True)

        most_used = sorted_usage[:5] if sorted_usage else []
        least_used = sorted_usage[-5:] if len(sorted_usage) > 5 else []

        # Find sections with highest confidence
        confidence = lp['confidence_by_section']
        sorted_confidence = sorted(
            confidence.items(),
            key=lambda x: x[1]['avg_confidence'],
            reverse=True
        )
        high_confidence_sections = sorted_confidence[:5] if sorted_confidence else []

        # Recommendations
        recommendations = []

        if success_rate < 0.7:
            recommendations.append({
                'type': 'similarity_threshold',
                'current': lp['optimal_similarity_threshold'],
                'recommended': max(0.2, lp['optimal_similarity_threshold'] - 0.05),
                'reason': f'Success rate low ({success_rate:.2%}), lower threshold for more results'
            })

        if vs['average_token_savings'] < 0.5:
            recommendations.append({
                'type': 'top_k',
                'current': lp['optimal_top_k'],
                'recommended': max(3, lp['optimal_top_k'] - 1),
                'reason': f'Token savings low ({vs["average_token_savings"]:.2%}), reduce sections loaded'
            })

        return {
            'total_queries': total,
            'success_rate': success_rate,
            'avg_confidence': vs['average_confidence'],
            'avg_token_savings': vs['average_token_savings'],
            'most_used_sections': most_used,
            'least_used_sections': least_used,
            'high_confidence_sections': high_confidence_sections,
            'recommendations': recommendations,
            'rl_spans_emitted': self.learning_data['rl_training']['total_spans_emitted']
        }

    def trigger_rl_training(self) -> Dict:
        """
        Trigger Agent-Lightning training on accumulated spans

        Returns:
            Training results
        """
        rl = self.learning_data['rl_training']

        # Check if we have enough spans
        min_spans = 100
        if rl['total_spans_emitted'] < min_spans:
            return {
                'status': 'insufficient_data',
                'spans_collected': rl['total_spans_emitted'],
                'spans_needed': min_spans,
                'message': f'Need {min_spans - rl["total_spans_emitted"]} more spans for training'
            }

        # Load all spans
        spans = []
        for span_file in self.rl_spans_path.glob('span_*.json'):
            with open(span_file, 'r') as f:
                spans.append(json.load(f))

        # Calculate optimal parameters from high-reward spans
        high_reward_spans = [s for s in spans if s['reward'] > 7.0]

        if not high_reward_spans:
            return {
                'status': 'no_high_reward_data',
                'message': 'No high-reward spans found (reward > 7.0)'
            }

        # Extract patterns from high-reward spans
        optimal_confidence = sum(s['output']['confidence'] for s in high_reward_spans) / len(high_reward_spans)
        optimal_sections_count = sum(len(s['output']['sections']) for s in high_reward_spans) / len(high_reward_spans)

        # Update learned policies
        rl['learned_policies'] = {
            'optimal_confidence_threshold': round(optimal_confidence - 0.1, 2),
            'optimal_sections_count': round(optimal_sections_count),
            'high_reward_patterns': len(high_reward_spans)
        }
        rl['last_training_run'] = datetime.now().isoformat()
        rl['training_count'] += 1

        self._save_learning_data()

        return {
            'status': 'success',
            'training_run': rl['training_count'],
            'spans_analyzed': len(spans),
            'high_reward_spans': len(high_reward_spans),
            'learned_policies': rl['learned_policies']
        }

    def get_stats(self) -> Dict:
        """Get comprehensive statistics"""
        return {
            'vector_search': self.learning_data['vector_search'],
            'learned_patterns': self.learning_data['learned_patterns'],
            'rl_training': self.learning_data['rl_training'],
            'last_updated': self.learning_data['last_updated']
        }


def main():
    """CLI interface"""
    import sys
    import argparse

    parser = argparse.ArgumentParser(description='Vector Search RL Bridge')
    parser.add_argument('command', choices=['track', 'analyze', 'train', 'stats'],
                        help='Command to execute')
    parser.add_argument('--query', type=str, help='Query to track')
    parser.add_argument('--confidence', type=float, help='Query confidence')
    parser.add_argument('--savings', type=str, help='Token savings (e.g., "92%")')
    parser.add_argument('--sections', type=str, nargs='*', help='Sections loaded')
    parser.add_argument('--feedback', choices=['helpful', 'not_helpful'],
                        help='User feedback')

    args = parser.parse_args()

    # Paths
    claude_dir = Path.home() / '.claude'
    learning_data = claude_dir / 'data' / 'vector-search-learning.json'
    rl_spans = claude_dir / 'agent-lightning' / 'spans' / 'vector-search'

    bridge = VectorSearchRLBridge(str(learning_data), str(rl_spans))

    if args.command == 'track':
        if not all([args.query, args.confidence, args.savings, args.sections]):
            print("Error: --query, --confidence, --savings, --sections required", file=sys.stderr)
            sys.exit(1)

        result = {
            'confidence': args.confidence,
            'token_savings': args.savings,
            'method': 'vector',
            'sections_loaded': args.sections
        }

        bridge.track_query(args.query, result, user_feedback=args.feedback)
        print(f"✅ Tracked query: {args.query}")

    elif args.command == 'analyze':
        analysis = bridge.analyze_patterns()
        print(json.dumps(analysis, indent=2))

    elif args.command == 'train':
        result = bridge.trigger_rl_training()
        print(json.dumps(result, indent=2))

    elif args.command == 'stats':
        stats = bridge.get_stats()
        print(json.dumps(stats, indent=2))


if __name__ == '__main__':
    main()
