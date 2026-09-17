import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class NoteStore {
    let context: ModelContext
    var errorMessage: String?
    private(set) var pendingDrafts: [UUID: NoteDraft] = [:]
    private(set) var undoMessage: String?
    private var pendingCheckpoints: [UUID: UUID] = [:]
    @ObservationIgnored private var undoOperation: (() -> Void)?

    init(context: ModelContext) { self.context = context }

    func undoLastAction() {
        guard let undoOperation else { return }
        self.undoOperation = nil
        undoMessage = nil
        undoOperation()
        save()
    }

    func dismissUndo() {
        undoMessage = nil
        undoOperation = nil
    }

    func offerRevisionRestoreUndo(_ previousDraft: NoteDraft, for note: InspirationNote) {
        offerUndo("편집 기록을 복구했습니다") { [weak self] in
            guard let self else { return }
            _ = self.commit(previousDraft, to: note)
        }
    }

    private func offerUndo(_ message: String, operation: @escaping () -> Void) {
        undoMessage = message
        undoOperation = operation
    }

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
        let placements = notes.filter { branch.contains($0.id) }.map {
            NotePlacement(note: $0, folderID: $0.folderID, parentNoteID: $0.parentNoteID,
                          sortOrder: $0.sortOrder, updatedAt: $0.updatedAt)
        }
        let expandedParent = parentID.flatMap { id in notes.first { $0.id == id } }
        let parentWasCollapsed = expandedParent?.isCollapsed
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
        if save() {
            offerUndo("가지를 이동했습니다") { [weak self] in
                for placement in placements {
                    placement.note.folderID = placement.folderID
                    placement.note.parentNoteID = placement.parentNoteID
                    placement.note.sortOrder = placement.sortOrder
                    placement.note.updatedAt = placement.updatedAt
                }
                if let expandedParent, let parentWasCollapsed {
                    expandedParent.isCollapsed = parentWasCollapsed
                }
                self?.touchFolder(oldFolder)
                self?.touchFolder(folderID)
            }
        }
    }

    func reorder(_ note: InspirationNote, offset: Int, notes: [InspirationNote]) {
        var siblings = Self.sorted(notes.filter {
            !$0.isDeleted && $0.folderID == note.folderID && $0.parentNoteID == note.parentNoteID
        })
        guard let index = siblings.firstIndex(where: { $0.id == note.id }),
              siblings.indices.contains(index + offset) else { return }
        let previousOrders = siblings.map { ($0, $0.sortOrder) }
        siblings.swapAt(index, index + offset)
        for (index, sibling) in siblings.enumerated() { sibling.sortOrder = index }
        touchFolder(note.folderID)
        if save() {
            offerUndo("가지 순서를 변경했습니다") { [weak self] in
                for (sibling, order) in previousOrders { sibling.sortOrder = order }
                self?.touchFolder(note.folderID)
            }
        }
    }

    func trash(_ note: InspirationNote, notes: [InspirationNote]) {
        let branch = Self.descendants(of: note.id, notes: notes)
        let previousStates = notes.filter { branch.contains($0.id) }.map {
            NoteDeletion(note: $0, isDeleted: $0.isDeleted, deletedAt: $0.deletedAt,
                         deletionBatchID: $0.deletionBatchID)
        }
        let batch = UUID()
        let now = Date()
        for member in notes where branch.contains(member.id) && !member.isDeleted {
            member.isDeleted = true
            member.deletedAt = now
            member.deletionBatchID = batch
        }
        touchFolder(note.folderID)
        if save() {
            offerUndo("가지와 하위 가지를 휴지통으로 이동했습니다") { [weak self] in
                for state in previousStates {
                    state.note.isDeleted = state.isDeleted
                    state.note.deletedAt = state.deletedAt
                    state.note.deletionBatchID = state.deletionBatchID
                }
                self?.touchFolder(note.folderID)
            }
        }
    }

    func trashFolder(_ folder: InspirationFolder, notes: [InspirationNote]) {
        let folderWasDeleted = folder.isDeleted
        let folderDeletedAt = folder.deletedAt
        let previousStates = notes.filter { $0.folderID == folder.id }.map {
            NoteDeletion(note: $0, isDeleted: $0.isDeleted, deletedAt: $0.deletedAt,
                         deletionBatchID: $0.deletionBatchID)
        }
        folder.isDeleted = true
        folder.deletedAt = Date()
        for note in notes where note.folderID == folder.id && !note.isDeleted {
            note.isDeleted = true
            note.deletedAt = folder.deletedAt
            note.deletionBatchID = folder.id
        }
        if save() {
            offerUndo("폴더와 메모를 휴지통으로 이동했습니다") {
                folder.isDeleted = folderWasDeleted
                folder.deletedAt = folderDeletedAt
                for state in previousStates {
                    state.note.isDeleted = state.isDeleted
                    state.note.deletedAt = state.deletedAt
                    state.note.deletionBatchID = state.deletionBatchID
                }
            }
        }
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

private struct NotePlacement {
    let note: InspirationNote
    let folderID: UUID?
    let parentNoteID: UUID?
    let sortOrder: Int
    let updatedAt: Date
}

private struct NoteDeletion {
    let note: InspirationNote
    let isDeleted: Bool
    let deletedAt: Date?
    let deletionBatchID: UUID?
}
