import Foundation
import SwiftData

@Model
final class InspirationNote {
    var id: UUID = UUID()
    var folderID: UUID?
    var parentNoteID: UUID?
    var title: String = ""
    var content: String = ""
    var tagNames: [String] = []
    // Calendar date, not a timestamp: stays the same when the time zone changes.
    var customDate: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortOrder: Int = 0
    var isCollapsed: Bool = false
    var isDeleted: Bool = false
    var deletedAt: Date?
    var deletionBatchID: UUID?

    init(folderID: UUID? = nil, parentNoteID: UUID? = nil, content: String = "", sortOrder: Int = 0) {
        self.folderID = folderID
        self.parentNoteID = parentNoteID
        self.content = content
        self.sortOrder = sortOrder
        let now = Date()
        createdAt = now
        updatedAt = now
    }
}

// Each editor owns its checkpoint ID. Other editors/devices create separate records.
@Model
final class NoteRevision {
    var id: UUID = UUID()
    var noteID: UUID = UUID()
    var title: String = ""
    var content: String = ""
    var tagNames: [String] = []
    var customDate: String?
    var createdAt: Date = Date()

    init(noteID: UUID, draft: NoteDraft, id: UUID = UUID()) {
        self.id = id
        self.noteID = noteID
        title = draft.title
        content = draft.content
        tagNames = draft.tags
        customDate = draft.customDate
    }
}

struct NoteDraft: Equatable {
    var title = ""
    var content = ""
    var tags: [String] = []
    var customDate: String?

    var label: String {
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !heading.isEmpty { return heading }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "새 영감" : String(text.prefix(100))
    }

    static func normalizedTags(_ text: String) -> [String] {
        Array(Set(text.split { $0.isWhitespace || $0 == "," || $0 == "#" }
            .map { String($0).lowercased() })).sorted()
    }
}
