#!/usr/bin/env python3
"""Extend the expiration date of the fake-codesigning provisioning profiles.

The profiles in build-system/fake-codesigning/profiles are signed with the self-signed certificate in
build-system/fake-codesigning/certs and expire (the ones in the repository expired on 2026-10-30), which makes
rules_apple refuse to build. This script decodes each profile, moves ExpirationDate into the future and signs it
again with the same self-signed certificate, the way build-system/Make/GenerateProfiles.py signs them.

usage: refresh_profiles.py <repository root>
"""
import os
import subprocess
import sys
import tempfile


def run(arguments, check=True):
    result = subprocess.run(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if check and result.returncode != 0:
        raise SystemExit('{} failed: {}{}'.format(' '.join(arguments), result.stdout, result.stderr))
    return result


def main(root):
    sys.path.insert(0, os.path.join(root, 'build-system', 'Make'))
    import GenerateProfiles

    codesigning = os.path.join(root, 'build-system', 'fake-codesigning')
    p12 = os.path.join(codesigning, 'certs', 'SelfSigned.p12')
    profiles = os.path.join(codesigning, 'profiles')

    identity = GenerateProfiles.get_signing_identity_from_p12(p12, '')
    if not identity:
        raise SystemExit('could not read the signing identity of {}'.format(p12))
    print('Signing identity:', identity)

    keychain = GenerateProfiles.setup_temp_keychain(p12, '')
    try:
        for name in sorted(os.listdir(profiles)):
            if not name.endswith('.mobileprovision'):
                continue
            path = os.path.join(profiles, name)
            plist = tempfile.mktemp(suffix='.plist')
            run(['security', 'cms', '-D', '-i', path, '-o', plist])
            run(['plutil', '-replace', 'ExpirationDate', '-date', '2030-01-01T00:00:00Z', plist])
            run(['plutil', '-remove', 'DER-Encoded-Profile', plist], check=False)
            run(['security', 'cms', '-S', '-k', keychain, '-N', identity, '-i', plist, '-o', path])
            os.unlink(plist)
            check = run(['security', 'cms', '-D', '-i', path])
            if '2030-01-01' not in check.stdout:
                raise SystemExit('{} was not updated'.format(name))
            print('Refreshed', name)
    finally:
        GenerateProfiles.cleanup_temp_keychain(keychain)


if __name__ == '__main__':
    main(sys.argv[1])
