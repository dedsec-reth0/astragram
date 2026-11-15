# AstraGram для iOS: сборка и публикация

AstraGram здесь — это Telegram для iOS (исходники Telegram-iOS) с добавленными функциями. Как поставить
готовую сборку, написано в [README](../README.md#установка); этот файл о том, как сборка получается.

## Как устроена сборка

Windows не умеет собирать iOS-приложения, поэтому сборка идёт на macOS-раннере GitHub Actions (образ `xcode-27`,
Xcode 27.1). Полная сборка Telegram занимает несколько часов, повторная с кэшем — около часа. Если одно задание не
укладывается в лимит GitHub (6 часов), workflow сохраняет кэш и сам запускает следующее задание, которое продолжает
с того же места.

IPA собирается без подписи Apple, с тестовой подписью из `build-system/fake-codesigning`. AltStore переподписывает
его вашим Apple ID при установке.

## Запуск

Каждый push в ветку `master` запускает workflow [Build AstraGram](../.github/workflows/build.yml). Коммит с `[skip ci]`
в сообщении сборку не запускает.

```powershell
gh run list --repo dedsec-reth0/astragram --limit 3
gh run watch --repo dedsec-reth0/astragram
```

## Что публикуется

В IPA нет ключей Telegram API: каждый вводит свои при первом запуске. Поэтому сборка публикуется открыто.

После удачной сборки [publish_release.py](ci/publish_release.py):

1. создаёт релиз `v<версия>-<сборка>` с двумя файлами:
   - `AstraGram-<версия>-<сборка>.ipa` — без расширений приложения, нужен 1 App ID (бесплатный Apple ID);
   - `AstraGram-<версия>-<сборка>-full.ipa` — со всеми расширениями, нужно 7 App ID;
2. обновляет источник AltStore, адрес которого не меняется:

   ```
   https://github.com/dedsec-reth0/astragram/releases/download/sidestore-source/source.json
   ```

Описание сборки для релиза и AltStore берётся из [WHATSNEW.md](WHATSNEW.md): его правят вместе с изменениями.

Обновить оформление источника без новой сборки:

```powershell
$env:GITHUB_REPOSITORY = "dedsec-reth0/astragram"
python astragram/ci/publish_release.py --refresh-source
```

## Ограничения установки через AltStore

- Бесплатный Apple ID подписывает на 7 дней: раз в неделю нажимайте **Refresh All**.
- У бесплатного Apple ID 10 App ID на 7 дней, поэтому по умолчанию ставится IPA без расширений (нет виджета,
  «Поделиться» и расширений уведомлений).
- Серверы Telegram отправляют push только приложениям, чей APNs-сертификат им известен; у переподписанной сборки
  такого нет, поэтому уведомления при закрытом приложении не приходят.

## Где настройки AstraGram

**Настройки → AstraGram.** Историю правок сообщения открывает долгое нажатие на отредактированное сообщение →
**История правок**.
