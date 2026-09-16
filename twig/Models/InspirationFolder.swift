import Foundation
import SwiftData

@Model
final class InspirationFolder {
    var id: UUID = UUID()
    var name: String = ""
    var theme: String = "default"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortOrder: Int = 0
    var isDeleted: Bool = false
    var deletedAt: Date?

    init(name: String, sortOrder: Int = 0) {
        let now = Date()
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = now
        self.updatedAt = now
    }
}
