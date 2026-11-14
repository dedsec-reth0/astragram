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

    public static var isConfigured: Bool {
        let settings = AyuGramSettings.current
        return !settings.aiApiKey.trimmingCharacters(in: .whitespaces).isEmpty && URL(string: settings.aiEndpoint) != nil
    }

    private static func baseUrl() -> String {
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
        request.setValue("Bearer \(settings.aiApiKey.trimmingCharacters(in: .whitespaces))", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": settings.aiModel.isEmpty ? "gpt-4o-mini" : settings.aiModel,
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
        guard AyuAI.isConfigured, let url = URL(string: AyuAI.baseUrl() + "/audio/transcriptions"), let fileData = try? Data(contentsOf: fileUrl) else {
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
            return isRussian ? "AI не настроен: укажите API-ключ в Настройки → AyuGram → AI." : "AI is not set up: add an API key in Settings → AyuGram → AI."
        case let .network(text):
            return (isRussian ? "Ошибка сети: " : "Network error: ") + text
        case let .server(text):
            return (isRussian ? "Ошибка AI: " : "AI error: ") + text
        }
    }
}
