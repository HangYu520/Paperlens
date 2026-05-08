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

    private var currentTask: Task<Void, Never>?
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }

    func cancelCurrent() {
        currentTask?.cancel()
        currentTask = nil
    }

    func translateStream(
        _ text: String,
        apiKey: String,
        model: String,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, TranslationError>) -> Void
    ) {
        guard !apiKey.isEmpty else {
            onComplete(.failure(.noAPIKey))
            return
        }

        cancelCurrent()

        currentTask = Task {
            do {
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
                        ["role": "system", "content": systemPrompt],
                        ["role": "user", "content": text]
                    ],
                    "temperature": 0.3,
                    "max_tokens": 4096,
                    "stream": true
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (bytes, response) = try await session.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    onComplete(.failure(.unknown("无效响应")))
                    return
                }

                switch httpResponse.statusCode {
                case 200:
                    var fullText = ""
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data: "), !line.hasPrefix("data: [DONE]") else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        guard let data = jsonStr.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                              let delta = chunk.choices.first?.delta.content else { continue }
                        fullText += delta
                        await MainActor.run { onToken(delta) }
                    }
                    let result = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                    await MainActor.run { onComplete(.success(result)) }

                case 401:
                    onComplete(.failure(.invalidAPIKey))
                case 429:
                    onComplete(.failure(.rateLimited))
                default:
                    onComplete(.failure(.unknown("服务器错误: \(httpResponse.statusCode)")))
                }
            } catch let error as TranslationError {
                onComplete(.failure(error))
            } catch let error as URLError {
                switch error.code {
                case .timedOut: onComplete(.failure(.timeout))
                case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                    onComplete(.failure(.noNetwork))
                default: onComplete(.failure(.unknown(error.localizedDescription)))
                }
            } catch {
                if error is CancellationError { return }
                onComplete(.failure(.unknown(error.localizedDescription)))
            }
        }
    }
}

private struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }
        let delta: Delta
    }
    let choices: [Choice]
}
