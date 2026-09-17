import SwiftUI

struct SyncStatusView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var monitor = SyncStatusMonitor()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(monitor.availability.label, systemImage: monitor.availability.systemImage)
                        .font(.headline)
                    Text(monitor.availability.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section("현재 준비된 항목") {
                    Label("CloudKit 호환 SwiftData 모델", systemImage: "checkmark.circle")
                    Label("오프라인 우선 로컬 저장", systemImage: "checkmark.circle")
                    Label("기기별 편집 기록 구분", systemImage: "checkmark.circle")
                    Label("외부 편집 변경 감지", systemImage: "checkmark.circle")
                }

                Section("Developer 등록 후 필요한 항목") {
                    Label("iCloud CloudKit capability", systemImage: "circle")
                    Label("Remote notifications background mode", systemImage: "circle")
                    Label("CloudKit 컨테이너와 Production 스키마", systemImage: "circle")
                    Label("여러 실제 기기 동기화 검증", systemImage: "circle")
                }

                if let containerID = StorageConfiguration.cloudContainerID {
                    Section("CloudKit 컨테이너") {
                        Text(containerID).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("동기화 상태")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem { Button("다시 확인", systemImage: "arrow.clockwise") { Task { await monitor.refresh() } } }
            }
            .task { await monitor.monitorAccountChanges() }
        }
        .editorSheetSize(minHeight: 440)
    }
}
