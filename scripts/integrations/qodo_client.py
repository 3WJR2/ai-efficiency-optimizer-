#!/usr/bin/env python3
"""
Qodo API Client
Fetches feature catalog, pricing, use cases, and integration guides
"""

from typing import Dict, List, Optional, Set
from base_client import BaseAPIClient


class QodoClient(BaseAPIClient):
    """Client for Qodo API - Product information and recommendations"""

    def __init__(self, config_path: str):
        super().__init__(config_path, 'qodo')

        # Qodo product catalog (embedded knowledge)
        self.product_catalog = {
            'qodo_gen': {
                'name': 'Qodo Gen',
                'description': 'AI-powered test generation and code quality improvement',
                'capabilities': [
                    'Automated test generation',
                    'Code analysis and suggestions',
                    'Bug detection and fixing',
                    'Code documentation',
                    'Test coverage improvement'
                ],
                'languages': ['Python', 'JavaScript', 'TypeScript', 'Java', 'Go', 'C#', 'Ruby', 'PHP'],
                'ide_support': ['VS Code', 'JetBrains IDEs', 'Visual Studio'],
                'use_cases': [
                    'Increase test coverage',
                    'Catch bugs before production',
                    'Speed up development',
                    'Improve code quality'
                ]
            },
            'qodo_merge': {
                'name': 'Qodo Merge',
                'description': 'AI-powered code review and PR optimization',
                'capabilities': [
                    'Automated PR reviews',
                    'Code quality analysis',
                    'Security vulnerability detection',
                    'Issue prioritization (15+ review agents)',
                    '/implement command for automatic fixes',
                    'Custom review agents'
                ],
                'platforms': ['GitHub', 'GitLab', 'Bitbucket', 'Azure DevOps'],
                'use_cases': [
                    'Reduce review time',
                    'Catch issues early',
                    'Enforce code standards',
                    'Improve PR quality'
                ]
            },
            'qodo_command': {
                'name': 'Qodo Command',
                'description': 'CLI-based AI agents for development workflows',
                'capabilities': [
                    'Custom CLI agents',
                    'CI/CD integration',
                    'Scheduled code reviews',
                    'Batch processing',
                    'Workflow automation'
                ],
                'integration': ['GitHub Actions', 'GitLab CI', 'Jenkins', 'CircleCI'],
                'use_cases': [
                    'Automate repetitive tasks',
                    'Integrate into CI/CD',
                    'Run reviews on schedule',
                    'Custom workflows'
                ]
            },
            'qodo_aware': {
                'name': 'Qodo Aware',
                'description': 'Multi-repository context engine for complex queries',
                'capabilities': [
                    'Multi-repo indexing',
                    'Cross-codebase search',
                    'Impact analysis',
                    'Dependency mapping',
                    'Complex refactoring support'
                ],
                'features': ['Semantic code search', 'Architecture analysis', 'Change impact'],
                'use_cases': [
                    'Understand large codebases',
                    'Plan complex changes',
                    'Analyze dependencies',
                    'Multi-repo refactoring'
                ]
            }
        }

        # Pain point to product mapping
        self.pain_point_mapping = {
            'testing': ['qodo_gen'],
            'code_quality': ['qodo_gen', 'qodo_merge'],
            'review_time': ['qodo_merge'],
            'pr_bottleneck': ['qodo_merge'],
            'security': ['qodo_merge'],
            'ci_cd': ['qodo_command'],
            'automation': ['qodo_command'],
            'large_codebase': ['qodo_aware'],
            'refactoring': ['qodo_aware'],
            'context': ['qodo_aware']
        }

    def test_connection(self) -> Dict:
        """Test Qodo API connection (or use embedded catalog)"""
        if not self.is_enabled():
            return {
                'connected': False,
                'message': 'Qodo integration is disabled in config'
            }

        # Qodo API might not exist yet - use embedded catalog
        return {
            'connected': True,
            'message': 'Using embedded Qodo product catalog',
            'features_available': self.integration_config.get('features', []),
            'products': list(self.product_catalog.keys())
        }

    def get_product_catalog(self) -> Dict:
        """Get complete Qodo product catalog"""
        return {
            'available': True,
            'products': self.product_catalog,
            'product_count': len(self.product_catalog)
        }

    def recommend_products(self, pain_points: List[str], tech_stack: Dict) -> Dict:
        """
        Recommend Qodo products based on pain points and tech stack

        Args:
            pain_points: List of pain point categories
            tech_stack: Technology stack information

        Returns:
            Product recommendations with reasoning
        """
        recommendations = []
        recommended_products = set()

        # Map pain points to products
        for pain_category in pain_points:
            products = self.pain_point_mapping.get(pain_category, [])
            for product in products:
                if product not in recommended_products:
                    recommended_products.add(product)
                    recommendations.append({
                        'product': product,
                        'product_name': self.product_catalog[product]['name'],
                        'reason': f"Addresses {pain_category} pain points",
                        'details': self.product_catalog[product]
                    })

        # Check tech stack compatibility
        primary_language = tech_stack.get('primary_language', '').lower()
        frameworks = [f.lower() for f in tech_stack.get('frameworks', [])]

        # Enhance recommendations with tech stack relevance
        for rec in recommendations:
            product_key = rec['product']
            product = self.product_catalog[product_key]

            # Check language support
            if 'languages' in product:
                supported_langs = [l.lower() for l in product['languages']]
                if primary_language in ' '.join(supported_langs):
                    rec['tech_fit'] = 'excellent'
                else:
                    rec['tech_fit'] = 'good'

            # Check platform/CI support
            if 'platforms' in product or 'integration' in product:
                rec['integration_ready'] = True

        # Sort by priority (most relevant first)
        recommendations.sort(key=lambda x: x.get('tech_fit') == 'excellent', reverse=True)

        return {
            'available': True,
            'recommendations': recommendations,
            'recommendation_count': len(recommendations),
            'all_products_relevant': self._check_relevance(pain_points, tech_stack)
        }

    def _check_relevance(self, pain_points: List[str], tech_stack: Dict) -> List[str]:
        """Check which products are relevant regardless of pain points"""
        relevant = []

        # Qodo Gen is almost always relevant
        relevant.append('qodo_gen')

        # Qodo Merge if using Git platforms
        tools = tech_stack.get('tools', [])
        if any(tool.lower() in ['github', 'gitlab', 'bitbucket'] for tool in tools):
            relevant.append('qodo_merge')

        # Qodo Command if using CI/CD
        if any(tool.lower() in ['github actions', 'gitlab ci', 'jenkins', 'circleci'] for tool in tools):
            relevant.append('qodo_command')

        return relevant

    def get_use_cases(self, product: str, industry: Optional[str] = None) -> Dict:
        """
        Get use cases for a specific Qodo product

        Args:
            product: Product key (qodo_gen, qodo_merge, etc.)
            industry: Optional industry filter

        Returns:
            Use cases and examples
        """
        if product not in self.product_catalog:
            return {
                'available': False,
                'message': f'Unknown product: {product}'
            }

        product_data = self.product_catalog[product]

        use_cases = []
        for use_case in product_data.get('use_cases', []):
            use_cases.append({
                'title': use_case,
                'description': self._expand_use_case(product, use_case),
                'typical_roi': self._estimate_roi(product, use_case)
            })

        return {
            'available': True,
            'product': product_data['name'],
            'use_cases': use_cases
        }

    def _expand_use_case(self, product: str, use_case: str) -> str:
        """Expand use case with more details"""
        expansions = {
            'qodo_gen': {
                'Increase test coverage': 'Generate comprehensive test suites automatically, improving coverage from 40% to 80%+ in weeks',
                'Catch bugs before production': 'AI-powered analysis detects bugs during development, reducing production incidents by 60%',
                'Speed up development': 'Automate test writing, saving 3-5 hours per developer per week',
                'Improve code quality': 'Get actionable suggestions for cleaner, more maintainable code'
            },
            'qodo_merge': {
                'Reduce review time': 'Cut PR review time by 70% with automated analysis and issue detection',
                'Catch issues early': 'Detect security vulnerabilities, performance issues, and bugs before merge',
                'Enforce code standards': 'Automatically check compliance with coding standards and best practices',
                'Improve PR quality': 'Guide developers to write better PRs with inline suggestions'
            },
            'qodo_command': {
                'Automate repetitive tasks': 'Build custom agents for common workflows like dependency updates, security scans',
                'Integrate into CI/CD': 'Run automated reviews and checks in your existing CI pipeline',
                'Run reviews on schedule': 'Schedule nightly or weekly deep code reviews across repositories',
                'Custom workflows': 'Create specialized agents for your unique development processes'
            },
            'qodo_aware': {
                'Understand large codebases': 'Query and navigate codebases with millions of lines using natural language',
                'Plan complex changes': 'Analyze impact of changes across multiple repositories before refactoring',
                'Analyze dependencies': 'Visualize and understand cross-repo dependencies and relationships',
                'Multi-repo refactoring': 'Execute large-scale refactoring safely with full context understanding'
            }
        }

        return expansions.get(product, {}).get(use_case, use_case)

    def _estimate_roi(self, product: str, use_case: str) -> str:
        """Estimate ROI for use case"""
        roi_estimates = {
            'qodo_gen': '3-5 hours saved per developer per week',
            'qodo_merge': '70% reduction in review time, 60% fewer production bugs',
            'qodo_command': '10-15 hours saved per team per week on automation',
            'qodo_aware': '50% faster onboarding, 40% faster feature development'
        }

        return roi_estimates.get(product, 'Significant time and quality improvements')

    def generate_demo_script(self, customer_context: Dict) -> Dict:
        """
        Generate customized demo script based on customer context

        Args:
            customer_context: Combined context from all data sources

        Returns:
            Demo script with talking points
        """
        # Extract relevant info
        pain_points = customer_context.get('pain_points', [])
        tech_stack = customer_context.get('tech_stack', {})
        company_name = customer_context.get('company_name', 'the customer')

        # Get product recommendations
        recommendations = self.recommend_products(
            [p.get('indicator', '') for p in pain_points],
            tech_stack
        )

        # Build demo script
        script = {
            'introduction': {
                'duration': '2 minutes',
                'talking_points': [
                    f"Thanks for taking the time to meet with us, {company_name}",
                    f"I understand you're currently working with {tech_stack.get('primary_language', 'your tech stack')}",
                    "Today I'll show you how Qodo can help address the challenges you mentioned"
                ]
            },
            'pain_point_review': {
                'duration': '3 minutes',
                'talking_points': self._generate_pain_point_review(pain_points)
            },
            'solution_demo': {
                'duration': '15 minutes',
                'products': []
            },
            'roi_discussion': {
                'duration': '5 minutes',
                'talking_points': self._generate_roi_talking_points(recommendations)
            },
            'next_steps': {
                'duration': '5 minutes',
                'talking_points': [
                    'Set up a trial environment',
                    'Schedule technical deep dive',
                    'Discuss integration requirements',
                    'Plan POC timeline'
                ]
            }
        }

        # Add product demos
        for rec in recommendations.get('recommendations', [])[:3]:  # Top 3
            product_demo = {
                'product': rec['product_name'],
                'why_relevant': rec['reason'],
                'demo_flow': self._generate_demo_flow(rec['product'], tech_stack),
                'key_features_to_show': rec['details']['capabilities'][:5]
            }
            script['solution_demo']['products'].append(product_demo)

        return {
            'available': True,
            'customer': company_name,
            'total_duration': '30 minutes',
            'script': script,
            'preparation_notes': self._generate_prep_notes(tech_stack, recommendations)
        }

    def _generate_pain_point_review(self, pain_points: List[Dict]) -> List[str]:
        """Generate talking points for pain point review"""
        if not pain_points:
            return ["Let's start by understanding your current development workflow"]

        points = ["Based on our previous conversations, I heard:"]
        for i, pp in enumerate(pain_points[:3], 1):  # Top 3
            context = pp.get('context', '')[:100]
            points.append(f"{i}. {context}...")

        points.append("Does that sound right? Anything else you'd like to add?")
        return points

    def _generate_roi_talking_points(self, recommendations: Dict) -> List[str]:
        """Generate ROI discussion points"""
        points = [
            "Let's talk about the impact Qodo can have on your team:",
        ]

        for rec in recommendations.get('recommendations', [])[:2]:  # Top 2
            product = rec['product']
            roi = self._estimate_roi(product, '')
            points.append(f"With {rec['product_name']}: {roi}")

        points.extend([
            "Typical customers see ROI in the first month",
            "What metrics matter most to you in evaluating this?"
        ])

        return points

    def _generate_demo_flow(self, product: str, tech_stack: Dict) -> List[str]:
        """Generate step-by-step demo flow for product"""
        flows = {
            'qodo_gen': [
                'Open a file in VS Code',
                'Highlight a function that needs tests',
                'Run Qodo Gen to generate tests',
                'Show generated tests and explanations',
                'Demonstrate code improvement suggestions'
            ],
            'qodo_merge': [
                'Open a sample PR in GitHub',
                'Show Qodo Merge analysis in PR comments',
                'Walk through flagged issues (15+ agents)',
                'Demonstrate /implement command for auto-fix',
                'Show issue prioritization'
            ],
            'qodo_command': [
                'Show CLI agent configuration',
                'Run custom agent on repository',
                'Demonstrate CI/CD integration',
                'Show scheduled review results',
                'Explain custom agent creation'
            ],
            'qodo_aware': [
                'Query codebase with natural language',
                'Show cross-repo dependency mapping',
                'Demonstrate impact analysis for refactoring',
                'Run complex architectural queries',
                'Show multi-repo context understanding'
            ]
        }

        return flows.get(product, ['Demonstrate key capabilities', 'Show relevant use cases'])

    def _generate_prep_notes(self, tech_stack: Dict, recommendations: Dict) -> List[str]:
        """Generate preparation notes for SE"""
        notes = []

        # Tech stack prep
        primary_lang = tech_stack.get('primary_language', '')
        if primary_lang:
            notes.append(f"Prepare {primary_lang} code examples")

        frameworks = tech_stack.get('frameworks', [])
        if frameworks:
            notes.append(f"Include examples with {', '.join(frameworks[:2])}")

        # Product-specific prep
        products = [r['product'] for r in recommendations.get('recommendations', [])]
        if 'qodo_gen' in products:
            notes.append("Have a function ready that needs tests")
        if 'qodo_merge' in products:
            notes.append("Prepare a sample PR with issues")
        if 'qodo_command' in products:
            notes.append("Show CI/CD integration examples")
        if 'qodo_aware' in products:
            notes.append("Have multi-repo example ready")

        notes.extend([
            "Test all demos in advance",
            "Have backup environment ready",
            "Prepare objection responses"
        ])

        return notes


if __name__ == '__main__':
    # Test Qodo client
    import sys
    import json

    config_path = sys.argv[1] if len(sys.argv) > 1 else './config.json'

    client = QodoClient(config_path)

    # Test connection
    print("Testing Qodo client...")
    result = client.test_connection()
    print(f"Connected: {result['connected']}")
    print(f"Message: {result['message']}")
    print(f"Products: {result.get('products', [])}")

    # Test catalog
    print("\n\nProduct Catalog:")
    catalog = client.get_product_catalog()
    print(json.dumps(catalog, indent=2))
