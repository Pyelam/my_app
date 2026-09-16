import SwiftUI
import UniformTypeIdentifiers

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }

    @MainActor
    static func export(folders: [InspirationFolder], notes: [InspirationNote], revisions: [NoteRevision]) -> String {
        var lines = ["# Twig 전체 메모", "", "내보낸 시각: \(Date().ISO8601Format())", "",
                     "휴지통과 편집 기록을 포함합니다. 이 파일은 읽기용 백업이며 앱으로 자동 가져오기는 지원하지 않습니다.", ""]
        for note in notes.sorted(by: { $0.createdAt < $1.createdAt }) {
            let draft = NoteStore.draft(for: note, revisions: revisions)
            lines += ["## \(draft.label.replacingOccurrences(of: "\n", with: " "))", "",
                      "- ID: \(note.id)",
                      "- 폴더: \(folders.first { $0.id == note.folderID }?.name ?? "수집함")",
                      "- 부모 ID: \(note.parentNoteID?.uuidString ?? "없음")",
                      "- 순서: \(note.sortOrder)",
                      "- 작성: \(note.createdAt.ISO8601Format())",
                      "- 수정: \(note.updatedAt.ISO8601Format())",
                      "- 지정 날짜: \(draft.customDate ?? "없음")",
                      "- 태그: \(draft.tags.map { "#" + $0 }.joined(separator: " "))",
                      "- 휴지통: \(note.isDeleted ? "예" : "아니요")", "", draft.content, ""]
            let history = revisions.filter { $0.noteID == note.id }.sorted { $0.createdAt < $1.createdAt }
            if !history.isEmpty { lines += ["### 편집 기록", ""] }
            for revision in history {
                lines += ["#### \(revision.createdAt.ISO8601Format()) · \(revision.id)", "",
                          revision.title, "", revision.content, "",
                          "태그: \(revision.tagNames.joined(separator: ", ")) · 지정 날짜: \(revision.customDate ?? "없음")", ""]
            }
            lines += ["---", ""]
        }
        return lines.joined(separator: "\n")
    }
}
