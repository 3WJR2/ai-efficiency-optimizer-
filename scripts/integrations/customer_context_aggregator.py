#!/usr/bin/env python3
"""
Customer Context Aggregator
Pulls data from Gong, HubSpot, GitHub, and Qodo to build comprehensive customer context
"""

import json
import sys
from pathlib import Path
from typing import Dict, List, Optional
from concurrent.futures import ThreadPoolExecutor, as_completed

# Import all clients
from gong_client import GongClient
from hubspot_client import HubSpotClient
from github_client import GitHubClient
from qodo_client import QodoClient


class CustomerContextAggregator:
    """Aggregates customer context from multiple data sources"""

    def __init__(self, config_path: str):
        """
        Initialize aggregator with all clients

        Args:
            config_path: Path to config.json
        """
        self.config_path = config_path

        # Load config to check parallel fetching
        with open(config_path, 'r') as f:
            config = json.load(f)

        self.parallel_fetching = config['data_collection'].get('parallel_fetching', True)
        self.max_concurrent = config['data_collection'].get('max_concurrent_requests', 4)

        # Initialize all clients
        self.gong = GongClient(config_path)
        self.hubspot = HubSpotClient(config_path)
        self.github = GitHubClient(config_path)
        self.qodo = QodoClient(config_path)

    def test_all_connections(self) -> Dict:
        """Test connections to all data sources"""
        connections = {
            'gong': self.gong.test_connection(),
            'hubspot': self.hubspot.test_connection(),
            'github': self.github.test_connection(),
            'qodo': self.qodo.test_connection()
        }

        # Summary
        connected_count = sum(1 for c in connections.values() if c.get('connected'))
        total_count = len(connections)

        return {
            'summary': f"{connected_count}/{total_count} integrations connected",
            'connections': connections,
            'all_connected': connected_count == total_count
        }

    def gather_customer_context(self, company_name: str, github_org: Optional[str] = None,
                               github_repo: Optional[str] = None) -> Dict:
        """
        Gather comprehensive customer context from all sources

        Args:
            company_name: Company name (for Gong and HubSpot)
            github_org: GitHub organization name (optional, defaults to company_name)
            github_repo: Specific GitHub repository (optional)

        Returns:
            Unified customer context
        """
        if not github_org:
            github_org = company_name.lower().replace(' ', '-')

        print(f"\n🔍 Gathering context for: {company_name}")
        print(f"   GitHub org: {github_org}")
        print(f"   Parallel fetching: {self.parallel_fetching}\n")

        # Fetch data from all sources
        if self.parallel_fetching:
            context_data = self._fetch_parallel(company_name, github_org, github_repo)
        else:
            context_data = self._fetch_sequential(company_name, github_org, github_repo)

        # Aggregate and enrich
        unified_context = self._unify_context(company_name, context_data)

        return unified_context

    def _fetch_parallel(self, company_name: str, github_org: str, github_repo: Optional[str]) -> Dict:
        """Fetch data from all sources in parallel"""
        context_data = {}

        with ThreadPoolExecutor(max_workers=self.max_concurrent) as executor:
            futures = {
                'gong': executor.submit(self._fetch_gong, company_name),
                'hubspot': executor.submit(self._fetch_hubspot, company_name),
                'github': executor.submit(self._fetch_github, github_org, github_repo),
                'qodo': executor.submit(self._fetch_qodo_catalog)
            }

            # Collect results as they complete
            for source, future in futures.items():
                try:
                    result = future.result(timeout=30)  # 30 second timeout per source
                    context_data[source] = result
                    status = '✅' if result.get('available') else '❌'
                    print(f"{status} {source.capitalize()}: {result.get('message', 'Success')}")
                except Exception as e:
                    context_data[source] = {'available': False, 'error': str(e)}
                    print(f"❌ {source.capitalize()}: Error - {e}")

        return context_data

    def _fetch_sequential(self, company_name: str, github_org: str, github_repo: Optional[str]) -> Dict:
        """Fetch data from all sources sequentially"""
        context_data = {}

        # Gong
        print("Fetching from Gong...")
        context_data['gong'] = self._fetch_gong(company_name)

        # HubSpot
        print("Fetching from HubSpot...")
        context_data['hubspot'] = self._fetch_hubspot(company_name)

        # GitHub
        print("Fetching from GitHub...")
        context_data['github'] = self._fetch_github(github_org, github_repo)

        # Qodo
        print("Fetching from Qodo...")
        context_data['qodo'] = self._fetch_qodo_catalog()

        return context_data

    def _fetch_gong(self, company_name: str) -> Dict:
        """Fetch Gong data"""
        try:
            return self.gong.get_account_context(company_name)
        except Exception as e:
            return {'available': False, 'error': str(e)}

    def _fetch_hubspot(self, company_name: str) -> Dict:
        """Fetch HubSpot data"""
        try:
            return self.hubspot.get_deal_context(company_name)
        except Exception as e:
            return {'available': False, 'error': str(e)}

    def _fetch_github(self, github_org: str, github_repo: Optional[str]) -> Dict:
        """Fetch GitHub data"""
        try:
            return self.github.get_repo_context(github_org, github_repo)
        except Exception as e:
            return {'available': False, 'error': str(e)}

    def _fetch_qodo_catalog(self) -> Dict:
        """Fetch Qodo product catalog"""
        try:
            return self.qodo.get_product_catalog()
        except Exception as e:
            return {'available': False, 'error': str(e)}

    def _unify_context(self, company_name: str, context_data: Dict) -> Dict:
        """Unify and enrich context from all sources"""
        # Base context
        unified = {
            'company_name': company_name,
            'data_sources': {
                'gong': context_data['gong'].get('available', False),
                'hubspot': context_data['hubspot'].get('available', False),
                'github': context_data['github'].get('available', False),
                'qodo': context_data['qodo'].get('available', False)
            },
            'timestamp': self._get_timestamp()
        }

        # Extract key information
        gong_data = context_data.get('gong', {})
        hubspot_data = context_data.get('hubspot', {})
        github_data = context_data.get('github', {})
        qodo_data = context_data.get('qodo', {})

        # Pain points (from Gong)
        if gong_data.get('available'):
            unified['pain_points'] = gong_data.get('pain_points', [])
            unified['decision_makers'] = gong_data.get('decision_makers', [])
            unified['recent_calls'] = gong_data.get('calls', [])

        # Deal information (from HubSpot)
        if hubspot_data.get('available') and hubspot_data.get('found'):
            unified['company_info'] = hubspot_data.get('company', {})
            unified['deals'] = hubspot_data.get('deals', {})
            unified['contacts'] = hubspot_data.get('contacts', {})
            unified['deal_stage'] = hubspot_data.get('insights', {}).get('deal_stage')

        # Tech stack (from GitHub)
        if github_data.get('available'):
            unified['tech_stack'] = github_data.get('tech_stack', {})
            if 'code_style' in github_data:
                unified['code_style'] = github_data['code_style']
            if 'repositories' in github_data:
                unified['repositories'] = github_data['repositories']

        # Product recommendations (from Qodo + pain points + tech stack)
        if qodo_data.get('available'):
            pain_categories = self._categorize_pain_points(unified.get('pain_points', []))
            tech_stack = unified.get('tech_stack', {})

            recommendations = self.qodo.recommend_products(pain_categories, tech_stack)
            unified['qodo_recommendations'] = recommendations

            # Generate demo script
            demo_script = self.qodo.generate_demo_script({
                'company_name': company_name,
                'pain_points': unified.get('pain_points', []),
                'tech_stack': tech_stack
            })
            unified['demo_script'] = demo_script

        # Generate executive summary
        unified['executive_summary'] = self._generate_executive_summary(unified)

        return unified

    def _categorize_pain_points(self, pain_points: List[Dict]) -> List[str]:
        """Categorize pain points into categories"""
        categories = set()

        category_keywords = {
            'testing': ['test', 'coverage', 'qa'],
            'code_quality': ['quality', 'bug', 'error', 'refactor'],
            'review_time': ['review', 'pr', 'merge'],
            'security': ['security', 'vulnerability', 'compliance'],
            'automation': ['manual', 'automate', 'repetitive'],
            'large_codebase': ['large', 'complex', 'monolith'],
            'velocity': ['slow', 'time', 'speed']
        }

        for pain_point in pain_points:
            context = pain_point.get('context', '').lower()
            for category, keywords in category_keywords.items():
                if any(keyword in context for keyword in keywords):
                    categories.add(category)

        return list(categories)

    def _generate_executive_summary(self, unified_context: Dict) -> Dict:
        """Generate high-level executive summary"""
        summary = {
            'company': unified_context.get('company_name'),
            'data_completeness': self._calculate_completeness(unified_context),
            'key_insights': []
        }

        # Deal stage insight
        deal_stage = unified_context.get('deal_stage')
        if deal_stage:
            summary['key_insights'].append(f"Deal stage: {deal_stage}")

        # Pain points insight
        pain_points = unified_context.get('pain_points', [])
        if pain_points:
            summary['key_insights'].append(f"{len(pain_points)} pain points identified")

        # Tech stack insight
        tech_stack = unified_context.get('tech_stack', {})
        if tech_stack.get('primary_language'):
            summary['key_insights'].append(f"Primary language: {tech_stack['primary_language']}")

        # Recommendations insight
        recommendations = unified_context.get('qodo_recommendations', {})
        rec_count = len(recommendations.get('recommendations', []))
        if rec_count:
            summary['key_insights'].append(f"{rec_count} Qodo products recommended")

        # Readiness score
        summary['demo_readiness_score'] = self._calculate_readiness(unified_context)

        return summary

    def _calculate_completeness(self, context: Dict) -> str:
        """Calculate data completeness percentage"""
        total_sources = 4
        available_sources = sum(1 for v in context['data_sources'].values() if v)

        percentage = (available_sources / total_sources) * 100

        if percentage == 100:
            return 'Complete (100%)'
        elif percentage >= 75:
            return f'Good ({int(percentage)}%)'
        elif percentage >= 50:
            return f'Partial ({int(percentage)}%)'
        else:
            return f'Limited ({int(percentage)}%)'

    def _calculate_readiness(self, context: Dict) -> str:
        """Calculate demo readiness score"""
        score = 0
        max_score = 5

        # Have pain points?
        if context.get('pain_points'):
            score += 1

        # Have tech stack?
        if context.get('tech_stack', {}).get('primary_language'):
            score += 1

        # Have deal info?
        if context.get('deals'):
            score += 1

        # Have recommendations?
        if context.get('qodo_recommendations'):
            score += 1

        # Have demo script?
        if context.get('demo_script'):
            score += 1

        percentage = (score / max_score) * 100

        if percentage >= 80:
            return f'Ready ({int(percentage)}%)'
        elif percentage >= 60:
            return f'Almost Ready ({int(percentage)}%)'
        else:
            return f'Needs More Data ({int(percentage)}%)'

    def _get_timestamp(self) -> str:
        """Get current timestamp"""
        from datetime import datetime
        return datetime.now().isoformat()

    def export_context(self, context: Dict, output_path: str):
        """Export context to JSON file"""
        output_file = Path(output_path)
        output_file.parent.mkdir(parents=True, exist_ok=True)

        with open(output_file, 'w') as f:
            json.dump(context, f, indent=2)

        print(f"\n✅ Context exported to: {output_file}")


