#!/usr/bin/env python3
"""
HubSpot API Client
Fetches company information, deal details, and contacts
"""

from typing import Dict, List, Optional
from base_client import BaseAPIClient


class HubSpotClient(BaseAPIClient):
    """Client for HubSpot API - CRM data"""

    def __init__(self, config_path: str):
        super().__init__(config_path, 'hubspot')

    def test_connection(self) -> Dict:
        """Test HubSpot API connection"""
        if not self.is_enabled():
            return {
                'connected': False,
                'message': 'HubSpot integration is disabled in config'
            }

        if not self.has_credentials():
            return {
                'connected': False,
                'message': 'No HubSpot credentials found'
            }

        try:
            # Test with account info endpoint
            result = self.get('/account-info/v3/api-usage/daily')
            return {
                'connected': True,
                'message': 'Successfully connected to HubSpot API',
                'features_available': self.integration_config.get('features', [])
            }
        except Exception as e:
            return {
                'connected': False,
                'message': f'Connection failed: {str(e)}'
            }

    def search_company(self, company_name: str) -> Optional[Dict]:
        """
        Search for a company by name

        Args:
            company_name: Company name to search

        Returns:
            Company object with ID and properties
        """
        if not self.is_enabled():
            return None

        try:
            # Search companies by name
            search_request = {
                'filterGroups': [{
                    'filters': [{
                        'propertyName': 'name',
                        'operator': 'CONTAINS_TOKEN',
                        'value': company_name
                    }]
                }],
                'properties': [
                    'name',
                    'domain',
                    'industry',
                    'numberofemployees',
                    'annualrevenue',
                    'city',
                    'state',
                    'country'
                ]
            }

            result = self.post('/crm/v3/objects/companies/search', json_data=search_request)

            results = result.get('results', [])
            if not results:
                return None

            # Return first match
            company = results[0]
            return {
                'id': company.get('id'),
                'name': company.get('properties', {}).get('name'),
                'domain': company.get('properties', {}).get('domain'),
                'industry': company.get('properties', {}).get('industry'),
                'employees': company.get('properties', {}).get('numberofemployees'),
                'revenue': company.get('properties', {}).get('annualrevenue'),
                'location': {
                    'city': company.get('properties', {}).get('city'),
                    'state': company.get('properties', {}).get('state'),
                    'country': company.get('properties', {}).get('country')
                }
            }

        except Exception as e:
            print(f"Error searching company: {e}")
            return None

    def get_company_deals(self, company_id: str) -> List[Dict]:
        """
        Get all deals associated with a company

        Args:
            company_id: HubSpot company ID

        Returns:
            List of deal objects
        """
        if not self.is_enabled():
            return []

        try:
            # Get company associations
            result = self.get(
                f'/crm/v4/objects/companies/{company_id}/associations/deals'
            )

            deal_ids = [item.get('toObjectId') for item in result.get('results', [])]

            if not deal_ids:
                return []

            # Get deal details
            deals = []
            for deal_id in deal_ids:
                deal_data = self.get(
                    f'/crm/v3/objects/deals/{deal_id}',
                    params={
                        'properties': [
                            'dealname',
                            'dealstage',
                            'amount',
                            'closedate',
                            'pipeline',
                            'createdate',
                            'hs_priority'
                        ]
                    }
                )

                props = deal_data.get('properties', {})
                deals.append({
                    'id': deal_id,
                    'name': props.get('dealname'),
                    'stage': props.get('dealstage'),
                    'amount': props.get('amount'),
                    'close_date': props.get('closedate'),
                    'pipeline': props.get('pipeline'),
                    'created_date': props.get('createdate'),
                    'priority': props.get('hs_priority')
                })

            return deals

        except Exception as e:
            print(f"Error fetching deals: {e}")
            return []

    def get_company_contacts(self, company_id: str) -> List[Dict]:
        """
        Get contacts associated with a company

        Args:
            company_id: HubSpot company ID

        Returns:
            List of contact objects
        """
        if not self.is_enabled():
            return []

        try:
            # Get company associations
            result = self.get(
                f'/crm/v4/objects/companies/{company_id}/associations/contacts'
            )

            contact_ids = [item.get('toObjectId') for item in result.get('results', [])]

            if not contact_ids:
                return []

            # Get contact details
            contacts = []
            for contact_id in contact_ids:
                contact_data = self.get(
                    f'/crm/v3/objects/contacts/{contact_id}',
                    params={
                        'properties': [
                            'firstname',
                            'lastname',
                            'email',
                            'jobtitle',
                            'phone',
                            'hs_lead_status',
                            'lifecyclestage'
                        ]
                    }
                )

                props = contact_data.get('properties', {})
                contacts.append({
                    'id': contact_id,
                    'first_name': props.get('firstname'),
                    'last_name': props.get('lastname'),
                    'email': props.get('email'),
                    'title': props.get('jobtitle'),
                    'phone': props.get('phone'),
                    'lead_status': props.get('hs_lead_status'),
                    'lifecycle_stage': props.get('lifecyclestage')
                })

            return contacts

        except Exception as e:
            print(f"Error fetching contacts: {e}")
            return []

    def get_deal_context(self, company_name: str) -> Dict:
        """
        Get comprehensive deal context for a company

        Args:
            company_name: Company name to search

        Returns:
            Complete deal context from HubSpot
        """
        if not self.is_enabled():
            return {
                'available': False,
                'message': 'HubSpot integration disabled'
            }

        if not self.has_credentials():
            return {
                'available': False,
                'message': 'HubSpot credentials not configured'
            }

        # Search for company
        company = self.search_company(company_name)

        if not company:
            return {
                'available': True,
                'company_name': company_name,
                'found': False,
                'message': f'Company "{company_name}" not found in HubSpot'
            }

        company_id = company['id']

        # Get deals and contacts
        deals = self.get_company_deals(company_id)
        contacts = self.get_company_contacts(company_id)

        # Analyze deals
        active_deals = [d for d in deals if d['stage'] not in ['closedwon', 'closedlost']]
        total_pipeline_value = sum(float(d.get('amount', 0) or 0) for d in active_deals)

        # Find primary contact (highest in lifecycle)
        primary_contact = self._identify_primary_contact(contacts)

        return {
            'available': True,
            'company_name': company_name,
            'found': True,
            'company': company,
            'deals': {
                'total': len(deals),
                'active': len(active_deals),
                'pipeline_value': total_pipeline_value,
                'deals': deals
            },
            'contacts': {
                'total': len(contacts),
                'primary': primary_contact,
                'all_contacts': contacts
            },
            'insights': self._generate_deal_insights(company, deals, contacts)
        }

    def _identify_primary_contact(self, contacts: List[Dict]) -> Optional[Dict]:
        """Identify the primary contact (most senior or engaged)"""
        if not contacts:
            return None

        # Lifecycle stage priority
        stage_priority = {
            'customer': 5,
            'opportunity': 4,
            'marketingqualifiedlead': 3,
            'salesqualifiedlead': 3,
            'lead': 2,
            'subscriber': 1,
            'other': 0
        }

        # Score contacts
        scored_contacts = []
        for contact in contacts:
            score = stage_priority.get(contact.get('lifecycle_stage', '').lower(), 0)

            # Boost score for senior titles
            title = (contact.get('title') or '').lower()
            if any(t in title for t in ['cto', 'vp', 'director', 'head', 'chief']):
                score += 10

            scored_contacts.append((score, contact))

        # Return highest scored
        scored_contacts.sort(key=lambda x: x[0], reverse=True)
        return scored_contacts[0][1] if scored_contacts else None

    def _generate_deal_insights(self, company: Dict, deals: List[Dict], contacts: List[Dict]) -> Dict:
        """Generate insights from deal data"""
        active_deals = [d for d in deals if d['stage'] not in ['closedwon', 'closedlost']]

        # Determine deal stage
        if not active_deals:
            deal_stage = 'no_active_deals'
        else:
            # Use most advanced stage
            stages = [d['stage'] for d in active_deals]
            if any('contract' in s.lower() for s in stages):
                deal_stage = 'contract_negotiation'
            elif any('proposal' in s.lower() or 'quote' in s.lower() for s in stages):
                deal_stage = 'proposal'
            elif any('demo' in s.lower() or 'presentation' in s.lower() for s in stages):
                deal_stage = 'demo'
            else:
                deal_stage = 'early_stage'

        # Assess engagement level
        contact_count = len(contacts)
        if contact_count >= 5:
            engagement = 'high'
        elif contact_count >= 2:
            engagement = 'medium'
        else:
            engagement = 'low'

        # Company size category
        employees = company.get('employees')
        if employees:
            try:
                emp_count = int(employees)
                if emp_count > 1000:
                    company_size = 'enterprise'
                elif emp_count > 200:
                    company_size = 'mid_market'
                else:
                    company_size = 'smb'
            except:
                company_size = 'unknown'
        else:
            company_size = 'unknown'

        return {
            'deal_stage': deal_stage,
            'engagement_level': engagement,
            'company_size': company_size,
            'has_active_deals': len(active_deals) > 0,
            'deal_count': len(active_deals),
            'contact_diversity': self._assess_contact_diversity(contacts)
        }

    def _assess_contact_diversity(self, contacts: List[Dict]) -> str:
        """Assess how diverse the contact roles are"""
        titles = [c.get('title', '').lower() for c in contacts if c.get('title')]

        if not titles:
            return 'unknown'

        # Check for different role types
        has_technical = any(t in title for title in titles for t in ['engineer', 'developer', 'architect', 'technical'])
        has_executive = any(t in title for title in titles for t in ['cto', 'vp', 'director', 'chief', 'head'])
        has_manager = any(t in title for title in titles for t in ['manager', 'lead'])

        roles_count = sum([has_technical, has_executive, has_manager])

        if roles_count >= 2:
            return 'diverse'
        elif roles_count == 1:
            return 'focused'
        else:
            return 'limited'


if __name__ == '__main__':
    # Test HubSpot client
    import sys

    config_path = sys.argv[1] if len(sys.argv) > 1 else './config.json'

    client = HubSpotClient(config_path)

    # Test connection
    print("Testing HubSpot connection...")
    result = client.test_connection()
    print(f"Connected: {result['connected']}")
    print(f"Message: {result['message']}")

    if result['connected']:
        print(f"Features: {result.get('features_available', [])}")
