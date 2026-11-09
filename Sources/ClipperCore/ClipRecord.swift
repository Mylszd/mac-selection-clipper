import Foundation

public struct ClipRecord: Codable, Equatable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let capturedAt: Date
    public let sourceApp: String
    public let sourceBundleID: String
    public let sourceTitle: String?
    public let sourceURL: String?
    public let text: String
    public init(id: UUID = UUID(), createdAt: Date = Date(), capturedAt: Date = Date(), sourceApp: String, sourceBundleID: String, sourceTitle: String? = nil, sourceURL: String? = nil, text: String) {
        self.id = id; self.createdAt = createdAt; self.capturedAt = capturedAt
        self.sourceApp = sourceApp; self.sourceBundleID = sourceBundleID
        self.sourceTitle = sourceTitle; self.sourceURL = sourceURL; self.text = text
    }
}
