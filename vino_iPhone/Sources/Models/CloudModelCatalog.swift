import Foundation

public struct CloudModelLicense: Codable, Hashable {
    public var licenseID: String
    public var leaseExpiresAt: String?
    public var policyFlags: [String]
    public var deviceBindingRequired: Bool
    public var deviceBindingID: String?

    public init(
        licenseID: String,
        leaseExpiresAt: String? = nil,
        policyFlags: [String] = [],
        deviceBindingRequired: Bool = false,
        deviceBindingID: String? = nil
    ) {
        self.licenseID = licenseID
        self.leaseExpiresAt = leaseExpiresAt
        self.policyFlags = policyFlags
        self.deviceBindingRequired = deviceBindingRequired
        self.deviceBindingID = deviceBindingID
    }

    enum CodingKeys: String, CodingKey {
        case licenseID = "licenseId"
        case leaseExpiresAt
        case policyFlags
        case deviceBindingRequired
        case deviceBindingID = "deviceBindingId"
    }
}

public struct CloudModelDescriptor: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    public var version: String
    public var summary: String
    public var organizationID: String
    public var modelBuildID: String
    public var fileName: String
    public var sourceFormat: String
    public var transportFormat: String
    public var sha256: String
    public var byteCount: Int
    public var isEncrypted: Bool
    public var supportedPlatforms: [String]
    public var tags: [String]
    public var license: CloudModelLicense

    public init(
        id: String,
        name: String,
        version: String,
        summary: String,
        organizationID: String,
        modelBuildID: String,
        fileName: String,
        sourceFormat: String,
        transportFormat: String,
        sha256: String,
        byteCount: Int,
        isEncrypted: Bool,
        supportedPlatforms: [String],
        tags: [String],
        license: CloudModelLicense
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.summary = summary
        self.organizationID = organizationID
        self.modelBuildID = modelBuildID
        self.fileName = fileName
        self.sourceFormat = sourceFormat
        self.transportFormat = transportFormat
        self.sha256 = sha256
        self.byteCount = byteCount
        self.isEncrypted = isEncrypted
        self.supportedPlatforms = supportedPlatforms
        self.tags = tags
        self.license = license
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case version
        case summary
        case organizationID = "organizationId"
        case modelBuildID = "modelBuildId"
        case fileName
        case sourceFormat
        case transportFormat
        case sha256
        case byteCount
        case isEncrypted
        case supportedPlatforms
        case tags
        case license
    }
}

public struct CloudModelCatalog: Codable, Hashable {
    public var models: [CloudModelDescriptor]
    public var syncedAt: String?

    public init(models: [CloudModelDescriptor] = [], syncedAt: String? = nil) {
        self.models = models
        self.syncedAt = syncedAt
    }
}

public struct CloudModelCatalogResponse: Codable, Hashable {
    public var models: [CloudModelDescriptor]
    public var syncedAt: String?
}

public struct CloudModelEncryptionDescriptor: Codable, Hashable {
    public var envelope: String
    public var algorithm: String
    public var keyDerivation: String
    public var ticketSecret: String

    public init(
        envelope: String,
        algorithm: String,
        keyDerivation: String,
        ticketSecret: String
    ) {
        self.envelope = envelope
        self.algorithm = algorithm
        self.keyDerivation = keyDerivation
        self.ticketSecret = ticketSecret
    }
}

public struct ModelDownloadTicketResponse: Codable, Hashable {
    public var ticketID: String
    public var modelID: String
    public var downloadURL: String
    public var expiresAt: String
    public var fileName: String
    public var sourceFormat: String
    public var transportFormat: String
    public var sha256: String
    public var byteCount: Int
    public var modelBuildID: String
    public var organizationID: String
    public var isEncrypted: Bool
    public var license: CloudModelLicense
    public var encryption: CloudModelEncryptionDescriptor?

    enum CodingKeys: String, CodingKey {
        case ticketID = "ticketId"
        case modelID = "modelId"
        case downloadURL
        case expiresAt
        case fileName
        case sourceFormat
        case transportFormat
        case sha256
        case byteCount
        case modelBuildID = "modelBuildId"
        case organizationID = "organizationId"
        case isEncrypted
        case license
        case encryption
    }
}

public struct LeaseRenewalResponse: Codable, Hashable {
    public var modelID: String
    public var licenseID: String
    public var leaseExpiresAt: String?
    public var policyFlags: [String]
    public var deviceBindingID: String?

    enum CodingKeys: String, CodingKey {
        case modelID = "modelId"
        case licenseID = "licenseId"
        case leaseExpiresAt
        case policyFlags
        case deviceBindingID = "deviceBindingId"
    }
}
