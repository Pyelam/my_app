import SwiftUI

struct SelectedNotePanel: View {
    @Environment(\.colorScheme) private var scheme
    let note: InspirationNote
    let notes: [InspirationNote]
    let revisions: [NoteRevision]
    let store: NoteStore
    let edit: () -> Void
    let select: (InspirationNote) -> Void
    @State private var nextThought = ""
    @State private var pendingChild: InspirationNote?
    @State private var childCheckpointID = UUID()
    @State private var saveFailed = false

    private var draft: NoteDraft { store.pendingDrafts[note.id] ?? NoteStore.draft(for: note, revisions: revisions) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("선택한 영감").font(.caption2).foregroundStyle(.secondary)
                        Text(draft.label).font(.title3.weight(.semibold)).lineLimit(2)
                        Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button("편집", systemImage: "pencil", action: edit)
                        .font(.caption).buttonStyle(.bordered).tint(.secondary)
                }
                if !draft.content.isEmpty {
                    Text(draft.content).font(.callout).foregroundStyle(.secondary)
                        .lineSpacing(5).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Button("이 생각을 조금 더 풀어 적어보세요", action: edit)
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
                Divider().padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("다음 가지").font(.caption.weight(.medium))
                    HStack {
                        TextField("이 생각에서 이어지는 다음 행동은?", text: $nextThought, axis: .vertical)
                            .textFieldStyle(.plain).font(.callout).lineLimit(1...3)
                            .accessibilityLabel("하위 가지 내용")
                        Button(action: addNextThought) {
                            Image(systemName: "arrow.down").font(.body)
                                .frame(width: 32, height: 32)
                                .background(BoardStyle.paper(scheme), in: Circle())
                                .overlay(Circle().strokeBorder(BoardStyle.rule(scheme), lineWidth: 1))
                                .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .disabled(nextThought.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityLabel("하위 가지로 추가")
                    }
                    if saveFailed {
                        Text("저장하지 못했습니다. 아래 화살표를 눌러 다시 시도해 주세요.")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
            }.padding(24)
        }
        .background(BoardStyle.paper(scheme))
        .onChange(of: nextThought) { _, _ in persistNextThought() }
    }

    private func persistNextThought() {
        guard pendingChild != nil || !nextThought.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let child = pendingChild ?? store.createNote(folderID: note.folderID, parentID: note.id, notes: notes)
        pendingChild = child
        saveFailed = !store.commit(NoteDraft(content: nextThought), to: child, checkpointID: childCheckpointID)
    }

    private func addNextThought() {
        persistNextThought()
        guard !saveFailed, let child = pendingChild else { return }
        pendingChild = nil
        childCheckpointID = UUID()
        nextThought = ""
        select(child)
    }
}
