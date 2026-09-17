import SwiftUI

struct ResizableSelectedNotePanel: View {
    @Environment(\.colorScheme) private var scheme
    let note: InspirationNote
    let folders: [InspirationFolder]
    let notes: [InspirationNote]
    let revisions: [NoteRevision]
    let store: NoteStore
    let totalHeight: CGFloat
    let edit: () -> Void
    @State private var panelHeight: CGFloat = 240
    @State private var previousExpandedHeight: CGFloat = 240
    @GestureState private var dragTranslation: CGFloat = 0

    private let minimumHeight: CGFloat = 110

    var body: some View {
        let height = displayedHeight
        VStack(spacing: 0) {
            resizeHandle(height: height)
            SelectedNotePanel(
                note: note,
                folders: folders,
                notes: notes,
                revisions: revisions,
                store: store,
                edit: edit
            )
            .id(note.id)
            .frame(height: height)
        }
    }

    private func resizeHandle(height: CGFloat) -> some View {
        let minimized = height <= minimumHeight + 8
        return VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Spacer()
                Capsule()
                    .fill(.secondary.opacity(0.45))
                    .frame(width: 48, height: 5)
                    .frame(width: 120, height: 28)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .updating($dragTranslation) { value, state, _ in
                                state = value.translation.height
                            }
                            .onEnded { value in
                                resize(to: panelHeight - value.translation.height)
                            }
                    )
                    .accessibilityLabel("선택한 영감 패널 크기")
                    .accessibilityValue("높이 \(Int(height))")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment:
                            resize(to: height + 60)
                        case .decrement:
                            resize(to: height - 60)
                        @unknown default:
                            break
                        }
                    }
                Spacer()
                Button(minimized ? "선택한 영감 펼치기" : "선택한 영감 최소화",
                       systemImage: minimized ? "chevron.up" : "chevron.down") {
                    togglePanel()
                }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 28)
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 29)
        .background(BoardStyle.paper(scheme))
    }

    private var maximumHeight: CGFloat {
        max(minimumHeight, totalHeight - 160)
    }

    private var displayedHeight: CGFloat {
        min(maximumHeight, max(minimumHeight, panelHeight - dragTranslation))
    }

    private func resize(to height: CGFloat) {
        let adjusted = min(maximumHeight, max(minimumHeight, height))
        panelHeight = adjusted
        if adjusted > minimumHeight + 8 { previousExpandedHeight = adjusted }
    }

    private func togglePanel() {
        let current = displayedHeight
        withAnimation(.easeInOut(duration: 0.2)) {
            if current <= minimumHeight + 8 {
                resize(to: previousExpandedHeight)
            } else {
                previousExpandedHeight = current
                panelHeight = minimumHeight
            }
        }
    }
}

struct SelectedNotePanel: View {
    private enum InlineField: Hashable { case title, content }

    @Environment(\.colorScheme) private var scheme
    let note: InspirationNote
    let folders: [InspirationFolder]
    let notes: [InspirationNote]
    let revisions: [NoteRevision]
    let store: NoteStore
    let edit: () -> Void
    @State private var showingMove = false
    @State private var isInlineEditing = false
    @State private var inlineDraft = NoteDraft()
    @State private var lastSavedInlineDraft = NoteDraft()
    @State private var inlineCheckpointID = UUID()
    @State private var inlineSaveFailed = false
    @FocusState private var inlineFocus: InlineField?

    private var draft: NoteDraft {
        isInlineEditing ? inlineDraft : (store.pendingDrafts[note.id] ?? NoteStore.draft(for: note, revisions: revisions))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("선택한 영감").font(.caption2).foregroundStyle(.secondary)
                        if isInlineEditing {
                            TextField("제목 (선택)", text: $inlineDraft.title, axis: .vertical)
                                .font(.title3.weight(.semibold))
                                .textFieldStyle(.plain)
                                .focused($inlineFocus, equals: .title)
                                .accessibilityLabel("선택한 영감 제목")
                        } else {
                            Button { startInlineEditing(focus: .title) } label: {
                                Text(draft.label).font(.title3.weight(.semibold)).lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("누르면 이 패널에서 바로 편집합니다")
                        }
                        Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    HStack {
                        if isInlineEditing {
                            Button("인라인 편집 완료", systemImage: "checkmark") { finishInlineEditing() }
                                .labelStyle(.iconOnly)
                        }
                        Button("이동", systemImage: "arrow.turn.up.right") { showingMove = true }
                        Button("편집", systemImage: "pencil") {
                            persistInlineDraft()
                            edit()
                        }
                    }
                    .font(.caption).buttonStyle(.bordered).tint(.secondary)
                }
                if isInlineEditing {
                    TextEditor(text: $inlineDraft.content)
                        .font(.callout)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 90)
                        .focused($inlineFocus, equals: .content)
                        .accessibilityLabel("선택한 영감 본문")
                    if inlineSaveFailed {
                        Button("저장하지 못했습니다 · 다시 저장") { persistInlineDraft() }
                            .font(.caption).foregroundStyle(.red)
                    }
                } else if !draft.content.isEmpty {
                    Button { startInlineEditing(focus: .content) } label: {
                        Text(draft.content).font(.callout).foregroundStyle(.secondary)
                            .lineSpacing(5).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("누르면 이 패널에서 바로 편집합니다")
                } else {
                    Button("이 생각을 조금 더 풀어 적어보세요") { startInlineEditing(focus: .content) }
                        .font(.callout).foregroundStyle(.secondary).buttonStyle(.plain)
                }
                if !draft.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(draft.tags, id: \.self) { tag in
                                Text("#\(tag)").font(.caption2)
                                    .padding(.horizontal, 9).padding(.vertical, 7)
                                    .background(BoardStyle.wash(scheme), in: Capsule())
                            }
                        }
                    }
                }

            }.padding(24)
        }
        .background(BoardStyle.paper(scheme))
        .sheet(isPresented: $showingMove) {
            MoveNoteView(note: note, folders: folders, notes: notes, revisions: revisions, store: store)
        }
        .onChange(of: inlineDraft) { _, _ in
            if isInlineEditing { persistInlineDraft() }
        }
        .onDisappear { persistInlineDraft() }
    }

    private func startInlineEditing(focus: InlineField) {
        let current = store.pendingDrafts[note.id] ?? NoteStore.draft(for: note, revisions: revisions)
        var editable = current
        if focus == .title,
           editable.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !editable.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            editable.title = current.label
        }
        inlineDraft = editable
        lastSavedInlineDraft = editable
        inlineCheckpointID = UUID()
        inlineSaveFailed = false
        isInlineEditing = true
        inlineFocus = focus
    }

    private func finishInlineEditing() {
        persistInlineDraft()
        guard !inlineSaveFailed else { return }
        inlineFocus = nil
        isInlineEditing = false
    }

    private func persistInlineDraft() {
        guard isInlineEditing, inlineDraft != lastSavedInlineDraft || inlineSaveFailed else { return }
        if store.commit(inlineDraft, to: note, checkpointID: inlineCheckpointID) {
            lastSavedInlineDraft = inlineDraft
            inlineSaveFailed = false
        } else {
            inlineSaveFailed = true
        }
    }
}
