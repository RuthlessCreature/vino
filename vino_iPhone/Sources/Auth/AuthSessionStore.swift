import Foundation

public actor AuthSessionStore {
    private let keychain = KeychainStore(service: "cc.vino.iphone.auth")
    private let sessionAccount = "primary-session"

    public init() {}

    public func loadSession() async -> AuthSession? {
        guard let data = try? await keychain.load(account: sessionAccount) else {
            return nil
        }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    public func saveSession(_ session: AuthSession) async {
        guard let data = try? JSONEncoder().encode(session) else {
            return
        }
        try? await keychain.save(data, account: sessionAccount)
    }

    public func clearSession() async {
        try? await keychain.delete(account: sessionAccount)
    }
}
