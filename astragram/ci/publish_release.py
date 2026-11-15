#!/usr/bin/env python3
"""Publish a built IPA as a GitHub release and add it to the AltStore source.

usage: publish_release.py IPA VERSION BUILD_NUMBER
       publish_release.py --refresh-source [--notes BUILD_NUMBER FILE]
(GH_TOKEN and GITHUB_REPOSITORY in the environment)

The IPA has no API credentials in it (every user enters their own in the app), so it can be public.

* The release `v<VERSION>-<BUILD_NUMBER>` gets the IPA; it becomes the latest release, which the app checks for updates.
* The AltStore/SideStore source (source.json) lives as an asset of the pre-release `sidestore-source`, so its URL never
  changes: https://github.com/<repo>/releases/download/sidestore-source/source.json
  AltStore shows "Update" when the source lists a newer build than the installed one.
* What a build brings is written in astragram/WHATSNEW.md; the release and the source show it.
* The source lists every released build, newest first, so AltStore can offer any of them. The list is read from
  the releases themselves each time, so it cannot lose a build.
* `--refresh-source` writes the source again (after its look or texts change), and `--notes` puts the text of
  FILE on one of its versions.
"""
import datetime
import json
import os
import shutil
import subprocess
import sys
import re
import tempfile
import zipfile

SOURCE_TAG = 'sidestore-source'
SOURCE_IDENTIFIER = 'com.github.dedsec-reth0.ayugram'
BUNDLE_ID = 'ph.telegra.Telegraph'
MAX_NEWS = 5
TINT_COLOR = '#7C4DFF'
WHATSNEW_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'WHATSNEW.md')
# What older builds brought, by build number: the text AltStore shows for a build in the list of versions.
VERSION_NOTES_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'version_notes.json')

APP_SUBTITLE = 'Telegram с режимом призрака и удалёнными сообщениями'
APP_DESCRIPTION = '''Telegram для iPhone с режимом призрака и сохранением удалённых сообщений. Всё включается отдельно в Настройки → AstraGram.

РЕЖИМ ПРИЗРАКА
Не отправлять «в сети», прочтение и «печатает», не отмечать просмотр историй и прослушивание голосовых.

ИСТОРИЯ СООБЩЕНИЙ
Удалённые сообщения остаются в чате с меткой, у изменённых есть история правок, одноразовые медиа не сгорают.

ЧАТЫ
Фильтры по словам, закладки, шаблоны, уведомления по словам, без рекламы в каналах и историй над чатами.

AI И ПЛАГИНЫ
AI через любой OpenAI-совместимый API со своим ключом и плагины на JavaScript.

ВИД
Материал стекла, пружинящие нажатия, монохромное оформление, вкладки по выбору.

ПЕРВЫЙ ЗАПУСК
Введите свои API ID и API Hash с my.telegram.org: в сборке ключей нет.

Неофициальный клиент. Push-уведомления при закрытом приложении не приходят.'''
SOURCE_DESCRIPTION = '''Сборки AstraGram для iOS: Telegram с режимом призрака, сохранением удалённых сообщений и плагинами.

Каждая сборка выходит здесь сразу после GitHub Actions. В ней нет ключей Telegram API: при первом запуске введите свои с my.telegram.org.'''


def gh(*args, check=True):
    return subprocess.run(['gh'] + list(args), check=check, capture_output=True, text=True, encoding='utf-8', errors='replace')


