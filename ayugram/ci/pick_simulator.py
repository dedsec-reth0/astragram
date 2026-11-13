#!/usr/bin/env python3
"""Point the UI test runner in Telegram/BUILD at a simulator that exists on this machine.

usage: pick_simulator.py SOURCE_DIR
The runner is declared for one fixed device and iOS version; CI images ship other ones.
"""
import json
import re
import subprocess
import sys


def main():
    source_dir = sys.argv[1]
    data = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', '-j', 'runtimes']))
    runtimes = [r for r in data['runtimes'] if r.get('isAvailable') and r.get('platform', r.get('name', '')).startswith('iOS')]
    if not runtimes:
        print('no available iOS simulator runtime')
        sys.exit(1)
    runtime = max(runtimes, key=lambda r: [int(p) for p in r['version'].split('.')])
    names = [d['name'] for d in runtime.get('supportedDeviceTypes', []) if d['name'].startswith('iPhone')]
    preferred = [n for n in names if re.fullmatch(r'iPhone \d+( Pro)?', n)]
    device = (preferred or names)[-1]
    version = '.'.join(runtime['version'].split('.')[:2])
    print('simulator: {} iOS {}'.format(device, version))

    path = source_dir + '/Telegram/BUILD'
    with open(path) as f:
        build = f.read()
    patched, count = re.subn(r'(ios_test_runner\(\s*name = "[^"]*",\s*device_type = )"[^"]*"(,\s*os_version = )"[^"]*"',
                     r'\g<1>"{}"\g<2>"{}"'.format(device, version), build)
    if count == 0:
        print('no test runner declaration found in Telegram/BUILD')
        sys.exit(1)
    with open(path, 'w') as f:
        f.write(patched)


if __name__ == '__main__':
    main()
