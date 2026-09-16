import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var context
    var body: some View { WorkspaceView(context: context) }
}

enum WorkspaceSection: Hashable {
    case home, inbox, all, trash, folder(UUID)
}

struct WorkspaceView: View {
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \InspirationFolder.sortOrder) private var folders: [InspirationFolder]
    @Query private var notes: [InspirationNote]
    @Query private var revisions: [NoteRevision]
    @State private var store: NoteStore
    @State private var section: WorkspaceSection? = .home
    @State private var selectedNoteID: UUID?
    @State private var pendingCaptureID: UUID?
    @State private var preferredColumn: NavigationSplitViewColumn = .detail
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var editingNoteID: UUID?
    @State private var didChooseInitialFolder = false
    @State private var showingFolderForm = false
    @State private var editingFolder: InspirationFolder?
    @State private var deletingFolder: InspirationFolder?
    @State private var showingQuickCapture = false
    @State private var showingExport = false
    @State private var exportDocument = MarkdownDocument(text: "")

    init(context: ModelContext) {
        _store = State(initialValue: NoteStore(context: context))
    }

    private var activeFolders: [InspirationFolder] { folders.filter { !$0.isDeleted } }
    private var selectedNote: InspirationNote? { notes.first { $0.id == selectedNoteID && !$0.isDeleted } }
    private var selectedFolder: InspirationFolder? {
        if case .folder(let id) = section { return activeFolders.first { $0.id == id } }
        return nil
    }
    private var boardNotes: [InspirationNote] {
        notes.filter { note in
            guard !note.isDeleted else { return false }
            if case .folder(let id) = section { return note.folderID == id }
            return note.folderID == nil || !activeFolders.contains { $0.id == note.folderID }
        }
    }
    private var showsBoard: Bool {
        if case .folder = section { return true }
        return section == .inbox
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredColumn) {
            sidebar
        } detail: {
            workspaceSurface
        }
        .tint(BoardStyle.ink(scheme))
        .onChange(of: section) { _, _ in
            if let pendingCaptureID {
                selectedNoteID = pendingCaptureID
                self.pendingCaptureID = nil
                preferredColumn = .detail
            } else {
                selectedNoteID = showsBoard ? NoteStore.sorted(boardNotes).first?.id : nil
                preferredColumn = .detail
            }
        }
        .task {
            guard !didChooseInitialFolder else { return }
            didChooseInitialFolder = true
            section = activeFolders.first.map { .folder($0.id) } ?? .inbox
        }
        .sheet(isPresented: $showingFolderForm) {
            FolderFormView(folder: editingFolder, store: store, nextOrder: folders.count) { folder in
                section = .folder(folder.id)
            }
        }
        .sheet(isPresented: $showingQuickCapture) {
            QuickCaptureView(folders: activeFolders, notes: notes, store: store) { note in
                let destination = note.folderID.map(WorkspaceSection.folder) ?? .inbox
                if section == destination {
                    openNote(note)
                } else {
                    pendingCaptureID = note.id
                    section = destination
                }
            }
        }
        .sheet(isPresented: Binding(get: { editingNoteID != nil }, set: { if !$0 { editingNoteID = nil } })) {
            NavigationStack {
                if let note = notes.first(where: { $0.id == editingNoteID && !$0.isDeleted }) {
                    NoteEditorView(note: note, folders: activeFolders, notes: notes, revisions: revisions, store: store) { next in
                        openNote(next)
                        editingNoteID = next.id
                    }
                    .id(note.id)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("완료") { editingNoteID = nil } }
                    }
                } else {
                    ContentUnavailableView("메모가 휴지통으로 이동했습니다", systemImage: "trash")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { editingNoteID = nil } } }
                }
            }
            .editorSheetSize(minHeight: 600)
        }
        .confirmationDialog("폴더를 휴지통으로 이동할까요?", isPresented: Binding(
            get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } }
        ), titleVisibility: .visible) {
            Button("폴더와 메모를 휴지통으로 이동", role: .destructive) {
                if let folder = deletingFolder { store.trashFolder(folder, notes: notes); section = .home }
                deletingFolder = nil
            }
        } message: {
            Text("폴더 안의 모든 가지 메모도 함께 이동합니다. 휴지통에서 복구할 수 있으며 자동으로 영구 삭제하지 않습니다.")
        }
        .alert("작업을 완료하지 못했습니다", isPresented: Binding(
            get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("다시 저장") { store.errorMessage = nil; store.retryPending() }
            Button("닫기", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .fileExporter(isPresented: $showingExport, document: exportDocument,
                      contentType: .plainText, defaultFilename: "Twig-전체메모.md") { result in
            if case .failure(let error) = result { store.errorMessage = error.localizedDescription }
        }
    }

    private var workspaceSurface: some View {
        VStack(spacing: 0) {
            InlineCaptureBar(notes: notes, store: store)
            Divider()
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    if showsBoard {
                        InspirationBoardView(title: selectedFolder?.name ?? "수집함", folder: selectedFolder,
                            notes: boardNotes, revisions: revisions, selectedNoteID: selectedNoteID, store: store,
                            select: openNote, edit: editNote,
                            editFolder: { editingFolder = selectedFolder; showingFolderForm = true },
                            allFolders: folders, allNotes: notes)
                    } else {
                        NoteBrowserView(section: section ?? .home, folders: folders, notes: notes, revisions: revisions,
                                        store: store, selectedNoteID: $selectedNoteID, openNote: openNote)
                    }
                    if let note = selectedNote {
                        Divider()
                        SelectedNotePanel(note: note, notes: notes, revisions: revisions, store: store,
                                          edit: { editNote(note) }, select: openNote)
                            .id(note.id)
                            .frame(height: min(320, max(140, geometry.size.height * 0.37)))
                    }
                }
            }
        }
        .background(BoardStyle.paper(scheme))
        .navigationTitle("Twig")
        .toolbar {
            ToolbarItem {
                Button("새 폴더", systemImage: "folder.badge.plus") { editingFolder = nil; showingFolderForm = true }
            }
            if showsBoard {
                ToolbarItem {
                    Button("메모 검색", systemImage: "magnifyingglass") { section = .all }
                }
            }
        }
    }

    private func editNote(_ note: InspirationNote) {
        openNote(note)
        editingNoteID = note.id
    }

    private var sidebar: some View {
        List(selection: $section) {
            Section {
                Button { showingQuickCapture = true } label: {
                    Label("빠른 영감 기록", systemImage: "square.and.pencil").padding(.vertical, 6)
                }.keyboardShortcut("n", modifiers: .command)
                NavigationLink(value: WorkspaceSection.home) { Label("홈", systemImage: "house") }
                NavigationLink(value: WorkspaceSection.inbox) {
                    Label("수집함 · \(notes.filter { !$0.isDeleted && $0.folderID == nil }.count)", systemImage: "tray")
                }
                NavigationLink(value: WorkspaceSection.all) { Label("전체 메모 검색", systemImage: "magnifyingglass") }
            }
            Section("영감 폴더") {
                ForEach(activeFolders) { folder in
                    NavigationLink(value: WorkspaceSection.folder(folder.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(folder.name, systemImage: "folder")
                            Text("\(notes.filter { !$0.isDeleted && $0.folderID == folder.id }.count)개의 생각")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 3)
                    }
                    .listRowBackground((FolderTheme(rawValue: folder.theme) ?? .default).color.opacity(0.07))
                    .contextMenu {
                        Button("이름 및 테마 수정", systemImage: "pencil") { editingFolder = folder; showingFolderForm = true }
                        Button("휴지통으로 이동", systemImage: "trash", role: .destructive) { deletingFolder = folder }
                    }
                }
                Button("새 폴더", systemImage: "folder.badge.plus") { editingFolder = nil; showingFolderForm = true }
            }
            if !activeFolders.isEmpty {
                Section("최근 수정한 폴더") {
                    ForEach(Array(activeFolders.sorted { $0.updatedAt > $1.updatedAt }.prefix(3))) { folder in
                        NavigationLink(folder.name, value: WorkspaceSection.folder(folder.id))
                    }
                }
            }
            if let note = notes.filter({ !$0.isDeleted }).min(by: { $0.updatedAt < $1.updatedAt }) {
                Section("다시 꺼내볼 영감") {
                    Button { openNote(note) } label: {
                        Label(NoteStore.draft(for: note, revisions: revisions).label, systemImage: "sparkles")
                            .lineLimit(3)
                    }
                }
            }
            Section {
                NavigationLink(value: WorkspaceSection.trash) { Label("휴지통", systemImage: "trash") }
                Button("전체 메모 내보내기", systemImage: "square.and.arrow.up") {
                    exportDocument = MarkdownDocument(text: MarkdownDocument.export(folders: folders, notes: notes, revisions: revisions))
                    showingExport = true
                }
                Text(StorageConfiguration.status).font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Twig")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    }

    private func openNote(_ note: InspirationNote) {
        var parentID = note.parentNoteID
        var visited: Set<UUID> = [note.id]
        var expanded = false
        while let id = parentID, visited.insert(id).inserted,
              let parent = notes.first(where: { $0.id == id && !$0.isDeleted }) {
            if parent.isCollapsed { parent.isCollapsed = false; expanded = true }
            parentID = parent.parentNoteID
        }
        if expanded { store.save() }
        selectedNoteID = note.id
        preferredColumn = .detail
    }
}

#Preview {
    ContentView().modelContainer(for: [InspirationFolder.self, InspirationNote.self, NoteRevision.self], inMemory: true)
}
