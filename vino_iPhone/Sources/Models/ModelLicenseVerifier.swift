import CryptoKit
import Foundation
import UIKit

public struct ModelValidationResult: Hashable {
    public var isValid: Bool
    public var message: String

    public init(isValid: Bool, message: String) {
        self.isValid = isValid
        self.message = message
    }
}

public enum ModelLicenseVerifier {
    public static func currentDeviceBindingID() -> String {
        if let identifier = UIDevice.current.identifierForVendor?.uuidString.lowercased(), !identifier.isEmpty {
            return identifier
        }

        return UIDevice.current.name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Data(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    public static func validate(
        metadata: ModelFileStore.Metadata,
        now: Date = Date(),
        deviceBindingID: String = currentDeviceBindingID()
    ) -> ModelValidationResult {
        if let expectedDevice = metadata.deviceBindingID,
           !expectedDevice.isEmpty,
           expectedDevice != deviceBindingID {
            return ModelValidationResult(isValid: false, message: "模型设备绑定不匹配")
        }

        if let leaseExpiresAt = metadata.leaseExpiresAt,
           !leaseExpiresAt.isEmpty {
            let formatter = ISO8601DateFormatter()
            if let expiry = formatter.date(from: leaseExpiresAt), expiry < now {
                return ModelValidationResult(isValid: false, message: "模型离线租约已过期")
            }
        }

        return ModelValidationResult(isValid: true, message: "ok")
    }
}
