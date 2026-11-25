import Foundation
import TelegramPresentationData
import TelegramCore

/// AstraGram's own interface strings (Russian and English; other languages fall back to English).
public struct AstraStrings {
    public let isRussian: Bool

    public init(_ strings: PresentationStrings) {
        let code = strings.baseLanguageCode.lowercased()
        self.isRussian = code.hasPrefix("ru") || code.hasPrefix("uk") || code.hasPrefix("be")
    }

    private func t(_ ru: String, _ en: String) -> String {
        return self.isRussian ? ru : en
    }

    public var title: String { t("AstraGram", "AstraGram") }

    // Ghost mode
    public var ghostHeader: String { t("РЕЖИМ ПРИЗРАКА", "GHOST MODE") }
    public var ghostMode: String { t("Режим призрака", "Ghost Mode") }
    public var ghostFooter: String { t("Включает все переключатели ниже. Быстро включить режим можно кнопкой с призраком над списком чатов.", "Turns on all the switches below. The ghost button above the chat list turns it on and off too.") }
    public var hideOnline: String { t("Не отправлять «в сети»", "Hide Online Status") }
    public var hideRead: String { t("Не отправлять прочтение", "Hide Read Receipts") }
    public var hideStories: String { t("Не отмечать просмотр историй", "Hide Story Views") }
    public var hideTyping: String { t("Не отправлять «печатает»", "Hide Typing") }
    public var hideContents: String { t("Не отмечать голосовые и кружки", "Don't Mark Voice as Played") }
    public var markReadAfterSend: String { t("Читать при ответе", "Read When Replying") }
    public var markReadAfterSendFooter: String { t("Чат отмечается прочитанным, когда вы в него пишете.", "A chat is marked as read when you write to it.") }

    // Anti-delete
    public var antiDeleteHeader: String { t("ИСТОРИЯ СООБЩЕНИЙ", "MESSAGE HISTORY") }
    public var saveDeleted: String { t("Сохранять удалённые сообщения", "Save Deleted Messages") }
    public var keepDeletedInChat: String { t("Показывать удалённые в чате", "Keep Deleted in Chat") }
    public var saveInChannels: String { t("Сохранять и в каналах", "Also in Channels") }
    public var saveEdits: String { t("Сохранять историю правок", "Save Edit History") }
    public var keepSelfDestructing: String { t("Не сжигать одноразовые медиа", "Keep View-Once Media") }
    public var deletedMessages: String { t("Удалённые сообщения", "Deleted Messages") }
    public var antiDeleteFooter: String { t("Удалённые собеседниками сообщения и одноразовые медиа остаются у вас. Хранятся только на этом устройстве.", "Messages others delete and view-once media stay with you. Stored only on this device.") }
    public var storageUsage: String { t("Размер базы", "Database Size") }
    public var clearHistory: String { t("Очистить сохранённую историю", "Clear Saved History") }
    public var clearHistoryConfirm: String { t("Удалить все сохранённые удалённые сообщения и версии правок?", "Delete all saved deleted messages and edit versions?") }
    public var clearDeletedConfirm: String { t("Удалить эти сохранённые удалённые сообщения? Восстановить их будет нельзя.", "Delete these saved deleted messages? They cannot be restored.") }
    public var clearHistoryDone: String { t("Сохранённая история очищена", "Saved history cleared") }

