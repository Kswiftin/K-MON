---
summary: "릴리스 실행 절차 — 태그 전용 release.sh, 문서·에셋 갱신 의무, 스크린샷 렌더 방법, 게이트의 함정."
read_when:
  - 버전을 배포할 때 (자연어 트리거 포함: "배포해줘", "릴리스 올려줘", "패치 배포")
  - release.sh 나 release.yml 게이트에 막혔을 때
  - UI 를 바꿔 스크린샷을 갱신해야 할 때
---

# 릴리스 실행 절차

버전 결정 규칙과 트리거는 `CLAUDE.md` §릴리스에 있다. 단계 목록과 스크립트 책임 분담은 `RELEASE.md`.
이 문서는 그 사이에 사람이 판단해야 하는 *실행 세부*를 담는다.

## 1. 문서·에셋 갱신 (매 릴리스 필수 — "할까요?" 묻지 말고 무조건 한다)

**스크립트가 이걸 검사하지 않는다.** 예전 `release.sh` 에는 문서 경고와 "신규 기능 = 신규 에셋"
하드 게이트가 있었지만, 태그 전용으로 축소되면서 함께 사라졌다. 지금 이 단계를 지키는 것은
`RELEASE.md` 체크리스트와 사람뿐이다.

- **README.md / README.en.md / README.ja.md** — 기능 목록·화면 구성. 셋 다 같은 골격이고
  (`핵심 동작`/`How it works`/`基本の流れ` → 표 형태의 `화면 둘러보기`/`Tour`), **세 파일 모두
  스크린샷을 싣는다.** 같은 문장을 세 번 붙여넣지 말고 각 언어로 다시 쓴다.
- **`assets/` 스크린샷** — 갱신(stale)과 커버리지(신규)는 다른 질문이다. 기존 이미지를 다시 그려도
  새 화면은 여전히 문서에 없다. 2.5.0 에서 플로팅 펫이 이미지 없이 나간 경로가 정확히 이것이다.
- 파일명 규약: 영어가 기본(`screenshot-gyms.png`), 한국어는 `-ko`·일본어는 `-ja` 접미
  (`screenshot-gyms-ja.png`). 언어에 따라 달라지는 글자가 화면에 없으면(도감 격자 등) 접미 없는
  파일 하나를 세 README 가 함께 쓴다 — 그때만 변형을 만들지 않는다.

### 스크린샷 만드는 방법 (HTML 렌더 — 라이브 캡처가 아니다)

팝오버를 실제로 띄워 찍지 않는다. 같은 치수의 HTML 목업을 그려 Chrome 헤드리스로 렌더한다.
렌더 자산은 저장소에 커밋하지 않으므로 매번 임시 디렉터리에서 만든다.

1. 치수를 소스에서 가져온다 — `PopoverMetrics.width` 360, `padding` 14(콘텐츠 폭 332),
   칩·슬롯 크기는 해당 View 의 `static let` (예: `TeamPickChip.height` 74, `chipWidth` 70).
2. 문구는 `Localization.swift` 의 실제 문자열을 쓴다(`t(ko, en, ja)`). 언어별로 치환만 바꿔 두 번 렌더한다.
3. 스프라이트는 앱과 같은 출처에서 받는다 — `https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/<id>.png`
   (`SpriteStore.base`). CSS 는 `image-rendering: pixelated`.
4. 다크 팝오버 배경 `#1c1c1e`, 강조색 `#0a84ff`, 본문 `rgba(255,255,255,0.92)` / 보조 `0.55` / 3차 `0.32`.
5. 렌더:
   ```bash
   "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
     --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
     --window-size=360,460 --screenshot=out.png "file://$PWD/mock.html"
   ```
   창 높이가 콘텐츠보다 크면 아래에 배경만 남는다 — PIL 로 균일한 아래쪽 줄을 잘라내고
   패딩 몫(14pt × 2배 = 28px)만 남긴다.
6. 결과는 폭 720px PNG(2배)다. 기존 에셋이 40~230KB 라 별도 최적화 없이 커밋해도 된다.
   애니 GIF(home)는 프레임 합성 후 `gifsicle -O3 --lossy` 로 줄인다(PIL 재인코딩 단독은 용량이 커진다).

## 2. 게이트의 함정

- **태그 push 후 `main` 머지 금지.** `release.yml` 은 태그 커밋이 `origin/main` HEAD 인지 확인한다.
  런 도중 다른 PR 이 머지되면 릴리스가 그 자리에서 실패한다.
- **같은 버전 재사용 불가.** `release.sh` 가 로컬·원격 태그 존재를 막으므로, 실패한 태그는
  `git tag -d` + `git push origin :refs/tags/<tag>` 로 지운 뒤 다시 시작한다.
- **로컬 warm build 는 warning 을 숨긴다.** `test-gate.sh` 의 warning 검사는 재컴파일 로그에 의존하므로
  로컬에서는 `swift package clean` 뒤에 돌린다. 신뢰 기준은 매번 cold build 인 CI 다.
- **커버리지 숫자는 증거가 아니다.** 새 조건 분기를 넣었으면 `xcrun llvm-cov show ... --show-regions` 로
  `^0` 을 직접 본다. 새 로직 코어 파일은 `test-gate.sh` 의 `LOGIC_CORE` 배열에 넣어야 세어진다 —
  넣지 않으면 게이트 밖에서 무테스트로 남는다(2.9.0 에서 `GymLeague.swift` 가 그 상태였다).
- **이 저장소에 랜딩(gh-pages)과 homebrew cask 는 없다.** 예전 문서가 지시했던 단계이니 찾지 않는다.
  README·인앱 업데이트 알림의 릴리스 표기는 동적이라 손댈 것도 없다.

## 3. 실행과 검증

```bash
./scripts/release.sh 2.9.0                # 태그 생성·push (v 없이)
gh run watch --workflow=release.yml       # 2~3분
gh release view v2.9.0                    # zip · sha256 · appcast
```

마지막으로 설치된 앱에서 업데이트 확인을 눌러 Sparkle 경로를 확인한다.
