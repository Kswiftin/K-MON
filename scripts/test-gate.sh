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
  # 교환 세션의 상태 기계와 **상대가 보낸 채팅의 신뢰경계**(길이·정규형 재검사, 상대가 못 바꾸는
  # 키로 세는 속도 제한)가 사는 곳. 소켓 부분은 단위 테스트가 안 닿아 파일 수치는 낮지만, 배열에
  # 넣지 않으면 그 검증기가 커버리지에서 통째로 빠진다 — PeerAdvertisement 를 넣은 이유와 같다.
  "Sources/PokeTokenBar/Core/PokemonTrade.swift"
  # 경매의 제안 국면과 **연결 회수**가 사는 곳. 교환을 넣은 이유와 같다 — 소켓 부분은 단위
  # 테스트가 안 닿아 파일 수치는 낮지만, 배열 밖에 두면 그 판정들이 커버리지에서 통째로 빠진다.
  # `#228`(끝난 제안이 연결을 놓지 않는 부류)이 이 파일이 배열 밖이라 아무 신호도 없이 살았다.
  "Sources/PokeTokenBar/Core/PokemonAuction.swift"
  # 광고 이름의 바이트 예산. 네 LAN 센터가 전부 이 한 함수를 지나므로 여기가 무테스트면 부류가
  # 통째로 무테스트다 — 이전엔 `PlayerGymRoomName` 안에 숨어 있어 커버리지에서 보이지 않았다.
  "Sources/PokeTokenBar/Core/LANServiceName.swift"
  # 어떤 방을 목록에 보여 줄지 정하는 판정. 접두가 개설과 갈리면 만든 방이 어느 목록에도 안 뜨고
  # (#209 가 그 상태였다), 내 방을 안 거르면 눌러도 아무 일이 없는 버튼이 남는다. 여섯 활동의
  # 표가 여기 한 곳뿐이라 배열 밖에 두면 그 표 전체가 커버리지에서 빠진다.
  "Sources/PokeTokenBar/Core/LANRoomList.swift"
  # 원격 카드 검증기(`valid`)·광고 이름·집 목록 사상이 사는 곳. 소켓 부분은 단위 테스트가 안 닿아
  # 파일 수치는 낮지만, 배열 밖에 두면 그 순수 함수들이 커버리지에서 통째로 빠진다 —
  # `if !homes.isEmpty { lastError = nil }` 같은 새 분기를 아무도 못 본 이유가 이것이었다.
  "Sources/PokeTokenBar/Core/MemoryHomeVisitCenter.swift"
  "Sources/PokeTokenBar/Core/DexGoals.swift"
  # 업데이트 뒤 릴리스 노트를 띄울지 정하는 판정. 배열 밖에 두면 "신규 설치엔 안 띄운다"·
  # "버전당 한 번" 분기가 커버리지에서 통째로 빠진다.
  "Sources/PokeTokenBar/Core/ReleaseNotesGate.swift"
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
  # 웨이브 런(오늘의 던전)의 순수 코어. 웨이브 진행·보상 추첨·상대 마릿수 판정이 여기 있고,
  # 게이트 밖에 두면 커버리지 집계에서 조용히 빠져 무테스트로 나갈 수 있다.
  "Sources/PokeTokenBar/Core/RogueRun.swift"
  "Sources/PokeTokenBar/Core/RogueRunSave.swift"
  "Sources/PokeTokenBar/Core/RunBoosts.swift"
  # 런의 2대2 전투 — 타겟팅·네 명 턴 순서·기절 슬롯 보충이 여기 있다. 승패 판정이 사는 파일은
  # 게이트 대상이라는 규칙(`TeamPracticeBattle`)을 그대로 따른다.
  "Sources/PokeTokenBar/Core/WaveBattle.swift"
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
  # §14 파도타기의 다음 홈 선택과 발자국 파생. 순수 함수라 게이트 대상이고, 배열에 안 넣으면
  # "오늘 다 돌았을 때" 처럼 **한쪽만 참인 분기**가 커버리지에서 조용히 빠진다.
  "Sources/PokeTokenBar/Core/MemoryHomeSurf.swift"
  # 터미널 프런트엔드의 순수 코어 — 칸 폭 계산·화면 조립·키 배정·명령 파싱. 부수효과가 없어
  # 전부 테스트가 닿는 자리이고, 게이트 밖에 두면 새 명령·새 키가 무테스트로 나간다.
  # 터미널 제어(TUITerminal)와 실행 루프(TUIWatch)는 판단을 두지 않으므로 대상이 아니다.
  "Sources/PokeTokenBar/TUI/TUIText.swift"
  "Sources/PokeTokenBar/TUI/TUIRender.swift"
  "Sources/PokeTokenBar/TUI/TUIKeymap.swift"
  "Sources/PokeTokenBar/TUI/PokedoroCommand.swift"
  # LAN 협동 레이드(#80)의 순수 코어 — 오늘의 보스 추첨·해치 시각·정산, 그리고 **오늘자 보스
  # 검증**(`validBoss`)이 여기 있다. 그 검증이 곧 조작 호스트가 보상을 부풀리는 길을 막는 경계라
  # 게이트 밖에 두면 신뢰경계가 통째로 커버리지에서 빠진다.
  "Sources/PokeTokenBar/Core/RaidBoss.swift"
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

