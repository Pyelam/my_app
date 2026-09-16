import SwiftUI

struct MoveNoteView: View {
    @Environment(\.dismiss) private var dismiss
    let note: InspirationNote
    let folders: [InspirationFolder]
    let notes: [InspirationNote]
    let revisions: [NoteRevision]
    let store: NoteStore
    @State private var folderID: UUID?
    @State private var parentID: UUID?

    init(note: InspirationNote, folders: [InspirationFolder], notes: [InspirationNote], revisions: [NoteRevision], store: NoteStore) {
        self.note = note
        self.folders = folders
        self.notes = notes
        self.revisions = revisions
        self.store = store
        _folderID = State(initialValue: note.folderID)
        _parentID = State(initialValue: note.parentNoteID)
    }

    private var candidates: [InspirationNote] {
        let excluded = NoteStore.descendants(of: note.id, notes: notes)
        return NoteStore.sorted(notes.filter { !$0.isDeleted && $0.folderID == folderID && !excluded.contains($0.id) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("폴더", selection: $folderID) {
                    Text("수집함").tag(nil as UUID?)
                    ForEach(folders.filter { !$0.isDeleted }) { folder in Text(folder.name).tag(Optional(folder.id)) }
                }.onChange(of: folderID) { _, _ in parentID = nil }
                Picker("부모 메모", selection: $parentID) {
                    Text("최상위 영감").tag(nil as UUID?)
                    ForEach(candidates) { candidate in
                        Text(NoteStore.draft(for: candidate, revisions: revisions).label).tag(Optional(candidate.id))
                    }
                }
                Text("하위 가지도 함께 이동합니다.").font(.caption).foregroundStyle(.secondary)
                if let error = store.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .navigationTitle("가지 이동")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("이동") {
                        store.move(note, folderID: folderID, parentID: parentID, notes: notes)
                        if store.errorMessage == nil { dismiss() }
                    }
                }
            }
        }.editorSheetSize(minHeight: 300)
    }
}
