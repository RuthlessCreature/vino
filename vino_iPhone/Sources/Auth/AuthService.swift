import Foundation
import UIKit

public enum CloudServiceError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case unauthorized
    case serverMessage(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "云端地址无效"
        case .invalidResponse:
            return "云端返回格式无效"
        case .unauthorized:
            return "云端鉴权失败"
        case .serverMessage(let message):
            return message
        }
    }
}

public actor AuthService {
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func login(baseURL: String, email: String, password: String) async throws -> AuthSession {
        let body: [String: Any] = [
            "email": email,
            "password": password,
            "deviceId": ModelLicenseVerifier.currentDeviceBindingID(),
            "deviceName": UIDevice.current.name,
            "platform": "iOS"
        ]

        let response: AuthLoginResponse = try await sendJSONRequest(
            baseURL: baseURL,
            path: "/api/cloud/v1/auth/login",
            method: "POST",
            bearerToken: nil,
            jsonBody: body
        )

        return AuthSession(
            accessToken: response.accessToken,
            tokenType: response.tokenType,
            expiresAt: response.expiresAt,
            user: response.user,
            cloudBaseURL: normalizedBaseURL(baseURL) ?? baseURL
        )
    }

    public func fetchModelCatalog(baseURL: String, session: AuthSession) async throws -> CloudModelCatalog {
        let response: CloudModelCatalogResponse = try await sendJSONRequest(
            baseURL: baseURL,
            path: "/api/cloud/v1/models",
            method: "GET",
            bearerToken: session.accessToken,
            jsonBody: nil
        )

        return CloudModelCatalog(
            models: response.models,
            syncedAt: response.syncedAt ?? ISO8601DateFormatter().string(from: Date())
        )
    }

    public func createDownloadTicket(baseURL: String, session: AuthSession, modelID: String) async throws -> ModelDownloadTicketResponse {
        try await sendJSONRequest(
            baseURL: baseURL,
            path: "/api/cloud/v1/models/\(modelID)/download-ticket",
            method: "POST",
            bearerToken: session.accessToken,
            jsonBody: [
                "deviceId": ModelLicenseVerifier.currentDeviceBindingID(),
                "deviceName": UIDevice.current.name
            ]
        )
    }

    public func downloadArtifact(ticket: ModelDownloadTicketResponse) async throws -> URL {
        guard let url = URL(string: ticket.downloadURL) else {
            throw CloudServiceError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (temporaryURL, response) = try await urlSession.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let data = (try? Data(contentsOf: temporaryURL)) ?? Data()
            throw try decodeError(from: data, statusCode: httpResponse.statusCode)
        }

        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: false)
            .appendingPathExtension((ticket.fileName as NSString).pathExtension.isEmpty ? "bin" : (ticket.fileName as NSString).pathExtension)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    public func renewLease(baseURL: String, session: AuthSession, modelID: String) async throws -> LeaseRenewalResponse {
        try await sendJSONRequest(
            baseURL: baseURL,
            path: "/api/cloud/v1/licenses/lease/renew",
            method: "POST",
            bearerToken: session.accessToken,
            jsonBody: [
                "modelId": modelID,
                "deviceId": ModelLicenseVerifier.currentDeviceBindingID()
            ]
        )
    }

    private func sendJSONRequest<Response: Decodable>(
        baseURL: String,
        path: String,
        method: String,
        bearerToken: String?,
        jsonBody: [String: Any]?
    ) async throws -> Response {
        guard
            let normalized = normalizedBaseURL(baseURL),
            let url = URL(string: normalized + path)
        else {
            throw CloudServiceError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if let jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw try decodeError(from: data, statusCode: httpResponse.statusCode)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw CloudServiceError.invalidResponse
        }
    }

    private func decodeError(from data: Data, statusCode: Int) throws -> Error {
        if statusCode == 401 {
            return CloudServiceError.unauthorized
        }

        if
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = object["error"] as? String ?? object["message"] as? String
        {
            return CloudServiceError.serverMessage(message)
        }

        return CloudServiceError.serverMessage("HTTP \(statusCode)")
    }

    private func normalizedBaseURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        }
        let value = "http://\(trimmed)"
        return value.hasSuffix("/") ? String(value.dropLast()) : value
    }
}
