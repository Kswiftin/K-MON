# 릴리스 프로세스

버전 배포는 **태그 하나로 시작한다.** 로컬 스크립트는 태그를 안전하게 만드는 일만 하고,
빌드·서명·appcast·Release 공개는 GitHub Actions(`.github/workflows/release.yml`)가 전부 맡는다.
로컬과 CI 가 서로 다른 바이너리를 배포하거나 Asset 없는 Release 가 먼저 공개되는 일을 막는 구조다.

## 한 줄 배포

```bash
./scripts/release.sh 2.9.0     # v 접두어 없이 x.y.z
```

### `release.sh` 가 검사하는 것

1. 버전 형식이 `x.y.z` 인가
2. 현재 브랜치가 `main` 인가
3. 커밋되지 않은 변경이 없는가
4. `HEAD` 가 `origin/main` 과 같은가 (`git fetch --no-tags origin main`)
5. `v<version>` 태그가 로컬·원격에 없는가
6. `./scripts/test-gate.sh` 가 통과하는가 (전체 테스트 + 자체 warning 0 + 로직 코어 커버리지)
7. 통과하면 주석 태그를 만들어 push → 여기서부터 비가역

### `release.yml` 이 하는 것

태그 push 로 시작해 순서대로 수행한다.

1. 태그 형식 + **태그 커밋이 `origin/main` HEAD 인지** 검증
2. Sparkle 서명키·macOS 서명 인증서(`MACOS_SIGNING_CERTIFICATE_P12`)·`KMON_GITHUB_OAUTH_CLIENT_ID` 존재 확인
3. `test-gate.sh` 재실행 (cold build — 로컬 warm build 가 숨긴 warning 이 여기서 잡힌다)
4. `build-app.sh` 로 앱 빌드 (`KMON_VERSION` 은 태그에서 주입, `CODESIGN_IDENTITY=K-MON Release`,
   `PTB_REQUIRE_STABLE_SIGN=1` 이라 ad-hoc 폴백이 금지된다)
5. Sparkle 프레임워크 임베드·서명·OAuth Client ID 확인
6. `Pokedoro.zip` + `Pokedoro.zip.sha256` + 서명된 `appcast.xml` 생성
7. 모든 검사를 통과한 **뒤에** GitHub Release 공개 (`--generate-notes`)

> 태그를 push 한 뒤 워크플로가 끝나기 전에 다른 PR 을 `main` 에 머지하면 2단계에서 실패한다.
> 런이 끝날 때까지 머지를 멈춘다.

## 릴리스 전 문서 체크리스트

기능·동작이 바뀐 릴리스면 **태그를 만들기 전에** 반영한다. 자세한 절차와 함정은
`docs/reference/release-workflow.md`.

- [ ] **README.md / README.en.md / README.ja.md** — 기능 목록, 화면 구성, 요구사항. 3개 언어 동시.
- [ ] **`assets/` 스크린샷** — UI(`Sources/PokeTokenBar/UI/`)가 바뀌었으면 갱신하고, **신규 기능이면
      새 에셋을 추가**한다(기존 이미지 재생성만으로는 새 화면이 문서에 없는 상태로 나간다). 던전
      방걷기 화면·트레이너 꾸미기(옷장)를 담은 스크린샷은 다음 릴리스에서 갱신이 필요하다.
- [ ] **`scripts/build-app.sh` 의 `DEFAULT_VERSION`** — 손으로 빌드한 앱만 옛 버전으로 뜨지 않게
      새 버전으로 올린다. 배포 산출물은 태그에서 주입받으므로 이 값을 쓰지 않는다.

## 릴리스 노트

CI 가 `gh release create --generate-notes` 로 PR 목록에서 자동 생성한다. 요약을 손보려면 공개 후:

```bash
gh release edit v2.9.0 --notes-file /tmp/notes.md
```

## 실패했을 때

- **공개 전 실패**(빌드·서명·appcast 단계) — 태그를 지우고 고친 뒤 같은 버전으로 다시 시작한다.
  ```bash
  git tag -d v2.9.0 && git push origin :refs/tags/v2.9.0
  ```
- **공개 후 발견** — 이미 배포된 버전은 되돌리지 않고 다음 패치로 올린다.

## 배포 후 검증

```bash
gh run watch --workflow=release.yml       # 약 2~3분
gh release view v2.9.0                    # zip · sha256 · appcast 3개 확인
```

설치된 앱에서 업데이트 확인을 한 번 눌러 Sparkle 경로까지 확인한다.

## 서명

- 릴리스 빌드는 `K-MON Release` 인증서로 CI 에서 서명한다. 개인키는 Actions secret
  (`MACOS_SIGNING_CERTIFICATE_P12` / `MACOS_SIGNING_CERTIFICATE_PASSWORD`)에만 있고 레포에 없다.
- designated requirement 가 버전 간 고정되므로 사용자의 Keychain "항상 허용"이 업데이트 후에도 유지된다.
- 인증서를 재생성하면 DR 이 바뀌어 전 사용자가 다시 프롬프트를 본다 — 재생성 금지.
- 로컬 수동 빌드는 같은 이름의 자체서명 인증서를 `scripts/create-signing-cert.sh` 로 만들어 쓰고,
  없으면 ad-hoc 으로 떨어진다(로컬 개발용).
