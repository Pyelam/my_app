import SwiftUI

struct InlineCaptureBar: View {
    @Environment(\.colorScheme) private var scheme
    let notes: [InspirationNote]
    let store: NoteStore
    @State private var text = ""
    @State private var captured: InspirationNote?
    @State private var checkpointID = UUID()
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkle").padding(.top, 12).accessibilityHidden(true)
                TextField("방금 떠오른 생각을 적어보세요…", text: $text, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(1...3)
                    .padding(.vertical, 11)
                    .accessibilityLabel("빠른 메모 입력")
                Button("수집함에 담기") { finish() }
                    .buttonStyle(BoardPrimaryButtonStyle())
                    .disabled(captured == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(failed ? Color.red : Color.secondary)
                    .accessibilityLabel(message)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(BoardStyle.wash(scheme))
        .onChange(of: text) { _, _ in persist() }
    }

    private func persist() {
        if captured == nil {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            captured = store.createNote(folderID: nil, notes: notes)
        }
        guard let captured else { return }
        failed = !store.commit(NoteDraft(content: text), to: captured, checkpointID: checkpointID)
        message = failed ? "저장하지 못했습니다. 입력을 유지하고 있습니다." : "수집함에 자동 저장됨"
    }

    private func finish() {
        persist()
        guard !failed, captured != nil else { return }
        captured = nil
        checkpointID = UUID()
        text = ""
        message = "수집함에 담았어요. 다음 생각도 이어서 적어보세요."
    }
}
