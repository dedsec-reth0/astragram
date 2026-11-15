import Foundation
import TelegramCore

/// AyuGram AI: an OpenAI-compatible API (OpenAI, OpenRouter, Groq, DeepSeek, a local server…) with the user's own key,
/// set in AyuGram → AI. Nothing is sent anywhere until the user asks for an AI action.
public enum AyuAI {
    public enum AIError: Error {
        case notConfigured
        case network(String)
        case server(String)
    }

    /// Without a key, a free public OpenAI-compatible service is used (Pollinations: no registration, about one
    /// request every 45 seconds, text only).
    public static let freeEndpoint = "https://text.pollinations.ai/openai"
    public static let freeModel = "openai"

    /// Whether the user's own key is set (otherwise the free service is used).
    public static var hasOwnKey: Bool {
        let settings = AyuGramSettings.current
        return !settings.aiApiKey.trimmingCharacters(in: .whitespaces).isEmpty && URL(string: settings.aiEndpoint) != nil
    }

    public static var isConfigured: Bool {
        return true
    }

    private static func baseUrl() -> String {
        if !AyuAI.hasOwnKey {
            return AyuAI.freeEndpoint
        }
        var endpoint = AyuGramSettings.current.aiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// Asks the model; `completion` is called on the main queue.
    public static func complete(system: String, user: String, completion: @escaping (Result<String, AIError>) -> Void) {
        let settings = AyuGramSettings.current
        guard AyuAI.isConfigured, let url = URL(string: AyuAI.baseUrl() + "/chat/completions") else {
            completion(.failure(.notConfigured))
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 120.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let hasOwnKey = AyuAI.hasOwnKey
        if hasOwnKey {
            request.setValue("Bearer \(settings.aiApiKey.trimmingCharacters(in: .whitespaces))", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "model": hasOwnKey ? (settings.aiModel.isEmpty ? "gpt-4o-mini" : settings.aiModel) : AyuAI.freeModel,
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
                    result = .failure(.server(AyuAI.errorText(data, status: status)))
                }
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }).resume()
    }

    /// Speech to text (an OpenAI-compatible /audio/transcriptions endpoint, model whisper-1).
    public static func transcribe(fileUrl: URL, fileName: String, mimeType: String, completion: @escaping (Result<String, AIError>) -> Void) {
        let settings = AyuGramSettings.current
        guard AyuAI.hasOwnKey, let url = URL(string: AyuAI.baseUrl() + "/audio/transcriptions"), let fileData = try? Data(contentsOf: fileUrl) else {
            completion(.failure(.notConfigured))
            return
        }
        let boundary = "AyuGram-\(UUID().uuidString)"
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
                    result = .failure(.server(AyuAI.errorText(data, status: status)))
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
        case let .network(text):
            return (isRussian ? "Ошибка сети: " : "Network error: ") + text
        case let .server(text):
            return (isRussian ? "Ошибка AI: " : "AI error: ") + text
        }
    }
}