def strip_extensions(source_path, target_path):
    """Copy the IPA without its app extensions (PlugIns, Watch).

    A free Apple ID may register 10 App IDs a week, and every extension takes one: the full IPA needs 7, so AltStore
    often fails with "no App IDs available". Without extensions the app needs one App ID, and signing is much faster.
    AltStore signs the app again anyway, so the stale code signature does not matter.
    """
    pattern = re.compile(r'^Payload/[^/]+\.app/(PlugIns|Watch)/')
    with zipfile.ZipFile(source_path) as source, zipfile.ZipFile(target_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as target:
        for info in source.infolist():
            if pattern.match(info.filename):
                continue
            target.writestr(info, source.read(info.filename), compress_type=info.compress_type, compresslevel=9)


def read_notes(path, fallback):
    """What the build brings: the text of WHATSNEW.md, or the commit title when there is none."""
    try:
        with open(path, encoding='utf-8') as f:
            text = f.read().strip()
    except OSError:
        text = ''
    return text or fallback


def load_source(repo, workdir):
    """The versions and the news of the published source, if there is one."""
    if gh('release', 'download', SOURCE_TAG, '--repo', repo, '--pattern', 'source.json', '--dir', workdir, check=False).returncode != 0:
        return [], []
    path = os.path.join(workdir, 'source.json')
    try:
        with open(path, encoding='utf-8') as f:
            source = json.load(f)
        versions = source['apps'][0]['versions']
        news = source.get('news') or []
    except (OSError, ValueError, KeyError, IndexError):
        versions, news = [], []
    os.remove(path)
    return versions, news


def release_versions(repo, known):
    """Every released build, newest first: what the releases hold, with the texts the source already has."""
    result = gh('api', 'repos/{}/releases?per_page=100'.format(repo), '--paginate', '--jq', '.[] | tojson')
    releases = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
    texts = {v.get('buildVersion'): v for v in known}
    try:
        with open(VERSION_NOTES_PATH, encoding='utf-8') as f:
            notes = json.load(f)
    except (OSError, ValueError):
        notes = {}
    versions = []
    for release in releases:
        match = re.match(r'^v(.+)-(\d+)$', release.get('tag_name') or '')
        if not match or release.get('draft'):
            continue
        version, build = match.group(1), match.group(2)
        ipas = [a for a in release.get('assets') or [] if a['name'].endswith('.ipa')]
        light = [a for a in ipas if not a['name'].endswith('-full.ipa')]
        if not light:
            continue
        asset = light[0]
        previous = texts.get(build) or {}
        description = notes.get(build) or previous.get('localizedDescription')
        if not description:
            # The first paragraph of the release text is what the build brought.
            description = (release.get('body') or '').replace('\r\n', '\n').split('\n\n')[0].strip()
            if len(ipas) == 1:
                description += '\n\nЭта сборка с расширениями приложения: ей нужно 7 App ID.'
        versions.append({
            'version': version,
            'buildVersion': build,
            'date': previous.get('date') or release.get('published_at'),
            'localizedDescription': description,
            'downloadURL': asset['browser_download_url'],
            'size': asset['size'],
            'minOSVersion': '15.0',
        })
    versions.sort(key=lambda v: int(v['buildVersion']), reverse=True)
    return versions


def write_source(repo, workdir, versions, news):
    raw = 'https://raw.githubusercontent.com/{}/master'.format(repo)
    source_url = 'https://github.com/{}/releases/download/{}/source.json'.format(repo, SOURCE_TAG)
    icon_url = raw + '/astragram/assets/icon.png'
    art_url = raw + '/astragram/assets/altstore'
    header_url = art_url + '/header.png'
    news_image_url = art_url + '/news.png'
    # The feature cards of the app page, 9:19.5 like an iPhone screenshot.
    screenshots = ['{}/card-{}.jpg'.format(art_url, n) for n in range(1, 6)]

    # The news shows the latest build.
    if versions:
        latest = versions[0]
        identifier = 'build-{}'.format(latest['buildVersion'])
        news = [item for item in news if item.get('identifier') not in (identifier, 'welcome')]
        # A caption is one sentence: the first line of what the build brought.
        caption = (latest.get('localizedDescription') or '').split(chr(10))[0].lstrip('• ').strip()
        news.insert(0, {
            'title': 'AstraGram {} ({})'.format(latest['version'], latest['buildVersion']),
            'identifier': identifier,
            'caption': caption,
            'date': latest['date'],
            'tintColor': '#4C1D95',
            'notify': False,
            'appID': BUNDLE_ID,
        })
        news = news[:MAX_NEWS - 1]
        for item in news:
            item.pop('imageURL', None)
            item['tintColor'] = '#4C1D95'
        # The oldest item: what the app is and what the first launch asks for.
        news.append({
            'title': 'Добро пожаловать в AstraGram',
            'identifier': 'welcome',
            'caption': 'При первом запуске введите свои API ID и API Hash с my.telegram.org.',
            'date': versions[-1]['date'],
            'tintColor': '#1E1B4B',
            'imageURL': news_image_url,
            'notify': False,
            'appID': BUNDLE_ID,
        })

    source = {
        'name': 'AstraGram для iOS',
        # The identifier a source was first published under; AltStore knows the source by it.
        'identifier': SOURCE_IDENTIFIER,
        'subtitle': 'Режим призрака, удалённые сообщения, плагины',
        'description': SOURCE_DESCRIPTION,
        'iconURL': icon_url,
        'headerURL': header_url,
        'website': 'https://github.com/{}'.format(repo),
        'sourceURL': source_url,
        'tintColor': TINT_COLOR,
        'featuredApps': [BUNDLE_ID],
        'apps': [{
            'name': 'AstraGram',
            'bundleIdentifier': BUNDLE_ID,
            'developerName': 'AstraGram для iOS',
            'subtitle': APP_SUBTITLE,
            'localizedDescription': APP_DESCRIPTION,
            'iconURL': icon_url,
            'tintColor': TINT_COLOR,
            'category': 'social',
            'screenshots': screenshots,
            'versions': versions,
            'appPermissions': {'entitlements': [], 'privacy': {}},
        }],
        'news': news,
    }
    path = os.path.join(workdir, 'source.json')
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(source, f, ensure_ascii=False, indent=2)
    gh('release', 'upload', SOURCE_TAG, path, '--repo', repo, '--clobber')
    gh('release', 'edit', SOURCE_TAG, '--repo', repo, '--title', 'Источник AltStore', '--notes',
       'Источник AstraGram для AltStore и SideStore. Добавьте этот адрес в **Browse → Sources → +**:\n\n```\n{}\n```\n\nФайл обновляется сам после каждой сборки.'.format(source_url), check=False)
    print('source updated:', source_url)


def refresh_source(arguments):
    repo = os.environ['GITHUB_REPOSITORY']
    workdir = tempfile.mkdtemp()
    known, news = load_source(repo, workdir)
    versions = release_versions(repo, known)
    if not versions:
        sys.exit('no released builds: nothing to refresh')
    if arguments[:1] == ['--notes']:
        build, notes = arguments[1], read_notes(arguments[2], '')
        matched = [v for v in versions if v.get('buildVersion') == build]
        if not matched or not notes:
            sys.exit('no version {} in the source, or no notes'.format(build))
        matched[0]['localizedDescription'] = notes
    write_source(repo, workdir, versions, news)


def main():
    if sys.argv[1:2] == ['--refresh-source']:
        refresh_source(sys.argv[2:])
        return
    ipa, version, build = sys.argv[1], sys.argv[2], sys.argv[3]
    repo = os.environ['GITHUB_REPOSITORY']
    tag = 'v{}-{}'.format(version, build)
    asset_name = 'AstraGram-{}-{}.ipa'.format(version, build)
    full_name = 'AstraGram-{}-{}-full.ipa'.format(version, build)
    download_url = 'https://github.com/{}/releases/download/{}/{}'.format(repo, tag, asset_name)
    source_url = 'https://github.com/{}/releases/download/{}/source.json'.format(repo, SOURCE_TAG)
    commit_title = subprocess.run(['git', 'log', '-1', '--pretty=%s'], capture_output=True, text=True).stdout.strip()
    whats_new = read_notes(WHATSNEW_PATH, commit_title)

    # The app's update alert shows the first line of the release text, so what is new comes first.
    notes = '''{whats_new}

## Установка

В AltStore: **Browse → Sources → +**, адрес источника:

```
{source_url}
```

Или скачайте файл ниже и откройте его в AltStore: **My Apps → +**.

| Файл | Для кого |
| --- | --- |
| `{asset_name}` | Бесплатный Apple ID: без расширений, нужен 1 App ID |
| `{full_name}` | Платный аккаунт разработчика: все расширения, нужно 7 App ID |

При первом запуске введите свои API ID и API Hash с [my.telegram.org](https://my.telegram.org).

<sub>Коммит: {commit_title}</sub>
'''.format(whats_new=whats_new, source_url=source_url, asset_name=asset_name, full_name=full_name, commit_title=commit_title)
    # The uploaded file keeps its own name (a `#label` only changes the label), so it is copied under the asset name.
    upload_dir = tempfile.mkdtemp()
    upload_path = os.path.join(upload_dir, asset_name)
    strip_extensions(ipa, upload_path)
    # The untouched build, with the share extension, widgets and the rest, for those with a paid developer account.
    full_path = os.path.join(upload_dir, full_name)
    shutil.copyfile(ipa, full_path)
    gh('release', 'create', tag, upload_path, full_path, '--repo', repo, '--title', 'AstraGram {} ({})'.format(version, build), '--notes', notes, '--latest')
    print('released', tag)

    # The current source, if there is one.
    if gh('release', 'view', SOURCE_TAG, '--repo', repo, check=False).returncode != 0:
        gh('release', 'create', SOURCE_TAG, '--repo', repo, '--title', 'Источник AltStore', '--prerelease', '--notes', 'AltStore / SideStore source: {}'.format(source_url))
    workdir = tempfile.mkdtemp()
    versions, news = load_source(repo, workdir)

    known = [v for v in versions if v.get('buildVersion') != build]
    known.insert(0, {
        'version': version,
        'buildVersion': build,
        'date': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        'localizedDescription': whats_new,
        'downloadURL': download_url,
        'size': os.path.getsize(upload_path),
        'minOSVersion': '15.0',
    })
    # Every released build, the new one included; if the releases cannot be read, what the source had.
    try:
        versions = release_versions(repo, known)
    except (subprocess.CalledProcessError, ValueError, KeyError):
        versions = []
    if not versions or versions[0]['buildVersion'] != build:
        versions = known
    write_source(repo, workdir, versions, news)


if __name__ == '__main__':
    main()
