import Foundation
import JavaScriptCore
import Postbox
import SwiftSignalKit
import TelegramCore

/// An installed AyuGram plugin.
public struct AyuPluginInfo: Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let author: String
    public let description: String
    public let isEnabled: Bool
    /// The error of the last load, if the plugin failed to load.
    public let error: String?
}

/// Runs AyuGram plugins: JavaScript files executed with JavaScriptCore (sideloaded apps cannot load native code).
///
/// A plugin is a `.js` file. Its header comments describe it:
///
///     // @id      reverse
///     // @name    Reverse
///     // @version 1.0
///     // @author  you
///     // @description Reverses messages sent with .rev
///
/// and its code fills the `plugin` object:
///
///     plugin.commands.rev = function (args, chat) { return args.split("").reverse().join("") }
///     plugin.onOutgoing = function (text, chat) { return text }          // the text to send (null: send nothing)
///     plugin.shouldHide = function (message) { return false }            // hide an incoming message
///
/// `chat` and `message` are plain objects (`chat.id`; `message.text`, `message.chatId`, `message.authorId`,
/// `message.id`). Plugins can call `ayu.log(text)`, `ayu.storage.get(key)` / `ayu.storage.set(key, value)` (kept per
/// plugin) and read `ayu.version`.
public final class AyuPluginManager {
    public static let shared = AyuPluginManager()

    private final class LoadedPlugin {
        let id: String
        let context: JSContext
        let plugin: JSValue

        init(id: String, context: JSContext, plugin: JSValue) {
            self.id = id
            self.context = context
            self.plugin = plugin
        }
    }

    private let lock = NSRecursiveLock()
    private var loaded: [LoadedPlugin] = []
    private var infos: [AyuPluginInfo] = []
    private let infosPromise = ValuePromise<[AyuPluginInfo]>([], ignoreRepeated: true)
    private var hideCache: [String: Bool] = [:]

    private static let enabledKey = "ayugram.plugins.enabled.v1"

