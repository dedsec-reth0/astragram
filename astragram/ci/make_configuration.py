#!/usr/bin/env python3
"""Generate the AstraGram build configuration from environment variables.

The Telegram API credentials are never committed: CI reads them from the
repository secrets TELEGRAM_API_ID / TELEGRAM_API_HASH.

bundle_id and team_id stay equal to the values the build-system/fake-codesigning
provisioning profiles were issued for (C67CF9S4VU.ph.telegra.Telegraph);
SideStore re-signs the IPA and rewrites the bundle identifier on install.
"""
import json
import os
import sys


def main():
    if len(sys.argv) != 2:
        print('usage: make_configuration.py <output.json>')
        sys.exit(2)

    base_path = os.path.join(os.path.dirname(__file__), '..', '..', 'build-system', 'appstore-configuration.json')
    with open(base_path) as f:
        configuration = json.load(f)

    api_id = os.environ.get('TELEGRAM_API_ID', '').strip()
    api_hash = os.environ.get('TELEGRAM_API_HASH', '').strip()

    configured = bool(api_id and api_hash)
    if configured:
        if not api_id.isdigit():
            print('TELEGRAM_API_ID must be a number')
            sys.exit(1)
        if len(api_hash) != 32 or any(c not in '0123456789abcdef' for c in api_hash.lower()):
            print('TELEGRAM_API_HASH must be a 32-character hex string')
            sys.exit(1)
        configuration['api_id'] = api_id
        configuration['api_hash'] = api_hash.lower()
    else:
        print('No API credentials are built in; '
              'the app asks every user for their own API ID and hash on the first launch.')

    # A sideloaded build cannot use App Store purchases or the iCloud/Siri entitlements of Telegram's team.
    configuration['is_appstore_build'] = 'false'
    configuration['appstore_id'] = '0'
    configuration['premium_iap_product_id'] = ''
    configuration['enable_siri'] = False
    configuration['enable_icloud'] = False

    with open(sys.argv[1], 'w') as f:
        json.dump(configuration, f, indent=2)

    github_env = os.environ.get('GITHUB_ENV')
    if github_env:
        with open(github_env, 'a') as f:
            f.write('ASTRA_CONFIGURED={}\n'.format('true' if configured else 'false'))


if __name__ == '__main__':
    main()
