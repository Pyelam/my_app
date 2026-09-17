import Foundation
import SwiftData

enum StorageConfiguration {
    static var cloudContainerID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "TwigCloudKitContainer") as? String,
              value.hasPrefix("iCloud."), !value.contains("$(") else { return nil }
        return value
    }

    static var status: String {
        cloudContainerID == nil ? "기기에 저장 · iCloud 미연결" : "기기에 저장 · iCloud 컨테이너 설정됨"
    }

    static func makeContainer() throws -> ModelContainer {
        let database: ModelConfiguration.CloudKitDatabase = cloudContainerID.map {
            ModelConfiguration.CloudKitDatabase.private($0)
        } ?? .none
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: false,
            cloudKitDatabase: database
        )
        return try ModelContainer(
            for: InspirationFolder.self, InspirationNote.self, NoteRevision.self,
            configurations: configuration
        )
    }
}
