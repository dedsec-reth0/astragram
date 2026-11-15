import Foundation
import TelegramPresentationData
import TelegramCore

/// AyuGram's own interface strings (Russian and English; other languages fall back to English).
public struct AyuStrings {
    public let isRussian: Bool

    public init(_ strings: PresentationStrings) {
        let code = strings.baseLanguageCode.lowercased()
        self.isRussian = code.hasPrefix("ru") || code.hasPrefix("uk") || code.hasPrefix("be")
    }

    private func t(_ ru: String, _ en: String) -> String {
        return self.isRussian ? ru : en
    }

    public var title: String { t("AyuGram", "AyuGram") }

    // Ghost mode
    public var ghostHeader: String { t("РЕЖИМ ПРИЗРАКА", "GHOST MODE") }
    public var ghostMode: String { t("Режим призрака", "Ghost Mode") }
    public var ghostFooter: String { t("Режим призрака включает все переключатели ниже сразу. Telegram может показать вас «в сети», когда вы отправляете сообщение: сервер отмечает активность сам.", "Ghost Mode turns on every switch below at once. Telegram may still show you online when you send a message: the server records that activity itself.") }
    public var hideOnline: String { t("Не отправлять «в сети»", "Don't send online status") }
    public var hideRead: String { t("Не отправлять прочтение", "Don't send read receipts") }
    public var hideStories: String { t("Не отмечать просмотр историй", "Don't mark stories as viewed") }
    public var hideTyping: String { t("Не отправлять «печатает»", "Don't send typing status") }
    public var hideContents: String { t("Не отмечать прослушивание голосовых и кружков", "Don't mark voice and video messages as played") }
    public var markReadAfterSend: String { t("Прочитать при отправке ответа", "Mark as read when replying") }
    public var markReadAfterSendFooter: String { t("Когда вы отправляете сообщение в чат, его входящие сообщения отмечаются прочитанными у собеседника, даже если прочтение скрыто.", "When you send a message to a chat, its incoming messages are marked as read for the other side, even with read receipts hidden.") }

    // Anti-delete
    public var antiDeleteHeader: String { t("ИСТОРИЯ СООБЩЕНИЙ", "MESSAGE HISTORY") }
    public var saveDeleted: String { t("Сохранять удалённые сообщения", "Save deleted messages") }
    public var keepDeletedInChat: String { t("Оставлять удалённые в чате", "Keep deleted messages in chat") }
    public var saveInChannels: String { t("Сохранять и в каналах", "Also in channels") }
    public var saveEdits: String { t("Сохранять историю правок", "Save edit history") }
    public var keepSelfDestructing: String { t("Не сжигать одноразовые медиа", "Keep self-destructing media") }
    public var deletedMessages: String { t("Удалённые сообщения", "Deleted Messages") }
    public var antiDeleteFooter: String { t("Сохраняются сообщения, которые удалили другие участники или сервер. Ваши удаления с этого устройства работают как обычно (удаления с других ваших устройств приходят от сервера и тоже сохраняются). Одноразовые фото, видео и голосовые после просмотра остаются в чате и открываются снова (у отправителя они отмечаются просмотренными, как обычно). Данные хранятся только на этом устройстве, в локальной базе SQLite.", "Messages deleted by other people or by the server are saved. Your deletions made on this device work as usual (deletions from your other devices come from the server and are saved too). View-once and self-destructing photos, videos and voice messages stay in the chat after you open them (for the sender they look viewed as usual). The data stays on this device, in a local SQLite database.") }
    public var storageUsage: String { t("Размер базы", "Database size") }
    public var clearHistory: String { t("Очистить сохранённую историю", "Clear Saved History") }
    public var clearHistoryConfirm: String { t("Удалить все сохранённые удалённые сообщения и версии правок?", "Delete all saved deleted messages and edit versions?") }
    public var clearDeletedConfirm: String { t("Удалить эти сохранённые удалённые сообщения? Восстановить их будет нельзя.", "Delete these saved deleted messages? They cannot be restored.") }
    public var clearHistoryDone: String { t("Сохранённая история очищена", "Saved history cleared") }

