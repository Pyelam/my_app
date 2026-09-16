import Foundation
import SwiftData
import Testing
@testable import TwigCore

@MainActor
struct NoteStoreTests {
    private func makeStore() throws -> NoteStore {
        let container = try ModelContainer(for: InspirationFolder.self, InspirationNote.self, NoteRevision.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return NoteStore(context: ModelContext(container))
    }

    @Test func movingBranchMovesDescendantsAndRejectsCycle() throws {
        let store = try makeStore()
        let folder = InspirationFolder(name: "이동할 폴더")
        store.context.insert(folder)
        let root = store.createNote(folderID: nil, notes: [])
        let child = store.createNote(folderID: nil, parentID: root.id, notes: [root])
        let notes = [root, child]
        store.move(root, folderID: nil, parentID: child.id, notes: notes)
        #expect(root.parentNoteID == nil)
        #expect(store.errorMessage != nil)
        store.move(root, folderID: folder.id, parentID: nil, notes: notes)
        #expect(root.folderID == folder.id)
        #expect(child.folderID == folder.id)
        #expect(child.parentNoteID == root.id)
    }

    @Test func movingToDeletedParentIsRejected() throws {
        let store = try makeStore()
        let root = store.createNote(folderID: nil, notes: [])
        let deleted = store.createNote(folderID: nil, notes: [root])
        store.trash(deleted, notes: [root, deleted])
        store.move(root, folderID: nil, parentID: deleted.id, notes: [root, deleted])
        #expect(root.parentNoteID == nil)
        #expect(store.errorMessage != nil)
    }

    @Test func restoringBranchDoesNotRestoreEarlierSeparateDeletion() throws {
        let store = try makeStore()
        let root = store.createNote(folderID: nil, notes: [])
        let child = store.createNote(folderID: nil, parentID: root.id, notes: [root])
        let notes = [root, child]
        store.trash(child, notes: notes)
        store.trash(root, notes: notes)
        store.restore(root, notes: notes, folders: [])
        #expect(!root.isDeleted)
        #expect(child.isDeleted)
    }

    @Test func restoringChildOfDeletedParentBecomesRootInInbox() throws {
        let store = try makeStore()
        let folder = InspirationFolder(name: "폴더")
        store.context.insert(folder)
        let root = store.createNote(folderID: folder.id, notes: [])
        let child = store.createNote(folderID: folder.id, parentID: root.id, notes: [root])
        let notes = [root, child]
        store.trashFolder(folder, notes: notes)
        store.restore(child, notes: notes, folders: [folder])
        #expect(!child.isDeleted)
        #expect(child.folderID == nil)
        #expect(child.parentNoteID == nil)
        #expect(root.isDeleted)
    }

    @Test func restoringFolderPreservesHierarchyAndEarlierTrash() throws {
        let store = try makeStore()
        let folder = InspirationFolder(name: "폴더")
        store.context.insert(folder)
        let root = store.createNote(folderID: folder.id, notes: [])
        let child = store.createNote(folderID: folder.id, parentID: root.id, notes: [root])
        let earlier = store.createNote(folderID: folder.id, notes: [root, child])
        let notes = [root, child, earlier]
        store.trash(earlier, notes: notes)
        store.trashFolder(folder, notes: notes)
        store.restoreFolder(folder, notes: notes)
        #expect(!folder.isDeleted && !root.isDeleted && !child.isDeleted)
        #expect(child.parentNoteID == root.id)
        #expect(earlier.isDeleted)
    }

    @Test func reorderOnlyChangesSiblings() throws {
        let store = try makeStore()
        let a = store.createNote(folderID: nil, notes: [])
        let b = store.createNote(folderID: nil, notes: [a])
        let child = store.createNote(folderID: nil, parentID: a.id, notes: [a, b])
        store.reorder(b, offset: -1, notes: [a, b, child])
        #expect(b.sortOrder == 0 && a.sortOrder == 1)
        #expect(child.sortOrder == 0 && child.parentNoteID == a.id)
    }

    @Test func differentEditorsKeepIndependentRecoveryCopies() throws {
        let store = try makeStore()
        let note = store.createNote(folderID: nil, notes: [])
        let session = UUID()
        #expect(store.commit(NoteDraft(content: "첫 입력"), to: note, checkpointID: session))
        #expect(store.commit(NoteDraft(content: "계속 입력"), to: note, checkpointID: session))
        #expect(store.commit(NoteDraft(content: "다른 기기 입력"), to: note))
        let history = try store.context.fetch(FetchDescriptor<NoteRevision>())
        #expect(history.count == 2)
        #expect(Set(history.map(\.content)) == Set(["계속 입력", "다른 기기 입력"]))
    }

    @Test func latestRevisionWinsEvenIfMutableNoteContainsStaleText() throws {
        let store = try makeStore()
        let note = store.createNote(folderID: nil, notes: [])
        let old = NoteRevision(noteID: note.id, draft: NoteDraft(content: "이전"))
        let new = NoteRevision(noteID: note.id, draft: NoteDraft(content: "최신"))
        old.createdAt = Date(timeIntervalSince1970: 100)
        new.createdAt = Date(timeIntervalSince1970: 200)
        note.content = "충돌로 남은 이전 본문"
        #expect(NoteStore.draft(for: note, revisions: [new, old]).content == "최신")
    }

    @Test func sameTimestampUsesDeterministicTieBreak() throws {
        let store = try makeStore()
        let note = store.createNote(folderID: nil, notes: [])
        let a = NoteRevision(noteID: note.id, draft: NoteDraft(content: "A"))
        let b = NoteRevision(noteID: note.id, draft: NoteDraft(content: "B"))
        a.createdAt = Date(timeIntervalSince1970: 100)
        b.createdAt = a.createdAt
        #expect(NoteStore.draft(for: note, revisions: [a, b]) == NoteStore.draft(for: note, revisions: [b, a]))
    }

    @Test func previousFolderOnlyStoreUpgradesWithoutDeletingFolders() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("migration.store")
        try autoreleasepool {
            let oldContainer = try ModelContainer(for: InspirationFolder.self,
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let context = ModelContext(oldContainer)
            context.insert(InspirationFolder(name: "기존 폴더"))
            try context.save()
        }
        let newContainer = try ModelContainer(for: InspirationFolder.self, InspirationNote.self, NoteRevision.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let context = ModelContext(newContainer)
        #expect(try context.fetch(FetchDescriptor<InspirationFolder>()).map(\.name) == ["기존 폴더"])
    }

    @Test func failedSaveReportsErrorWithoutDiscardingTypedText() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("readonly.store")
        try autoreleasepool {
            let container = try ModelContainer(for: InspirationFolder.self, InspirationNote.self, NoteRevision.self,
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let context = ModelContext(container)
            context.insert(InspirationNote(content: "원본"))
            try context.save()
        }
        let container = try ModelContainer(for: InspirationFolder.self, InspirationNote.self, NoteRevision.self,
            configurations: ModelConfiguration(url: url, allowsSave: false, cloudKitDatabase: .none))
        let store = NoteStore(context: ModelContext(container))
        let note = try #require(store.context.fetch(FetchDescriptor<InspirationNote>()).first)
        #expect(!store.commit(NoteDraft(content: "저장 실패해도 보존할 입력"), to: note))
        #expect(store.errorMessage != nil)
        #expect(note.content == "저장 실패해도 보존할 입력")
        #expect(store.pendingDrafts[note.id]?.content == "저장 실패해도 보존할 입력")
        #expect(store.context.hasChanges)
    }

    @Test func contentSurvivesReopeningDiskStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        try autoreleasepool {
            let container = try ModelContainer(for: InspirationFolder.self, InspirationNote.self, NoteRevision.self,
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let store = NoteStore(context: ModelContext(container))
            let note = store.createNote(folderID: nil, notes: [])
            #expect(store.commit(NoteDraft(content: "앱 종료 후에도 유지", tags: ["앱"], customDate: "2026-09-16"), to: note))
        }
        let reopened = try ModelContainer(for: InspirationFolder.self, InspirationNote.self, NoteRevision.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let context = ModelContext(reopened)
        let note = try #require(context.fetch(FetchDescriptor<InspirationNote>()).first)
        let history = try context.fetch(FetchDescriptor<NoteRevision>())
        #expect(NoteStore.draft(for: note, revisions: history).content == "앱 종료 후에도 유지")
        #expect(NoteStore.draft(for: note, revisions: history).customDate == "2026-09-16")
    }
}
