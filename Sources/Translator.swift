import Foundation

enum TranslationError: LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case noNetwork
    case rateLimited
    case timeout
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "请先在设置中配置 API Key"
        case .invalidAPIKey: return "API Key 无效，请检查"
        case .noNetwork: return "无网络连接"
        case .rateLimited: return "请求过于频繁，请稍后重试"
        case .timeout: return "翻译超时，请重试"
        case .unknown(let msg): return msg
        }
    }
}

final class TranslatorService {
    static let shared = TranslatorService()

    private var currentTask: URLSessionDataTask?
    private let session: URLSession
    private let queue = DispatchQueue(label: "com.paperlens.translator")

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 40
        session = URLSession(configuration: config)
    }

    func cancelCurrent() {
        queue.sync {
            currentTask?.cancel()
            currentTask = nil
        }
    }

    func translate(_ text: String, apiKey: String, model: String) async throws -> String {
        guard !apiKey.isEmpty else { throw TranslationError.noAPIKey }

        cancelCurrent()

        let url = URL(string: "https://api.deepseek.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let detailed = UserDefaults.standard.bool(forKey: "detailedTranslation")
        let systemPrompt: String
        if detailed {
            systemPrompt = "你是一个学术论文翻译与解析助手。请对以下英文文本进行深入翻译和解析：\n1. 输出流畅准确的中文译文\n2. 在关键术语后以括号标注英文原文\n3. 对复杂句式进行结构解析\n4. 补充相关的学术背景或参考文献信息（如适用）\n请使用清晰的标题和小标题组织内容。"
        } else {
            systemPrompt = "你是一个学术论文翻译助手。将用户提供的英文文本翻译为中文。要求：1. 保持学术论文的专业性和严谨性 2. 术语翻译准确 3. 不添加任何解释或补充 4. 仅输出译文"
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3,
            "max_tokens": 4096
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await withCheckedThrowingContinuation { continuation in
            currentTask = session.dataTask(with: request) { data, response, error in
                if let error = error as? URLError {
                    switch error.code {
                    case .timedOut:
                        continuation.resume(throwing: TranslationError.timeout)
                    case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                        continuation.resume(throwing: TranslationError.noNetwork)
                    default:
                        continuation.resume(throwing: TranslationError.unknown(error.localizedDescription))
                    }
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(throwing: TranslationError.unknown("无效响应"))
                    return
                }

                switch httpResponse.statusCode {
                case 200:
                    guard let data = data else {
                        continuation.resume(throwing: TranslationError.unknown("空响应"))
                        return
                    }
                    do {
                        let decoded = try JSONDecoder().decode(DeepSeekResponse.self, from: data)
                        let content = decoded.choices.first?.message.content ?? ""
                        continuation.resume(returning: content.trimmingCharacters(in: .whitespacesAndNewlines))
                    } catch {
                        continuation.resume(throwing: TranslationError.unknown("解析响应失败"))
                    }
                case 401:
                    continuation.resume(throwing: TranslationError.invalidAPIKey)
                case 429:
                    continuation.resume(throwing: TranslationError.rateLimited)
                default:
                    continuation.resume(throwing: TranslationError.unknown("服务器错误: \(httpResponse.statusCode)"))
                }
            }
            currentTask?.resume()
        }
    }
}

private struct DeepSeekResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}
