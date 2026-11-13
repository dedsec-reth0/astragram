#!/usr/bin/env python3
"""Publish a built IPA as a GitHub release and add it to the SideStore source.

usage: publish_release.py IPA VERSION BUILD_NUMBER   (GH_TOKEN and GITHUB_REPOSITORY in the environment)

The IPA has no API credentials in it (every user enters their own in the app), so it can be public.

* The release `v<VERSION>-<BUILD_NUMBER>` gets the IPA; it becomes the latest release, which the app checks for updates.
* The SideStore/AltStore source (source.json) lives as an asset of the pre-release `sidestore-source`, so its URL never
  changes: https://github.com/<repo>/releases/download/sidestore-source/source.json
  SideStore shows "Update" when the source lists a newer build than the installed one.
"""
import datetime
import json
import os
import subprocess
import sys
import tempfile

SOURCE_TAG = 'sidestore-source'
BUNDLE_ID = 'ph.telegra.Telegraph'
MAX_VERSIONS = 10


def gh(*args, check=True):
    return subprocess.run(['gh'] + list(args), check=check, capture_output=True, text=True)


def main():
    ipa, version, build = sys.argv[1], sys.argv[2], sys.argv[3]
    repo = os.environ['GITHUB_REPOSITORY']
    tag = 'v{}-{}'.format(version, build)
    asset_name = 'AyuGram-{}-{}.ipa'.format(version, build)
    download_url = 'https://github.com/{}/releases/download/{}/{}'.format(repo, tag, asset_name)
    source_url = 'https://github.com/{}/releases/download/{}/source.json'.format(repo, SOURCE_TAG)
    commit_title = subprocess.run(['git', 'log', '-1', '--pretty=%s'], capture_output=True, text=True).stdout.strip()

    notes = '{}\n\nУстановка: SideStore → Sources → + → {}\n\nПри первом запуске введите свои API ID и API Hash с my.telegram.org.'.format(commit_title, source_url)
    gh('release', 'create', tag, '{}#{}'.format(ipa, asset_name), '--repo', repo, '--title', 'AyuGram {} ({})'.format(version, build), '--notes', notes, '--latest')
    print('released', tag)

    # The current source, if there is one.
    if gh('release', 'view', SOURCE_TAG, '--repo', repo, check=False).returncode != 0:
        gh('release', 'create', SOURCE_TAG, '--repo', repo, '--title', 'SideStore source', '--prerelease', '--notes', 'SideStore / AltStore source: {}'.format(source_url))
    workdir = tempfile.mkdtemp()
    versions = []
    if gh('release', 'download', SOURCE_TAG, '--repo', repo, '--pattern', 'source.json', '--dir', workdir, check=False).returncode == 0:
        try:
            with open(os.path.join(workdir, 'source.json')) as f:
                versions = json.load(f)['apps'][0]['versions']
        except (OSError, ValueError, KeyError, IndexError):
            versions = []
        os.remove(os.path.join(workdir, 'source.json'))

    versions = [v for v in versions if v.get('buildVersion') != build]
    versions.insert(0, {
        'version': version,
        'buildVersion': build,
        'date': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        'localizedDescription': commit_title,
        'downloadURL': download_url,
        'size': os.path.getsize(ipa),
        'minOSVersion': '15.0',
    })
    versions = versions[:MAX_VERSIONS]

    source = {
        'name': 'AyuGram for iOS',
        'identifier': 'com.github.{}'.format(repo.replace('/', '.').lower()),
        'subtitle': 'AyuGram: ghost mode, anti-delete, plugins',
        'sourceURL': source_url,
        'website': 'https://github.com/{}'.format(repo),
        'apps': [{
            'name': 'AyuGram',
            'bundleIdentifier': BUNDLE_ID,
            'developerName': 'AyuGram for iOS',
            'subtitle': 'Telegram с режимом призрака и сохранением удалённых сообщений',
            'localizedDescription': 'Telegram для iOS с функциями AyuGram: режим призрака, сохранение удалённых и изменённых сообщений, одноразовые медиа, фильтры, плагины. При первом запуске введите свои API ID и API Hash с my.telegram.org.',
            'iconURL': 'https://raw.githubusercontent.com/{}/master/Telegram/Telegram-iOS/AppIcons.xcassets/BlueIcon.appiconset/Icon1@180x180.png'.format(repo),
            'tintColor': '#2AABEE',
            'category': 'social',
            'versions': versions,
            'appPermissions': {'entitlements': [], 'privacy': {}},
        }],
        'news': [],
    }
    path = os.path.join(workdir, 'source.json')
    with open(path, 'w') as f:
        json.dump(source, f, ensure_ascii=False, indent=2)
    gh('release', 'upload', SOURCE_TAG, path, '--repo', repo, '--clobber')
    print('source updated:', source_url)


if __name__ == '__main__':
    main()
