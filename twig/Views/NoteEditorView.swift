import SwiftUI

struct NoteEditorView: View {
    @Environment(\.scenePhase) private var scenePhase
    let note: InspirationNote
    let folders: [InspirationFolder]
    let notes: [InspirationNote]
    let revisions: [NoteRevision]
    let store: NoteStore
    let openNote: (InspirationNote) -> Void
    @State private var draft: NoteDraft
    @State private var lastSaved: NoteDraft
    @State private var tagText: String
    @State private var saveFailed = false
    @State private var showingMove = false
    @State private var showingHistory = false
    @State private var showingDelete = false
    @State private var receivedEdit = false
    @State private var checkpointID = UUID()
    @State private var checkpointStarted = Date()

    init(note: InspirationNote, folders: [InspirationFolder], notes: [InspirationNote],
         revisions: [NoteRevision], store: NoteStore, openNote: @escaping (InspirationNote) -> Void) {
        self.note = note
        self.folders = folders
        self.notes = notes
        self.revisions = revisions
        self.store = store
        self.openNote = openNote
        let saved = NoteStore.draft(for: note, revisions: revisions)
        let initial = store.pendingDrafts[note.id] ?? saved
        _draft = State(initialValue: initial)
        _lastSaved = State(initialValue: saved)
        _saveFailed = State(initialValue: store.pendingDrafts[note.id] != nil)
        _tagText = State(initialValue: initial.tags.joined(separator: " "))
    }

    private var incoming: NoteDraft { NoteStore.draft(for: note, revisions: revisions) }
    private var children: [InspirationNote] { NoteStore.sorted(notes.filter { !$0.isDeleted && $0.parentNoteID == note.id }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if saveFailed {
                HStack {
                    Label("저장 실패 · 입력 내용을 유지하고 있습니다", systemImage: "exclamationmark.triangle")
                    Button("다시 저장") { persist() }
                }.font(.callout).padding()
            }
            if receivedEdit {
                HStack {
                    Text("다른 편집 내용이 반영되었습니다. 이전 글은 편집 기록에서 확인할 수 있습니다.")
                    Button("확인") { receivedEdit = false }
                }.font(.caption).padding()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    location
                    TextField("제목 (선택)", text: $draft.title, axis: .vertical)
                        .font(.title2).textFieldStyle(.plain)
                        .accessibilityLabel("메모 제목, 선택 사항")
                    ZStack(alignment: .topLeading) {
                        if draft.content.isEmpty {
                            Text("지금 떠오른 생각을 적어 보세요.")
                                .foregroundStyle(.secondary).padding(.top, 8).padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $draft.content)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 300)
                            .accessibilityLabel("메모 본문")
                    }
                    Divider()
                    TextField("태그 · 공백 또는 쉼표로 구분", text: $tagText)
                        .onChange(of: tagText) { _, text in draft.tags = NoteDraft.normalizedTags(text) }
                    Toggle("사용자 지정 날짜", isOn: Binding(
                        get: { draft.customDate != nil },
                        set: { draft.customDate = $0 ? CalendarDay.string(Date()) : nil }
                    ))
                    if draft.customDate != nil {
                        DatePicker("날짜", selection: Binding(
                            get: { CalendarDay.date(draft.customDate ?? "") ?? Date() },
                            set: { draft.customDate = CalendarDay.string($0) }
                        ), displayedComponents: .date)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("작성 \(note.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        Text("수정 \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        Label(saveFailed ? "저장 대기" : "기기에 저장됨", systemImage: saveFailed ? "clock" : "checkmark.circle")
                    }.font(.caption).foregroundStyle(.secondary)
                    if !children.isEmpty {
                        Divider()
                        Text("하위 가지").font(.headline)
                        ForEach(children) { child in
                            Button { openNote(child) } label: {
                                Label(NoteStore.draft(for: child, revisions: revisions).label, systemImage: "arrow.turn.down.right")
                            }.padding(.vertical, 5)
                        }
                    }
                }.padding()
            }
        }
        .navigationTitle("영감 편집")
        .toolbar {
            ToolbarItem {
                Button("가지 만들기", systemImage: "plus") {
                    openNote(store.createNote(folderID: note.folderID, parentID: note.id, notes: notes))
                }
            }
            ToolbarItem {
                Menu("메모 작업", systemImage: "ellipsis.circle") {
                    Button("폴더 또는 부모 변경", systemImage: "arrow.turn.up.right") { showingMove = true }
                    Button("위로 이동", systemImage: "arrow.up") { store.reorder(note, offset: -1, notes: notes) }
                    Button("아래로 이동", systemImage: "arrow.down") { store.reorder(note, offset: 1, notes: notes) }
                    Button("편집 기록", systemImage: "clock.arrow.circlepath") { showingHistory = true }
                    Button("휴지통으로 이동", systemImage: "trash", role: .destructive) { showingDelete = true }
                }
            }
        }
        .onChange(of: draft) { _, _ in persist() }
        .onChange(of: store.pendingDrafts[note.id]) { _, pending in
            if pending == nil && saveFailed { saveFailed = false; lastSaved = draft }
        }
        .onChange(of: incoming) { _, value in
            guard value != draft, !saveFailed else { return }
            receivedEdit = true
            checkpointID = UUID()
            checkpointStarted = Date()
            lastSaved = value
            draft = value
            tagText = value.tags.joined(separator: " ")
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { persist() } }
        .onDisappear { persist() }
        .sheet(isPresented: $showingMove) {
            MoveNoteView(note: note, folders: folders, notes: notes, revisions: revisions, store: store)
        }
        .sheet(isPresented: $showingHistory) {
            RevisionHistoryView(revisions: revisions.filter { $0.noteID == note.id }) { revision in
                let previousDraft = draft
                let restoredDraft = NoteDraft(
                    title: revision.title,
                    content: revision.content,
                    tags: revision.tagNames,
                    customDate: revision.customDate
                )
                checkpointID = UUID()
                checkpointStarted = Date()
                if store.commit(restoredDraft, to: note, checkpointID: checkpointID) {
                    lastSaved = restoredDraft
                    draft = restoredDraft
                    tagText = restoredDraft.tags.joined(separator: " ")
                    store.offerRevisionRestoreUndo(previousDraft, for: note)
                } else {
                    saveFailed = true
                }
            }
        }
        .confirmationDialog("메모와 하위 가지를 휴지통으로 이동할까요?", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("휴지통으로 이동", role: .destructive) { store.trash(note, notes: notes) }
        } message: { Text("휴지통에서 복구할 수 있습니다.") }
    }

    private var location: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(folders.first { $0.id == note.folderID }?.name ?? "수집함", systemImage: "folder")
                .font(.caption).foregroundStyle(.secondary)
            if let parent = notes.first(where: { $0.id == note.parentNoteID && !$0.isDeleted }) {
                Button { openNote(parent) } label: {
                    Label(NoteStore.draft(for: parent, revisions: revisions).label, systemImage: "arrow.up")
                        .font(.caption).lineLimit(2)
                }
            }
        }
    }

    private func persist() {
        guard draft != lastSaved || saveFailed else { return }
        // Persist every change, but group recovery history into 30-second typing checkpoints.
        if Date().timeIntervalSince(checkpointStarted) >= 30 {
            checkpointID = UUID()
            checkpointStarted = Date()
        }
        if store.commit(draft, to: note, checkpointID: checkpointID) { lastSaved = draft; saveFailed = false }
        else { saveFailed = true }
    }
}

