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
    @Query(sort: \InspirationFolder.sortOrder) private var folders: [InspirationFolder]
    @Query private var notes: [InspirationNote]
    @Query private var revisions: [NoteRevision]
    @State private var store: NoteStore
    @State private var section: WorkspaceSection? = .home
    @State private var selectedNoteID: UUID?
    @State private var pendingCaptureID: UUID?
    @State private var preferredColumn: NavigationSplitViewColumn = .sidebar
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

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            sidebar
        } content: {
            NoteBrowserView(section: section ?? .home, folders: folders, notes: notes, revisions: revisions,
                            store: store, selectedNoteID: $selectedNoteID, openNote: openNote)
        } detail: {
            if let note = selectedNote {
                NoteEditorView(note: note, folders: activeFolders, notes: notes,
                               revisions: revisions, store: store, openNote: openNote)
                    .id(note.id)
            } else {
                ContentUnavailableView("생각을 펼쳐 보세요", systemImage: "leaf",
                                       description: Text("메모를 선택하거나 새로운 영감을 기록하세요."))
            }
        }
        .onChange(of: section) { _, _ in
            if let pendingCaptureID {
                selectedNoteID = pendingCaptureID
                self.pendingCaptureID = nil
                preferredColumn = .detail
            } else {
                selectedNoteID = nil
                preferredColumn = .content
            }
        }
        .sheet(isPresented: $showingFolderForm) {
            FolderFormView(folder: editingFolder, store: store, nextOrder: folders.count)
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
        selectedNoteID = note.id
        preferredColumn = .detail
    }
}

#Preview {
    ContentView().modelContainer(for: [InspirationFolder.self, InspirationNote.self, NoteRevision.self], inMemory: true)
}