# 위 두 게이트의 셋째 형제. 타입도 시트도 살아 있는데 기능이 죽는 세 번째 형태가 **세이브에
# 쓰기만 하는 API** 다 — 앨범 mutator 를 아무 화면도 부르지 않으면 그 값은 영원히 기본값이다.
# Memory Home 방문이 정확히 그 상태로 릴리스됐다: `pin`·`setSharedPinnedMemory`·
# `setFeaturedPhoto`·`setPeerAlias`·`setMemoryHomeBlocked`·`clearProfileMessage` 여섯 개가
# 호출부 0곳이어서, 방문자가 받는 카드의 대표 기억·대표 사진이 **모든 릴리스에서 빈 값**이었고
# 누가 다녀갔는지 볼 화면도, 차단할 길도 없었다(TODAY/TOTAL 숫자만 올랐다).
#
# 테스트로는 못 막는다 — 앨범 메서드를 직접 호출해 지속성을 보면 전부 통과한다(호출자가 화면이
# 아니어도 통과하기 때문이다). 커버리지로도 못 막는다(테스트가 그 줄을 실행하므로 100% 로 찍힌다).
# 남는 형태가 grep 이다. 대상은 **`save()` 를 부르는 비-private 함수** 다 — 세이브를 바꾸는
# API 라는 것이 이 부류의 경계이고, `set` 접두만 보면 `pin` 같은 이름을 놓친다.
#
# **이 게이트가 잡는 것은 "호출부가 0곳" 하나다.** 실제로 여섯 번 일어난 형태가 그것이다.
# 잡지 못하는 것: 호출부가 **마운트되지 않은 뷰 멤버 안**에 있는 경우(아무도 그리지 않는
# `private var panel: some View` 안에서 mutator 를 부르면 여기서는 도달 가능해 보인다).
# 그 형태를 grep 으로 근사해 보았으나 뷰 멤버 200여 개에 오탐이 쏟아져 버렸다 — 시트에 한해
# 서는 위의 "도달 불가 시트 스윕" 이 그 몫을 하고, 일반 뷰 멤버는 UI 테스트의 몫으로 남는다.
# 해제 조건: 뷰의 도달 가능성을 검증하는 UI 테스트가 생기면 그때 이 게이트를 그쪽으로 옮긴다.
echo "▶ 호출부 없는 앨범 mutator 스윕 (세이브에 쓰기만 하는 API)"
# 화면에서 부르지 않는 것이 **맞는** 것들. 새로 넣을 때는 왜 그런지 여기 적는다.
CORE_ONLY_MUTATORS=(
  # 기억 숨기기. `isHidden` 은 결산·연속 카드가 이미 읽지만(`!isHidden` 필터) 켜는 화면이
  # 없어 값이 늘 false 다 = 그 필터들이 전부 무동작이다. 기억 관리 화면의 공백이라 방문
  # 기능과 분리해 남긴다 — 화면을 붙이거나 필터와 함께 지우는 것이 해소다.
  "setHidden"
  # legacy 방 테마. R8 `roomStyle` 이 대체했고 카드의 `roomTheme` 은 구버전 피어 호환으로만
  # 남아 있다. 로컬에서 고를 값이 아니므로 호출부가 없는 것이 맞다 — 은퇴시킬 때 와이어
  # 필드까지 함께 정리한다.
  "setTheme"
)
UNCALLED_MUTATORS=""
# **주석 줄은 빼고 센다.** 이 저장소의 문서 주석은 API 이름을 끊임없이 인용하므로, 원문 그대로
# 세면 `/// setPeerAlias(...) 는 …` 한 줄이 그 mutator 를 영원히 "호출됨" 으로 만든다 —
# 게이트가 잡으려는 바로 그 부류를 산문 한 줄로 통과시키는 셈이다. 줄 끝 주석은 코드를 함께
# 지울 위험이 있어 건드리지 않는다(줄 전체가 주석인 경우만 지운다).
SWIFT_CODE=$(find Sources/PokeTokenBar -name '*.swift' -exec cat {} + | sed '/^[[:space:]]*\/\//d')
while read -r NAME; do
  [[ -z "$NAME" ]] && continue
  SKIP=""
  for ALLOWED in "${CORE_ONLY_MUTATORS[@]}"; do [[ "$NAME" == "$ALLOWED" ]] && SKIP=1 && break; done
  [[ -n "$SKIP" ]] && continue
  # 호출부는 파일을 가리지 않는다 — 같은 파일 안에서만 불리는 것(`appendLocalMessage`)도
  # 도달 가능하다. 선언 줄 수와 등장 횟수가 같으면 아무도 부르지 않는 것이다.
  CALLS=$(printf '%s\n' "$SWIFT_CODE" | grep -oE "\b${NAME}\(" | wc -l | tr -d ' ')
  DECLS=$(printf '%s\n' "$SWIFT_CODE" | grep -oE "func ${NAME}\(" | wc -l | tr -d ' ')
  [[ "$CALLS" == "$DECLS" ]] && UNCALLED_MUTATORS+="$NAME"$'\n'
