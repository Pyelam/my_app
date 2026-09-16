import SwiftUI

struct InspirationBoardView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var cardWidth: CGFloat = 176
    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = 64
    let title: String
    let folder: InspirationFolder?
    let notes: [InspirationNote]
    let revisions: [NoteRevision]
    let selectedNoteID: UUID?
    let store: NoteStore
    let select: (InspirationNote) -> Void
    let edit: (InspirationNote) -> Void
    let editFolder: () -> Void
    @State private var movingNote: InspirationNote?
    @State private var deletingNote: InspirationNote?
    let allFolders: [InspirationFolder]
    let allNotes: [InspirationNote]

    private var ordered: [InspirationNote] { NoteStore.sorted(notes) }
    private var layout: TreeCardLayout {
        TreeCardLayout.make(nodes: ordered.map { TreeNode(id: $0.id, parentID: $0.parentNoteID, collapsed: $0.isCollapsed) },
                            cardWidth: Double(cardWidth), cardHeight: Double(cardHeight))
    }
    private var parents: Set<UUID> { Set(notes.compactMap(\.parentNoteID)) }
    private var hasExpandedBranches: Bool { notes.contains { parents.contains($0.id) && !$0.isCollapsed } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if notes.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.title2).foregroundStyle(.secondary)
                    Text("작은 생각 하나에서 시작해요").font(.headline)
                    Text("첫 영감을 적고, 옆의 + 버튼으로 가지를 뻗어보세요.").font(.callout).foregroundStyle(.secondary)
                    Button("첫 영감 만들기") { addRoot() }.buttonStyle(BoardPrimaryButtonStyle())
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                graph
            }
        }
        .background(BoardStyle.paper(scheme))
        .sheet(item: $movingNote) { note in
            MoveNoteView(note: note, folders: allFolders, notes: allNotes, revisions: revisions, store: store)
        }
        .confirmationDialog("이 영감과 하위 가지를 휴지통으로 이동할까요?", isPresented: Binding(
            get: { deletingNote != nil }, set: { if !$0 { deletingNote = nil } }
        ), titleVisibility: .visible) {
            Button("휴지통으로 이동", role: .destructive) {
                if let deletingNote { store.trash(deletingNote, notes: allNotes) }
                deletingNote = nil
            }
        } message: { Text("휴지통에서 다시 복구할 수 있습니다.") }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text("씨앗 하나에서 가지를 뻗어 아이디어를 구체화해요")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !parents.isEmpty {
                Button(hasExpandedBranches ? "가지 접기" : "가지 펼치기") {
                    let collapse = hasExpandedBranches
                    for note in notes where parents.contains(note.id) { note.isCollapsed = collapse }
                    store.save()
                }
                .font(.caption).buttonStyle(.bordered).tint(.secondary)
                .accessibilityHint("이 폴더의 모든 가지에 적용합니다")
            }
            Menu {
                Button("최상위 영감 추가", systemImage: "plus") { addRoot() }
                if folder != nil { Button("폴더 이름 및 테마", systemImage: "pencil") { editFolder() } }
            } label: {
                Image(systemName: "ellipsis").frame(width: 32, height: 32).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("폴더 작업")
        }.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 4)
    }

    private var graph: some View {
        let layout = layout
        let index = Dictionary(ordered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Canvas { context, _ in
                            var path = Path()
                            for edge in layout.connections {
                                path.move(to: CGPoint(x: edge.startX, y: edge.startY))
                                path.addLine(to: CGPoint(x: edge.startX, y: edge.endY))
                                path.addLine(to: CGPoint(x: edge.endX, y: edge.endY))
                            }
                            context.stroke(path, with: .color(BoardStyle.rule(scheme)), lineWidth: 1)
                        }.allowsHitTesting(false).accessibilityHidden(true)
                        ForEach(layout.cards) { frame in
                            if let note = index[frame.id] {
                                card(note, depth: frame.depth)
                                    .frame(width: cardWidth + 44, height: cardHeight)
                                    .id(note.id)
                                    .position(x: CGFloat(frame.x) + (cardWidth + 44) / 2, y: CGFloat(frame.y) + cardHeight / 2)
                            }
                        }
                    }
                    .frame(width: max(geometry.size.width, CGFloat(layout.width)), height: max(geometry.size.height, CGFloat(layout.height)), alignment: .topLeading)
                }
                .onChange(of: selectedNoteID) { _, id in
                    if let id { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo(id) } }
                }
            }
        }
    }

    private func card(_ note: InspirationNote, depth: Int) -> some View {
        let draft = store.pendingDrafts[note.id] ?? NoteStore.draft(for: note, revisions: revisions)
        let selected = selectedNoteID == note.id
        let textColor = selected ? BoardStyle.paper(scheme) : BoardStyle.ink(scheme)
        let theme = FolderTheme(rawValue: folder?.theme ?? "default") ?? .default
        let background = selected ? BoardStyle.ink(scheme) : BoardStyle.paper(scheme)
        let subtitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (note.updatedAt.formatted(date: .abbreviated, time: .omitted))
            : (draft.content.isEmpty ? "생각을 이어서 적어보세요" : draft.content)

        return HStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Button { select(note) } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(draft.label).font(.callout.weight(.semibold)).lineLimit(2)
                        Text(subtitle).font(.caption2).lineLimit(1).opacity(0.65)
                    }
                    .padding(.leading, 13).padding(.trailing, parents.contains(note.id) ? 32 : 13)
                    .frame(width: cardWidth, height: cardHeight, alignment: .leading)
                    .foregroundStyle(textColor)
                    .background(background)
                    .overlay { if !selected { theme.color.opacity(theme == .default ? 0 : 0.065) } }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BoardStyle.rule(scheme), lineWidth: 1))
                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.04), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(draft.label)
                .accessibilityValue("\(depth + 1)단계\(selected ? ", 선택됨" : "")")
                .accessibilityHint("선택하면 아래에 내용이 표시됩니다")
                if parents.contains(note.id) {
                    Button {
                        note.isCollapsed.toggle()
                        store.save()
                    } label: {
                        Image(systemName: note.isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(textColor.opacity(0.7))
                            .frame(width: 32, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(note.isCollapsed ? "하위 가지 펼치기" : "하위 가지 접기")
                }
            }
            .contextMenu {
                Button("메모 편집", systemImage: "pencil") { edit(note) }
                Button("가지 만들기", systemImage: "plus") { addChild(to: note) }
                Button("위로 이동", systemImage: "arrow.up") { store.reorder(note, offset: -1, notes: allNotes) }
                Button("아래로 이동", systemImage: "arrow.down") { store.reorder(note, offset: 1, notes: allNotes) }
                Button("폴더 또는 부모 변경", systemImage: "arrow.turn.up.right") { movingNote = note }
                Button("휴지통으로 이동", systemImage: "trash", role: .destructive) { deletingNote = note }
            }
            Button { addChild(to: note) } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary).frame(width: 23, height: 23)
                    .background(BoardStyle.paper(scheme), in: Circle())
                    .overlay(Circle().strokeBorder(BoardStyle.rule(scheme), lineWidth: 1))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(draft.label)에 가지 추가")
        }
    }

    private func addRoot() {
        let note = store.createNote(folderID: folder?.id, notes: allNotes)
        select(note)
        edit(note)
    }

    private func addChild(to parent: InspirationNote) {
        let note = store.createNote(folderID: parent.folderID, parentID: parent.id, notes: allNotes)
        select(note)
        edit(note)
    }
}
