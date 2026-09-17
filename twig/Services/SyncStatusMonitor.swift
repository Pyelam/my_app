import CloudKit
import Foundation
import Observation

enum SyncAvailability: Equatable {
    case localOnly
    case checking
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case unavailable(String)

    var label: String {
        switch self {
        case .localOnly: "기기에만 저장 중"
        case .checking: "iCloud 상태 확인 중"
        case .available: "iCloud 동기화 사용 가능"
        case .noAccount: "iCloud 로그인이 필요함"
        case .restricted: "iCloud 사용이 제한됨"
        case .temporarilyUnavailable: "iCloud를 일시적으로 사용할 수 없음"
        case .unavailable: "iCloud 상태를 확인할 수 없음"
        }
    }

    var detail: String {
        switch self {
        case .localOnly:
            "CloudKit 컨테이너가 아직 연결되지 않았습니다. 현재 데이터는 이 기기에 안전하게 보관됩니다."
        case .checking:
            "이 기기의 iCloud 계정 접근 상태를 확인하고 있습니다."
        case .available:
            "이 기기의 iCloud 계정을 사용할 수 있습니다. SwiftData가 변경 사항을 자동으로 동기화합니다."
        case .noAccount:
            "설정에서 iCloud에 로그인하고 iCloud Drive를 켜 주세요."
        case .restricted:
            "자녀 보호 기능이나 기기 관리 정책이 iCloud 접근을 제한하고 있습니다."
        case .temporarilyUnavailable:
            "로컬 데이터를 삭제하지 않습니다. 계정 상태가 바뀌면 다시 확인합니다."
        case .unavailable(let message):
            message
        }
    }

    var systemImage: String {
        switch self {
        case .available: "checkmark.icloud"
        case .checking: "icloud"
        case .localOnly: "internaldrive"
        case .noAccount, .restricted, .temporarilyUnavailable, .unavailable: "exclamationmark.icloud"
        }
    }
}

@MainActor
@Observable
final class SyncStatusMonitor {
    private(set) var availability: SyncAvailability = .localOnly

    func refresh() async {
        guard let containerID = StorageConfiguration.cloudContainerID else {
            availability = .localOnly
            return
        }

        availability = .checking
        let result: (CKAccountStatus, String?) = await withCheckedContinuation { continuation in
            CKContainer(identifier: containerID).accountStatus { status, error in
                continuation.resume(returning: (status, error?.localizedDescription))
            }
        }

        if let message = result.1 {
            availability = .unavailable(message)
            return
        }

        availability = switch result.0 {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .temporarilyUnavailable: .temporarilyUnavailable
        case .couldNotDetermine: .unavailable("잠시 후 다시 확인해 주세요. 로컬 데이터는 계속 사용할 수 있습니다.")
        @unknown default: .unavailable("알 수 없는 iCloud 계정 상태입니다.")
        }
    }

    func monitorAccountChanges() async {
        await refresh()
        for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }
}

enum InstallationIdentity {
    private static let defaultsKey = "TwigInstallationIdentifier"

    static let current: String = {
        if let existing = UserDefaults.standard.string(forKey: defaultsKey) {
            return existing
        }
        let identifier = UUID().uuidString
        UserDefaults.standard.set(identifier, forKey: defaultsKey)
        return identifier
    }()
}