    // Appearance
    public var appearanceHeader: String { t("ВНЕШНИЙ ВИД И ЧАТЫ", "APPEARANCE AND CHATS") }
    public var deletedMark: String { t("Метка удалённого", "Deleted mark") }
    public var editedMark: String { t("Метка изменённого", "Edited mark") }
    public var editedMarkPlaceholder: String { t("стандартная", "default") }
    public var showSeconds: String { t("Секунды во времени сообщений", "Seconds in message time") }
    public var showPeerId: String { t("Показывать ID в профиле", "Show ID in profiles") }
    public var hideSponsored: String { t("Скрыть рекламу в каналах", "Hide sponsored messages") }
    public var hideStoriesInList: String { t("Скрыть истории над чатами", "Hide stories above chats") }
    public var confirmSticker: String { t("Подтверждать отправку стикеров", "Confirm sending stickers") }
    public var confirmStickerQuestion: String { t("Отправить стикер?", "Send this sticker?") }
    public var confirmGifQuestion: String { t("Отправить GIF?", "Send this GIF?") }
    public var send: String { t("Отправить", "Send") }
    public var haptics: String { t("Тактильный отклик", "Haptic feedback") }
    public var appearanceFooter: String { t("Темы, цвета, шрифты, пузыри сообщений и иконки приложения настраиваются в разделе «Оформление».", "Themes, colors, fonts, message bubbles and app icons are in the Appearance section.") }
    public var openAppearance: String { t("Оформление и темы", "Appearance and Themes") }

    // Filters
    public var filtersHeader: String { t("ФИЛЬТРЫ СООБЩЕНИЙ", "MESSAGE FILTERS") }
    public var filters: String { t("Фильтры сообщений", "Message Filters") }
    public var filtersEnabled: String { t("Включить фильтры", "Enable filters") }
    public var addFilter: String { t("Добавить фильтр", "Add Filter") }
    public var filterPlaceholder: String { t("слово или /регулярное выражение/", "word or /regular expression/") }
    public var filtersFooter: String { t("Сообщения, содержащие слово из списка (без учёта регистра) или подходящие под регулярное выражение в косых чертах, скрываются в чатах. Нажмите на фильтр, чтобы удалить его.", "Messages containing a word from the list (case-insensitive) or matching a regular expression written between slashes are hidden in chats. Tap a filter to delete it.") }
    public var invalidRegex: String { t("Неверное регулярное выражение", "Invalid regular expression") }

    // Translator
    public var translatorHeader: String { t("ПЕРЕВОДЧИК", "TRANSLATOR") }
    public var translatorSettings: String { t("Язык и перевод", "Language and Translation") }
    public var translatorFooter: String { t("Встроенный переводчик Telegram: кнопка «Перевести» в меню сообщения и перевод целых чатов.", "Telegram's built-in translator: the Translate button in the message menu and whole-chat translation.") }

    // About
    public var aboutHeader: String { t("О ПРИЛОЖЕНИИ", "ABOUT") }
    public var resetSettings: String { t("Сбросить настройки AyuGram", "Reset AyuGram Settings") }
    public var resetDone: String { t("Настройки AyuGram сброшены", "AyuGram settings reset") }

    // Deleted messages screen
    public var noDeletedMessages: String { t("Здесь появятся сообщения, которые были удалены.", "Deleted messages will appear here.") }
    public var allChats: String { t("Все чаты", "All Chats") }
    public var copyText: String { t("Копировать текст", "Copy Text") }
    public var openInChat: String { t("Показать в чате", "Show in Chat") }
    public var removeFromHistory: String { t("Удалить из истории", "Remove from History") }
    public var clearChatHistory: String { t("Очистить", "Clear") }
    public var deletedAt: String { t("удалено", "deleted") }
    public var sentAt: String { t("отправлено", "sent") }
    public var you: String { t("Вы", "You") }

