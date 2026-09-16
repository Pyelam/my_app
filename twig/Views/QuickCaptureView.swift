import SwiftUI

struct QuickCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    let folders: [InspirationFolder]
    let notes: [InspirationNote]
    let store: NoteStore
    let completion: (InspirationNote) -> Void
    @State private var content = ""
    @State private var captured: InspirationNote?
    @State private var folderID: UUID?
    @State private var newFolderName = ""
    @State private var createdFolder: InspirationFolder?
    @State private var saveFailed = false
    @State private var checkpointID = UUID()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
              VStack(alignment: .leading, spacing: 16) {
                Text("분류는 나중에 해도 괜찮아요.").foregroundStyle(.secondary)
                TextEditor(text: $content).focused($focused).frame(minHeight: 180)
                    .accessibilityLabel("빠른 영감 본문")
                Label(saveFailed ? "저장 실패 · 다시 시도해 주세요" : (captured == nil ? "입력하면 수집함에 저장됩니다" : "기기에 저장됨"),
                      systemImage: saveFailed ? "exclamationmark.triangle" : "tray")
                    .font(.caption).foregroundStyle(.secondary)
                if captured != nil {
                    Picker("저장 위치", selection: $folderID) {
                        Text("수집함").tag(nil as UUID?)
                        ForEach(folders) { folder in Text(folder.name).tag(Optional(folder.id)) }
                        if let createdFolder, !folders.contains(where: { $0.id == createdFolder.id }) {
                            Text(createdFolder.name).tag(Optional(createdFolder.id))
                        }
                    }
                    HStack {
                        TextField("새 폴더 이름", text: $newFolderName)
                        Button("만들기") {
                            let folder = InspirationFolder(name: newFolderName.trimmingCharacters(in: .whitespacesAndNewlines), sortOrder: folders.count)
                            store.context.insert(folder)
                            createdFolder = folder
                            folderID = folder.id
                            newFolderName = ""
                        }.disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
              }.padding()
            }
            .navigationTitle("빠른 영감")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { persist(); if !saveFailed { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        persist()
                        if !saveFailed, let captured { completion(captured); dismiss() }
                    }.disabled(captured == nil)
                }
            }
            .onChange(of: content) { _, _ in persist() }
            .onChange(of: folderID) { _, _ in
                if let captured {
                    store.move(captured, folderID: folderID, parentID: nil, notes: notes + (notes.contains { $0.id == captured.id } ? [] : [captured]))
                    saveFailed = store.errorMessage != nil
                }
            }
            .onAppear { focused = true }
        }
        .editorSheetSize(minHeight: 420)
        .interactiveDismissDisabled(saveFailed)
    }

    private func persist() {
        if captured == nil {
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            captured = store.createNote(folderID: nil, notes: notes)
        }
        if let captured {
            if captured.content != content || saveFailed {
                saveFailed = !store.commit(NoteDraft(content: content), to: captured, checkpointID: checkpointID)
            }
        }
    }
}
