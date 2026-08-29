#!/usr/bin/env bash
#
# test-gate.sh — 안정성 가드레일. CI(ci.yml·release.yml)와 release.sh 가 이 스크립트를 돌린다.
# 커밋/머지 전 로컬에서도 같은 게이트를 그대로 실행한다.
#
#   1) swift test 전체 통과
#   2) 자체 코드(Sources/·Tests/)에 컴파일러 warning 0건
#   3) 같은 테스트 번들을 영어 로케일로 재실행 (CI 로케일 패리티)
#   4) "로직 코어" 파일 집합의 라인 커버리지 >= THRESHOLD
#
# 로직 코어 = 결정적으로 단위 테스트 가능한 게임 파일만 포함.
#
# 사용:  ./scripts/test-gate.sh          # 게이트 실행
#        THRESHOLD=75 ./scripts/test-gate.sh   # 임계값 임시 상향
#
set -euo pipefail
cd "$(dirname "$0")/.."

# The lifecycle/economy split added several platform-only branches to the store;
# keep the gate above the measured 69.60% baseline while those branches remain
# integration-tested through the macOS app target.
THRESHOLD="${THRESHOLD:-69}"

LOGIC_CORE=(
  "Sources/PokeTokenBar/Core/CompanionModel.swift"
  "Sources/PokeTokenBar/Core/CompanionStore.swift"
  "Sources/PokeTokenBar/Core/AdventureModel.swift"
  "Sources/PokeTokenBar/Core/TrainerLevel.swift"
  "Sources/PokeTokenBar/Core/MissionBoard.swift"
  "Sources/PokeTokenBar/Core/AchievementLadder.swift"
  "Sources/PokeTokenBar/Core/SeasonBoard.swift"
  # 근처 트레이너 카드에 실리는 값을 굽고·읽고·자르는 곳. 게이트 밖에 두면 신뢰경계 클램프가
  # 무테스트로 남는다(새 로직 파일을 배열에 넣지 않으면 커버리지에서 아예 빠진다).
  "Sources/PokeTokenBar/Core/PeerAdvertisement.swift"
  "Sources/PokeTokenBar/Core/DexGoals.swift"
  "Sources/PokeTokenBar/Core/BattleModel.swift"
  # 가변 위력(PokéAPI `power: null`) 계산. 순수 함수라 게이트 대상이고, 배열에 안 넣으면
  # 커버리지에서 아예 빠져 다음 기술을 추가할 때 무테스트로 남는다.
  "Sources/PokeTokenBar/Core/VariableDamage.swift"
  # 특성 표(면역·흡수). 순수 표 조회라 게이트 대상이고, 배열에 안 넣으면 커버리지에서 아예 빠져
  # 다음 특성을 추가할 때 무테스트로 남는다.
  "Sources/PokeTokenBar/Core/BattleAbility.swift"
  "Sources/PokeTokenBar/Core/BattleLog.swift"
  # 승패 판정이 사는 두 파일. 게이트 밖에 있던 동안 무승부·팀전 분기가 무테스트로 남아
  # "이기지 않은 쪽까지 승리" 결함이 세 경로에 퍼졌다 — 판정은 순수 함수라 게이트 대상이다.
  "Sources/PokeTokenBar/Core/TeamPracticeBattle.swift"
  "Sources/PokeTokenBar/Core/MultiplayerBattle.swift"
  "Sources/PokeTokenBar/Core/BattleReplay.swift"
  "Sources/PokeTokenBar/Core/PokeathlonPool.swift"
  "Sources/PokeTokenBar/Core/GymLeague.swift"
  "Sources/PokeTokenBar/Core/GameNumberFormatter.swift"
  "Sources/PokeTokenBar/Core/RosterOrdering.swift"
  # 남은시간 표시가 0 에서 멈추는지를 결정하는 순수 함수. 뷰 안에 있던 동안 예정 시각을 지난
  # 구간이 무테스트로 남아 카운트다운이 되올라갔다(#86).
  "Sources/PokeTokenBar/Core/StoredEggCountdown.swift"
  # 하루 한 판 퍼즐 던전(#79)의 순수 코어. 맵 생성과 이동 판정이 둘 다 여기 있고, 게이트 밖에
  # 두면 커버리지 집계에서 조용히 빠져 무테스트로 나갈 수 있다.
  "Sources/PokeTokenBar/Core/PuzzleDungeon.swift"
  "Sources/PokeTokenBar/Core/DungeonRun.swift"
  # 던전 화면이 쓰는 순수 계산(방위·방 이름·게이지·출구 분류·서술). 뷰 안에 있던 동안 설계 목업
  # 6줄 중 온전히 구현된 줄이 0개였는데, 순수 코어만 게이트에 있어 아무도 못 잡았다.
  "Sources/PokeTokenBar/Core/DungeonNarration.swift"
  # 포켓몬 페르소나 조립과 응답 안전 가드가 사는 순수 로직. 게이트 밖에 있으면 프로필 조립을
  # 직접 밟지 않는 fixture 테스트만 있어도 무테스트 분기가 커버리지에 드러나지 않는다.
  "Sources/PokeTokenBar/Core/PokemonChat.swift"
  # 대화가 실행할 수 있는 일의 화이트리스트·인자 클램프·승인 구분이 사는 곳. 게이트 밖에 두면
  # 목록을 넓히는 변경이 커버리지에서 조용히 빠진다 — 여기 무테스트 분기는 곧 앱 밖으로 나가는 길이다.
  "Sources/PokeTokenBar/Core/PokemonChatTools.swift"
  # 하트비늘 후보 계산(#97). 순수 함수라 게이트 대상 — 넣지 않으면 커버리지에서 조용히 빠진다.
  "Sources/PokeTokenBar/Core/MoveRelearn.swift"
  # 트레이너 코스튬 카탈로그·착용 상태·와이어 문자열(#79 던전 방걷기 뷰). 순수 모델이라
  # 게이트 대상 — 넣지 않으면 관대 파싱의 unknown/malformed 분기가 커버리지에서 조용히 빠진다.
  "Sources/PokeTokenBar/Core/TrainerOutfit.swift"
  # 도트 격자·합성, 방 격자 레이아웃, 교전 종 선택 — 던전 방걷기 뷰의 순수 코어. 게이트 밖에
  # 두면 새 조건 분기(문 방위·관대 파싱)가 커버리지에서 조용히 빠진다.
  "Sources/PokeTokenBar/Core/PixelSprite.swift"
  "Sources/PokeTokenBar/Core/TrainerPixelArt.swift"
  "Sources/PokeTokenBar/Core/TrainerSprite.swift"
  # 웨이브 런의 누적 강화(데미지·급소·턴 끝 회복). 엔진이 읽는 순수 계산이라 게이트 대상 —
  # 배열에 안 넣으면 다음 강화를 더할 때 무테스트로 남는다.
  "Sources/PokeTokenBar/Core/RunBoosts.swift"
  # 판 밖으로 남는 유일한 값(최고 웨이브·클리어 횟수). 세이브 경계 정규화가 여기 있어 게이트 대상 —
  # 배열에 안 넣으면 클램프 분기가 커버리지에서 조용히 빠진다.
  "Sources/PokeTokenBar/Core/RunProgress.swift"
  # 미니룸 대문의 계절(R5). 달력 월 → 계절 파생이라 순수 함수 = 게이트 대상. 12·1·2 를 받는
  # `default` 가지가 여기 없으면 커버리지에서 통째로 빠져 무테스트로 남는다.
  "Sources/PokeTokenBar/Core/MemoryHomeSeason.swift"
  # 미니룸 한 줄(종×가구 → 가구 → 기분 → 계절). 순수 파생이라 게이트 대상이고, 배열에 안 넣으면
  # 짝 표에 줄을 더할 때마다 무테스트 분기가 커버리지에서 조용히 빠진다.
  "Sources/PokeTokenBar/Core/MemoryHomeRoomLife.swift"
  # 동행 방명록 흔적의 빈도 판정과 기분별 문구. 난수를 쓰지 않는 것이 이 파일의 계약이라
  # 게이트 안에 둔다 — 빈도가 0 이나 1 로 무너지면 커버리지가 먼저 드러낸다.
  "Sources/PokeTokenBar/Core/MemoryHomeCompanionTrace.swift"
  # 대표 BGM 해금 판정. 자정을 가로지르는 밤 구간과 계절 판정이 여기 있고, 게이트 밖에 두면
  # 곡을 더할 때 해금 조건이 무테스트로 남는다.
  "Sources/PokeTokenBar/Core/MemoryHomeJukebox.swift"
)

