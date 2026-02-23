#!/usr/bin/env python3
"""
GitHub API Client
Detects tech stack, analyzes code style, and manages PRs
"""

import re
from typing import Dict, List, Optional, Set
from collections import Counter
from base_client import BaseAPIClient


class GitHubClient(BaseAPIClient):
    """Client for GitHub API - Repository and code analysis"""

    def __init__(self, config_path: str):
        super().__init__(config_path, 'github')

    def test_connection(self) -> Dict:
        """Test GitHub API connection"""
        if not self.is_enabled():
            return {
                'connected': False,
                'message': 'GitHub integration is disabled in config'
            }

        if not self.has_credentials():
            return {
                'connected': False,
                'message': 'No GitHub credentials found'
            }

        try:
            # Test with user endpoint
            result = self.get('/user')
            return {
                'connected': True,
                'message': f"Successfully connected to GitHub as {result.get('login')}",
                'features_available': self.integration_config.get('features', [])
            }
        except Exception as e:
            return {
                'connected': False,
                'message': f'Connection failed: {str(e)}'
            }

    def get_org_repos(self, org_name: str, limit: int = 50) -> List[Dict]:
        """
        Get repositories for an organization

        Args:
            org_name: GitHub organization name
            limit: Maximum number of repos to return

        Returns:
            List of repository objects
        """
        if not self.is_enabled():
            return []

        try:
            result = self.get(
                f'/orgs/{org_name}/repos',
                params={
                    'sort': 'updated',
                    'per_page': limit,
                    'type': 'all'
                }
            )

            repos = []
            for repo in result:
                repos.append({
                    'name': repo.get('name'),
                    'full_name': repo.get('full_name'),
                    'description': repo.get('description'),
                    'language': repo.get('language'),
                    'stars': repo.get('stargazers_count'),
                    'forks': repo.get('forks_count'),
                    'updated_at': repo.get('updated_at'),
                    'private': repo.get('private'),
                    'url': repo.get('html_url')
                })

            return repos

        except Exception as e:
            print(f"Error fetching org repos: {e}")
            return []

    def detect_tech_stack(self, org_name: str, repo_name: Optional[str] = None) -> Dict:
        """
        Detect technology stack from repository/repositories

        Args:
            org_name: GitHub organization name
            repo_name: Specific repo (if None, analyzes all org repos)

        Returns:
            Tech stack analysis
        """
        if not self.is_enabled():
            return {'available': False, 'message': 'GitHub integration disabled'}

        try:
            if repo_name:
                # Analyze single repo
                repos_to_analyze = [{
                    'full_name': f'{org_name}/{repo_name}',
                    'name': repo_name
                }]
            else:
                # Get all org repos
                repos = self.get_org_repos(org_name)
                repos_to_analyze = [{'full_name': r['full_name'], 'name': r['name']} for r in repos[:10]]  # Limit to 10

            # Aggregate tech stack data
            languages = Counter()
            frameworks = set()
            tools = set()

            for repo in repos_to_analyze:
                repo_full_name = repo['full_name']

                # Get languages
                try:
                    langs = self.get(f'/repos/{repo_full_name}/languages')
                    languages.update(langs)
                except:
                    pass

                # Detect frameworks and tools from files
                repo_tech = self._detect_repo_technologies(repo_full_name)
                frameworks.update(repo_tech['frameworks'])
                tools.update(repo_tech['tools'])

            # Determine primary language
            primary_language = languages.most_common(1)[0][0] if languages else 'unknown'

            return {
                'available': True,
                'org_name': org_name,
                'repo_name': repo_name,
                'languages': dict(languages),
                'primary_language': primary_language,
                'frameworks': list(frameworks),
                'tools': list(tools),
                'repos_analyzed': len(repos_to_analyze),
                'tech_summary': self._generate_tech_summary(primary_language, frameworks, tools)
            }

        except Exception as e:
            print(f"Error detecting tech stack: {e}")
            return {
                'available': True,
                'error': str(e),
                'message': 'Failed to detect tech stack'
            }

    def _detect_repo_technologies(self, repo_full_name: str) -> Dict:
        """Detect frameworks and tools from repository files"""
        frameworks = set()
        tools = set()

        # Check key files
        key_files = {
            'package.json': ['react', 'vue', 'angular', 'next', 'express', 'nest'],
            'requirements.txt': ['django', 'flask', 'fastapi', 'pytest', 'pandas'],
            'Gemfile': ['rails', 'sinatra', 'rspec'],
            'go.mod': ['gin', 'echo', 'fiber'],
            'pom.xml': ['spring'],
            'build.gradle': ['spring', 'micronaut'],
            'Cargo.toml': ['actix', 'rocket', 'tokio'],
            'composer.json': ['laravel', 'symfony']
        }

        ci_files = [
            '.github/workflows',
            '.gitlab-ci.yml',
            'Jenkinsfile',
            '.circleci/config.yml'
        ]

        for filename, framework_patterns in key_files.items():
            try:
                content = self.get(f'/repos/{repo_full_name}/contents/{filename}')
                if content and not isinstance(content, list):
                    # File exists - check for frameworks
                    file_content = self._get_file_content(content)
                    if file_content:
                        for pattern in framework_patterns:
                            if pattern.lower() in file_content.lower():
                                frameworks.add(pattern)
            except:
                pass

        # Check for CI/CD tools
        for ci_file in ci_files:
            try:
                self.get(f'/repos/{repo_full_name}/contents/{ci_file}')
                # File exists
                if 'github' in ci_file:
                    tools.add('GitHub Actions')
                elif 'gitlab' in ci_file:
                    tools.add('GitLab CI')
                elif 'Jenkins' in ci_file:
                    tools.add('Jenkins')
                elif 'circleci' in ci_file:
                    tools.add('CircleCI')
            except:
                pass

        # Check for Docker
        try:
            self.get(f'/repos/{repo_full_name}/contents/Dockerfile')
            tools.add('Docker')
        except:
            pass

        # Check for Kubernetes
        try:
            self.get(f'/repos/{repo_full_name}/contents/k8s')
            tools.add('Kubernetes')
        except:
            pass

        return {
            'frameworks': frameworks,
            'tools': tools
        }

    def _get_file_content(self, file_object: Dict) -> Optional[str]:
        """Decode file content from GitHub API response"""
        try:
            import base64
            content = file_object.get('content', '')
            decoded = base64.b64decode(content).decode('utf-8')
            return decoded
        except:
            return None

    def _generate_tech_summary(self, primary_language: str, frameworks: Set, tools: Set) -> str:
        """Generate human-readable tech stack summary"""
        parts = []

        if primary_language and primary_language != 'unknown':
            parts.append(f"{primary_language} development")

        if frameworks:
            framework_list = ', '.join(sorted(frameworks)[:3])  # Top 3
            parts.append(f"using {framework_list}")

        if tools:
            tool_list = ', '.join(sorted(tools)[:3])  # Top 3
            parts.append(f"with {tool_list}")

        return ' '.join(parts) if parts else 'Unable to determine tech stack'

    def analyze_code_style(self, org_name: str, repo_name: str) -> Dict:
        """
        Analyze code style patterns from repository

        Args:
            org_name: GitHub organization
            repo_name: Repository name

        Returns:
            Code style analysis
        """
        if not self.is_enabled():
            return {'available': False}

        repo_full_name = f'{org_name}/{repo_name}'

        try:
            # Get recent commits
            commits = self.get(f'/repos/{repo_full_name}/commits', params={'per_page': 10})

            # Analyze commit messages
            commit_patterns = self._analyze_commit_patterns(commits)

            # Get PR review patterns
            prs = self.get(f'/repos/{repo_full_name}/pulls', params={
                'state': 'closed',
                'per_page': 20
            })

            pr_patterns = self._analyze_pr_patterns(prs)

            return {
                'available': True,
                'repo': repo_full_name,
                'commit_style': commit_patterns,
                'pr_style': pr_patterns,
                'recommendations': self._generate_style_recommendations(commit_patterns, pr_patterns)
            }

        except Exception as e:
            print(f"Error analyzing code style: {e}")
            return {
                'available': True,
                'error': str(e)
            }

    def _analyze_commit_patterns(self, commits: List[Dict]) -> Dict:
        """Analyze commit message patterns"""
        messages = [c.get('commit', {}).get('message', '') for c in commits]

        # Check for conventional commits
        conventional = sum(1 for m in messages if re.match(r'^(feat|fix|docs|style|refactor|test|chore)(\(.+\))?:', m))

        # Average length
        avg_length = sum(len(m.split('\n')[0]) for m in messages) / len(messages) if messages else 0

        # Check for emoji usage
        has_emoji = sum(1 for m in messages if re.search(r'[\U0001F300-\U0001F9FF]', m))

        return {
            'uses_conventional_commits': conventional > len(messages) * 0.5,
            'conventional_commit_percentage': (conventional / len(messages) * 100) if messages else 0,
            'avg_subject_length': int(avg_length),
            'uses_emoji': has_emoji > 0
        }

    def _analyze_pr_patterns(self, prs: List[Dict]) -> Dict:
        """Analyze PR patterns"""
        if not prs:
            return {'has_data': False}

        # Average PR size (by commits)
        avg_commits = sum(pr.get('commits', 0) for pr in prs) / len(prs)

        # PR naming patterns
        titles = [pr.get('title', '') for pr in prs]
        has_prefix = sum(1 for t in titles if re.match(r'^\[.+\]', t))

        return {
            'has_data': True,
            'avg_commits_per_pr': round(avg_commits, 1),
            'uses_pr_prefixes': has_prefix > len(prs) * 0.3,
            'pr_count_analyzed': len(prs)
        }

    def _generate_style_recommendations(self, commit_style: Dict, pr_style: Dict) -> List[str]:
        """Generate style recommendations for demos"""
        recommendations = []

        if commit_style.get('uses_conventional_commits'):
            recommendations.append("Use conventional commits format (feat:, fix:, etc.)")

        if commit_style.get('avg_subject_length', 0) < 50:
            recommendations.append("Keep commit messages concise (under 50 chars)")

        if pr_style.get('uses_pr_prefixes'):
            recommendations.append("Use PR prefixes like [Feature] or [Bugfix]")

        if pr_style.get('avg_commits_per_pr', 0) < 5:
            recommendations.append("Keep PRs focused (small, atomic changes)")

        return recommendations if recommendations else ["Follow repository's existing patterns"]

    def create_demo_pr(self, org_name: str, repo_name: str, branch_name: str,
                      title: str, body: str, base_branch: str = 'main') -> Dict:
        """
        Create a demo pull request

        Args:
            org_name: GitHub organization
            repo_name: Repository name
            branch_name: Source branch name
            title: PR title
            body: PR description
            base_branch: Target branch (default: main)

        Returns:
            Created PR object
        """
        if not self.is_enabled():
            return {'success': False, 'message': 'GitHub integration disabled'}

        repo_full_name = f'{org_name}/{repo_name}'

        try:
            pr_data = {
                'title': title,
                'body': body,
                'head': branch_name,
                'base': base_branch
            }

            result = self.post(f'/repos/{repo_full_name}/pulls', json_data=pr_data)

            return {
                'success': True,
                'pr_number': result.get('number'),
                'pr_url': result.get('html_url'),
                'pr_id': result.get('id')
            }

        except Exception as e:
            print(f"Error creating PR: {e}")
            return {
                'success': False,
                'error': str(e)
            }

    def get_repo_context(self, org_name: str, repo_name: Optional[str] = None) -> Dict:
        """
        Get comprehensive repository context

        Args:
            org_name: GitHub organization name
            repo_name: Specific repository (if None, analyzes org)

        Returns:
            Complete GitHub context
        """
        if not self.is_enabled():
            return {
                'available': False,
                'message': 'GitHub integration disabled'
            }

        if not self.has_credentials():
            return {
                'available': False,
                'message': 'GitHub credentials not configured'
            }

        # Get tech stack
        tech_stack = self.detect_tech_stack(org_name, repo_name)

        result = {
            'available': True,
            'org_name': org_name,
            'repo_name': repo_name,
            'tech_stack': tech_stack
        }

        # If specific repo, get code style
        if repo_name:
            code_style = self.analyze_code_style(org_name, repo_name)
            result['code_style'] = code_style

        # Get org repos summary
        if not repo_name:
            repos = self.get_org_repos(org_name, limit=20)
            result['repositories'] = {
                'count': len(repos),
                'top_repos': repos[:5],
                'languages': self._aggregate_languages(repos)
            }

        return result

    def _aggregate_languages(self, repos: List[Dict]) -> Dict:
        """Aggregate languages across repos"""
        lang_counter = Counter()
        for repo in repos:
            lang = repo.get('language')
            if lang:
                lang_counter[lang] += 1

        return dict(lang_counter.most_common(5))


if __name__ == '__main__':
    # Test GitHub client
    import sys

    config_path = sys.argv[1] if len(sys.argv) > 1 else './config.json'

    client = GitHubClient(config_path)

    # Test connection
    print("Testing GitHub connection...")
    result = client.test_connection()
    print(f"Connected: {result['connected']}")
    print(f"Message: {result['message']}")

    if result['connected']:
        print(f"Features: {result.get('features_available', [])}")