    // Edit history
    public var editHistory: String { t("История правок", "Edit History") }
    public var originalVersion: String { t("Исходная версия", "Original") }
    public func versionN(_ n: Int) -> String {
        return self.isRussian ? "Версия \(n)" : "Version \(n)"
    }
    public var currentVersion: String { t("Текущая версия", "Current version") }
    public var noEditHistory: String { t("Для этого сообщения нет сохранённых версий: правки сохраняются с момента установки AyuGram.", "No saved versions for this message: edits are saved since AyuGram was installed.") }

    public func mediaKind(_ kind: AyuSavedMediaKind) -> String {
        switch kind {
        case .photo: return t("Фото", "Photo")
        case .video: return t("Видео", "Video")
        case .voice: return t("Голосовое сообщение", "Voice message")
        case .roundVideo: return t("Видеосообщение", "Video message")
        case .sticker: return t("Стикер", "Sticker")
        case .gif: return t("GIF", "GIF")
        case .music: return t("Музыка", "Music")
        case .file: return t("Файл", "File")
        case .poll: return t("Опрос", "Poll")
        case .contact: return t("Контакт", "Contact")
        case .location: return t("Геопозиция", "Location")
        case .webpage: return t("Ссылка", "Link")
        case .service: return t("Служебное сообщение", "Service message")
        case .other: return t("Медиа", "Media")
        case .none: return ""
        }
    }