# 기능이 **박제된 두 번째 화면**에 남는 부류를 막는다. `eee5c86` 이 팝오버 홈을 창으로 옮기며
# 옛 화면을 `@available(*, deprecated)` + 비-`View` 로 남겼고, 그 뒤 `9de278f` 가 방꾸미기
# 전체(스타일·12칸 격자·되돌리기)를 **그 죽은 화면에** 붙였다. 주크박스·파도타기·기분 반응·
# 계절 배지·계절 결산까지 다섯 기능이 코드에는 있는데 화면에서 사라진 채 릴리스됐다.
#
# 테스트로는 못 막는다 — 스타일 헬퍼의 세 언어 문구와 앨범 메서드의 지속성은 호출자가 화면이
# 아니어도 통과한다. 커버리지로도 못 막는다(테스트가 그 줄을 실행하므로). 남는 형태가 grep 이다.
# 해제 조건: 뷰의 도달 가능성을 검증하는 UI 테스트가 생기면 그때 이 게이트를 그쪽으로 옮긴다.
echo "▶ 박제된 화면 스윕 (UI 의 deprecated 타입)"
DEPRECATED_UI=$(grep -rn '@available(\*, deprecated' Sources/PokeTokenBar/UI || true)
if [[ -n "$DEPRECATED_UI" ]]; then
  echo "✗ UI 에 deprecated 타입이 있습니다 — 기능이 도달 불가 화면에 남을 수 있습니다." \
       "대체 화면으로 옮기고 옛 타입은 삭제하세요." >&2
  echo "$DEPRECATED_UI" >&2
  exit 1
