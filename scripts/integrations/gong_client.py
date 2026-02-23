#!/usr/bin/env python3
"""
Gong API Client
Fetches call transcripts, pain points, and decision maker information
"""

import re
from typing import Dict, List, Optional
from datetime import datetime, timedelta
from base_client import BaseAPIClient


class GongClient(BaseAPIClient):
    """Client for Gong API - Sales call intelligence"""

    def __init__(self, config_path: str):
        super().__init__(config_path, 'gong')

    def test_connection(self) -> Dict:
        """Test Gong API connection"""
        if not self.is_enabled():
            return {
                'connected': False,
                'message': 'Gong integration is disabled in config'
            }

        if not self.has_credentials():
            return {
                'connected': False,
                'message': 'No Gong credentials found'
            }

        try:
            # Test with a simple API call
            result = self.get('/v2/calls', params={'fromDateTime': datetime.now().isoformat()})
            return {
                'connected': True,
                'message': 'Successfully connected to Gong API',
                'features_available': self.integration_config.get('features', [])
            }
        except Exception as e:
            return {
                'connected': False,
                'message': f'Connection failed: {str(e)}'
            }

    def get_account_calls(self, account_name: str, days_back: int = 30) -> List[Dict]:
        """
        Get recent calls for a specific account

        Args:
            account_name: Company name to search for
            days_back: How many days back to search (default 30)

        Returns:
            List of call objects with metadata
        """
        if not self.is_enabled():
            return []

        from_date = (datetime.now() - timedelta(days=days_back)).isoformat()

        try:
            # Search for calls mentioning the account
            result = self.get('/v2/calls', params={
                'fromDateTime': from_date,
                'contentSelector': {
                    'exposedFields': {
                        'content': True,
                        'structure': True
                    }
                }
            })

            calls = result.get('calls', [])

            # Filter calls that mention the account name
            account_calls = []
            for call in calls:
                # Check if account name is in call title or parties
                if self._is_account_call(call, account_name):
                    account_calls.append({
                        'id': call.get('id'),
                        'title': call.get('title'),
                        'date': call.get('started'),
                        'duration': call.get('duration'),
                        'participants': self._extract_participants(call),
                        'url': call.get('url')
                    })

            return account_calls

        except Exception as e:
            print(f"Error fetching account calls: {e}")
            return []

    def get_call_transcript(self, call_id: str) -> Optional[Dict]:
        """
        Get full transcript for a specific call

        Args:
            call_id: Gong call ID

        Returns:
            {
                'call_id': str,
                'transcript': str,
                'speakers': [{'name': str, 'role': str}],
                'duration': int,
                'date': str
            }
        """
        if not self.is_enabled():
            return None

        try:
            result = self.get(f'/v2/calls/{call_id}/transcript')

            transcript_data = result.get('callTranscript', {})

            # Combine all transcript segments
            full_transcript = []
            speakers = set()

            for segment in transcript_data.get('transcript', []):
                speaker_name = segment.get('speakerName', 'Unknown')
                text = segment.get('text', '')
                speakers.add(speaker_name)
                full_transcript.append(f"{speaker_name}: {text}")

            return {
                'call_id': call_id,
                'transcript': '\n'.join(full_transcript),
                'speakers': [{'name': s, 'role': 'unknown'} for s in speakers],
                'duration': result.get('duration'),
                'date': result.get('started')
            }

        except Exception as e:
            print(f"Error fetching transcript: {e}")
            return None

    def extract_pain_points(self, transcript: str) -> List[Dict]:
        """
        Extract pain points from call transcript using pattern matching

        Args:
            transcript: Full call transcript text

        Returns:
            List of pain points with context
        """
        pain_indicators = [
            # Problem statements
            r"(struggling with|having trouble|difficult to|pain point|challenge|issue|problem)",
            # Frustration
            r"(frustrated|annoying|waste.*time|slow|manual)",
            # Gaps
            r"(missing|lack of|don't have|need.*but|wish we had)",
            # Current state issues
            r"(currently.*manually|takes too long|inefficient|error-prone)"
        ]

        pain_points = []
        lines = transcript.split('\n')

        for i, line in enumerate(lines):
            for pattern in pain_indicators:
                if re.search(pattern, line, re.IGNORECASE):
                    # Extract context (current line + next 2 lines)
                    context_lines = lines[i:min(i+3, len(lines))]
                    context = ' '.join(context_lines)

                    pain_points.append({
                        'indicator': pattern,
                        'context': context[:500],  # Limit context length
                        'line_number': i + 1
                    })
                    break  # Only match once per line

        return pain_points

    def identify_decision_makers(self, transcript: str) -> List[Dict]:
        """
        Identify decision makers from transcript

        Args:
            transcript: Full call transcript text

        Returns:
            List of potential decision makers with titles
        """
        decision_titles = [
            r"(CTO|Chief Technology Officer)",
            r"(VP.*Engineering|VP.*Technology)",
            r"(Engineering Manager|Development Manager)",
            r"(Head of Engineering|Head of Development)",
            r"(Director.*Engineering|Director.*Technology)",
            r"(Lead.*Engineer|Principal.*Engineer)"
        ]

        decision_makers = []
        lines = transcript.split('\n')

        for line in lines:
            # Extract speaker name (format: "Name: text")
            match = re.match(r'^([^:]+):', line)
            if match:
                speaker = match.group(1).strip()

                # Check if title is mentioned
                for title_pattern in decision_titles:
                    if re.search(title_pattern, line, re.IGNORECASE):
                        decision_makers.append({
                            'name': speaker,
                            'title': re.search(title_pattern, line, re.IGNORECASE).group(0),
                            'context': line[:200]
                        })
                        break

        return decision_makers

    def get_account_context(self, account_name: str, days_back: int = 30) -> Dict:
        """
        Get comprehensive context for an account

        Args:
            account_name: Company name
            days_back: Days to look back for calls

        Returns:
            Complete account context from Gong
        """
        if not self.is_enabled():
            return {
                'available': False,
                'message': 'Gong integration disabled'
            }

        if not self.has_credentials():
            return {
                'available': False,
                'message': 'Gong credentials not configured'
            }

        # Get recent calls
        calls = self.get_account_calls(account_name, days_back)

        if not calls:
            return {
                'available': True,
                'account_name': account_name,
                'calls': [],
                'pain_points': [],
                'decision_makers': [],
                'message': f'No calls found for {account_name} in last {days_back} days'
            }

        # Get transcript for most recent call
        most_recent_call = calls[0]
        transcript_data = self.get_call_transcript(most_recent_call['id'])

        if not transcript_data:
            return {
                'available': True,
                'account_name': account_name,
                'calls': calls,
                'pain_points': [],
                'decision_makers': [],
                'message': 'Could not fetch transcript'
            }

        # Extract insights
        pain_points = self.extract_pain_points(transcript_data['transcript'])
        decision_makers = self.identify_decision_makers(transcript_data['transcript'])

        return {
            'available': True,
            'account_name': account_name,
            'calls': calls,
            'most_recent_call': {
                'id': most_recent_call['id'],
                'date': most_recent_call['date'],
                'url': most_recent_call['url'],
                'participants': most_recent_call['participants']
            },
            'transcript': transcript_data['transcript'][:2000],  # Truncate for overview
            'pain_points': pain_points,
            'decision_makers': decision_makers,
            'insights': self._generate_insights(pain_points, decision_makers)
        }

    def _is_account_call(self, call: Dict, account_name: str) -> bool:
        """Check if a call is related to the account"""
        account_lower = account_name.lower()

        # Check title
        if account_lower in call.get('title', '').lower():
            return True

        # Check parties/participants
        for party in call.get('parties', []):
            if account_lower in party.get('name', '').lower():
                return True
            if account_lower in party.get('emailAddress', '').lower():
                return True

        return False

    def _extract_participants(self, call: Dict) -> List[str]:
        """Extract participant names from call"""
        participants = []
        for party in call.get('parties', []):
            name = party.get('name')
            if name:
                participants.append(name)
        return participants

    def _generate_insights(self, pain_points: List[Dict], decision_makers: List[Dict]) -> Dict:
        """Generate high-level insights from extracted data"""
        return {
            'pain_point_count': len(pain_points),
            'primary_pain_categories': self._categorize_pain_points(pain_points),
            'decision_maker_count': len(decision_makers),
            'seniority_level': self._assess_seniority(decision_makers)
        }

    def _categorize_pain_points(self, pain_points: List[Dict]) -> List[str]:
        """Categorize pain points into themes"""
        categories = set()

        category_keywords = {
            'code_quality': ['bug', 'error', 'quality', 'test'],
            'velocity': ['slow', 'time', 'manual', 'inefficient'],
            'collaboration': ['review', 'merge', 'conflict', 'communication'],
            'security': ['security', 'vulnerability', 'compliance']
        }

        for pain_point in pain_points:
            context_lower = pain_point['context'].lower()
            for category, keywords in category_keywords.items():
                if any(keyword in context_lower for keyword in keywords):
                    categories.add(category)

        return list(categories)

    def _assess_seniority(self, decision_makers: List[Dict]) -> str:
        """Assess overall seniority level of decision makers"""
        if not decision_makers:
            return 'unknown'

        titles = [dm.get('title', '').lower() for dm in decision_makers]

        if any('cto' in t or 'chief' in t or 'vp' in t for t in titles):
            return 'executive'
        elif any('director' in t or 'head of' in t for t in titles):
            return 'senior'
        elif any('manager' in t or 'lead' in t for t in titles):
            return 'mid'
        else:
            return 'engineer'


if __name__ == '__main__':
    # Test Gong client
    import sys

    config_path = sys.argv[1] if len(sys.argv) > 1 else './config.json'

    client = GongClient(config_path)

    # Test connection
    print("Testing Gong connection...")
    result = client.test_connection()
    print(f"Connected: {result['connected']}")
    print(f"Message: {result['message']}")

    if result['connected']:
        print(f"Features: {result.get('features_available', [])}")
