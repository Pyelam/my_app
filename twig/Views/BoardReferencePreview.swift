import SwiftData
import SwiftUI

// Reference content exists only in this in-memory preview, never in the user's database.
private struct BoardReferencePreview: View {
    private let container: ModelContainer?

    init() {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try? ModelContainer(for: InspirationFolder.self, InspirationNote.self, NoteRevision.self,
                                       configurations: configuration)
        guard let container else { return }
        let context = container.mainContext
        let folder = InspirationFolder(name: "영감 메모앱")
        context.insert(folder)
        func add(_ title: String, _ content: String, parent: InspirationNote? = nil, order: Int = 0) -> InspirationNote {
            let note = InspirationNote(folderID: folder.id, parentNoteID: parent?.id, content: content, sortOrder: order)
            note.title = title
            context.insert(note)
            return note
        }
        let root = add("영감 메모앱", "떠오른 생각을 빠르게 적고, 나중에 가지를 뻗으며 쓸모 있는 아이디어로 발전시키는 앱.")
        root.tagNames = ["앱", "영감", "기획"]
        _ = add("왜 필요한가?", "생각은 금방 사라진다", parent: root)
        let flow = add("핵심 사용 흐름", "꼭 적기 → 발전시키기", parent: root, order: 1)
        _ = add("즉시 기록", "제목 · 분류 없이 저장", parent: flow)
        _ = add("가지 뻗기", "하위 메모로 구체화", parent: flow, order: 1)
        _ = add("실제로 활용", "기획서 · 콘텐츠로 전환", parent: root, order: 2)
    }

    var body: some View {
        if let container {
            ContentView().modelContainer(container)
        } else {
            Text("미리보기 저장소를 만들 수 없습니다.")
        }
    }
}

#Preview("카드 트리 · 밝게") {
    BoardReferencePreview().preferredColorScheme(.light).frame(width: 720, height: 920)
}

#Preview("카드 트리 · 어둡게") {
    BoardReferencePreview().preferredColorScheme(.dark).frame(width: 720, height: 920)
}
