import Foundation
#if canImport(os)
import os
#endif

/// HTTP client for the Anthropic Messages API.
public actor AnthropicClient {
    private let apiKey: String
    private let session: URLSession
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let apiVersion = "2023-06-01"

    #if canImport(os)
    private let logger = Logger(subsystem: "com.photocrawler", category: "AnthropicClient")
    #endif

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// Send a messages request to the Anthropic API.
    public func sendMessage(_ request: MessagesRequest) async throws -> MessagesResponse {
        guard let url = URL(string: baseURL) else {
            throw AnthropicClientError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.timeoutInterval = 120

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        #if canImport(os)
        logger.info("Sending request to Claude API (model: \(request.model))")
        #endif

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicClientError.invalidResponse
        }

        #if canImport(os)
        logger.info("Received response: HTTP \(httpResponse.statusCode)")
        #endif

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data) {
                throw AnthropicClientError.apiError(
                    statusCode: httpResponse.statusCode,
                    message: errorResponse.error.message
                )
            }
            throw AnthropicClientError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(MessagesResponse.self, from: data)
    }

    /// Send an image with a text prompt for content extraction.
    public func extractContent(
        imageData: Data,
        mediaType: String,
        systemPrompt: String,
        userPrompt: String,
        model: String,
        maxTokens: Int = 4096
    ) async throws -> MessagesResponse {
        let base64 = imageData.base64EncodedString()

        let request = MessagesRequest(
            model: model,
            maxTokens: maxTokens,
            system: systemPrompt,
            messages: [
                Message(role: "user", content: [
                    .image(mediaType: mediaType, base64Data: base64),
                    .text(userPrompt)
                ])
            ]
        )

        return try await sendMessage(request)
    }
}

/// Errors from the Anthropic API client.
public enum AnthropicClientError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case apiError(statusCode: Int, message: String)
    case noTextContent

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from API"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
        case .noTextContent:
            return "No text content in API response"
        }
    }
}
