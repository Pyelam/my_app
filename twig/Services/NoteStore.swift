import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class NoteStore {
    let context: ModelContext
    var errorMessage: String?
    private(set) var pendingDrafts: [UUID: NoteDraft] = [:]
    private var pendingCheckpoints: [UUID: UUID] = [:]

    init(context: ModelContext) { self.context = context }

    @discardableResult
    func save() -> Bool {
        do {
            try context.save()
            errorMessage = nil
            return true
        } catch {
            errorMessage = "저장하지 못했습니다. 입력 내용은 현재 화면에 유지됩니다. 저장 공간을 확인한 후 다시 시도해 주세요.\n\(error.localizedDescription)"
            return false
        }
    }

    static func draft(for note: InspirationNote, revisions: [NoteRevision]) -> NoteDraft {
        let latest = revisions.filter { $0.noteID == note.id }.max {
            if $0.createdAt == $1.createdAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.createdAt < $1.createdAt
        }
        if let latest {
            return NoteDraft(title: latest.title, content: latest.content,
                             tags: latest.tagNames, customDate: latest.customDate)
        }
        return NoteDraft(title: note.title, content: note.content,
                         tags: note.tagNames, customDate: note.customDate)
    }

    func commit(_ draft: NoteDraft, to note: InspirationNote, checkpointID: UUID = UUID()) -> Bool {
        // Keep failed edits beyond the editor view's lifetime so navigation cannot discard them.
        pendingDrafts[note.id] = draft
        pendingCheckpoints[note.id] = checkpointID
        // A checkpoint belongs to one editor session, so other devices' copies stay intact.
        do {
            let history = try context.fetch(FetchDescriptor<NoteRevision>())
            if let checkpoint = history.first(where: { $0.id == checkpointID && $0.noteID == note.id }) {
                checkpoint.title = draft.title
                checkpoint.content = draft.content
                checkpoint.tagNames = draft.tags
                checkpoint.customDate = draft.customDate
                checkpoint.createdAt = Date()
            } else {
                context.insert(NoteRevision(noteID: note.id, draft: draft, id: checkpointID))
            }
        } catch {
            errorMessage = "편집 기록을 저장하지 못했습니다. \(error.localizedDescription)"
            return false
        }
        note.title = draft.title
        note.content = draft.content
        note.tagNames = draft.tags
        note.customDate = draft.customDate
        note.updatedAt = Date()
        touchFolder(note.folderID)
        let saved = save()
        if saved {
            pendingDrafts.removeValue(forKey: note.id)
            pendingCheckpoints.removeValue(forKey: note.id)
        }
        return saved
    }

    func retryPending() {
        do {
            let notes = try context.fetch(FetchDescriptor<InspirationNote>())
            for (id, draft) in pendingDrafts {
                guard let note = notes.first(where: { $0.id == id }) else { continue }
                if !commit(draft, to: note, checkpointID: pendingCheckpoints[id] ?? UUID()) { return }
            }
            save()
        } catch { errorMessage = error.localizedDescription }
    }

    func touchFolder(_ id: UUID?) {
        guard let id else { return }
        do {
            let folders = try context.fetch(FetchDescriptor<InspirationFolder>())
            folders.first { $0.id == id }?.updatedAt = Date()
        } catch { errorMessage = error.localizedDescription }
    }

    func createNote(folderID: UUID?, parentID: UUID? = nil, notes: [InspirationNote]) -> InspirationNote {
        let order = notes.filter { !$0.isDeleted && $0.folderID == folderID && $0.parentNoteID == parentID }
            .map(\.sortOrder).max() ?? -1
        let note = InspirationNote(folderID: folderID, parentNoteID: parentID, sortOrder: order + 1)
        context.insert(note)
        if let parentID { notes.first { $0.id == parentID }?.isCollapsed = false }
        touchFolder(folderID)
        save()
        return note
    }

    static func descendants(of id: UUID, notes: [InspirationNote]) -> Set<UUID> {
        TreeTopology.descendants(of: id, nodes: notes.map { TreeNode(id: $0.id, parentID: $0.parentNoteID) })
    }

    func move(_ note: InspirationNote, folderID: UUID?, parentID: UUID?, notes: [InspirationNote]) {
        let branch = Self.descendants(of: note.id, notes: notes)
        if let parentID {
            guard !branch.contains(parentID),
                  notes.contains(where: { $0.id == parentID && !$0.isDeleted && $0.folderID == folderID }) else {
                errorMessage = "자기 자신이나 하위 가지로 이동할 수 없습니다."
                return
            }
        }
        let oldFolder = note.folderID
        note.parentNoteID = parentID
        note.sortOrder = (notes.filter { !$0.isDeleted && $0.folderID == folderID && $0.parentNoteID == parentID }
            .map(\.sortOrder).max() ?? -1) + 1
        for member in notes where branch.contains(member.id) {
            member.folderID = folderID
            member.updatedAt = Date()
        }
        if let parentID { notes.first { $0.id == parentID }?.isCollapsed = false }
        touchFolder(oldFolder)
        touchFolder(folderID)
        save()
    }

    func reorder(_ note: InspirationNote, offset: Int, notes: [InspirationNote]) {
        var siblings = Self.sorted(notes.filter {
            !$0.isDeleted && $0.folderID == note.folderID && $0.parentNoteID == note.parentNoteID
        })
        guard let index = siblings.firstIndex(where: { $0.id == note.id }),
              siblings.indices.contains(index + offset) else { return }
        siblings.swapAt(index, index + offset)
        for (index, sibling) in siblings.enumerated() { sibling.sortOrder = index }
        touchFolder(note.folderID)
        save()
    }

    func trash(_ note: InspirationNote, notes: [InspirationNote]) {
        let branch = Self.descendants(of: note.id, notes: notes)
        let batch = UUID()
        let now = Date()
        for member in notes where branch.contains(member.id) && !member.isDeleted {
            member.isDeleted = true
            member.deletedAt = now
            member.deletionBatchID = batch
        }
        touchFolder(note.folderID)
        save()
    }

    func trashFolder(_ folder: InspirationFolder, notes: [InspirationNote]) {
        folder.isDeleted = true
        folder.deletedAt = Date()
        for note in notes where note.folderID == folder.id && !note.isDeleted {
            note.isDeleted = true
            note.deletedAt = folder.deletedAt
            note.deletionBatchID = folder.id
        }
        save()
    }

    func restore(_ note: InspirationNote, notes: [InspirationNote], folders: [InspirationFolder]) {
        let branch = Self.descendants(of: note.id, notes: notes)
        let batch = note.deletionBatchID
        let restoring = notes.filter { branch.contains($0.id) && $0.isDeleted && $0.deletionBatchID == batch }
        let ids = Set(restoring.map(\.id))
        for member in restoring {
            member.isDeleted = false
            member.deletedAt = nil
            member.deletionBatchID = nil
            if !folders.contains(where: { $0.id == member.folderID && !$0.isDeleted }) { member.folderID = nil }
            if let parent = member.parentNoteID,
               !ids.contains(parent) && !notes.contains(where: {
                   $0.id == parent && !$0.isDeleted && $0.folderID == member.folderID
               }) { member.parentNoteID = nil }
        }
        save()
    }

    func restoreFolder(_ folder: InspirationFolder, notes: [InspirationNote]) {
        folder.isDeleted = false
        folder.deletedAt = nil
        for note in notes where note.deletionBatchID == folder.id {
            note.isDeleted = false
            note.deletedAt = nil
            note.deletionBatchID = nil
        }
        save()
    }

    static func sorted(_ notes: [InspirationNote]) -> [InspirationNote] {
        notes.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
