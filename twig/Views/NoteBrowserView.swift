import SwiftUI

struct NoteBrowserView: View {
    let section: WorkspaceSection
    let folders: [InspirationFolder]
    let notes: [InspirationNote]
    let revisions: [NoteRevision]
    let store: NoteStore
    @Binding var selectedNoteID: UUID?
    let openNote: (InspirationNote) -> Void
    @State private var search = ""
    @State private var dateKind = "없음"
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var showingFilters = false
    @State private var movingNote: InspirationNote?
    @State private var deletingNote: InspirationNote?
    @State private var randomID: UUID?
    @State private var editingFolder = false

    private var folder: InspirationFolder? {
        if case .folder(let id) = section { return folders.first { $0.id == id } }
        return nil
    }
    private var title: String {
        switch section {
        case .home: "다시 꺼내볼 영감"
        case .inbox: "수집함"
        case .all: "전체 메모"
        case .trash: "휴지통"
        case .folder: folder?.name ?? "영감 폴더"
        }
    }
    private var scoped: [InspirationNote] {
        notes.filter { note in
            if section == .trash { return note.isDeleted }
            guard !note.isDeleted else { return false }
            switch section {
            case .inbox: return note.folderID == nil || !folders.contains { $0.id == note.folderID && !$0.isDeleted }
            case .folder(let id): return note.folderID == id
            default: return true
            }
        }
    }
    private var filtered: [InspirationNote] {
        scoped.filter { note in
            let draft = NoteStore.draft(for: note, revisions: revisions)
            let terms = search.split(whereSeparator: \.isWhitespace).map(String.init)
            let matches = terms.allSatisfy { term in
                if term.hasPrefix("#") { return draft.tags.contains { $0.localizedCaseInsensitiveContains(String(term.dropFirst())) } }
                return (draft.title + " " + draft.content + " " + draft.tags.joined(separator: " ")).localizedCaseInsensitiveContains(term)
            }
            guard matches else { return false }
            let calendar = Calendar.current
            let lower = calendar.startOfDay(for: min(startDate, endDate))
            let upper = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(startDate, endDate))) ?? endDate
            switch dateKind {
            case "작성일": return note.createdAt >= lower && note.createdAt < upper
            case "수정일":
                let latest = revisions.filter { $0.noteID == note.id }.map(\.createdAt).max() ?? note.updatedAt
                let modified = max(latest, note.updatedAt)
                return modified >= lower && modified < upper
            case "지정 날짜":
                guard let date = draft.customDate else { return false }
                return date >= CalendarDay.string(min(startDate, endDate)) && date <= CalendarDay.string(max(startDate, endDate))
            default: return true
            }
        }
    }

    private var rows: [TreeRow] {
        if !search.isEmpty || dateKind != "없음" || section == .all || section == .home || section == .trash {
            return filtered.sorted { $0.updatedAt > $1.updatedAt }.map { TreeRow(note: $0, depth: 0) }
        }
        return TreeRow.flatten(scoped)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showingFilters {
                VStack(alignment: .leading) {
                    Picker("날짜 기준", selection: $dateKind) {
                        ForEach(["없음", "작성일", "수정일", "지정 날짜"], id: \.self) { Text($0) }
                    }
                    if dateKind != "없음" {
                        DatePicker("시작", selection: $startDate, displayedComponents: .date)
                        DatePicker("끝", selection: $endDate, displayedComponents: .date)
                    }
                    Text("키워드와 #태그를 함께 입력할 수 있습니다.").font(.caption).foregroundStyle(.secondary)
                }.padding()
                Divider()
            }
            List(selection: $selectedNoteID) {
                if section == .trash {
                    Section {
                        Text("삭제한 항목은 자동으로 영구 삭제하지 않습니다. 원래 폴더가 없으면 수집함으로 복구됩니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(folders.filter(\.isDeleted)) { folder in
                        HStack {
                            Label(folder.name, systemImage: "folder")
                            Spacer()
                            Button("복구") { store.restoreFolder(folder, notes: notes) }
                        }
                    }
                }
                if section == .home, search.isEmpty, dateKind == "없음", let note = rediscovered {
                    Section("오늘 다시 볼 영감") {
                        Button { openNote(note) } label: {
                            Label(NoteStore.draft(for: note, revisions: revisions).label, systemImage: "sparkles")
                        }
                        Button("다른 영감 보기", systemImage: "shuffle") {
                            randomID = scoped.filter { $0.id != note.id }.randomElement()?.id ?? note.id
                        }
                    }
                }
                ForEach(rows) { row in noteRow(row) }
                if rows.isEmpty && (section != .trash || folders.filter(\.isDeleted).isEmpty) {
                    ContentUnavailableView(search.isEmpty ? "아직 영감이 없습니다" : "검색 결과가 없습니다",
                        systemImage: search.isEmpty ? "leaf" : "magnifyingglass",
                        description: Text(section == .trash ? "삭제한 메모는 이곳에서 복구할 수 있습니다." : "새 메모를 만들거나 검색 조건을 바꿔 보세요."))
                }
            }
        }
        .navigationTitle(title)
        .searchable(text: $search, prompt: "제목, 본문, #태그 검색")
        .toolbar {
            ToolbarItem {
                Button("검색 필터", systemImage: dateKind == "없음" ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") { showingFilters.toggle() }
            }
            if section != .trash {
                ToolbarItem {
                    Button("최상위 영감 추가", systemImage: "plus") { openNote(store.createNote(folderID: folder?.id, notes: notes)) }
                }
            }
            if folder != nil {
                ToolbarItem { Button("폴더 수정", systemImage: "pencil") { editingFolder = true } }
            }
        }
        .sheet(isPresented: $editingFolder) { FolderFormView(folder: folder, store: store, nextOrder: folders.count) }
        .sheet(item: $movingNote) { note in
            MoveNoteView(note: note, folders: folders, notes: notes, revisions: revisions, store: store)
        }
        .confirmationDialog("메모와 하위 가지를 이동할까요?", isPresented: Binding(
            get: { deletingNote != nil }, set: { if !$0 { deletingNote = nil } }
        ), titleVisibility: .visible) {
            Button("휴지통으로 이동", role: .destructive) {
                if let note = deletingNote { store.trash(note, notes: notes) }
                deletingNote = nil
            }
        } message: { Text("하위 가지도 함께 휴지통으로 이동하며, 나중에 복구할 수 있습니다.") }
        .onChange(of: section) { _, _ in search = ""; dateKind = "없음" }
    }

    private var rediscovered: InspirationNote? {
        if let randomID, let note = scoped.first(where: { $0.id == randomID }) { return note }
        let candidates = scoped.sorted { $0.createdAt < $1.createdAt }
        guard !candidates.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return candidates[day % candidates.count]
    }

    private func noteRow(_ row: TreeRow) -> some View {
        let note = row.note
        let draft = NoteStore.draft(for: note, revisions: revisions)
        let hasChildren = scoped.contains { $0.parentNoteID == note.id }
        return HStack(alignment: .top, spacing: 8) {
            if section != .trash && hasChildren {
                Button {
                    note.isCollapsed.toggle()
                    store.save()
                } label: {
                    Image(systemName: note.isCollapsed ? "chevron.right" : "chevron.down")
                        .frame(minWidth: 32, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(note.isCollapsed ? "하위 가지 펼치기" : "하위 가지 접기")
            }
            if section == .trash {
                VStack(alignment: .leading) {
                    Text(draft.label).lineLimit(3)
                    Button("가지 복구") { store.restore(note, notes: notes, folders: folders) }
                }
            } else {
                NavigationLink(value: note.id) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.label).lineLimit(3)
                        if row.depth > 4 { Text("깊이 \(row.depth + 1)").font(.caption).foregroundStyle(.secondary) }
                        if !draft.tags.isEmpty {
                            Text(draft.tags.map { "#" + $0 }.joined(separator: " "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }.padding(.vertical, 6)
                }
            }
        }
        .padding(.leading, CGFloat(min(row.depth, 4)) * 14)
        .tag(note.id)
        .contextMenu {
            if !note.isDeleted {
                Button("가지 만들기", systemImage: "plus") { openNote(store.createNote(folderID: note.folderID, parentID: note.id, notes: notes)) }
                Button("위로 이동", systemImage: "arrow.up") { store.reorder(note, offset: -1, notes: notes) }
                Button("아래로 이동", systemImage: "arrow.down") { store.reorder(note, offset: 1, notes: notes) }
                Button("폴더 또는 부모 변경", systemImage: "arrow.turn.up.right") { movingNote = note }
                Button("휴지통으로 이동", systemImage: "trash", role: .destructive) { deletingNote = note }
            }
        }
    }
}

struct TreeRow: Identifiable {
    let note: InspirationNote
    let depth: Int
    var id: UUID { note.id }

    @MainActor
    static func flatten(_ notes: [InspirationNote]) -> [TreeRow] {
        let sorted = NoteStore.sorted(notes)
        let index = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let placements = TreeTopology.flatten(sorted.map { TreeNode(id: $0.id, parentID: $0.parentNoteID, collapsed: $0.isCollapsed) })
        return placements.compactMap { placement in
            index[placement.id].map { TreeRow(note: $0, depth: placement.depth) }
        }
    }
}