done < <(awk '
  # `static`·`nonisolated`·`override` 가 앞에 붙은 선언도 잡아야 한다. 놓치면 `name`·`priv` 가
  # **앞 함수의 값으로 남아**, 그 안의 `save()` 가 엉뚱한 이름에 붙는다(잡아야 할 것을 가리거나,
  # mutator 도 아닌 이름으로 빌드를 깨뜨린다).
  /func [A-Za-z_]+\(/ {
    priv = ($0 ~ /(private|fileprivate) func/)
    match($0, /func [A-Za-z_]+/); name = substr($0, RSTART + 5, RLENGTH - 5)
  }
  /save\(\)/ && name != "" && !priv && !seen[name] { print name; seen[name] = 1 }
' Sources/PokeTokenBar/Core/PokemonChat.swift | sort -u)
# 범위 한계(의도적, #225): 아직 이 한 파일만 훑는다. 같은 awk 를 `Core/CompanionStore.swift` 에
# 돌리면 호출부 0곳인 mutator 가 8개 나오고, 그중 둘(`ensureStarterCandidates`·`chooseStarter`)은
# 죽은 종 선택 경로라 allowlist 가 아니라 삭제 판단이 필요하다. 그 판단이 끝나면 범위를
# `Core/` 전체로 넓힌다.
# 이 가드가 **구조적으로 못 보는** 반대쪽도 있다: 짝이 아예 없는 mutator(켜기만 있고 끄기가
# 없는 것)는 "호출부 0곳" 이 될 수 없다. `docs/reference/defect-log.md` 의 같은 항목을 본다.
if [[ -n "$UNCALLED_MUTATORS" ]]; then
  echo "✗ 아무도 부르지 않는 앨범 mutator 가 있습니다 — 그 값은 영원히 기본값이고," \
       "방문자가 받는 카드에는 빈 필드로 나갑니다. 화면을 붙이거나 API 를 삭제하세요" \
       "(화면에서 부르지 않는 것이 맞다면 CORE_ONLY_MUTATORS 에 이유와 함께 넣으세요)." >&2
  echo "$UNCALLED_MUTATORS" >&2
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

# Bonjour 광고 이름은 **닉네임 + 설치별 고유 접미**여야 한다. 접미가 없으면 같은 이름을 쓰는 두
# 기기가 충돌하고, mDNS 가 한쪽을 `이름 (2)` 로 개명한다 → 개명당한 쪽은 저장된 원문으로 자기를
# 거르므로 상대를 자기로 착각해 목록에서 지운다. `BattleNet`·`PokemonTrade`·`MultiplayerRoomCenter`
# 는 처음부터 접미를 붙였는데 `MemoryHomeVisitCenter` 만 원문을 광고해 VISIT 이 조용히 죽어 있었다.
#
# 길이도 같은 결함의 일부다. Bonjour 인스턴스 이름 상한은 63 **UTF-8 바이트**라 글자 수로 자르면
# 한글 닉네임이 20자에 넘치고, mDNS 는 **꼬리부터** 자르므로 방금 붙인 고유 접미가 제일 먼저
# 사라진다 — 접미를 붙인 의미가 통째로 없어진다.
#
# 이전 판 게이트는 **식별자 이름**(`...serviceName`)만 봤다. `let serviceName = <맨 닉네임>` 이면
# 원래 결함을 그대로 넣고도 통과한다. 그래서 규칙을 "이름을 굽는 공용 헬퍼를 지나는가" 로 바꿨다 —
# 이전 판 주석이 적어 둔 해제 조건(`공용 헬퍼 하나로 네 센터를 합치면`)이 바로 이것이다.
# 예산 계산 자체는 `LANServiceNameTests` 가 검증한다. 여기서 막는 건 "헬퍼를 안 지나는 새 센터".
echo "▶ Bonjour 광고 이름 스윕 (공용 헬퍼 · 63바이트 예산)"
ADVERTISERS=$(grep -rlE 'NWListener\.Service|listener\.service *=' Sources/PokeTokenBar | sort -u)
BARE_SERVICE_NAME=""
while read -r FILE; do
  [[ -z "$FILE" ]] && continue
  grep -qF 'LANServiceName.make' "$FILE" || BARE_SERVICE_NAME+="$FILE (LANServiceName.make 미사용)"$'\n'
done <<< "$ADVERTISERS"
# 광고 줄이 문자열 리터럴을 그대로 이름으로 넘기면 헬퍼를 우회한 것이다.
LITERAL_NAME=$(grep -rnE '(NWListener\.Service|listener\.service *=).*name: *"' Sources/PokeTokenBar || true)
[[ -n "$LITERAL_NAME" ]] && BARE_SERVICE_NAME+="$LITERAL_NAME"$'\n'
# 광고 이름 변수에 리터럴·보간을 직접 담는 것도 같은 우회다(`let serviceName = "\(name)#\(tag)"`).
LITERAL_ASSIGN=$(grep -rnE '[sS]erviceName *= *"' Sources/PokeTokenBar || true)
[[ -n "$LITERAL_ASSIGN" ]] && BARE_SERVICE_NAME+="$LITERAL_ASSIGN"$'\n'
if [[ -n "$BARE_SERVICE_NAME" ]]; then
  echo "✗ 공용 헬퍼를 지나지 않고 Bonjour 이름을 굽는 곳이 있습니다 —" \
       "고유 접미가 없거나 63바이트에서 잘려 같은 이름의 두 기기가 서로를 자기로 오인합니다." \
       "\`LANServiceName.make(base:suffix:)\` 를 쓰세요." >&2
  echo "$BARE_SERVICE_NAME" >&2
  exit 1
fi
echo "✓ 없음"

# 같은 파일들의 형제 규칙. LAN 탐색 파라미터는 `includePeerToPeer` 를 켠다 — 안 켜면 AWDL
# (피어투피어) 경로로 붙은 이웃이 통째로 안 보인다. 네 센터 중 `MemoryHomeVisitCenter` 만
# 빠져 있었고, 컴파일도 테스트도 통과했다.
#
# 대상을 `listener.service`(=호스트)에서 뽑으면 **탐색 전용** 화면은 한 번도 안 본다 — 플래그가
# 빠졌을 때 실제로 이웃이 사라지는 쪽이 바로 그쪽이다. 그래서 `NWBrowser` 를 만드는 자리로 뽑는다.
echo "▶ LAN 파라미터 스윕 (includePeerToPeer)"
NO_P2P=""
while read -r FILE; do
  [[ -z "$FILE" ]] && continue
  # **대입**을 본다. 단어만 찾으면 그 규칙을 설명하는 주석이 게이트를 만족시킨다 —
  # `MemoryHomeVisitCenter` 는 실제로 그 주석을 갖고 있어, 코드 줄을 지워도 통과했다.
  grep -qE 'includePeerToPeer *= *true' "$FILE" || NO_P2P+="$FILE"$'\n'
done < <(grep -rlE 'NWBrowser\(|NWListener\.Service' Sources/PokeTokenBar | sort -u)
if [[ -n "$NO_P2P" ]]; then
  echo "✗ includePeerToPeer 를 켜지 않는 LAN 센터가 있습니다 —" \
       "AWDL 로 붙은 이웃이 목록에서 사라집니다." >&2
  echo "$NO_P2P" >&2
  exit 1
fi
echo "✓ 없음"

# 실패한 `NWBrowser`/`NWListener` 는 **참조를 버리기 전에 `cancel()`** 해야 한다. 참조만 버리면
# 객체가 큐·포트·핸들러를 붙든 채 살아남아 슬립 복귀·인터페이스 변경마다 하나씩 쌓이고, 죽은
# 브라우저가 계속 콜백을 쏜다. `BattleNet.startListener` 가 이 규칙을 주석으로 적어 두고도 정작
# 자기 `.failed` 분기에서 어겼고(같은 파일!), `MemoryHomeVisitCenter` 가 그대로 따라 했다.
# 테스트로는 못 막는다 — 누수는 관측 가능한 상태를 남기지 않는다.
echo "▶ 취소 없이 버려지는 LAN 객체 스윕"
ORPHANED=""
while IFS=: read -r FILE LINE _; do
  [[ -z "$FILE" ]] && continue
  BODY=$(sed -n "${LINE}p" "$FILE")
  # 주석 줄은 규칙을 설명하는 문장이다.
  [[ "$(echo "$BODY" | sed 's/^[[:space:]]*//')" == //* ]] && continue
  PREV=$(sed -n "$((LINE - 1))p" "$FILE")
  [[ "$BODY" == *"cancel()"* || "$PREV" == *"cancel()"* ]] || ORPHANED+="$FILE:$LINE:$BODY"$'\n'
done < <(grep -rnE '\b(browser|listener) = nil' Sources/PokeTokenBar || true)
if [[ -n "$ORPHANED" ]]; then
  echo "✗ cancel() 없이 참조만 버리는 LAN 객체가 있습니다 —" \
       "실패한 객체가 큐·포트를 붙든 채 남아 슬립 복귀마다 누적됩니다." >&2
  echo "$ORPHANED" >&2
  exit 1
fi
echo "✓ 없음"

# `lastError` 는 화면에 닿아야 존재한다. `MemoryHomeVisitCenter` 는 권한 거부(`NoAuth`)를 위한
# 3개국어 안내 문구까지 만들어 두고도 그 값을 어느 화면도 읽지 않아, 모든 실패가 "주변 홈을 찾는
# 중이에요…" 한 줄로 뭉개진 채 릴리스됐다 — 사용자에게는 원인 없는 무동작이다.
#
# 테스트로는 못 막는다(센터의 `lastError` 를 직접 읽어 검증하면 통과한다). 남는 형태가 grep 이다.
# 해제 조건: 뷰의 도달 가능성을 검증하는 UI 테스트가 생기면 그때 그쪽으로 옮긴다.
# 대상은 `...Center` 로 끝나는 클래스다 — LAN/세션 센터의 이름 규약이며, 같은 파일에 사는
# 타이머·스케줄러 같은 형제 타입을 오탐하지 않는 유일하게 싼 경계다.
#
# "그 파일이 센터 이름을 언급하고 어딘가에 lastError 라는 글자가 있다" 로는 못 막는다 —
# `PopoverView` 는 이미 `MemoryHomeVisitCenter` 를 언급하므로, 누가 거기에 **다른** 센터의
# 오류 줄을 붙이는 순간 이 게이트는 Memory Home 오류 UI 가 0줄이어도 통과한다. 그래서 그 파일에서
# **해당 타입으로 선언된 식별자**를 뽑아 `<그 변수>.lastError` 를 찾는다.
echo "▶ 침묵하는 실패 스윕 (화면이 읽지 않는 lastError)"
UNSHOWN_ERROR=""
while read -r CENTER; do
  [[ -z "$CENTER" ]] && continue
  SHOWN=""
  while read -r FILE; do
    [[ -z "$FILE" ]] && continue
    while read -r VAR; do
      [[ -z "$VAR" ]] && continue
      if grep -qE "\b${VAR}\.lastError\b" "$FILE"; then SHOWN=1; break; fi
    # `|| true` 가 없으면 안 된다 — `set -e` 아래서 첫 grep 이 빈손이면(=@Environment 로만 받는
    # 파일) 그룹이 거기서 끊겨 두 번째 형태를 영영 못 본다. 실제로 `BattleCenter` 를 오탐했다.
    done < <({ # `let visits: MemoryHomeVisitCenter` 형태
               grep -oE "(let|var) [A-Za-z_][A-Za-z0-9_]*: *${CENTER}\b" "$FILE" | awk '{print $2}' | tr -d ':' || true
               # `@Environment(BattleCenter.self) private var center` 형태 — 이쪽이 다수다.
               grep -oE "@Environment\(${CENTER}\.self\).*var [A-Za-z_][A-Za-z0-9_]*" "$FILE" | awk '{print $NF}' || true
             } | sort -u)
    [[ -n "$SHOWN" ]] && break
  done < <(grep -rlF "$CENTER" Sources/PokeTokenBar/UI | sort -u || true)
  [[ -n "$SHOWN" ]] || UNSHOWN_ERROR+="$CENTER"$'\n'
done < <(grep -rlF 'var lastError' Sources/PokeTokenBar/Core \
         | xargs -r grep -hoE 'final class [A-Za-z]+Center' | awk '{print $3}' | sort -u)
if [[ -n "$UNSHOWN_ERROR" ]]; then
  echo "✗ 화면이 읽지 않는 lastError 를 가진 센터가 있습니다 —" \
       "실패가 원인 없는 무동작으로 보입니다. 해당 화면에 오류 줄을 붙이세요." >&2
  echo "$UNSHOWN_ERROR" >&2
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
# 공유 버전 상수를 **여러 테스트가 리터럴로 박으면** 정당한 상향이 무관한 테스트를 무더기로
# 깨뜨린다. 레이드(#80)가 `protocolVersion` 을 14 → 15 로 올렸을 때 다섯 개가 빨개졌고 그중 넷은
# 레이드와 아무 관계가 없었다 — 빨간 게 다섯인데 넷이 무해하면 **진짜 회귀와 구별이 안 된다.**
# 그러면 다음 사람은 다섯을 기계적으로 sed 하고, 그 안에 섞인 진짜 실패를 같이 덮는다.
#
# 각 테스트가 주장하려던 사실은 대개 절대값이 아니라 "내 기능이 들어간 뒤로 되돌아가지 않았다"
# 이므로 `XCTAssertGreaterThanOrEqual` 로 쓴다. 정확한 현재 값의 동결은 **상수당 한 곳**에만 두고,
# 그 자리가 버전별 변경 이력도 함께 든다 — 올리는 사람이 고칠 곳이 하나면 빠뜨릴 자리도 없다.
#
# 테스트로는 못 막는다: 이 규칙의 위반은 "테스트가 여럿이다" 라는 소스의 성질이지 런타임 동작이
# 아니다. 커버리지로도 안 보인다(중복된 단언도 똑같이 실행된다). 남는 형태가 grep 이다.
#
# 대상은 **타입 프로퍼티**(대문자로 시작하는 수신자)뿐이다 — `state.economyVersion` 처럼 인스턴스
# 필드를 리터럴과 대조하는 건 그 테스트의 정당한 fixture 검증이라 여기 걸리면 안 된다.
# 한계: 리터럴이 다음 줄로 넘어가는 여러 줄 호출은 못 본다. 그 형태가 나오면 그때 넓힌다.
echo "▶ 버전 상수 리터럴 동결 스윕 (상수당 한 곳)"
VERSION_PINS=$(grep -rnE 'XCTAssertEqual\([A-Z][A-Za-z0-9_]*\.[A-Za-z0-9_]*Version, *[0-9]' Tests \
               | grep -vE '^[^:]*:[0-9]+:[[:space:]]*//' || true)
DUPLICATE_PINS=$(echo "$VERSION_PINS" | grep -oE '[A-Z][A-Za-z0-9_]*\.[A-Za-z0-9_]*Version' | sort | uniq -d || true)
if [[ -n "$DUPLICATE_PINS" ]]; then
  echo "✗ 같은 버전 상수를 여러 테스트가 리터럴로 박고 있습니다 —" \
       "정당한 상향이 무관한 테스트를 깨뜨려 진짜 회귀와 구별되지 않습니다." \
       "동결은 한 곳만 남기고 나머지는 XCTAssertGreaterThanOrEqual 로 자기 기능의 하한만 보세요." >&2
  while read -r SYMBOL; do
    [[ -z "$SYMBOL" ]] && continue
    echo "  $SYMBOL:" >&2
    echo "$VERSION_PINS" | grep -F "$SYMBOL" | sed 's/^/    /' >&2
  done <<< "$DUPLICATE_PINS"
  exit 1
fi
echo "✓ 없음"

# LAN 프레임을 읽는 콜백의 **실패 분기는 연결을 끝내야 한다.** 조용히 리턴하면 상대가 앱을 정상
# 종료했을 때 아무도 그것을 모른다 — TCP 는 FIN 만 남기고 `NWConnection` 상태는 `.ready` 에
# 머무르므로 `stateUpdateHandler` 의 `.failed`/`.cancelled` 가 영영 안 뜬다. 죽은 소켓 위에 세션이
# 살아 있는 것처럼 남는다.
#
# 이 부류는 **두 번 물렸다**: `PokemonTrade`(2026-08-30)를 고칠 때 형제 전수를 세지 않아
# `PokemonAuction` 이 남았고, 그게 `#228` 이 됐다. 부류를 문서에 적는 것으로는 스윕이 완료되지
# 않는다 — 그래서 게이트로 내린다.
#
# 테스트로는 못 막는다 — 이 줄을 밟으려면 살아 있는 소켓 두 개와 **정상 종료**가 필요하고, 닫힌
# 소켓에 한 바이트라도 쓰면 RST 가 `.failed` 로 돌아와 상태 핸들러가 회수해 버린다(결함을
# 되주입해도 통과한다). 커버리지로도 못 막는다 — `return` 이든 `drop` 이든 그 줄은 똑같이 세어진다.
#
# 한계 둘. ① 잡는 것은 **한 줄짜리** `else { return }` 이다(`#228` 이 가졌던 그 모양). 여러 줄로
# 벌어진 나쁜 분기는 못 본다 — 그 형태가 나오면 그때 넓힌다. ② `count` 비교를 요구하므로 길이
# 없는 `guard let data else { return }` 도 못 본다 — 그쪽까지 넓히면 소켓과 무관한 옵셔널 가드가
# 통째로 걸려 오진이 잡는 것보다 많아진다. 그래서 **오진은 표기로 뺀다**(아래 `not-a-socket`).
# 비정렬 로드 스윕과 같은 한계이고, 해제 조건도 같다: 프레이밍 다섯 벌을 공용 헬퍼로 합치면
# 이 게이트를 그 헬퍼의 단위 테스트로 옮긴다.
echo "▶ 조용히 끝나는 프레임 읽기 스윕 (실패 분기가 연결을 안 끊는다)"
SILENT_READ=$(grep -rnE 'guard .*\b(data|header)\.count *[=<>!]+.*else \{ *return *\}' Sources/PokeTokenBar \
              | grep -v '^[^:]*:[0-9]*:[[:space:]]*//' \
              | grep -v 'not-a-socket' || true)
if [[ -n "$SILENT_READ" ]]; then
  echo "✗ 프레임 읽기의 실패 분기가 조용히 리턴하는 곳 $(wc -l <<< "$SILENT_READ" | tr -d ' ')건 —" \
       "상대가 정상 종료하면 FIN 만 오고 상태는 .ready 에 머물러 죽은 소켓이 남습니다." \
       "drop()/connectionDropped()/cancel() 로 끝내세요." \
       "소켓 읽기가 아닌 바이트 파싱(세이브·블롭 파서 등)이면 그 줄 끝에 // not-a-socket 을 적어 빼세요." >&2
  echo "$SILENT_READ" >&2
  exit 1
fi
echo "✓ 없음"

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