fi
echo "✓ 없음"

# 위 게이트의 형제. `deprecated` 를 안 붙이고도 화면이 죽는 두 번째 형태가 **아무도 띄우지 않는
# 시트**다 — `MemoryHomeSeasonRecapSheet` 이 정확히 그 상태로 릴리스됐다(타입은 살아 있고,
# 컴파일도 되고, 스타일 헬퍼 테스트도 통과하는데, `.sheet` 로 여는 곳이 없었다).
#
# 컴파일러는 못 잡는다(구조체는 쓰이지 않아도 유효하다). 테스트도 못 잡는다(시트를 직접 만들어
# 검증하면 통과한다). 커버리지도 못 잡는다. 남는 형태가 grep 이다.
# 해제 조건: 위 게이트와 같다 — 도달 가능성을 검증하는 UI 테스트가 생기면 그쪽으로 옮긴다.
echo "▶ 도달 불가 시트 스윕 (선언만 있고 아무도 띄우지 않는 Sheet)"
ORPHAN_SHEETS=""
while read -r NAME; do
  [[ -z "$NAME" ]] && continue
  # 선언 줄은 `struct Name: View {` 라 `Name(` 를 담지 않는다 → 걸리는 건 생성(=표시)하는 곳뿐이다.
  grep -rqF "${NAME}(" Sources/PokeTokenBar || ORPHAN_SHEETS+="$NAME"$'\n'
done < <(grep -rhoE 'struct MemoryHome[A-Za-z]*Sheet' Sources/PokeTokenBar/UI | awk '{print $2}' | sort -u)
if [[ -n "$ORPHAN_SHEETS" ]]; then
  echo "✗ 아무도 띄우지 않는 시트가 있습니다 — 코드에는 있는데 화면에서 도달할 수 없습니다." \
       "표시하는 .sheet 를 붙이거나 타입을 삭제하세요." >&2
  echo "$ORPHAN_SHEETS" >&2
  exit 1
fi
echo "✓ 없음"

