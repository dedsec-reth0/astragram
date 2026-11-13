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
    public var hideContents: String { t("Не отмечать прослушивание голосовых", "Don't mark voice messages as played") }
    public var markReadAfterSend: String { t("Прочитать при отправке ответа", "Mark as read when replying") }
    public var markReadAfterSendFooter: String { t("Когда вы отправляете сообщение в чат, его входящие сообщения отмечаются прочитанными у собеседника, даже если прочтение скрыто.", "When you send a message to a chat, its incoming messages are marked as read for the other side, even with read receipts hidden.") }

    // Anti-delete
    public var antiDeleteHeader: String { t("ИСТОРИЯ СООБЩЕНИЙ", "MESSAGE HISTORY") }
    public var saveDeleted: String { t("Сохранять удалённые сообщения", "Save deleted messages") }
    public var keepDeletedInChat: String { t("Оставлять удалённые в чате", "Keep deleted messages in chat") }
    public var saveInChannels: String { t("Сохранять и в каналах", "Also in channels") }
    public var saveEdits: String { t("Сохранять историю правок", "Save edit history") }
    public var deletedMessages: String { t("Удалённые сообщения", "Deleted Messages") }
    public var antiDeleteFooter: String { t("Сохраняются сообщения, которые удалили другие участники или сервер. Ваши собственные удаления работают как обычно. Данные хранятся только на этом устройстве, в локальной базе SQLite.", "Messages deleted by other people or by the server are saved. Your own deletions work as usual. The data stays on this device, in a local SQLite database.") }
    public var storageUsage: String { t("Размер базы", "Database size") }
    public var clearHistory: String { t("Очистить сохранённую историю", "Clear Saved History") }
    public var clearHistoryConfirm: String { t("Удалить все сохранённые удалённые сообщения и версии правок?", "Delete all saved deleted messages and edit versions?") }
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
}