    // Appearance
    public var appearanceHeader: String { t("ИНТЕРФЕЙС", "INTERFACE") }
    public var deletedMark: String { t("Метка удалённого", "Deleted Mark") }
    public var editedMark: String { t("Метка изменённого", "Edited Mark") }
    public var editedMarkPlaceholder: String { t("стандартная", "default") }
    public var showSeconds: String { t("Секунды во времени сообщений", "Seconds in Message Time") }
    public var showPeerId: String { t("Показывать ID в профиле", "Show ID in Profiles") }
    public var hideSponsored: String { t("Скрыть рекламу в каналах", "Hide Sponsored Messages") }
    public var hideStoriesInList: String { t("Скрыть истории над чатами", "Hide Stories Above Chats") }
    public var confirmSticker: String { t("Подтверждать отправку стикеров", "Confirm Sending Stickers") }
    public var confirmStickerQuestion: String { t("Отправить стикер?", "Send this sticker?") }
    public var confirmGifQuestion: String { t("Отправить GIF?", "Send this GIF?") }
    public var send: String { t("Отправить", "Send") }
    public var haptics: String { t("Тактильный отклик", "Haptic Feedback") }
    public var appearanceFooter: String { t("Темы, шрифты и иконки — в разделе «Оформление» Telegram.", "Themes, fonts and icons are in Telegram's Appearance settings.") }
    public var openAppearance: String { t("Оформление и темы", "Appearance and Themes") }

    // Filters
    public var filtersHeader: String { t("ФИЛЬТРЫ СООБЩЕНИЙ", "MESSAGE FILTERS") }
    public var filters: String { t("Фильтры сообщений", "Message Filters") }
    public var filtersEnabled: String { t("Включить фильтры", "Enable filters") }
    public var addFilter: String { t("Добавить фильтр", "Add Filter") }
    public var filterPlaceholder: String { t("слово или /регулярное выражение/", "word or /regular expression/") }
    public var filtersFooter: String { t("Сообщения со словом из списка или подходящие под /регулярное выражение/ скрываются.", "Messages with a listed word or matching a /regular expression/ are hidden.") }
    public var invalidRegex: String { t("Неверное регулярное выражение", "Invalid regular expression") }

    // Translator
    public var translatorHeader: String { t("ПЕРЕВОДЧИК", "TRANSLATOR") }
    public var translatorSettings: String { t("Язык и перевод", "Language and Translation") }
    public var translatorFooter: String { t("Кнопка «Перевести» в меню сообщения и перевод чатов.", "The Translate button in the message menu and chat translation.") }

    // About
    public var aboutHeader: String { t("О ПРИЛОЖЕНИИ", "ABOUT") }
    public var resetSettings: String { t("Сбросить настройки AstraGram", "Reset AstraGram Settings") }
    public var resetConfirm: String { t("Все настройки AstraGram вернутся к стандартным. Ключ AI, чаты под Face ID и Face ID для настроек останутся.", "All AstraGram settings return to their defaults. The AI key, chats locked with Face ID and Face ID for these settings stay.") }
    public var resetDone: String { t("Настройки AstraGram сброшены", "AstraGram settings reset") }

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
    public var noEditHistory: String { t("Для этого сообщения нет сохранённых версий: правки сохраняются с момента установки AstraGram.", "No saved versions for this message: edits are saved since AstraGram was installed.") }

