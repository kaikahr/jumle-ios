//
//  OpenAIService.swift
//  jumle
//
//  Created by Kai Kahar on 2025-08-13.
//
import Foundation

// MARK: - Lightweight throttler (limits concurrency to protect rate limits)
actor AIThrottle {
    private let maxConcurrent: Int
    private var running = 0
    private var queue: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int = 4) {
        self.maxConcurrent = maxConcurrent
    }

    func acquire() async {
        if running < maxConcurrent {
            running += 1
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.append(cont)
        }
        running += 1
    }

    func release() {
        running = max(0, running - 1)
        if !queue.isEmpty, running < maxConcurrent {
            let cont = queue.removeFirst()
            cont.resume()
        }
    }
}

// MARK: - Simple disk+memory cache
final class AICache {
    static let shared = AICache()
    private let mem = NSCache<NSString, NSString>()
    private let fm = FileManager.default
    private let dir: URL

    private init() {
        dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ai-cache", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func fileURL(for key: String) -> URL { dir.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString + ".txt") }

    func get(_ key: String) -> String? {
        if let m = mem.object(forKey: key as NSString) { return m as String }
        let url = fileURL(for: key)
        if let data = try? Data(contentsOf: url), let s = String(data: data, encoding: .utf8) {
            mem.setObject(s as NSString, forKey: key as NSString)
            return s
        }
        return nil
    }

    func set(_ key: String, _ value: String) {
        mem.setObject(value as NSString, forKey: key as NSString)
        let url = fileURL(for: key)
        try? value.data(using: .utf8)?.write(to: url, options: .atomic)
    }
}

// MARK: - OpenAI client (Chat Completions)
struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

final class OpenAIService {
    static let shared = OpenAIService()

    private let session: URLSession
    private let apiKey: String
    private let model: String
    private let throttle = AIThrottle(maxConcurrent: 50) // tune if needed
    private let cache = AICache.shared

    private init() {
        // Load your API key from Info.plist (String key: OPENAI_API_KEY)
        guard let key = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String, !key.isEmpty else {
            fatalError("Missing OPENAI_API_KEY in Info.plist")
        }
        apiKey = key
        model = "gpt-4o-mini" // fast + cost-efficient

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }
    
    // ✅ NEW METHOD: For Explain/Context buttons - returns plain text
        func completeTextCached(key: String, system: String, user: String, maxTokens: Int = 400, temperature: Double = 0.2) async throws -> String {
            if let cached = cache.get(key) { return cached }

            await throttle.acquire()
            defer { Task { await throttle.release() } }

            var lastErr: Error?
            for attempt in 0..<3 {
                do {
                    let out = try await completeTextOnly(system: system, user: user, maxTokens: maxTokens, temperature: temperature)
                    cache.set(key, out)
                    return out
                } catch {
                    lastErr = error
                    // Exponential backoff (jitter)
                    let base = UInt64(300_000_000) // 0.3s
                    let delay = base * UInt64(1 << attempt)
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
            throw lastErr ?? URLError(.cannotLoadFromNetwork)
        }

    // Public helper with caching + retries + throttling
    func completeCached(key: String, system: String, user: String, maxTokens: Int = 400, temperature: Double = 0.2) async throws -> String {
        if let cached = cache.get(key) { return cached }

        await throttle.acquire()
        defer { Task { await throttle.release() } }

        var lastErr: Error?
        for attempt in 0..<3 {
            do {
                let out = try await complete(system: system, user: user, maxTokens: maxTokens, temperature: temperature)
                cache.set(key, out)
                return out
            } catch {
                lastErr = error
                // Exponential backoff (jitter)
                let base = UInt64(300_000_000) // 0.3s
                let delay = base * UInt64(1 << attempt)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        throw lastErr ?? URLError(.cannotLoadFromNetwork)
    }

    // ✅ NEW PRIVATE METHOD: Makes text-only API calls (for Explain/Context)
        private func completeTextOnly(system: String, user: String, maxTokens: Int, temperature: Double) async throws -> String {
            let url = URL(string: "https://api.openai.com/v1/chat/completions")!
            let messages = [
                OpenAIMessage(role: "system", content: system),
                OpenAIMessage(role: "user", content: user)
            ]
            // ✅ NO response_format - allows plain text responses
            let body: [String: Any] = [
                "model": model,
                "messages": messages.map { ["role": $0.role, "content": $0.content] },
                "temperature": temperature,
                "max_tokens": maxTokens
            ]

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("application/json", forHTTPHeaderFields: "Content-Type")
            req.addValue("Bearer \(apiKey)", forHTTPHeaderFields: "Authorization")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw NSError(domain: "OpenAI", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: msg])
            }

            // Minimal JSON parse
            struct Choice: Codable { let message: OpenAIMessage }
            struct Response: Codable { let choices: [Choice] }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
                throw URLError(.zeroByteResource)
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    
    // Core call to Chat Completions API
    private func complete(system: String, user: String, maxTokens: Int, temperature: Double) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        let messages = [
            OpenAIMessage(role: "system", content: system),
            OpenAIMessage(role: "user", content: user)
        ]
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": temperature,
            "max_tokens": maxTokens,
            "response_format": ["type": "json_object"]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderFields: "Content-Type")
        req.addValue("Bearer \(apiKey)", forHTTPHeaderFields: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "OpenAI", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        // Minimal JSON parse
        struct Choice: Codable { let message: OpenAIMessage }
        struct Response: Codable { let choices: [Choice] }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
            throw URLError(.zeroByteResource)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension URLRequest {
    mutating func addValue(_ value: String, forHTTPHeaderFields field: String) {
        addValue(value, forHTTPHeaderField: field)
    }
}