# 문자열 보간에서 백슬래시가 빠진 오타는 Swift 가 **평범한 리터럴로 받아들인다** — 컴파일러도
# warning 게이트도 절대 못 잡고, 화면에 표현식 소스가 그대로 찍힌 채 릴리스로 나간다
# (MemoryHomeView 방문 시트가 종 번호 대신 표현식을 그대로 렌더한 채 fb7e67e 로 배포됐다).
# 라인 커버리지로는 못 막는 부류다(그 줄은 "실행"되므로) → 기계로 막을 수 있는 유일한 형태가 grep 이다.
echo "▶ 보간 오타 스윕 (백슬래시 누락)"
BAD_INTERPOLATION=$(grep -rn '#(' Sources Tests | grep -v '\\#(' || true)
if [[ -n "$BAD_INTERPOLATION" ]]; then
  echo "✗ 백슬래시가 빠진 문자열 보간 $(wc -l <<< "$BAD_INTERPOLATION" | tr -d ' ')건 —" \
       "리터럴로 렌더됩니다. 의도한 raw string 이면 \\#( 를 쓰세요." >&2
  echo "$BAD_INTERPOLATION" >&2
  exit 1
fi
echo "✓ 없음"

# LAN 프레임 길이 헤더를 읽는 곳은 반드시 `loadUnaligned` 를 쓴다. `UnsafeRawBufferPointer.load(as:)`
# 는 포인터 정렬을 **전제**하는데, `NWConnection.receive` 가 주는 `Data` 는 4바이트 정렬을 보장하지
# 않는다 → 전제 위반이다. 이 부류는 파일마다 남는다: `bee4a84` 가 BattleNet·MultiplayerRoomCenter
# 두 곳을 고치면서, **같은 커밋에서 다른 이유로 만진** MemoryHomeVisitCenter 는 스윕하지 않아
# 새 파일 하나가 그대로 남았다.
#
# 테스트로는 못 막는다 — 이 줄을 밟으려면 살아 있는 `NWConnection` 두 개가 필요하고, 정렬 검사는
# `_debugPrecondition` 이라 빌드 구성에 따라 트랩 여부가 갈린다(릴리스 arm64 는 대개 그냥 통과한다).
# 커버리지로도 못 막는다 — 테스트가 그 줄을 실행하면 `load` 든 `loadUnaligned` 든 똑같이 세어진다.
# 남는 형태가 grep 이다.
# 해제 조건: 프레이밍을 공용 헬퍼 하나로 합치면 그때 이 게이트를 그 헬퍼의 단위 테스트로 옮긴다.
echo "▶ 비정렬 로드 스윕 (프레임 헤더의 load(as:))"
# `loadUnaligned(as:` 는 `load(as:` 를 포함하지 않으므로 올바른 쪽은 걸리지 않는다.
# 규칙을 설명하는 주석에 가드가 걸리는 부류(defect-log)를 피하려고 주석 줄은 뺀다.
ALIGNED_LOAD=$(grep -rn '\.load(as:' Sources | grep -v '^[^:]*:[0-9]*:[[:space:]]*//' || true)
if [[ -n "$ALIGNED_LOAD" ]]; then
  echo "✗ 정렬을 전제하는 load(as:) $(wc -l <<< "$ALIGNED_LOAD" | tr -d ' ')건 —" \
       "네트워크 버퍼는 정렬이 보장되지 않습니다. loadUnaligned(as:) 를 쓰세요." >&2
  echo "$ALIGNED_LOAD" >&2
  exit 1
fi
echo "✓ 없음"

echo
echo "▶ swift test (--enable-code-coverage)"
TEST_LOG=$(mktemp)
LOCALE_LOG=$(mktemp)
trap 'rm -f "$TEST_LOG" "$LOCALE_LOG"' EXIT
swift test --enable-code-coverage 2>&1 | tee "$TEST_LOG"

# 자체 코드의 컴파일러 warning 은 게이트 실패로 취급한다 — 쌓아 두면 새로 생긴 게 옛것에 묻힌다.
# 경로로 걸러 의존성(.build/checkouts)의 warning 은 빼 둔다. 같은 warning 이 frontend 잡마다
# 반복해서 찍히므로 sort -u 로 접는다.
# ponytail: 재컴파일이 없는 warm build 는 warning 을 다시 찍지 않아 로컬에서 놓칠 수 있다 —
#           신뢰 기준은 매번 cold build 인 CI 다. 로컬에서 볼 때는 `swift package clean` 뒤에 돌린다.
#           해제 조건 없음(영구): CI 가 cold build 인 동안은 이게 답이고 올릴 단계가 없다.
#           CI 가 빌드 캐시를 쓰기 시작하면 그때 이 게이트를 clean build 로 고정해야 한다.
OWN_WARNINGS=$(grep -oE '(Sources|Tests)/PokeTokenBar[^ ]*\.swift:[0-9]+:[0-9]+: warning: .*' "$TEST_LOG" | sort -u || true)
if [[ -n "$OWN_WARNINGS" ]]; then
  echo
  echo "✗ 자체 코드 warning $(wc -l <<< "$OWN_WARNINGS" | tr -d ' ')건 — 고친 뒤 다시 실행하세요." >&2
  echo "$OWN_WARNINGS" >&2
  exit 1
