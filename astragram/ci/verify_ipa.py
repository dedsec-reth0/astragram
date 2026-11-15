#!/usr/bin/env python3
"""Sanity-check a built IPA: a zip with Payload/<App>.app containing a 64-bit arm64 executable,
the AstraGram display name and the expected app extensions."""
import plistlib
import struct
import sys
import zipfile

EXPECTED_EXTENSIONS = ['Share', 'NotificationService', 'NotificationContent', 'Widget']


def main(path):
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        apps = sorted({n.split('/')[1] for n in names if n.startswith('Payload/') and n.count('/') >= 2 and n.split('/')[1].endswith('.app')})
        if len(apps) != 1:
            raise SystemExit('expected exactly one app in Payload, found {}'.format(apps))
        app = apps[0]
        info = plistlib.loads(z.read('Payload/{}/Info.plist'.format(app)))
        binary = z.read('Payload/{}/{}'.format(app, info['CFBundleExecutable']))
        magic = struct.unpack('<I', binary[:4])[0]
        if magic not in (0xfeedfacf, 0xbebafeca):
            raise SystemExit('main executable is not a 64-bit Mach-O (magic {:x})'.format(magic))
        plugins = sorted({n.split('/')[3] for n in names if n.startswith('Payload/{}/PlugIns/'.format(app)) and n.count('/') >= 4})
        missing = [e for e in EXPECTED_EXTENSIONS if not any(p.startswith(e) for p in plugins)]
        print('App:          ', app)
        print('Display name: ', info.get('CFBundleDisplayName'))
        print('Bundle id:    ', info.get('CFBundleIdentifier'))
        print('Version:      ', info.get('CFBundleShortVersionString'), '(' + str(info.get('CFBundleVersion')) + ')')
        print('Min iOS:      ', info.get('MinimumOSVersion'))
        print('Extensions:   ', ', '.join(plugins))
        print('Size:          {:.1f} MB'.format(sum(i.file_size for i in z.infolist()) / 1e6))
        if info.get('CFBundleDisplayName') != 'AstraGram':
            raise SystemExit('unexpected display name')
        if missing:
            raise SystemExit('missing extensions: {}'.format(missing))


if __name__ == '__main__':
    main(sys.argv[1])
