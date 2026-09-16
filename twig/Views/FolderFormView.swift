import SwiftUI

struct FolderFormView: View {
    @Environment(\.dismiss) private var dismiss
    let folder: InspirationFolder?
    let store: NoteStore
    let nextOrder: Int
    @State private var name = ""
    @State private var theme = FolderTheme.default
    @State private var insertedFolder: InspirationFolder?
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("폴더 이름", text: $name)
                Picker("테마", selection: $theme) {
                    ForEach(FolderTheme.allCases) { theme in
                        Label(theme.label, systemImage: "circle.fill").foregroundStyle(theme.color).tag(theme)
                    }
                }
                if saveFailed { Text("저장하지 못했습니다. 다시 시도해 주세요.").foregroundStyle(.red) }
            }
            .navigationTitle(folder == nil ? "새 영감 폴더" : "폴더 수정")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        let target = folder ?? insertedFolder ?? InspirationFolder(name: name, sortOrder: nextOrder)
                        if folder == nil && insertedFolder == nil { store.context.insert(target); insertedFolder = target }
                        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        target.theme = theme.rawValue
                        target.updatedAt = Date()
                        if store.save() { dismiss() } else { saveFailed = true }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                name = folder?.name ?? ""
                theme = FolderTheme(rawValue: folder?.theme ?? "default") ?? .default
            }
        }.editorSheetSize(minHeight: 260)
    }
}
