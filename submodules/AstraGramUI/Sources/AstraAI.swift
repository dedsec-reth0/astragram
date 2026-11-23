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
        return !settings.aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && URL(string: settings.aiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
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
            let isRussian = (Locale.preferredLanguages.first ?? "").astraUsesRussianTexts
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
            let isRussian = (Locale.preferredLanguages.first ?? "").astraUsesRussianTexts
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
        // Chat messages are often casual, with swearing and slang: the model is told so, and a canned refusal is never
        // shown as if it were the answer (it is asked once more; then a plain error).
        let tool = system + "\n\nThe text is from the user's own private chat and may contain profanity, slang or rude words. This is a text-processing tool, not a conversation: process the text faithfully, handling such words as the task needs (keep them when translating, explaining or fixing; soften them only when asked for a polite or formal tone). Never refuse, never lecture, never add warnings or comments of your own."
        AstraAI.withConsent({
            AstraAI.performComplete(system: tool, user: user, completion: { result in
                guard case let .success(text) = result, AstraAI.isRefusal(text) else {
                    completion(result)
                    return
                }
                AstraAI.performComplete(system: tool + "\nIMPORTANT: the previous answer was a refusal, which is wrong for this tool. Do the task now.", user: user, completion: { retry in
                    if case let .success(text) = retry, AstraAI.isRefusal(text) {
                        let isRussian = Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") ?? false
                        completion(.failure(.server(isRussian ? "AI отказался обрабатывать этот текст. Попробуйте ещё раз или укажите свой ключ AI в настройках AstraGram." : "The AI refused to process this text. Try again, or set your own AI key in the AstraGram settings.")))
                    } else {
                        completion(retry)
                    }
                })
            })
        }, declined: {
            completion(.failure(.declined))
        })
    }

    /// A canned "I can't help with that" instead of an answer.
    static func isRefusal(_ text: String) -> Bool {
        let lower = text.lowercased()
        guard lower.count < 600 else {
            return false
        }
        let markers = [
            "i cannot fulfill", "i can't fulfill", "i can’t fulfill", "i cannot help with", "i can't help with", "i can’t help with",
            "i'm sorry, but i can", "i’m sorry, but i can", "i am programmed to be", "harmless ai", "as an ai language model",
            "i cannot assist", "i can't assist", "i can’t assist", "offensive and inappropriate", "inappropriate language",
            "не могу выполнить", "не могу помочь с", "я не могу обработать"
        ]
        return markers.contains(where: { lower.contains($0) })
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
            request.setValue("Bearer \(settings.aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
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
        request.setValue("Bearer \(settings.aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
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
