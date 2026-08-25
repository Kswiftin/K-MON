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
  # 하트비늘 후보 계산(#97). 순수 함수라 게이트 대상 — 넣지 않으면 커버리지에서 조용히 빠진다.
  "Sources/PokeTokenBar/Core/MoveRelearn.swift"
)

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
