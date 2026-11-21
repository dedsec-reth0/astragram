# Бот огоньков AstraGram

Огонёк считает сам AstraGram на телефоне по сообщениям чата. Бот нужен только тем, у кого AstraGram нет: он показывает
им счёт, напоминает вечером написать и принимает восстановление пропущенного дня.

## Как устроено

- Сервер — [Cloudflare Workers](https://workers.cloudflare.com/) с базой D1. Бесплатного тарифа хватает с запасом
  (100 000 запросов в день); свой сервер держать не нужно, HTTPS из коробки.
- Боту приходят только числа: Telegram ID собеседника, счёт огонька, сколько сообщений каждый написал сегодня, можно ли
  восстановить вчерашний день и часовой пояс. Тексты сообщений к нему не попадают.
- Приложение подписывает запросы случайным токеном из Keychain; на сервере хранится только SHA-256 токена. Токен
  привязывается к аккаунту, когда владелец нажимает «Старт» в боте по ссылке из AstraGram.
- Webhook Telegram проверяется секретом, выведенным из токена бота. Токен бота хранится только в секретах GitHub и
  Cloudflare, в репозитории его нет.
- Данные, которые месяц никто не обновлял, удаляются сами. «Отключить бота огоньков» в AstraGram удаляет всё о владельце.

## Запуск (один раз)

1. В Telegram у [@BotFather](https://t.me/BotFather): `/newbot`, имя и username бота. Скопируйте токен.
2. Зарегистрируйтесь на [dash.cloudflare.com](https://dash.cloudflare.com/sign-up) (бесплатно). Откройте
   Workers & Pages один раз, чтобы Cloudflare выдал адрес `*.workers.dev`.
3. Там же: My Profile → API Tokens → Create Token → шаблон «Edit Cloudflare Workers», добавьте право
   Account → D1 → Edit. Скопируйте токен и Account ID (он справа на главной странице Workers & Pages).
4. В репозитории GitHub: Settings → Secrets and variables → Actions → New repository secret:
   `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `STREAK_BOT_TOKEN`.
5. Actions → Streak Bot → Run workflow. Или локально: `npx wrangler login`, `npx wrangler deploy`,
   `npx wrangler secret put BOT_TOKEN`, затем открыть `<адрес сервера>/setup` — сервер сам подключит бота.
   Username бота и адрес сервера прописаны в `AstraStreakBot` (`AstraStreakController.swift`).

Сейчас запущены бот @infoastragram_bot и сервер https://astragram-streak-bot.dedsec-reth0.workers.dev.

Обновления сервера выкладываются сами при каждом изменении этой папки в `master`.

## Огоньки на всех устройствах

Приложение с версии 2 (`"v": 2` в `/api/sync`) хранит здесь общий список огоньков аккаунта (таблица `streak_list`):
день начала каждого огонька или пометку, что его выключили. Каждое устройство отправляет, что на нём включили
(`starts`) и выключили (`stops`) с прошлой синхронизации, и получает в ответ весь список (`streaks`, `stopped`).
Старая копия огонька с устройства, которое ещё не узнало о выключении, его не возвращает. Числа за один и тот же день
с разных устройств сливаются по большему: устройство без загруженной старой переписки насчитывает меньше.

Проверка без Node, на встроенном в macOS JavaScriptCore и настоящем SQLite:

```
python3 astragram/streak-bot/test/run_sync_test.py
```