struct RevisionHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let revisions: [NoteRevision]
    let restore: (NoteRevision) -> Void
    @State private var selected: NoteRevision?

    var body: some View {
        NavigationStack {
            List {
                Text("이전 글을 선택해 복구하면 새로운 편집 기록으로 저장합니다. 기존 기록도 유지됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(revisions.sorted { $0.createdAt > $1.createdAt }) { revision in
                    Button { selected = revision } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(revision.createdAt.formatted(date: .abbreviated, time: .standard)).font(.caption)
                            Text(revision.title.isEmpty ? String(revision.content.prefix(120)) : revision.title).lineLimit(3)
                            Text(revision.sourceInstallationID.isEmpty
                                 ? "기존 편집 기록"
                                 : (revision.sourceInstallationID == InstallationIdentity.current ? "이 기기" : "다른 기기"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if revisions.isEmpty { Text("아직 편집 기록이 없습니다.") }
            }
            .navigationTitle("편집 기록")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
            .sheet(item: $selected) { revision in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(revision.title).font(.title2)
                            Text(revision.content).textSelection(.enabled)
                            Text(revision.tagNames.map { "#" + $0 }.joined(separator: " ")).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding()
                    }
                    .navigationTitle("이전 내용")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("닫기") { selected = nil } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("이 내용으로 복구") { restore(revision); selected = nil; dismiss() }
                        }
                    }
                }.editorSheetSize(minHeight: 400)
            }
        }.editorSheetSize(minHeight: 420)
    }
}
