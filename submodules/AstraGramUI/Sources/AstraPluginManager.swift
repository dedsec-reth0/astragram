import Foundation
import JavaScriptCore
import Postbox
import SwiftSignalKit
import TelegramCore

/// An installed AstraGram plugin.
public struct AstraPluginInfo: Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let author: String
    public let description: String
    public let isEnabled: Bool
    /// The error of the last load, if the plugin failed to load.
    public let error: String?
}

/// Runs AstraGram plugins: JavaScript files executed with JavaScriptCore (sideloaded apps cannot load native code).
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
/// `message.id`). Plugins can call `astra.log(text)`, `astra.storage.get(key)` / `astra.storage.set(key, value)` (kept per
/// plugin) and read `astra.version`.
public final class AstraPluginManager {
    public static let shared = AstraPluginManager()

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
    private var infos: [AstraPluginInfo] = []
    private let infosPromise = ValuePromise<[AstraPluginInfo]>([], ignoreRepeated: true)
    private var hideCache: [String: Bool] = [:]

    private static let enabledKey = "ayugram.plugins.enabled.v1"

    private var directory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("ayugram-plugins", isDirectory: true)
    }

    private var enabledIds: Set<String> {
        get {
            return Set(UserDefaults.standard.stringArray(forKey: AstraPluginManager.enabledKey) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: AstraPluginManager.enabledKey)
        }
    }

    public var plugins: Signal<[AstraPluginInfo], NoError> {
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
        AstraPluginHooks.setOutgoingHook({ [weak self] text, peerId in
            return self?.handleOutgoing(text: text, peerId: peerId)
        })
        AstraPluginHooks.setHideHook({ [weak self] message in
            return self?.shouldHide(message) ?? false
        })
    }

    // MARK: Management

    /// Installs (or replaces) a plugin from its source. Returns the plugin id, or nil when the source has no `@id`.
    @discardableResult
    public func install(source: String, enable: Bool = true) -> String? {
        let header = AstraPluginManager.parseHeader(source)
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
        // A plugin installed switched off is switched off even when it replaces an enabled one with the same id.
        var enabled = self.enabledIds
        if enable {
            enabled.insert(id)
        } else {
            enabled.remove(id)
        }
        self.enabledIds = enabled
        self.reload()
        return id
    }

    /// The sources of the installed plugins (for AstraGram backups).
    public func exportSources() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "js" }.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
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
        // What the plugin kept goes with it.
        UserDefaults.standard.removeObject(forKey: "ayugram.plugins.storage." + id)
        var ids = self.enabledIds
        ids.remove(id)
        self.enabledIds = ids
        self.reload()
    }

    public func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil)) ?? []
        let enabledIds = self.enabledIds
        var loaded: [LoadedPlugin] = []
        var infos: [AstraPluginInfo] = []
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where url.pathExtension == "js" {
            guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            let header = AstraPluginManager.parseHeader(source)
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
            infos.append(AstraPluginInfo(id: id, name: header["name"] ?? id, version: header["version"] ?? "", author: header["author"] ?? "", description: header["description"] ?? "", isEnabled: isEnabled, error: error))
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

    // JavaScriptCore's Objective-C API is imported with implicitly unwrapped or non-optional types depending on the
    // SDK; these helpers give the same types either way.
    private static func newObject(in context: JSContext) -> JSValue {
        let value: JSValue = JSValue(newObjectIn: context)
        return value
    }

    private static func property(_ value: JSValue, _ name: String) -> JSValue? {
        let result: JSValue? = value.forProperty(name)
        if let result = result, !result.isUndefined, !result.isNull {
            return result
        }
        return nil
    }

    private static func call(_ function: JSValue, _ arguments: [Any]) -> JSValue? {
        let result: JSValue? = function.call(withArguments: arguments)
        return result
    }

    private static func string(_ value: JSValue) -> String? {
        let result: String? = value.toString()
        return result
    }

    private func load(id: String, source: String) -> Result<LoadedPlugin, LoadError> {
        let context: JSContext = JSContext()
        var exceptionText: String?
        context.exceptionHandler = { _, exception in
            let exceptionValue: JSValue? = exception
            exceptionText = exceptionValue.flatMap { AstraPluginManager.string($0) } ?? "error"
        }

        let storageKey = "ayugram.plugins.storage." + id
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let log: @convention(block) (String) -> Void = { text in
            #if DEBUG
            NSLog("[AstraPlugin \(id)] \(text)")
            #endif
        }
        // The storage keeps JSON strings; the JavaScript wrapper below turns them back into values.
        let storageGet: @convention(block) (String) -> String? = { key in
            let values = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
            return values[key]
        }
        let storageSet: @convention(block) (String, String?) -> Void = { key, value in
            var values = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
            if let value = value {
                values[key] = value
            } else {
                values.removeValue(forKey: key)
            }
            UserDefaults.standard.set(values, forKey: storageKey)
        }
        context.setObject(unsafeBitCast(log, to: AnyObject.self), forKeyedSubscript: "__astraLog" as NSString)
        context.setObject(unsafeBitCast(storageGet, to: AnyObject.self), forKeyedSubscript: "__astraStorageGet" as NSString)
        context.setObject(unsafeBitCast(storageSet, to: AnyObject.self), forKeyedSubscript: "__astraStorageSet" as NSString)
        context.setObject(version, forKeyedSubscript: "__astraVersion" as NSString)
        context.evaluateScript("""
        var astra = {
            version: __astraVersion,
            log: function (text) { __astraLog(String(text)) },
            storage: {
                get: function (key) { var value = __astraStorageGet(String(key)); return value == null ? null : JSON.parse(value) },
                set: function (key, value) { __astraStorageSet(String(key), value === undefined || value === null ? null : JSON.stringify(value)) }
            }
        };
        var ayu = astra;
        var plugin = { commands: {} };
        """)

        context.evaluateScript(source, withSourceURL: URL(string: "astragram-plugin://\(id).js"))
        if let exceptionText = exceptionText {
            return .failure(LoadError(message: exceptionText))
        }
        guard let plugin = AstraPluginManager.property(context.globalObject, "plugin") else {
            return .failure(LoadError(message: "plugin object is missing"))
        }
        context.exceptionHandler = { _, exception in
            let exceptionValue: JSValue? = exception
            #if DEBUG
            NSLog("[AstraPlugin \(id)] error: \(exceptionValue.flatMap { AstraPluginManager.string($0) } ?? "")")
            #else
            let _ = exceptionValue
            #endif
        }
        return .success(LoadedPlugin(id: id, context: context, plugin: plugin))
    }

    // MARK: Hooks

    private func chatObject(_ peerId: PeerId, in context: JSContext) -> JSValue {
        let chat = AstraPluginManager.newObject(in: context)
        chat.setValue(NSNumber(value: astraBotApiId(peerId)), forProperty: "id")
        return chat
    }

    private func handleOutgoing(text: String, peerId: PeerId) -> AstraPluginOutgoingResult? {
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
                    guard let commands = AstraPluginManager.property(loaded.plugin, "commands"), let command = AstraPluginManager.property(commands, name), command.isObject else {
                        continue
                    }
                    guard let result = AstraPluginManager.call(command, [args, self.chatObject(peerId, in: loaded.context)]) else {
                        return .drop
                    }
                    if result.isString, let resultText = AstraPluginManager.string(result), !resultText.isEmpty {
                        return .send(resultText)
                    }
                    return .drop
                }
            }
        }

        var current = text
        var changed = false
        for loaded in self.loaded {
            guard let hook = AstraPluginManager.property(loaded.plugin, "onOutgoing"), hook.isObject else {
                continue
            }
            guard let result = AstraPluginManager.call(hook, [current, self.chatObject(peerId, in: loaded.context)]) else {
                continue
            }
            if result.isNull {
                return .drop
            }
            if result.isString, let resultText = AstraPluginManager.string(result) {
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
            guard let hook = AstraPluginManager.property(loaded.plugin, "shouldHide"), hook.isObject else {
                continue
            }
            let object = AstraPluginManager.newObject(in: loaded.context)
            object.setValue(message.text, forProperty: "text")
            object.setValue(NSNumber(value: message.id.id), forProperty: "id")
            object.setValue(NSNumber(value: astraBotApiId(message.id.peerId)), forProperty: "chatId")
            if let author = message.author {
                object.setValue(NSNumber(value: astraBotApiId(author.id)), forProperty: "authorId")
            }
            if let result = AstraPluginManager.call(hook, [object]), result.toBool() {
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
