import SwiftData
import SwiftUI

@main
struct MyApp: App {
    private let storage: Result<ModelContainer, Error>

    init() {
        storage = Result {
            // Persist on this device. Enable iCloud in a later development step.
            let configuration = ModelConfiguration(
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            return try ModelContainer(
                for: InspirationFolder.self,
                configurations: configuration
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            switch storage {
            case .success(let container):
                ContentView()
                    .modelContainer(container)
            case .failure:
                // Keep the existing store intact if opening it fails.
                ContentUnavailableView(
                    "저장소를 열 수 없습니다",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("앱을 종료한 뒤 다시 실행해 주세요. 문제가 계속되면 앱 데이터를 삭제하지 말고 문의해 주세요.")
                )
            }
        }
    }
}
