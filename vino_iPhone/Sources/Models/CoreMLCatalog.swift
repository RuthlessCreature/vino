import Foundation

public struct CoreMLModelRecord: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    public var version: String
    public var isEnabled: Bool
    public var isActive: Bool

    public init(
        id: String,
        name: String,
        version: String,
        isEnabled: Bool = true,
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.isEnabled = isEnabled
        self.isActive = isActive
    }
}

public struct CoreMLCatalog: Codable, Hashable {
    public var models: [CoreMLModelRecord]

    public init(models: [CoreMLModelRecord] = []) {
        self.models = models
    }

    public static let sample = CoreMLCatalog(models: [
        CoreMLModelRecord(id: "defect-detector-v4", name: "Defect Detector", version: "4.0.0", isEnabled: true, isActive: true),
        CoreMLModelRecord(id: "edge-segmenter-v2", name: "Edge Segmenter", version: "2.1.3", isEnabled: true, isActive: false)
    ])

    public mutating func upsert(_ model: CoreMLModelRecord) {
        if let index = models.firstIndex(where: { $0.id == model.id }) {
            models[index] = model
        } else {
            models.append(model)
        }
    }

    @discardableResult
    public mutating func remove(modelID: String) -> Bool {
        guard let index = models.firstIndex(where: { $0.id == modelID }) else {
            return false
        }

        models.remove(at: index)
        return true
    }

    public mutating func activate(modelID: String) {
        for index in models.indices {
            if models[index].id == modelID {
                models[index].isActive = true
                models[index].isEnabled = true
            }
        }
    }

    public mutating func deactivate(modelID: String) {
        guard let index = models.firstIndex(where: { $0.id == modelID }) else {
            return
        }
        models[index].isActive = false
    }

    public mutating func setEnabled(_ isEnabled: Bool, for modelID: String) {
        guard let index = models.firstIndex(where: { $0.id == modelID }) else {
            return
        }
        models[index].isEnabled = isEnabled
        if !isEnabled {
            models[index].isActive = false
        }
    }

    public var activeModels: [CoreMLModelRecord] {
        models.filter { $0.isEnabled && $0.isActive }
    }

    public var enabledModels: [CoreMLModelRecord] {
        models.filter(\.isEnabled)
    }
}
