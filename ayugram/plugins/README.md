# Плагины AyuGram для iOS

Плагин — это файл `.js`. Он выполняется встроенным в iOS движком JavaScriptCore: подписанное через SideStore приложение не может загружать нативный код, поэтому плагины пишутся на JavaScript (Python-плагины Android-версии здесь не работают).

Установка: **Настройки → AyuGram → Плагины → «Установить из файла»** (или скопируйте код плагина и нажмите «Установить из буфера обмена»).

## Заголовок

Первые строки файла описывают плагин:

```js
// @id          reverse        (обязательно: латиница, цифры, . _ -)
// @name        Reverse
// @version     1.0
// @author      you
// @description Переворачивает текст командой .rev
```

## Что может плагин

```js
// Команда: сообщение ".rev привет" отправится как "тевирп".
// Вернуть строку — отправить её вместо команды, вернуть null — ничего не отправлять.
plugin.commands.rev = function (args, chat) {
    return args.split("").reverse().join("")
}

// Любое исходящее сообщение: вернуть новый текст, тот же текст, или null (не отправлять).
plugin.onOutgoing = function (text, chat) {
    return text
}

// Входящее сообщение в открытом чате: true — скрыть его.
plugin.shouldHide = function (message) {
    return message.text.indexOf("казино") >= 0
}
```

Объекты: `chat.id`; `message.id`, `message.text`, `message.chatId`, `message.authorId` (ID в формате Bot API).

API: `ayu.log(text)`, `ayu.version`, `ayu.storage.get(key)`, `ayu.storage.set(key, value)` (хранилище у каждого плагина своё).

Примеры: [`examples/`](examples/).
