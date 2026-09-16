# iCloud 설정 및 검증

현재는 로컬 모드입니다. Apple Developer 계정 식별자가 아직 없어 실제 CloudKit 연결은 활성화하지 않았습니다. 별도 서버나 앱 회원가입은 필요하지 않습니다.

## 먼저 로컬 기능 검증

[검증 체크리스트](VALIDATION.md)의 로컬 항목과 `swift test`를 먼저 실행하세요. 기존 데이터가 있다면 전체 메모 내보내기를 수행하고 테스트용 기기/계정으로 동기화를 검증하세요. 저장소 초기화 오류가 생겨도 앱을 삭제해 해결하지 마세요.

## Xcode 설정

1. `twig` 타깃의 Signing & Capabilities에서 Apple Developer Team과 실제 Bundle Identifier를 지정합니다.
2. **iCloud** capability를 추가하고 **CloudKit**을 선택합니다.
3. `iCloud.<실제 Bundle ID>` 형태의 컨테이너를 등록하고 선택합니다. 모든 지원 기기가 같은 컨테이너를 사용해야 합니다.
4. iOS 타깃에 **Background Modes → Remote notifications**를 추가합니다. Mac에서는 해당 iCloud capability와 서명 권한을 확인합니다.
5. 타깃의 Info에 사용자 정의 String 키 **`TwigCloudKitContainer`**를 추가하고 위 컨테이너 ID를 입력합니다. Info.plist 자동 생성 방식을 유지하려면 Build Settings에 `INFOPLIST_KEY_TwigCloudKitContainer`를 추가해 같은 문자열을 Debug/Release에 지정할 수도 있습니다.
6. Xcode가 만든 entitlements 파일이 Code Signing Entitlements에 연결됐는지 확인합니다. 직접 만든 가짜 Team ID나 placeholder 컨테이너를 사용하지 않습니다.
7. 같은 iCloud 계정으로 로그인한 두 실제 기기에 설치합니다.

`StorageConfiguration.makeContainer()`는 이 키가 없으면 `.none`, 설정되면 지정한 `.private(containerID)`를 사용합니다. 상태 문구의 “동기화 설정됨”은 설정이 활성화됐다는 뜻이며 업로드 완료 표시가 아닙니다.

Apple은 CloudKit 연동 모델에서 고유성 제약과 필수 관계에 제한을 둡니다. 이 앱은 고유성 제약을 추가하지 않고 기본값이 있는 필드 및 선택적 ID를 사용합니다. 관계 무결성은 앱의 가지 조작 코드가 관리합니다. [Apple: SwiftData 동기화](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)

## 두 기기 테스트

- A에서 폴더·부모·자식 메모를 만든 후 B에서 내용과 구조 확인
- A를 오프라인으로 전환해 편집 → 앱 재실행 → 내용 유지 → 온라인 복귀 후 B 확인
- A/B에서 같은 메모를 서로 다른 내용으로 수정 → 양쪽의 편집 기록에 각각의 내용이 남는지 확인
- 제목, 본문, 태그, 사용자 지정 날짜가 같은 편집 기록으로 복구되는지 확인
- 양쪽에서 부모 변경/삭제/복구가 겹칠 때 메모가 사라지거나 무한 트리가 되지 않는지 확인
- 로컬 데이터가 있는 설치에 iCloud를 켰을 때 기존 메모가 유지되는지 확인
- 로그인 해제, iCloud 저장 공간 부족, 네트워크 단절 상황에서 로컬 입력 확인

SwiftData 자동 동기화는 즉시 완료나 임의의 트리 작업 전체에 대한 원자적 처리를 보장하는 앱 수준 트랜잭션이 아닙니다. 계정 전환과 구조 충돌을 실제 기기에서 확인하기 전에는 동기화 안정성이 검증됐다고 볼 수 없습니다.

## 배포 전

CloudKit Console에서 Development 스키마를 검증한 뒤 Production에 배포해야 합니다. TestFlight/실제 배포 환경과 개발 환경을 구분해 확인하세요. Apple Developer 등록, 인증서, 프로비저닝, 컨테이너 생성 및 Production 스키마 배포는 이 작업에서 수행하지 않았습니다.

참고: [Apple: ModelConfiguration](https://developer.apple.com/documentation/swiftdata/modelconfiguration), [Apple: SwiftData 동기화](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