    // AyuGram features, second batch
    public var messageMenu: String { t("AyuGram", "AyuGram") }
    public var messageDetails: String { t("Детали сообщения", "Message Details") }
    public var repeatMessage: String { t("Повторить", "Repeat") }
    public var copyPlain: String { t("Копировать без форматирования", "Copy Without Formatting") }
    public var readUntil: String { t("Прочитать до этого места", "Read Until Here") }
    public var hideMessage: String { t("Скрыть сообщение", "Hide Message") }
    public var copied: String { t("Скопировано", "Copied") }
    public var readUntilDone: String { t("Отмечено прочитанным", "Marked as read") }
    public var hiddenDone: String { t("Сообщение скрыто на этом устройстве", "Message hidden on this device") }
    public var detailsMessageId: String { t("ID сообщения", "Message ID") }
    public var detailsChatId: String { t("ID чата", "Chat ID") }
    public var detailsAuthorId: String { t("ID автора", "Author ID") }
    public var detailsDate: String { t("Дата", "Date") }
    public var detailsEdited: String { t("Изменено", "Edited") }
    public var detailsViews: String { t("Просмотры", "Views") }
    public var detailsForwards: String { t("Пересылки", "Forwards") }
    public var detailsForwardedFrom: String { t("Переслано от", "Forwarded from") }
    public var detailsOriginalDate: String { t("Дата оригинала", "Original date") }
    public var detailsFile: String { t("Файл", "File") }
    public var detailsSize: String { t("Размер", "Size") }
    public var detailsPackId: String { t("ID набора", "Pack ID") }
    public var detailsPackOwner: String { t("ID автора набора", "Pack author ID") }
    public var detailsPack: String { t("Набор", "Pack") }
    public var detailsPhoto: String { t("Фото", "Photo") }
    public var ghostButtonHint: String { t("Кнопка 👻 в шапке экрана «Чаты» включает и выключает весь режим призрака.", "The 👻 button at the top of the Chats screen turns the whole Ghost Mode on and off.") }
    public var markReadAfterReaction: String { t("Прочитать при реакции и голосовании", "Mark as read when reacting or voting") }
    public var sendViaSchedule: String { t("Отправлять через отложку", "Send via schedule") }
    public var sendViaScheduleFooter: String { t("Сообщения отправляются как отложенные на несколько секунд вперёд, поэтому отправка не показывает вас «в сети». Работает, когда включено «Не отправлять «в сети»».", "Messages are sent as scheduled a few seconds ahead, so sending does not show you online. Works while \"Don't send online status\" is on.") }
    public var privacyHeader: String { t("ОГРАНИЧЕНИЯ И ПРИВАТНОСТЬ", "RESTRICTIONS AND PRIVACY") }
    public var removeCopyRestrictions: String { t("Снять запрет копирования", "Remove copy restrictions") }
    public var allowScreenshots: String { t("Разрешить скриншоты", "Allow screenshots") }
    public var streamerMode: String { t("Режим стримера", "Streamer mode") }
    public var privacyFooter: String { t("Снятие запрета позволяет копировать текст и сохранять медиа из защищённых чатов, а пересылка из них отправляет копию (медиа скачивается и загружается заново). Скриншоты секретных чатов и одноразовых медиа перестают блокироваться, собеседник не получает уведомления. Режим стримера скрывает окно приложения при записи экрана и трансляции.", "Removing restrictions lets you copy text and save media from protected chats, and forwarding from them sends a copy (media is downloaded and uploaded again). Screenshots of secret chats and self-destructing media are no longer blocked and the other side is not notified. Streamer mode hides the app window from screen recording and sharing.") }
    public var chatsHeader: String { t("ЧАТЫ", "CHATS") }
    public var hideBlocked: String { t("Скрывать сообщения заблокированных", "Hide messages of blocked users") }
    public var hideSimilarChannels: String { t("Скрывать похожие каналы", "Hide similar channels") }
    public var hideFolderCounters: String { t("Скрывать счётчики на папках", "Hide folder unread counters") }
    public var hideAllChatsFolder: String { t("Скрывать папку «Все чаты»", "Hide the \"All Chats\" folder") }
    public var increaseRecentStickers: String { t("До 100 недавних стикеров", "Up to 100 recent stickers") }
    public var showServiceTime: String { t("Время служебных сообщений", "Service message time") }
    public var simpleReplies: String { t("Простые ответы и цитаты", "Simple replies and quotes") }
    public var confirmMessageSend: String { t("Подтверждать отправку сообщений", "Confirm sending messages") }
    public var unhideMessages: String { t("Показать скрытые сообщения", "Show hidden messages") }
    public var plugins: String { t("Плагины", "Plugins") }
    public var unhideMessagesDone: String { t("Скрытые сообщения снова видны (откройте чат заново)", "Hidden messages are visible again (reopen the chat)") }
    public var pluginsFooter: String { t("Плагины на JavaScript меняют исходящие сообщения, реагируют на входящие и добавляют команды вида .команда. Устанавливайте только плагины, которым доверяете.", "JavaScript plugins change outgoing messages, react to incoming ones and add commands like .command. Install only plugins you trust.") }
    public var pluginsInstall: String { t("Установить из файла", "Install from File") }
    public var pluginsInstallFromClipboard: String { t("Установить из буфера обмена", "Install from Clipboard") }
    public var pluginsInstalled: String { t("УСТАНОВЛЕННЫЕ", "INSTALLED") }
    public var pluginsEmpty: String { t("Плагинов пока нет. Плагин — это файл .js с описанием в начале. Пример есть в документации AyuGram для iOS.", "No plugins yet. A plugin is a .js file with a header. See the AyuGram for iOS docs for an example.") }
    public var pluginsDelete: String { t("Удалить", "Delete") }
    public var pluginsInvalid: String { t("Не удалось загрузить плагин", "Could not load the plugin") }
    public var pluginsInstalledDone: String { t("Плагин установлен", "Plugin installed") }
    public var pluginsHelp: String { t("Как писать плагины", "Writing Plugins") }
    public var burnNow: String { t("Сжечь сейчас", "Burn Now") }
    public var burnDone: String { t("Медиа сожжено", "Media burned") }
    public var messageShot: String { t("Скриншот сообщения", "Message Shot") }
    public var registrationDate: String { t("Регистрация", "Registered") }
    public var localPremium: String { t("Локальный Premium", "Local Premium") }
    public var showRegistrationDate: String { t("Дата регистрации в профиле", "Registration date in profiles") }
    public var localPremiumFooter: String { t("Локальный Premium отображает ваш аккаунт как Premium только на этом устройстве: открываются функции интерфейса, но то, что проверяет сервер (большие файлы, премиум-стикеры для других), работать не будет.", "Local Premium shows your account as Premium on this device only: interface features unlock, but anything the server checks (large files, premium stickers for others) will not work.") }
    public var apiCredentials: String { t("API ID и Hash", "API ID and Hash") }
    public var viewHeader: String { t("ВИД СООБЩЕНИЙ", "MESSAGES") }
    public var wideMessages: String { t("Широкие сообщения", "Wide messages") }
    public var channelBadge: String { t("Значок 📢 у пишущих от имени канала", "📢 badge for posting as a channel") }
    public var checkForUpdates: String { t("Проверять обновления", "Check for updates") }
    public var checkUpdatesNow: String { t("Проверить обновления сейчас", "Check for Updates Now") }
    public var notificationsHeader: String { t("УВЕДОМЛЕНИЯ", "NOTIFICATIONS") }
    public var backgroundNotifications: String { t("Уведомления без push", "Notifications without push") }
    public var keepAliveInBackground: String { t("Держать соединение в фоне", "Stay connected in background") }
    public var backgroundNotificationsFooter: String { t("Push-уведомления Telegram не приходят в приложения, установленные через AltStore. «Держать соединение в фоне» не даёт iOS усыпить AyuGram (проигрывается тишина, музыке это не мешает), поэтому сообщения приходят и уведомляются сразу, но батарея расходуется быстрее. Без него AyuGram проверяет сообщения, только когда iOS сама его будит (раз в 15–60 минут или реже). Смахивание AyuGram из списка недавних приложений останавливает и то и другое.", "Telegram push notifications do not reach apps installed with AltStore. \"Stay connected in background\" keeps iOS from suspending AyuGram (it plays silence, music is not affected), so messages arrive and are notified at once, at the cost of battery. Without it AyuGram checks for messages only when iOS wakes it up (every 15–60 minutes or less often). Swiping AyuGram away from recent apps stops both.") }
    public var shortcutGhostOn: String { t("Включить режим призрака", "Turn On Ghost Mode") }
    public var shortcutGhostOff: String { t("Выключить режим призрака", "Turn Off Ghost Mode") }
    public var shortcutStateOn: String { t("Сейчас включён", "Now on") }
    public var shortcutStateOff: String { t("Сейчас выключен", "Now off") }
    public var shortcutDedsecOn: String { t("DEDSEC: тишина групп и каналов", "DEDSEC: Silence Groups & Channels") }
    public var shortcutDedsecOff: String { t("DEDSEC: вернуть звук групп и каналов", "DEDSEC: Unmute Groups & Channels") }
    public var shortcutDedsecSubtitleOn: String { t("🔕 Группы и каналы молчат", "🔕 Groups and channels are silent") }
    public var shortcutDedsecSubtitleOff: String { t("Одна кнопка для всех групп и каналов", "One switch for all groups and channels") }
    public var ghostToastOn: String { t("Режим призрака включён", "Ghost Mode is on") }
    public var ghostToastOff: String { t("Режим призрака выключен", "Ghost Mode is off") }
    public var dedsecToastOn: String { t("🔕 DEDSEC: группы и каналы без звука и уведомлений", "🔕 DEDSEC: groups and channels are silent") }
    public var dedsecToastOff: String { t("🔔 DEDSEC: уведомления групп и каналов включены", "🔔 DEDSEC: group and channel notifications are on") }
    public var dedsecHeader: String { t("DEDSEC", "DEDSEC") }
    public var dedsecSilence: String { t("Тишина групп и каналов", "Silence groups and channels") }
    public var dedsecFooter: String { t("Функция от автора (DEDSEC): выключает уведомления и звуки всех групп и каналов одной кнопкой, новые группы и каналы тоже будут молчать. Чтобы какой-то чат уведомлял, включите в его профиле уведомления: это исключение. Переключается и из меню иконки приложения (долгое нажатие на иконку).", "From the author (DEDSEC): one switch turns off notifications and sounds of all groups and channels, and new ones are silent too. To keep a chat notifying, turn its notifications on in its profile: that is an exception. Also available from the app icon menu (long press the icon).") }
    public var liquidGlassBeta: String { t("Liquid Glass+ (бета)", "Liquid Glass+ (beta)") }
    public var liquidGlassFooter: String { t("Бета-вид по концепту Liquid Glass: в профиле круглые стеклянные кнопки с подписью снизу, нижняя панель из трёх вкладок («Контакты», «Чаты», «Настройки»; звонки остаются в настройках). Обычный вид остаётся по умолчанию. Применяется после перезапуска приложения.", "A beta look after the Liquid Glass concept: round glass buttons with labels under them in profiles, a tab bar of three tabs (Contacts, Chats, Settings; calls stay in Settings). The regular look stays the default. Applied after the app restarts.") }
    public var themesHeader: String { t("ВИД (БЕТА)", "LOOK (BETA)") }
    public var listAdd: String { t("Добавить", "Add") }
    public var aiHeader: String { t("OPENAI-СОВМЕСТИМЫЙ API", "OPENAI-COMPATIBLE API") }
    public var aiKey: String { t("Ключ", "Key") }
    public var aiModel: String { t("Модель", "Model") }
    public var aiTest: String { t("Проверить подключение", "Test Connection") }
    public var aiFooter: String { t("Без ключа AI работает через бесплатный публичный сервис Pollinations: регистрация не нужна, но не чаще одного запроса в 45 секунд и только текст (расшифровка голосовых недоступна). Со своим ключом (OpenAI, OpenRouter, Groq, DeepSeek или свой сервер с OpenAI-совместимым API) ограничений нет. Текст отправляется в сервис только когда вы сами выбираете AI-действие. Ключ хранится только на этом устройстве.", "Without a key, AI uses the free public Pollinations service: no sign-up, but at most one request every 45 seconds and text only (no voice transcription). With your own key (OpenAI, OpenRouter, Groq, DeepSeek or your own OpenAI-compatible server) there are no such limits. Text is sent to the service only when you pick an AI action. The key stays on this device.") }
    public var bookmarks: String { t("Закладки", "Bookmarks") }
    public var bookmarksEmpty: String { t("Закладок пока нет. Долгое нажатие на сообщение → AyuGram → «В закладки».", "No bookmarks yet. Long press a message → AyuGram → Bookmark.") }
    public var bookmarksClear: String { t("Удалить все закладки", "Delete All Bookmarks") }
    public var bookmarksClearConfirm: String { t("Удалить все закладки? Сами сообщения останутся в чатах.", "Delete all bookmarks? The messages stay in their chats.") }
    public var toolsHeader: String { t("ИНСТРУМЕНТЫ", "TOOLS") }
    public var aiSettings: String { t("AI", "AI") }
    public var templates: String { t("Шаблоны сообщений", "Message Templates") }
    public var templatePlaceholder: String { t("имя = текст", "name = text") }
    public var templatesFooter: String { t("Шаблон пишется как «имя = текст» (\\n — перенос строки). Отправьте «;имя», и вместо этого уйдёт текст шаблона.", "Write a template as \"name = text\" (\\n is a line break). Send \";name\" and the template text is sent instead.") }
    public var keywordAlerts: String { t("Уведомления по словам", "Keyword Alerts") }
    public var keywordPlaceholder: String { t("слово или фраза", "word or phrase") }
    public var keywordAlertsFooter: String { t("Сообщения с этими словами уведомляют, даже если чат без звука (работает вместе с «Уведомления без push»).", "Messages with these words notify even when the chat is muted (works with Notifications without push).") }
    public var backupExport: String { t("Экспорт настроек AyuGram", "Export AyuGram Settings") }
    public var backupImport: String { t("Импорт настроек AyuGram", "Import AyuGram Settings") }
    public var backupDone: String { t("Настройки восстановлены", "Settings restored") }
    public var backupInvalid: String { t("Это не резервная копия AyuGram", "This is not an AyuGram backup") }
    public var mediaHeader: String { t("ФИЛЬТРЫ МЕДИА", "MEDIA FILTERS") }
    public var hideStickers: String { t("Скрывать стикеры других", "Hide stickers from others") }
    public var hideGifs: String { t("Скрывать GIF других", "Hide GIFs from others") }
    public var aiMenu: String { t("AI ✨", "AI ✨") }
    public var aiTranslate: String { t("Перевести", "Translate") }
    public var aiSummarize: String { t("Кратко пересказать", "Summarize") }
    public var aiExplain: String { t("Объяснить", "Explain") }
    public var aiReply: String { t("Предложить ответ", "Suggest a Reply") }
    public var aiImprove: String { t("Исправить и улучшить", "Fix and Improve") }
    public var aiFormal: String { t("Сделать официальнее", "Make It Formal") }
    public var aiFriendly: String { t("Сделать дружелюбнее", "Make It Friendly") }
    public var aiChatSummary: String { t("Пересказ чата (100 сообщений)", "Chat Summary (100 messages)") }
    public var aiActionPoints: String { t("Главное и задачи из чата", "Key Points and Tasks") }
    public var aiTranscribe: String { t("Расшифровать голосовое (AI)", "Transcribe Voice (AI)") }
    public var ocr: String { t("Распознать текст на фото", "Recognize Text") }
    public var bookmarkAdd: String { t("В закладки", "Bookmark") }
    public var bookmarkRemove: String { t("Убрать из закладок", "Remove Bookmark") }
    public var bookmarkAdded: String { t("Сообщение в закладках AyuGram", "Message bookmarked") }
    public var exportChat: String { t("Экспорт чата и статистика", "Export Chat and Statistics") }
    public var aiNotConfiguredShort: String { t("Сначала добавьте ключ в Настройки → AyuGram → AI", "First add a key in Settings → AyuGram → AI") }
    public var aiFree: String { t("бесплатный", "free") }
    public var onlineForExceptions: String { t("Онлайн для избранных", "Online for selected people") }
    public var onlineWhoSees: String { t("Кому виден мой онлайн", "Who Sees My Online Status") }
    public var onlineForExceptionsFooter: String { t("Список режима призрака: выбранные люди видят вас «в сети», остальные нет. Сервер Telegram сам решает, кому показывать статус, поэтому, пока список не пуст и включено «Не отправлять „в сети“», AyuGram ставит приватность «Последняя активность» в «Никто, кроме списка», а при выключении режима призрака возвращает прежний вариант (Все / Контакты / Никто, без старых исключений). Без Premium вы тоже не видите время захода тех, от кого скрыли своё.", "The list of Ghost Mode: the selected people see you online, others do not. The Telegram server decides who sees the status, so while the list is not empty and online status is hidden, AyuGram sets Last Seen privacy to Nobody except the list, and puts the previous option back (Everybody / Contacts / Nobody, without old exceptions) when Ghost Mode is turned off. Without Premium you also do not see the last seen time of people you hide yours from.") }
    public var ghostOnlineExceptions: String { t("Кто видит меня в сети", "Who Sees Me Online") }
    public var ghostOnlineNobody: String { t("никто", "nobody") }
}
