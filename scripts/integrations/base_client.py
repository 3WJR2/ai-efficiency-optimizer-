#!/usr/bin/env python3
"""
Base API Client
Provides common functionality for all integration clients
"""

import json
import time
import hashlib
import requests
from pathlib import Path
from typing import Dict, Optional, Any
from datetime import datetime, timedelta


class BaseAPIClient:
    """Base class for all API clients with caching, rate limiting, and error handling"""

    def __init__(self, config_path: str, integration_name: str):
        """
        Initialize base client

        Args:
            config_path: Path to config.json
            integration_name: Name of integration (gong, hubspot, github, qodo)
        """
        self.integration_name = integration_name

        # Load config
        with open(config_path, 'r') as f:
            self.config = json.load(f)

        self.integration_config = self.config['integrations'][integration_name]
        self.cache_config = self.config['caching']
        self.data_config = self.config['data_collection']

        # Setup paths
        self.cache_dir = Path(self.cache_config['cache_dir'].replace('~', str(Path.home())))
        self.cache_dir.mkdir(parents=True, exist_ok=True)

        credentials_path = Path(self.config['credentials_path'].replace('~', str(Path.home())))
        credentials_file = credentials_path / f"{integration_name}.json"

        # Load credentials if available
        self.credentials = {}
        if credentials_file.exists():
            with open(credentials_file, 'r') as f:
                self.credentials = json.load(f)

        # Rate limiting
        self.rate_limit = self.integration_config.get('rate_limit', {})
        self.request_timestamps = []

        # Session for connection pooling
        self.session = requests.Session()
        self._setup_session()

    def _setup_session(self):
        """Setup session with auth headers"""
        if 'api_key' in self.credentials:
            self.session.headers['Authorization'] = f"Bearer {self.credentials['api_key']}"
        elif 'access_token' in self.credentials:
            self.session.headers['Authorization'] = f"Bearer {self.credentials['access_token']}"

        self.session.headers['User-Agent'] = 'Claude-SE-Workflow/1.0'

    def _get_cache_key(self, endpoint: str, params: Dict) -> str:
        """Generate cache key from endpoint and params"""
        key_str = f"{self.integration_name}:{endpoint}:{json.dumps(params, sort_keys=True)}"
        return hashlib.md5(key_str.encode()).hexdigest()

    def _get_cached_response(self, cache_key: str) -> Optional[Dict]:
        """Get cached response if available and not expired"""
        if not self.cache_config['enabled']:
            return None

        cache_file = self.cache_dir / f"{cache_key}.json"

        if not cache_file.exists():
            return None

        try:
            with open(cache_file, 'r') as f:
                cached = json.load(f)

            # Check expiry
            cached_time = datetime.fromisoformat(cached['timestamp'])
            ttl = timedelta(seconds=self.cache_config['ttl_seconds'])

            if datetime.now() - cached_time < ttl:
                return cached['data']
            else:
                # Expired, remove
                cache_file.unlink()
                return None
        except Exception as e:
            print(f"Cache read error: {e}")
            return None

    def _save_cached_response(self, cache_key: str, data: Dict):
        """Save response to cache"""
        if not self.cache_config['enabled']:
            return

        cache_file = self.cache_dir / f"{cache_key}.json"

        cached = {
            'timestamp': datetime.now().isoformat(),
            'integration': self.integration_name,
            'data': data
        }

        try:
            with open(cache_file, 'w') as f:
                json.dump(cached, f, indent=2)
        except Exception as e:
            print(f"Cache write error: {e}")

    def _check_rate_limit(self):
        """Check and enforce rate limits"""
        if not self.rate_limit:
            return

        now = time.time()

        # Clean old timestamps
        if 'requests_per_minute' in self.rate_limit:
            cutoff = now - 60
            self.request_timestamps = [t for t in self.request_timestamps if t > cutoff]

            # Check limit
            limit = self.rate_limit['requests_per_minute']
            if len(self.request_timestamps) >= limit:
                sleep_time = 60 - (now - self.request_timestamps[0])
                if sleep_time > 0:
                    print(f"Rate limit: sleeping {sleep_time:.1f}s")
                    time.sleep(sleep_time)

        elif 'requests_per_hour' in self.rate_limit:
            cutoff = now - 3600
            self.request_timestamps = [t for t in self.request_timestamps if t > cutoff]

            limit = self.rate_limit['requests_per_hour']
            if len(self.request_timestamps) >= limit:
                sleep_time = 3600 - (now - self.request_timestamps[0])
                if sleep_time > 0:
                    print(f"Rate limit: sleeping {sleep_time:.1f}s")
                    time.sleep(sleep_time)

        self.request_timestamps.append(now)

    def _make_request(self, method: str, endpoint: str, **kwargs) -> Dict:
        """
        Make HTTP request with retries, rate limiting, and caching

        Args:
            method: HTTP method (GET, POST, etc.)
            endpoint: API endpoint
            **kwargs: Additional request parameters

        Returns:
            Response data as dict
        """
        # Check cache for GET requests
        if method == 'GET':
            params = kwargs.get('params', {})
            cache_key = self._get_cache_key(endpoint, params)
            cached = self._get_cached_response(cache_key)
            if cached:
                print(f"Cache hit: {endpoint}")
                return cached

        # Rate limiting
        self._check_rate_limit()

        # Build URL
        base_url = self.integration_config['base_url']
        url = f"{base_url}/{endpoint.lstrip('/')}"

        # Retry logic
        retry_count = 0
        max_retries = self.data_config['retry_attempts']
        retry_delay = self.data_config['retry_delay_seconds']
        timeout = self.data_config['timeout_seconds']

        while retry_count <= max_retries:
            try:
                response = self.session.request(
                    method=method,
                    url=url,
                    timeout=timeout,
                    **kwargs
                )

                response.raise_for_status()
                data = response.json()

                # Cache successful GET requests
                if method == 'GET':
                    self._save_cached_response(cache_key, data)

                return data

            except requests.exceptions.RequestException as e:
                retry_count += 1
                if retry_count > max_retries:
                    raise Exception(f"Request failed after {max_retries} retries: {e}")

                print(f"Request failed (attempt {retry_count}/{max_retries}): {e}")
                time.sleep(retry_delay * retry_count)  # Exponential backoff

        raise Exception("Request failed")

    def get(self, endpoint: str, params: Optional[Dict] = None) -> Dict:
        """Make GET request"""
        return self._make_request('GET', endpoint, params=params or {})

    def post(self, endpoint: str, data: Optional[Dict] = None, json_data: Optional[Dict] = None) -> Dict:
        """Make POST request"""
        return self._make_request('POST', endpoint, data=data, json=json_data)

    def is_enabled(self) -> bool:
        """Check if integration is enabled"""
        return self.integration_config.get('enabled', False)

    def has_credentials(self) -> bool:
        """Check if credentials are configured"""
        return bool(self.credentials)

    def test_connection(self) -> Dict:
        """
        Test API connection

        Returns:
            {
                'connected': True/False,
                'message': 'Success' or error message,
                'features_available': [...]
            }
        """
        if not self.is_enabled():
            return {
                'connected': False,
                'message': f'{self.integration_name} integration is disabled in config'
            }

        if not self.has_credentials():
            return {
                'connected': False,
                'message': f'No credentials found for {self.integration_name}'
            }

        try:
            # Subclasses should override this with actual test
            return {
                'connected': True,
                'message': 'Base client initialized',
                'features_available': self.integration_config.get('features', [])
            }
        except Exception as e:
            return {
                'connected': False,
                'message': str(e)
            }
