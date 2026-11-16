import Foundation
import UIKit
import TelegramCore

/// AstraGram AI: an OpenAI-compatible API (OpenAI, OpenRouter, Groq, DeepSeek, a local server…) with the user's own key,
/// set in AstraGram → AI. Nothing is sent anywhere until the user asks for an AI action.
public enum AstraAI {
    public enum AIError: Error {
        case notConfigured
        /// The user did not agree to send the text to the AI server.
        case declined
        case network(String)
        case server(String)
    }

    /// Without a key, a free public OpenAI-compatible service is used (Pollinations: no registration, about one
    /// request every 45 seconds, text only).
    public static let freeEndpoint = "https://text.pollinations.ai/openai"
    public static let freeModel = "openai"

    /// Whether the user's own key is set (otherwise the free service is used).
    public static var hasOwnKey: Bool {
        let settings = AstraGramSettings.current
        return !settings.aiApiKey.trimmingCharacters(in: .whitespaces).isEmpty && URL(string: settings.aiEndpoint) != nil
    }

    public static var isConfigured: Bool {
        return true
    }

    /// Whether an endpoint may carry the key and the text: https, or http to this device only.
    public static func isSecureEndpoint(_ endpoint: String) -> Bool {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
            return false
        }
        if scheme == "https" {
            return true
        }
        return scheme == "http" && (host == "localhost" || host == "127.0.0.1" || host == "::1")
    }

    /// An error when the own endpoint is not secure (nothing is sent then).
    private static func insecureEndpointError() -> AIError? {
        if AstraAI.hasOwnKey && !AstraAI.isSecureEndpoint(AstraGramSettings.current.aiEndpoint) {
            let isRussian = (Locale.preferredLanguages.first ?? "").lowercased().hasPrefix("ru")
            return .server(isRussian ? "Адрес AI должен начинаться с https:// — по http ключ и текст ушли бы незашифрованными. Ничего не отправлено." : "The AI address must start with https:// — over http the key and the text would travel unencrypted. Nothing was sent.")
        }
        return nil
    }

    private static func baseUrl() -> String {
        if !AstraAI.hasOwnKey {
            return AstraAI.freeEndpoint
        }
        var endpoint = AstraGramSettings.current.aiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        while endpoint.hasSuffix("/") {
            endpoint.removeLast()
        }
        return endpoint
    }

    private static func errorText(_ data: Data?, status: Int) -> String {
        if let data = data, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
                return message
            }
            if let message = object["message"] as? String {
                return message
            }
        }
        return "HTTP \(status)"
    }

    /// AstraGram security: AI sends chat text to a server outside Telegram. The first request to a host is asked about,
    /// and the answer is remembered for that host.
    private static func withConsent(_ proceed: @escaping () -> Void, declined: @escaping () -> Void) {
        let host = URL(string: AstraAI.baseUrl())?.host ?? AstraAI.baseUrl()
        if AstraGramSettings.current.aiConsentEndpoint == host {
            proceed()
            return
        }
        DispatchQueue.main.async {
            guard let presenter = astraTopViewController() else {
                declined()
                return
            }
            let isRussian = (Locale.preferredLanguages.first ?? "").lowercased().hasPrefix("ru")
            let alert = UIAlertController(
                title: isRussian ? "Отправить текст в AI?" : "Send the text to AI?",
                message: isRussian ? "Текст сообщений уйдёт на сервер \(host), за пределы Telegram. Его владелец сможет этот текст прочитать." : "The text of the messages goes to the server \(host), outside Telegram. Its owner can read that text.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: isRussian ? "Отмена" : "Cancel", style: .cancel, handler: { _ in
                declined()
            }))
            alert.addAction(UIAlertAction(title: isRussian ? "Отправлять" : "Send", style: .default, handler: { _ in
                AstraGramSettings.update { $0.aiConsentEndpoint = host }
                proceed()
            }))
            presenter.present(alert, animated: true)
        }
    }

    /// Asks the model; `completion` is called on the main queue.
    public static func complete(system: String, user: String, completion: @escaping (Result<String, AIError>) -> Void) {
        if let error = AstraAI.insecureEndpointError() {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            return
        }
        AstraAI.withConsent({
            AstraAI.performComplete(system: system, user: user, completion: completion)
        }, declined: {
            completion(.failure(.declined))
        })
    }

    private static func performComplete(system: String, user: String, completion: @escaping (Result<String, AIError>) -> Void) {
        let settings = AstraGramSettings.current
        guard AstraAI.isConfigured, let url = URL(string: AstraAI.baseUrl() + "/chat/completions") else {
            completion(.failure(.notConfigured))
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 120.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let hasOwnKey = AstraAI.hasOwnKey
        if hasOwnKey {
            request.setValue("Bearer \(settings.aiApiKey.trimmingCharacters(in: .whitespaces))", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "model": hasOwnKey ? (settings.aiModel.isEmpty ? "gpt-4o-mini" : settings.aiModel) : AstraAI.freeModel,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.4
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            let result: Result<String, AIError>
            if let error = error {
                result = .failure(.network(error.localizedDescription))
            } else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200, let data = data, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let choices = object["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any], let content = message["content"] as? String {
                    result = .success(content.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    result = .failure(.server(AstraAI.errorText(data, status: status)))
                }
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }).resume()
    }

    /// Speech to text (an OpenAI-compatible /audio/transcriptions endpoint, model whisper-1).
    public static func transcribe(fileUrl: URL, fileName: String, mimeType: String, completion: @escaping (Result<String, AIError>) -> Void) {
        if let error = AstraAI.insecureEndpointError() {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            return
        }
        AstraAI.withConsent({
            AstraAI.performTranscribe(fileUrl: fileUrl, fileName: fileName, mimeType: mimeType, completion: completion)
        }, declined: {
            completion(.failure(.declined))
        })
    }

    private static func performTranscribe(fileUrl: URL, fileName: String, mimeType: String, completion: @escaping (Result<String, AIError>) -> Void) {
        let settings = AstraGramSettings.current
        guard AstraAI.hasOwnKey, let url = URL(string: AstraAI.baseUrl() + "/audio/transcriptions"), let fileData = try? Data(contentsOf: fileUrl) else {
            completion(.failure(.notConfigured))
            return
        }
        let boundary = "AstraGram-\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) {
            body.append(string.data(using: .utf8)!)
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url, timeoutInterval: 180.0)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.aiApiKey.trimmingCharacters(in: .whitespaces))", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            let result: Result<String, AIError>
            if let error = error {
                result = .failure(.network(error.localizedDescription))
            } else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200, let data = data, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let text = object["text"] as? String {
                    result = .success(text.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    result = .failure(.server(AstraAI.errorText(data, status: status)))
                }
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }).resume()
    }

    public static func describe(_ error: AIError, isRussian: Bool) -> String {
        switch error {
        case .notConfigured:
            return isRussian ? "Для этого действия нужен свой API-ключ: Настройки → AstraGram → AI (бесплатный AI работает только с текстом)." : "This action needs your own API key: Settings → AstraGram → AI (the free AI handles text only)."
        case .declined:
            return isRussian ? "Текст не отправлен." : "The text was not sent."
        case let .network(text):
            return (isRussian ? "Ошибка сети: " : "Network error: ") + text
        case let .server(text):
            return (isRussian ? "Ошибка AI: " : "AI error: ") + text
        }
    }
}