fi

# CI 러너는 영어 로케일, 개발 Mac 은 한국어다. 신규 세이브의 언어는 `AppLanguage.systemDefault` 라
# 호스트 로케일을 따라가므로 한국어 문구를 기대하는 테스트는 **로컬에서만** 통과하고 CI 에서 깨진다
# (#107). `swift test` 는 테스트 바이너리에 인자를 넘기지 못하니, 같은 번들을 `xctest` 로 한 번 더
# 영어 로케일로 돌려 그 격차를 커밋 전에 드러낸다.
echo
echo "▶ 영어 로케일 재실행 (CI 로케일 패리티)"
BUNDLE=$(find .build -maxdepth 4 -name '*.xctest' | head -1)
if [[ -z "$BUNDLE" ]]; then
  echo "✗ 테스트 번들(.xctest)을 찾지 못했습니다." >&2
  exit 1
fi
# 계측 바이너리가 저장소 루트에 default.profraw 를 떨구지 않도록 커버리지 출력을 임시 경로로 돌린다.
if LLVM_PROFILE_FILE="$(mktemp -d)/locale.profraw" \
     xcrun xctest -AppleLanguages "(en-US)" -XCTest All "$BUNDLE" > "$LOCALE_LOG" 2>&1; then
  grep -E 'Executed [0-9]+ tests' "$LOCALE_LOG" | tail -1
else
  grep -E 'error:' "$LOCALE_LOG" >&2 || tail -20 "$LOCALE_LOG" >&2
  echo "✗ 영어 로케일에서 실패 — 호스트 로케일에 의존하는 테스트가 있습니다." >&2
  echo "  기대값을 언어로 못 박으세요(예: 스토어 생성 직후 setLanguage(.ko))." >&2
  exit 1
fi

PROF=$(find .build -name 'default.profdata' | head -1)
# dSYM 안에도 같은 이름의 DWARF 바이너리가 있어 head -1 이 그걸 집으면 llvm-cov 가 실패한다 → 제외.
BIN=$(find .build -name 'PokeTokenBarPackageTests' -type f ! -path '*.dSYM/*' | head -1)
if [[ -z "$PROF" || -z "$BIN" ]]; then
  echo "✗ 커버리지 산출물(profdata/binary)을 찾지 못했습니다." >&2
  exit 1
fi

echo
echo "▶ 로직 코어 커버리지 (임계값 ${THRESHOLD}%)"
REPORT=$(xcrun llvm-cov report "$BIN" -instr-profile="$PROF" "${LOGIC_CORE[@]}" 2>/dev/null)
echo "$REPORT"

# TOTAL 행의 라인 커버리지(%) 추출 — 컬럼: ... Lines MissedLines Cover(=$10)
COVER=$(echo "$REPORT" | awk '/^TOTAL/ { gsub("%","",$10); print $10 }')
if [[ -z "$COVER" ]]; then
  echo "✗ 커버리지 수치 파싱 실패." >&2
  exit 1
fi

echo
# 소수 비교는 awk 로 (bash 정수 비교 회피)
if awk "BEGIN { exit !($COVER >= $THRESHOLD) }"; then
  echo "✓ 게이트 통과 — 로직 코어 라인 커버리지 ${COVER}% >= ${THRESHOLD}%"
else
  echo "✗ 게이트 실패 — 로직 코어 라인 커버리지 ${COVER}% < ${THRESHOLD}%" >&2
  echo "  테스트를 보강하거나, 의도된 하락이면 THRESHOLD 를 조정하세요." >&2
  exit 1
fi