    public func mediaKind(_ kind: AstraSavedMediaKind) -> String {
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

    // AstraGram features, second batch
    public var messageMenu: String { t("AstraGram", "AstraGram") }
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
    public var ghostButtonHint: String { t("", "") }
    public var markReadAfterReaction: String { t("Читать при реакции", "Read When Reacting") }
    public var sendViaSchedule: String { t("Отправлять через отложку", "Send via Schedule") }
    public var sendViaScheduleFooter: String { t("Сообщения уходят как отложенные через 12 секунд — так отправка не показывает вас «в сети».", "Messages are sent as scheduled in 12 seconds, so sending doesn't show you online.") }
    public var privacyHeader: String { t("ОГРАНИЧЕНИЯ", "RESTRICTIONS") }
    public var removeCopyRestrictions: String { t("Снять запрет копирования", "Remove Copy Restrictions") }
    public var allowScreenshots: String { t("Разрешить скриншоты", "Allow Screenshots") }
    public var streamerMode: String { t("Режим стримера", "Streamer Mode") }
    public var privacyFooter: String { t("Позволяет копировать и сохранять из защищённых чатов и делать скриншоты без уведомления. Режим стримера скрывает приложение на записи экрана.", "Copy and save from protected chats and take screenshots without notice. Streamer Mode hides the app from screen recording.") }
    public var chatsHeader: String { t("ЧАТЫ", "CHATS") }
    public var hideBlocked: String { t("Скрывать сообщения заблокированных", "Hide Messages of Blocked Users") }
    public var hideSimilarChannels: String { t("Скрывать похожие каналы", "Hide Similar Channels") }
    public var hideFolderCounters: String { t("Скрывать счётчики на папках", "Hide Folder Unread Counters") }
    public var hideAllChatsFolder: String { t("Скрывать папку «Все чаты»", "Hide the \"All Chats\" Folder") }
    public var increaseRecentStickers: String { t("До 100 недавних стикеров", "Up to 100 Recent Stickers") }
    public var showServiceTime: String { t("Время служебных сообщений", "Service Message Time") }
    public var simpleReplies: String { t("Простые ответы и цитаты", "Simple Replies and Quotes") }
    public var confirmMessageSend: String { t("Подтверждать отправку сообщений", "Confirm Sending Messages") }
    public var unhideMessages: String { t("Показать скрытые сообщения", "Show Hidden Messages") }
    public var plugins: String { t("Плагины", "Plugins") }
    public var unhideMessagesDone: String { t("Скрытые сообщения снова видны (откройте чат заново)", "Hidden messages are visible again (reopen the chat)") }
    public var pluginsFooter: String { t("Плагины на JavaScript меняют сообщения и добавляют команды. Ставьте только те, которым доверяете.", "JavaScript plugins change messages and add commands. Install only ones you trust.") }
    public var pluginsInstall: String { t("Установить из файла", "Install from File") }
    public var pluginsInstallFromClipboard: String { t("Установить из буфера обмена", "Install from Clipboard") }
    public var pluginsInstalled: String { t("УСТАНОВЛЕННЫЕ", "INSTALLED") }
    public var pluginsEmpty: String { t("Плагинов пока нет. Плагин — это файл .js с описанием в начале. Пример есть в документации AstraGram для iOS.", "No plugins yet. A plugin is a .js file with a header. See the AstraGram for iOS docs for an example.") }
    public var pluginsDelete: String { t("Удалить", "Delete") }
    public var pluginsInvalid: String { t("Не удалось загрузить плагин", "Could not load the plugin") }
    public var pluginsNoSource: String { t("Буфер обмена пуст или iOS не дала его прочитать. Скопируйте код плагина и при запросе разрешите вставку.", "The clipboard is empty or iOS did not let AstraGram read it. Copy the plugin's code and allow pasting when asked.") }
    public var pluginsNoHeader: String { t("Это не плагин AstraGram: в первых строках нет «// @id …». Пример — в разделе «Как писать плагины».", "This is not an AstraGram plugin: its first lines have no \"// @id …\". See Writing Plugins for an example.") }
    public var pluginsInstalledDone: String { t("Плагин установлен", "Plugin installed") }
    public var pluginsHelp: String { t("Как писать плагины", "Writing Plugins") }
    public var burnNow: String { t("Сжечь сейчас", "Burn Now") }
    public var burnDone: String { t("Медиа сожжено", "Media burned") }
    public var messageShot: String { t("Скриншот сообщения", "Message Shot") }
    public var registrationDate: String { t("Регистрация", "Registered") }
    public var localPremium: String { t("Локальный Premium", "Local Premium") }
    public var showRegistrationDate: String { t("Дата регистрации", "Registration Date") }
    public var localPremiumFooter: String { t("Premium только на этом устройстве: открывает функции интерфейса, но не серверные возможности.", "Premium on this device only: unlocks interface features, not server ones.") }
    public var apiCredentials: String { t("API ID и Hash", "API ID and Hash") }
    public var viewHeader: String { t("ВИД СООБЩЕНИЙ", "MESSAGES") }
    public var wideMessages: String { t("Широкие сообщения", "Wide Messages") }
    public var channelBadge: String { t("Значок ◆ у постов от каналов", "◆ for Posts as Channel") }
    public var checkForUpdates: String { t("Проверять обновления", "Check for Updates") }
    public var checkUpdatesNow: String { t("Проверить обновления сейчас", "Check for Updates Now") }
    public var notificationsHeader: String { t("УВЕДОМЛЕНИЯ", "NOTIFICATIONS") }
    public var backgroundNotifications: String { t("Уведомления без push", "Notifications Without Push") }
    public var keepAliveInBackground: String { t("Держать соединение в фоне", "Stay Connected in Background") }
    public var backgroundNotificationsFooter: String { t("Push-уведомления не приходят в приложения из AltStore. «Держать соединение в фоне» доставляет сообщения сразу, но тратит больше заряда.", "Push notifications don't reach apps from AltStore. Staying connected delivers messages at once but uses more battery.") }
    public var shortcutGhostOn: String { t("Включить режим призрака", "Turn On Ghost Mode") }
    public var shortcutGhostOff: String { t("Выключить режим призрака", "Turn Off Ghost Mode") }
    public var shortcutStateOn: String { t("Сейчас включён", "Now on") }
    public var shortcutStateOff: String { t("Сейчас выключен", "Now off") }
    public var shortcutDedsecOn: String { t("DEDSEC: тишина групп и каналов", "DEDSEC: Silence Groups & Channels") }
    public var shortcutDedsecOff: String { t("DEDSEC: вернуть звук групп и каналов", "DEDSEC: Unmute Groups & Channels") }
    public var shortcutDedsecSubtitleOn: String { t("Группы и каналы молчат", "Groups and channels are silent") }
    public var shortcutDedsecSubtitleOff: String { t("Одна кнопка для всех групп и каналов", "One switch for all groups and channels") }
    public var ghostToastOn: String { t("Режим призрака включён", "Ghost Mode is on") }
    public var ghostToastOff: String { t("Режим призрака выключен", "Ghost Mode is off") }
    public var dedsecToastOn: String { t("DEDSEC: группы и каналы без звука и уведомлений", "DEDSEC: groups and channels are silent") }
    public var dedsecToastOff: String { t("DEDSEC: уведомления групп и каналов включены", "DEDSEC: group and channel notifications are on") }
    public var dedsecHeader: String { t("DEDSEC", "DEDSEC") }
    public var dedsecSilence: String { t("Тишина групп и каналов", "Silence Groups and Channels") }
    public var dedsecFooter: String { t("Выключает уведомления всех групп и каналов, включая новые. Исключения задаются в профиле чата.", "Mutes all groups and channels, new ones too. Set exceptions in a chat's profile.") }
    public var liquidGlassBeta: String { t("Liquid Glass+ (бета)", "Liquid Glass+ (beta)") }
    public var liquidGlassFooter: String { t("Бета-вид по концепту Liquid Glass: в профиле круглые стеклянные кнопки с подписью снизу, нижняя панель из трёх вкладок («Контакты», «Чаты», «Настройки»; звонки остаются в настройках). Обычный вид остаётся по умолчанию. Применяется после перезапуска приложения.", "A beta look after the Liquid Glass concept: round glass buttons with labels under them in profiles, a tab bar of three tabs (Contacts, Chats, Settings; calls stay in Settings). The regular look stays the default. Applied after the app restarts.") }
    public var themesHeader: String { t("ВИД (БЕТА)", "LOOK (BETA)") }
    public var listAdd: String { t("Добавить", "Add") }
    public var aiHeader: String { t("OPENAI-СОВМЕСТИМЫЙ API", "OPENAI-COMPATIBLE API") }
    public var aiKey: String { t("Ключ", "Key") }
    public var aiModel: String { t("Модель", "Model") }
    public var aiTest: String { t("Проверить подключение", "Test Connection") }
    public var aiFooter: String { t("Без ключа работает бесплатный сервис Pollinations (1 запрос в 45 секунд). Со своим ключом ограничений нет. Текст уходит в сервис только по вашему действию.", "Without a key, the free Pollinations service is used (1 request per 45 s). With your own key there are no limits. Text is sent only when you choose an AI action.") }
    public var bookmarks: String { t("Закладки", "Bookmarks") }
    public var bookmarksEmpty: String { t("Закладок пока нет. Долгое нажатие на сообщение → AstraGram → «В закладки».", "No bookmarks yet. Long press a message → AstraGram → Bookmark.") }
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
    public var backupExport: String { t("Экспорт настроек AstraGram", "Export AstraGram Settings") }
    public var backupImport: String { t("Импорт настроек AstraGram", "Import AstraGram Settings") }
    public var backupDone: String { t("Настройки восстановлены", "Settings restored") }
    public var backupInvalid: String { t("Это не резервная копия AstraGram", "This is not an AstraGram backup") }
    public var mediaHeader: String { t("ФИЛЬТРЫ МЕДИА", "MEDIA FILTERS") }
    public var hideStickers: String { t("Скрывать стикеры других", "Hide Stickers from Others") }
    public var hideGifs: String { t("Скрывать GIF других", "Hide GIFs from Others") }
    public var aiMenu: String { t("AI", "AI") }
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
    public var bookmarkAdded: String { t("Сообщение в закладках AstraGram", "Message bookmarked") }
    public var exportChat: String { t("Экспорт чата и статистика", "Export Chat and Statistics") }
    public var aiNotConfiguredShort: String { t("Сначала добавьте ключ в Настройки → AstraGram → AI", "First add a key in Settings → AstraGram → AI") }
    public var aiFree: String { t("Бесплатно", "Free") }
    public var lookHeader: String { t("ВИД", "LOOK") }
    public var roundProfileButtons: String { t("Круглые кнопки в профиле", "Round Profile Buttons") }
    public var profileMusicCapsule: String { t("Музыка капсулой в профиле", "Profile Music as a Capsule") }
    public var contactsTab: String { t("Вкладка «Контакты»", "Contacts Tab") }
    public var callsTab: String { t("Вкладка «Звонки»", "Calls Tab") }
    public var monochrome: String { t("Монохромное оформление", "Monochrome Look") }
    public var lookFooter: String { t("Монохром оставляет только чёрный, белый и серые. Значок AstraGram виден у тех, у кого он тоже включён. Часть изменений применяется после перезапуска.", "Monochrome keeps only black, white and grays. The AstraGram badge is seen by people who have it on too. Some changes apply after a restart.") }
    public var restartApp: String { t("Перезапустить AstraGram", "Restart AstraGram") }
    public var restartFooter: String { t("AstraGram закроется и пришлёт уведомление, чтобы открыться снова.", "AstraGram closes and sends a notification to reopen it.") }
    public var restartNotificationTitle: String { t("AstraGram закрыт", "AstraGram is closed") }
    public var restartNotificationText: String { t("Нажмите, чтобы открыть снова.", "Tap to open it again.") }
    public var glassMaterial: String { t("Материал стекла", "Glass Material") }
    public var glassMaterialStandard: String { t("Стандартный", "Standard") }
    public var glassMaterialClear: String { t("Прозрачный", "Clear") }
    public var glassMaterialMatte: String { t("Матовый", "Matte") }
    public var springPresses: String { t("Пружинящие нажатия", "Springy Presses") }
    public var showAstraGiftRibbon: String { t("Надпись AstraGram на подарках", "AstraGram Label on Gifts") }
    public var monochromePlainBackground: String { t("Однотонный фон чатов", "Plain Chat Background") }
    public var astraBadge: String { t("Значок AstraGram у имени", "AstraGram Badge by My Name") }
    public var streaks: String { t("🔥 Огоньки", "🔥 Streaks") }
    public var astraBadgeClear: String { t("Убрать метку из имени", "Remove Mark from Name") }
    public var astraBadgeCleared: String { t("Метка AstraGram убрана из имени, значок выключен", "The AstraGram mark is removed from your name and the badge is off") }
    public var astraBadgeNothing: String { t("В имени нет метки AstraGram, значок выключен", "Your name has no AstraGram mark; the badge is off") }
    public var securityHeader: String { t("БЕЗОПАСНОСТЬ", "SECURITY") }
    public var securityCheck: String { t("Проверка безопасности", "Security Check") }
    public var lockedChats: String { t("Чаты под Face ID", "Chats Locked with Face ID") }
    public var lockedChatsNone: String { t("Нет", "None") }
    public var lockedChatsReason: String { t("Изменить список защищённых чатов", "Change the list of locked chats") }
    public var biometricForAstraGram: String { t("Face ID для настроек AstraGram", "Face ID for AstraGram Settings") }
    public var hideInAppSwitcher: String { t("Скрывать в переключателе", "Hide in App Switcher") }
    public var blockThirdPartyKeyboards: String { t("Запретить сторонние клавиатуры", "Block Third-Party Keyboards") }
    public var warnSuspiciousLinks: String { t("Предупреждать о ссылках", "Warn About Links") }
    public var stripLinkTrackers: String { t("Убирать трекеры из ссылок", "Remove Trackers from Links") }
    public var clipboardExpire: String { t("Очищать буфер через минуту", "Clear Clipboard in a Minute") }
    public var clipboardLocalOnly: String { t("Буфер только на этом устройстве", "Local-Only Clipboard") }
    public var telegramPrivacy: String { t("Конфиденциальность Telegram", "Telegram Privacy") }
    public var securityFooter: String { t("Чаты под Face ID скрывают текст в списке. Сторонние клавиатуры видят всё, что вы набираете.", "Chats locked with Face ID hide their text in the chat list. Third-party keyboards see everything you type.") }
    public var pluginInstallTitle: String { t("Установить плагин?", "Install the Plugin?") }
    public var pluginInstallWarning: String { t("Плагин — это программа: она видит ваши сообщения и может менять то, что вы отправляете. Устанавливайте плагины только из источников, которым доверяете.", "A plugin is a program: it sees your messages and can change what you send. Install plugins only from sources you trust.") }
    public var pluginInstallConfirm: String { t("Установить", "Install") }

    // Pages of the AstraGram settings (the main page lists them, Telegram-settings style).
    public var pageGhost: String { t("Режим призрака", "Ghost Mode") }
    public var pageHistory: String { t("Удалённые и правки", "Deleted and Edited") }
    public var pagePrivacy: String { t("Конфиденциальность", "Privacy") }
    public var pageSecurity: String { t("Безопасность", "Security") }
    public var pageAppearance: String { t("Оформление", "Appearance") }
    public var pageChats: String { t("Чаты и медиа", "Chats and Media") }
    public var pageNotifications: String { t("Уведомления", "Notifications") }
    public var pageStreaks: String { t("Огоньки", "Streaks") }
    public var pageGiftShop: String { t("Магазин подарков", "Gift Shop") }
    public var pageFeedback: String { t("Ошибки и идеи", "Bugs and Ideas") }
    public var pageDonate: String { t("Поддержать AstraGram", "Support AstraGram") }
    public var pageTools: String { t("AI и инструменты", "AI and Tools") }
    public var pageAbout: String { t("Об AstraGram", "About AstraGram") }
    public var valueOn: String { t("Вкл.", "On") }
    public var valueOff: String { t("Выкл.", "Off") }
    public var valuePartial: String { t("Частично", "Partly") }
    public var rootFooter: String { t("Настройки AstraGram действуют для всех аккаунтов на этом устройстве.", "AstraGram settings apply to all accounts on this device.") }
}
