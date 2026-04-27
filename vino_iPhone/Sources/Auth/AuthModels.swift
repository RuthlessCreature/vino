import Foundation

public struct AuthUserProfile: Codable, Hashable {
    public var userID: String
    public var email: String
    public var displayName: String
    public var organizationID: String
    public var organizationName: String

    public init(
        userID: String,
        email: String,
        displayName: String,
        organizationID: String,
        organizationName: String
    ) {
        self.userID = userID
        self.email = email
        self.displayName = displayName
        self.organizationID = organizationID
        self.organizationName = organizationName
    }

    enum CodingKeys: String, CodingKey {
        case userID = "userId"
        case email
        case displayName
        case organizationID = "organizationId"
        case organizationName
    }
}

public struct AuthSession: Codable, Hashable {
    public var accessToken: String
    public var tokenType: String
    public var expiresAt: String
    public var user: AuthUserProfile
    public var cloudBaseURL: String

    public init(
        accessToken: String,
        tokenType: String = "Bearer",
        expiresAt: String,
        user: AuthUserProfile,
        cloudBaseURL: String
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresAt = expiresAt
        self.user = user
        self.cloudBaseURL = cloudBaseURL
    }

    public var authorizationHeader: String {
        "\(tokenType) \(accessToken)"
    }

    public var isExpired: Bool {
        let formatter = ISO8601DateFormatter()
        guard let expiry = formatter.date(from: expiresAt) else {
            return false
        }
        return expiry <= Date()
    }
}

public struct AuthLoginResponse: Codable, Hashable {
    public var accessToken: String
    public var tokenType: String
    public var expiresAt: String
    public var user: AuthUserProfile

    public init(accessToken: String, tokenType: String, expiresAt: String, user: AuthUserProfile) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresAt = expiresAt
        self.user = user
    }

    enum CodingKeys: String, CodingKey {
        case accessToken
        case tokenType
        case expiresAt
        case user
    }
}