    private var directory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("ayugram-plugins", isDirectory: true)
    }

    private var enabledIds: Set<String> {
        get {
            return Set(UserDefaults.standard.stringArray(forKey: AyuPluginManager.enabledKey) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: AyuPluginManager.enabledKey)
        }
    }

    public var plugins: Signal<[AyuPluginInfo], NoError> {
        return self.infosPromise.get()
    }

    public var enabledCount: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.infos.filter { $0.isEnabled && $0.error == nil }.count
    }

    private init() {
    }

    /// Loads the installed plugins and connects them to TelegramCore. Called once at app launch.
    public func start() {
        self.reload()
        AyuPluginHooks.setOutgoingHook({ [weak self] text, peerId in
            return self?.handleOutgoing(text: text, peerId: peerId)
        })
        AyuPluginHooks.setHideHook({ [weak self] message in
            return self?.shouldHide(message) ?? false
        })
    }

    // MARK: Management

    /// Installs (or replaces) a plugin from its source. Returns the plugin id, or nil when the source has no `@id`.
    @discardableResult
    public func install(source: String) -> String? {
        let header = AyuPluginManager.parseHeader(source)
        guard let id = header["id"], !id.isEmpty, id.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            return nil
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        let url = self.directory.appendingPathComponent(id + ".js")
        do {
            try source.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        var enabled = self.enabledIds
        enabled.insert(id)
        self.enabledIds = enabled
        self.reload()
        return id
    }

    public func setEnabled(id: String, enabled: Bool) {
        var ids = self.enabledIds
        if enabled {
            ids.insert(id)
        } else {
            ids.remove(id)
        }
        self.enabledIds = ids
        self.reload()
    }

    public func remove(id: String) {
        try? FileManager.default.removeItem(at: self.directory.appendingPathComponent(id + ".js"))
        var ids = self.enabledIds
        ids.remove(id)
        self.enabledIds = ids
        self.reload()
    }

    public func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil)) ?? []
        let enabledIds = self.enabledIds
        var loaded: [LoadedPlugin] = []
        var infos: [AyuPluginInfo] = []
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where url.pathExtension == "js" {
            guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            let header = AyuPluginManager.parseHeader(source)
            let id = url.deletingPathExtension().lastPathComponent
            let isEnabled = enabledIds.contains(id)
            var error: String?
            if isEnabled {
                switch self.load(id: id, source: source) {
                case let .success(plugin):
                    loaded.append(plugin)
                case let .failure(loadError):
                    error = loadError.message
                }
            }
            infos.append(AyuPluginInfo(id: id, name: header["name"] ?? id, version: header["version"] ?? "", author: header["author"] ?? "", description: header["description"] ?? "", isEnabled: isEnabled, error: error))
        }
        self.lock.lock()
        self.loaded = loaded
        self.infos = infos
        self.hideCache = [:]
        self.lock.unlock()
        self.infosPromise.set(infos)
    }

    // MARK: Loading

    private struct LoadError: Error {
        let message: String
    }

    private static func parseHeader(_ source: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in source.components(separatedBy: .newlines).prefix(40) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("//") else {
                continue
            }
            let content = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
            guard content.hasPrefix("@") else {
                continue
            }
            let parts = content.dropFirst().split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2 {
                result[String(parts[0]).lowercased()] = String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        return result
    }

    private func load(id: String, source: String) -> Result<LoadedPlugin, LoadError> {
        guard let context = JSContext() else {
            return .failure(LoadError(message: "JavaScriptCore is not available"))
        }
        var exceptionText: String?
        context.exceptionHandler = { _, exception in
            exceptionText = exception?.toString()
        }

        let storageKey = "ayugram.plugins.storage." + id
        let ayu = JSValue(newObjectIn: context)!
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        ayu.setValue(version, forProperty: "version")
        let log: @convention(block) (String) -> Void = { text in
            NSLog("[AyuPlugin \(id)] \(text)")
        }
        ayu.setValue(unsafeBitCast(log, to: AnyObject.self), forProperty: "log")
        let storage = JSValue(newObjectIn: context)!
        let storageGet: @convention(block) (String) -> Any? = { key in
            let values = UserDefaults.standard.dictionary(forKey: storageKey) ?? [:]
            return values[key]
        }
        let storageSet: @convention(block) (String, JSValue) -> Void = { key, value in
            var values = UserDefaults.standard.dictionary(forKey: storageKey) ?? [:]
            if value.isUndefined || value.isNull {
                values.removeValue(forKey: key)
            } else if let object = value.toObject(), JSONSerialization.isValidJSONObject([object]) {
                values[key] = object
            }
            UserDefaults.standard.set(values, forKey: storageKey)
        }
        storage.setValue(unsafeBitCast(storageGet, to: AnyObject.self), forProperty: "get")
        storage.setValue(unsafeBitCast(storageSet, to: AnyObject.self), forProperty: "set")
        ayu.setValue(storage, forProperty: "storage")
        context.setObject(ayu, forKeyedSubscript: "ayu" as NSString)

        let plugin = JSValue(newObjectIn: context)!
        plugin.setValue(JSValue(newObjectIn: context), forProperty: "commands")
        context.setObject(plugin, forKeyedSubscript: "plugin" as NSString)

        context.evaluateScript(source, withSourceURL: URL(string: "ayugram-plugin://\(id).js"))
        if let exceptionText = exceptionText {
            return .failure(LoadError(message: exceptionText))
        }
        context.exceptionHandler = { _, exception in
            NSLog("[AyuPlugin \(id)] error: \(exception?.toString() ?? "")")
        }
        return .success(LoadedPlugin(id: id, context: context, plugin: plugin))
    }

    // MARK: Hooks

    private func chatObject(_ peerId: PeerId, in context: JSContext) -> JSValue {
        let chat = JSValue(newObjectIn: context)!
        chat.setValue(NSNumber(value: ayuBotApiId(peerId)), forProperty: "id")
        return chat
    }

    private func handleOutgoing(text: String, peerId: PeerId) -> AyuPluginOutgoingResult? {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.loaded.isEmpty {
            return nil
        }

        // A command: ".name arguments" handled by the first plugin that has it.
        if text.hasPrefix(".") {
            let body = text.dropFirst()
            let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            if let name = parts.first.map(String.init), !name.isEmpty {
                let args = parts.count > 1 ? String(parts[1]) : ""
                for loaded in self.loaded {
                    guard let commands = loaded.plugin.forProperty("commands"), let command = commands.forProperty(name), command.isObject, !command.isUndefined else {
                        continue
                    }
                    guard let result = command.call(withArguments: [args, self.chatObject(peerId, in: loaded.context)]) else {
                        return .drop
                    }
                    if result.isString, let resultText = result.toString(), !resultText.isEmpty {
                        return .send(resultText)
                    }
                    return .drop
                }
            }
        }

        var current = text
        var changed = false
        for loaded in self.loaded {
            guard let hook = loaded.plugin.forProperty("onOutgoing"), hook.isObject else {
                continue
            }
            guard let result = hook.call(withArguments: [current, self.chatObject(peerId, in: loaded.context)]) else {
                continue
            }
            if result.isNull {
                return .drop
            }
            if result.isString, let resultText = result.toString() {
                if resultText != current {
                    current = resultText
                    changed = true
                }
            }
        }
        return changed ? .send(current) : nil
    }

    private func shouldHide(_ message: Message) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.loaded.isEmpty {
            return false
        }
        let cacheKey = "\(message.id.peerId.toInt64()):\(message.id.namespace):\(message.id.id):\(message.text.hashValue)"
        if let cached = self.hideCache[cacheKey] {
            return cached
        }
        var hide = false
        for loaded in self.loaded {
            guard let hook = loaded.plugin.forProperty("shouldHide"), hook.isObject else {
                continue
            }
            let object = JSValue(newObjectIn: loaded.context)!
            object.setValue(message.text, forProperty: "text")
            object.setValue(NSNumber(value: message.id.id), forProperty: "id")
            object.setValue(NSNumber(value: ayuBotApiId(message.id.peerId)), forProperty: "chatId")
            if let author = message.author {
                object.setValue(NSNumber(value: ayuBotApiId(author.id)), forProperty: "authorId")
            }
            if let result = hook.call(withArguments: [object]), result.toBool() {
                hide = true
                break
            }
        }
        if self.hideCache.count > 5000 {
            self.hideCache = [:]
        }
        self.hideCache[cacheKey] = hide
        return hide
    }
}
