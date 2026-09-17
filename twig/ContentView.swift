import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var context
    var body: some View { WorkspaceView(context: context) }
}

enum WorkspaceSection: Hashable {
    case home, inbox, favorites, all, trash, folder(UUID)
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
    @State private var targetedDropSection: WorkspaceSection?
    @State private var showingSyncStatus = false
    @State private var showingOnboarding = false
    @AppStorage("recentNoteIDs") private var recentNoteIDStorage = ""
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false

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
    private var recentNotes: [InspirationNote] {
        recentNoteIDStorage.split(separator: ",").compactMap { value in
            guard let id = UUID(uuidString: String(value)) else { return nil }
            return notes.first { $0.id == id && !$0.isDeleted }
        }
    }
    private var navigationNotes: [InspirationNote] {
        let active = notes.filter { !$0.isDeleted }
        switch section ?? .home {
        case .inbox:
            return NoteStore.sorted(boardNotes)
        case .folder:
            return NoteStore.sorted(boardNotes)
        case .favorites:
            return active.filter(\.isFavorite).sorted { $0.updatedAt > $1.updatedAt }
        case .home, .all:
            return active.sorted { $0.updatedAt > $1.updatedAt }
        case .trash:
            return []
        }
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
            if !didCompleteOnboarding { showingOnboarding = true }
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
        .sheet(isPresented: $showingSyncStatus) { SyncStatusView() }
        .sheet(isPresented: $showingOnboarding, onDismiss: { didCompleteOnboarding = true }) {
            OnboardingView {
                didCompleteOnboarding = true
                showingOnboarding = false
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
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    if showsBoard {
                        InspirationBoardView(title: selectedFolder?.name ?? "수집함", folder: selectedFolder,
                            notes: boardNotes, revisions: revisions, selectedNoteID: selectedNoteID, store: store,
                            select: openNote, edit: editNote,
                            allFolders: folders, allNotes: notes)
                    } else {
                        NoteBrowserView(section: section ?? .home, folders: folders, notes: notes, revisions: revisions,
                                        store: store, selectedNoteID: $selectedNoteID, openNote: openNote)
                    }
                    if let note = selectedNote {
                        ResizableSelectedNotePanel(
                            note: note,
                            folders: activeFolders,
                            notes: notes,
                            revisions: revisions,
                            store: store,
                            totalHeight: geometry.size.height,
                            previous: adjacentNote(offset: -1),
                            next: adjacentNote(offset: 1),
                            navigate: openNote,
                            edit: { editNote(note) }
                        )
                    }
                }
            }
        }
        .background(BoardStyle.paper(scheme))
        .safeAreaInset(edge: .bottom) {
            if let message = store.undoMessage {
                HStack(spacing: 12) {
                    Text(message).font(.callout).lineLimit(2)
                    Spacer(minLength: 8)
                    Button("실행 취소") { store.undoLastAction() }
                        .font(.callout.weight(.semibold))
                    Button("닫기", systemImage: "xmark") { store.dismissUndo() }
                        .labelStyle(.iconOnly)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("Twig")
        .toolbar {
            ToolbarItem {
                SaveStatusIndicator(state: store.saveState)
            }
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
                    Label("빠른 메모", systemImage: "square.and.pencil").padding(.vertical, 6)
                }.keyboardShortcut("n", modifiers: .command)
                NavigationLink(value: WorkspaceSection.home) { Label("홈", systemImage: "house") }
                NavigationLink(value: WorkspaceSection.inbox) {
                    Label("수집함 · \(notes.filter { !$0.isDeleted && $0.folderID == nil }.count)", systemImage: "tray")
                }
                .dropDestination(for: String.self) { items, _ in
                    moveDroppedNote(items, folderID: nil, destination: .inbox)
                } isTargeted: { targeted in
                    targetedDropSection = targeted ? .inbox : (targetedDropSection == .inbox ? nil : targetedDropSection)
                }
                .listRowBackground(targetedDropSection == .inbox ? Color.green.opacity(0.18) : Color.clear)
                NavigationLink(value: WorkspaceSection.all) { Label("전체 메모 검색", systemImage: "magnifyingglass") }
                NavigationLink(value: WorkspaceSection.favorites) {
                    Label("즐겨찾기 · \(notes.filter { !$0.isDeleted && $0.isFavorite }.count)", systemImage: "star")
                }
            }
            Section("생각 폴더") {
                ForEach(activeFolders) { folder in
                    NavigationLink(value: WorkspaceSection.folder(folder.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(folder.name, systemImage: "folder")
                            Text("\(notes.filter { !$0.isDeleted && $0.folderID == folder.id }.count)개의 생각")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 3)
                    }
                    .dropDestination(for: String.self) { items, _ in
                        moveDroppedNote(items, folderID: folder.id, destination: .folder(folder.id))
                    } isTargeted: { targeted in
                        let destination = WorkspaceSection.folder(folder.id)
                        targetedDropSection = targeted ? destination : (targetedDropSection == destination ? nil : targetedDropSection)
                    }
                    .listRowBackground(targetedDropSection == .folder(folder.id)
                        ? Color.green.opacity(0.18)
                        : (FolderTheme(rawValue: folder.theme) ?? .default).color.opacity(0.07))
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
            if !recentNotes.isEmpty {
                Section("최근 본 메모") {
                    ForEach(recentNotes.prefix(5)) { note in
                        Button { openRecentNote(note) } label: {
                            Label(NoteStore.draft(for: note, revisions: revisions).label,
                                  systemImage: "clock")
                                .lineLimit(2)
                        }
                    }
                }
            }
            if let note = notes.filter({ !$0.isDeleted }).min(by: { $0.updatedAt < $1.updatedAt }) {
                Section("다시 꺼내볼 생각") {
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
                Button { showingSyncStatus = true } label: {
                    Label(StorageConfiguration.status, systemImage: "icloud")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("사용 방법", systemImage: "questionmark.circle") {
                    showingOnboarding = true
                }
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
        recordRecentlyViewed(note.id)
        preferredColumn = .detail
    }

    private func openRecentNote(_ note: InspirationNote) {
        recordRecentlyViewed(note.id)
        let destination = note.folderID.map(WorkspaceSection.folder) ?? .inbox
        if section == destination {
            openNote(note)
        } else {
            pendingCaptureID = note.id
            section = destination
        }
    }

    private func adjacentNote(offset: Int) -> InspirationNote? {
        guard let selectedNoteID,
              let index = navigationNotes.firstIndex(where: { $0.id == selectedNoteID }) else { return nil }
        let destination = index + offset
        guard navigationNotes.indices.contains(destination) else { return nil }
        return navigationNotes[destination]
    }

    private func recordRecentlyViewed(_ id: UUID) {
        var ids = recentNoteIDStorage.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        recentNoteIDStorage = ids.prefix(12).map(\.uuidString).joined(separator: ",")
    }

    private func moveDroppedNote(_ items: [String], folderID: UUID?, destination: WorkspaceSection) -> Bool {
        guard let id = items.compactMap(NoteDragPayload.decode).first,
              let note = notes.first(where: { $0.id == id && !$0.isDeleted }) else { return false }
        guard store.move(note, folderID: folderID, parentID: nil, notes: notes) else { return false }
        targetedDropSection = nil
        selectedNoteID = note.id
        if section != destination {
            pendingCaptureID = note.id
            section = destination
        }
        return true
    }
}

private struct SaveStatusIndicator: View {
    let state: NoteStore.SaveState

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
            .accessibilityLabel(title)
    }

    private var title: String {
        switch state {
        case .saved: "저장됨"
        case .saving: "저장 중"
        case .failed: "저장 실패"
        }
    }

    private var icon: String {
        switch state {
        case .saved: "checkmark.circle"
        case .saving: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var color: Color {
        state == .failed ? .red : .secondary
    }
}

private struct OnboardingView: View {
    let complete: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 44))
                            .foregroundStyle(.green)
                        Text("생각을 가지처럼 연결하세요")
                            .font(.title.bold())
                        Text("Twig에서는 짧게 기록한 생각을 연결하고 자유롭게 다시 배치할 수 있습니다.")
                            .foregroundStyle(.secondary)
                    }
                    OnboardingTip(icon: "plus", title: "가지 만들기",
                                  detail: "메모 옆의 +를 눌러 이어지는 하위 가지를 만드세요.")
                    OnboardingTip(icon: "hand.draw", title: "길게 눌러 이동",
                                  detail: "가지를 길게 누른 뒤 다른 가지나 최상위 영역으로 끌어 이동하세요.")
                    OnboardingTip(icon: "hand.point.up.left", title: "배경을 밀어 탐색",
                                  detail: "카드가 아닌 배경을 터치하거나 드래그해 넓은 보드를 이동하세요.")
                    OnboardingTip(icon: "rectangle.bottomthird.inset.filled", title: "선택 패널 조절",
                                  detail: "하단 손잡이를 움직여 선택한 메모의 내용을 편한 크기로 확인하세요.")
                    OnboardingTip(icon: "checkmark.circle", title: "여러 메모 정리",
                                  detail: "목록의 선택 버튼으로 여러 메모를 즐겨찾기·이동·삭제할 수 있습니다.")
                    Button("Twig 시작하기") { complete() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
                .padding(28)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("사용 방법")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { complete() }
                }
            }
        }
        .editorSheetSize(minHeight: 560)
    }
}

private struct OnboardingTip: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ContentView().modelContainer(for: [InspirationFolder.self, InspirationNote.self, NoteRevision.self], inMemory: true)
}
