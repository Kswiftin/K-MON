# 개발 환경과 검증

이 저장소는 Pokédoro 앱을 만드는 Swift Package입니다. 패키지·실행 파일·데이터 디렉터리에는 기존 이름 `PokeTokenBar`를 사용합니다. 아래 명령은 저장소 루트에서 실행합니다.

## 환경

- macOS 14 이상.
- Swift 6 툴체인. 전체 XCTest 테스트와 CI와 같은 검증에는 Xcode 16 이상이 필요합니다.
- 의존성 버전은 `Package.swift`와 커밋된 `Package.resolved`를 따릅니다.

## 빌드

```bash
swift build
```

앱 번들을 만들려면 안정적인 로컬 서명 신원을 먼저 준비합니다.

```bash
./scripts/create-signing-cert.sh   # 최초 1회
KMON_SKIP_INSTALL=1 ./scripts/build-app.sh
```

산출물은 `build/Pokédoro.app`입니다. `KMON_SKIP_INSTALL=1`을 빼면 스크립트가 실행 중인 앱을 종료하고 `/Applications/Pokédoro.app`을 교체합니다. 서명 신원이 없으면 기본 빌드는 중단됩니다. ad-hoc 서명은 빌드마다 macOS 권한 확인이 반복될 수 있으므로 필요한 개발 상황에서만 `PTB_ALLOW_ADHOC=1`로 명시합니다.

## 테스트와 CI

Xcode가 있는 환경에서 전체 테스트를 실행합니다.

```bash
swift test
```

PR의 `build-test` 잡은 아래 게이트를 실행합니다. 전체 테스트, 자체 컴파일 경고, 로직 코어 커버리지와 변경 경로의 추가 검증을 함께 확인합니다.

```bash
./scripts/test-gate.sh
```

CI에는 이 게이트 앞에 별도 빌드 단계를 넣지 않습니다. 재컴파일이 생략되면 경고 검사가 진단 로그를 관측하지 못하기 때문입니다. 로컬에서 경고까지 확인할 때는 `swift package clean` 뒤 게이트를 실행합니다.

Command Line Tools만 있는 환경에서는 다음 명령으로 `Tests/PokeTokenBarLocalTests`의 swift-testing 테스트만 실행할 수 있습니다. `Tests/PokeTokenBarTests`의 XCTest 검증을 대체하지 않습니다.

```bash
./scripts/test-local.sh
```

PR에서는 `build-test`와 `secret-scan` 결과를 확인합니다. `main` push는 전체 테스트를 다시 실행하지 않고 검증 도구 캐시를 준비합니다. 릴리스 워크플로는 배포할 커밋을 별도로 검증합니다.

## 변경할 때 참고할 문서

- 협업 절차와 PR 작성: [기여 가이드](contributing.md).
- 코드와 테스트 작성 원칙: [개발 규약](conventions.md).
- 배포와 실패 대응: [릴리스 절차](releasing.md).
- 기능별 구현 계약과 과거 설계: [기술 참조 목록](../README.md#기술-참조).
