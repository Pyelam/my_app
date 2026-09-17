import SwiftUI

struct SelectedNotePanel: View {
    @Environment(\.colorScheme) private var scheme
    let note: InspirationNote
    let folders: [InspirationFolder]
    let notes: [InspirationNote]
    let revisions: [NoteRevision]
    let store: NoteStore
    let edit: () -> Void
    @State private var showingMove = false

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
                    HStack {
                        Button("이동", systemImage: "arrow.turn.up.right") { showingMove = true }
                        Button("편집", systemImage: "pencil", action: edit)
                    }
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

            }.padding(24)
        }
        .background(BoardStyle.paper(scheme))
        .sheet(isPresented: $showingMove) {
            MoveNoteView(note: note, folders: folders, notes: notes, revisions: revisions, store: store)
        }
    }
}