def main():
    """Main CLI interface"""
    if len(sys.argv) < 3:
        print("Usage: python customer_context_aggregator.py <config_path> <company_name> [github_org] [github_repo]")
        print("\nExample:")
        print("  python customer_context_aggregator.py config.json \"Acme Corp\" acme-org")
        print("  python customer_context_aggregator.py config.json \"TechCo\" techco-org backend-api")
        sys.exit(1)

    config_path = sys.argv[1]
    company_name = sys.argv[2]
    github_org = sys.argv[3] if len(sys.argv) > 3 else None
    github_repo = sys.argv[4] if len(sys.argv) > 4 else None

    # Initialize aggregator
    aggregator = CustomerContextAggregator(config_path)

    # Test connections
    print("=" * 60)
    print("TESTING CONNECTIONS")
    print("=" * 60)
    connections = aggregator.test_all_connections()
    print(f"\n{connections['summary']}\n")

    for source, result in connections['connections'].items():
        status = '✅' if result['connected'] else '❌'
        print(f"{status} {source.upper()}: {result['message']}")

    # Gather context
    print("\n" + "=" * 60)
    print("GATHERING CUSTOMER CONTEXT")
    print("=" * 60)

    context = aggregator.gather_customer_context(company_name, github_org, github_repo)

    # Display summary
    print("\n" + "=" * 60)
    print("EXECUTIVE SUMMARY")
    print("=" * 60)

    summary = context.get('executive_summary', {})
    print(f"\nCompany: {summary.get('company')}")
    print(f"Data Completeness: {summary.get('data_completeness')}")
    print(f"Demo Readiness: {summary.get('demo_readiness_score')}")
    print("\nKey Insights:")
    for insight in summary.get('key_insights', []):
        print(f"  • {insight}")

    # Export
    output_path = f"~/.claude/data/customer-contexts/{company_name.lower().replace(' ', '-')}.json"
    output_path = Path(output_path).expanduser()
    aggregator.export_context(context, str(output_path))

    print("\n" + "=" * 60)
    print("✅ COMPLETE")
    print("=" * 60)


if __name__ == '__main__':
    main()
