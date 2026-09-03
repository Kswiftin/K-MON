#!/usr/bin/env bash
#
# mutator-sweep.sh — "세이브에 쓰기만 하는 API" 스윕. `test-gate.sh` 가 부르고,
# `verify-mutator-gate.sh`(결함 주입 하네스)도 **같은 이 파일**을 부른다.
#
# 왜 게이트에서 떼어냈나: 판정을 테스트하려면 결함을 주입한 트리에 스윕만 돌려야 하는데,
# 인라인이면 하네스가 로직을 복사할 수밖에 없다 — 그러면 "찾는 쪽과 세는 쪽이 다른 규칙"
# (docs/reference/defect-log.md) 부류를 하네스와 게이트 사이에 새로 만든다. 한 파일을
# 둘이 부르면 하네스가 검증한 것이 곧 게이트가 실행하는 것이다.
#
# 종료코드: 0 = 죽은 mutator 없음 · 1 = 있음(목록을 stderr 로)
set -euo pipefail
cd "$(dirname "$0")/.."

# 위 두 게이트의 셋째 형제. 타입도 시트도 살아 있는데 기능이 죽는 세 번째 형태가 **세이브에
# 쓰기만 하는 API** 다 — 앨범 mutator 를 아무 화면도 부르지 않으면 그 값은 영원히 기본값이다.
# Memory Home 방문이 정확히 그 상태로 릴리스됐다: `pin`·`setSharedPinnedMemory`·
# `setFeaturedPhoto`·`setPeerAlias`·`setMemoryHomeBlocked`·`clearProfileMessage` 여섯 개가
# 호출부 0곳이어서, 방문자가 받는 카드의 대표 기억·대표 사진이 **모든 릴리스에서 빈 값**이었고
# 누가 다녀갔는지 볼 화면도, 차단할 길도 없었다(TODAY/TOTAL 숫자만 올랐다).
#
# 테스트로는 못 막는다 — 앨범 메서드를 직접 호출해 지속성을 보면 전부 통과한다(호출자가 화면이
# 아니어도 통과하기 때문이다). 커버리지로도 못 막는다(테스트가 그 줄을 실행하므로 100% 로 찍힌다).
# 남는 형태가 정적 분석이다. 대상은 **`save()` 를 부르는 비-private 함수** 다 — 세이브를 바꾸는
# API 라는 것이 이 부류의 경계이고, `set` 접두만 보면 `pin` 같은 이름을 놓친다.
#
# **이 게이트가 잡는 것은 "호출부가 0곳" 하나다.** 실제로 여섯 번 일어난 형태가 그것이다.
# 잡지 못하는 것: 호출부가 **마운트되지 않은 뷰 멤버 안**에 있는 경우(아무도 그리지 않는
# `private var panel: some View` 안에서 mutator 를 부르면 여기서는 도달 가능해 보인다).
# 그 형태를 grep 으로 근사해 보았으나 뷰 멤버 200여 개에 오탐이 쏟아져 버렸다 — 시트에 한해
# 서는 위의 "도달 불가 시트 스윕" 이 그 몫을 하고, 일반 뷰 멤버는 UI 테스트의 몫으로 남는다.
# 해제 조건: 뷰의 도달 가능성을 검증하는 UI 테스트가 생기면 그때 이 게이트를 그쪽으로 옮긴다.
echo "▶ 호출부 없는 mutator 스윕 (세이브에 쓰기만 하는 API)"
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

# **판정은 이름이 아니라 선언 위치로 한다**(#233). 이전 판은 `등장 횟수 == 선언 줄 수` 라는
# 이름 단위 산술이었다 — 스윕 범위가 `Sources/` 전부로 넓어지자 같은 이름이 여러 타입에 사는
# 일이 흔해져(`send` 9선언/120등장, `record` 6, `delete`·`tick`·`clamped` 3) **살아 있는 동명
# 함수의 호출부가 죽은 선언의 0곳을 메웠다.** grep 으로는 못 고친다: `store.send(...)` 가 9개
# `send` 중 어느 선언으로 해석되는지는 타입 추론이 필요하다.
#
# 그래서 SwiftPM 이 매 빌드마다 쓰는 인덱스 스토어를 읽는다(선언마다 USR, 참조마다 그 USR).
# 판정 본체는 `Tools/MutatorGate` 이고, 이 스크립트는 **정책**만 쥔다 — 예외 목록과 `debug`
# 접두 규칙. 도구가 못 보는 것 목록은 `Tools/MutatorGate/Sources/main.swift` 머리주석에 있다.
echo "  · 빌드 + 인덱스 스토어 준비"
# **먼저 빌드한다.** 낡은 인덱스를 읽으면 판정이 조용히 거짓이 된다(지운 선언이 유령으로
# 남거나, 새로 죽은 mutator 가 아직 인덱스에 없어 통과한다). CI 는 앞 단계에서 이미 빌드해
# 두므로 여기서는 대개 no-op 이고, 로컬에서도 게이트가 곧 쓸 빌드를 앞당기는 것뿐이다.
#
# **게이트와 같은 플래그로 빌드한다**(`--enable-code-coverage`). 플래그가 다르면 SwiftPM 이
# 모듈을 통째로 다시 컴파일한다 — plain 빌드 뒤 커버리지 빌드가 19초를 다시 쓰는 것을 실측했다.
# 인덱스 방출은 커버리지와 무관하므로, 뒤따르는 `swift test --enable-code-coverage` 가 이
# 산출물을 그대로 재사용하도록 맞추는 쪽이 공짜다.
swift build --enable-code-coverage >/dev/null
INDEX_STORE="$(swift build --show-bin-path)/index/store"
# 스토어가 없으면 **판정하지 않고 실패한다.** SwiftPM 이 인덱스 방출을 멈추거나 경로를 바꾸면
# "결함 0건" 과 "볼 것이 없었다" 가 구별되지 않는다 — 이 게이트가 존재하는 이유가 그 구별이다.
if [[ ! -d "$INDEX_STORE" ]]; then
  echo "✗ 인덱스 스토어가 없습니다($INDEX_STORE) — 판정할 수 없습니다." \
       "SwiftPM 이 인덱스를 방출하지 않으면 이 스윕은 아무것도 못 봅니다." >&2
  exit 1
fi
swift build --package-path Tools/MutatorGate >/dev/null
DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
export DEVELOPER_DIR

# 도구는 사실만 낸다: `<파일>:<줄><TAB><심볼 이름>`. 정책 필터는 아래에서 건다.
FINDINGS=$(./Tools/MutatorGate/.build/debug/MutatorGate "$INDEX_STORE" Sources/PokeTokenBar)

while IFS=$'\t' read -r LOCATION SYMBOL; do
  [[ -z "$LOCATION" ]] && continue
  # 인덱스의 심볼 이름은 인자 라벨까지 갖는다(`setTheme(_:for:)`). 예외 목록과 `debug` 규칙은
  # 맨이름으로 쓰므로 라벨을 떼고 대조한다 — 목록에 시그니처를 적게 하면 인자가 하나 바뀔
  # 때마다 목록이 조용히 무효가 된다.
  NAME="${SYMBOL%%(*}"
  # `debug` 접두는 **이름 하나하나가 아니라 규칙으로** 건너뛴다. 이 저장소의 `debug…` 는 전부
  # `/// 테스트 전용` 이 붙은 시딩 훅이라(화면에서 부르지 않는 것이 정상이다), 이름을 박아 두면
  # `debugSetFoo` 가 하나 늘 때마다 allowlist 가 같이 자란다 — 그때마다 손대는 목록은 결국
  # 아무도 안 읽는다. 관례를 규칙으로 올려 목록을 "진짜 예외" 에만 쓴다.
  #
  # **접두만으로는 면제하지 않는다 — `Tests/` 에 호출부가 있어야 한다.** 이름만 보고 통과시키면
  # 규칙 자체가 우회로가 된다(죽은 mutator 에 `debug` 를 붙이면 사라진다). 그리고 아무도 안 쓰는
  # 시딩 훅도 죽은 코드이므로 걸러야 한다 — 접두 규칙의 근거가 "테스트가 쓴다" 이니, 그것을 검사한다.
  # 해제 조건: 없다. 이 조건이 규칙의 본문이다.
  #
  # 이 검사는 **인덱스가 아니라 `Tests/` 원문**을 본다. 로컬에서 `PTB_NO_XCTEST=1` 이면 XCTest
  # 타깃이 아예 컴파일되지 않아 인덱스에 없다 — 의미 기반으로 바꾸면 CI 는 초록인데 로컬만
  # 빨강이 된다(게이트가 환경에 따라 다른 답을 내면 아무도 안 믿는다).
  [[ "$NAME" == debug* ]] && grep -rqE "\b${NAME}\(" Tests && continue
  SKIP=""
  for ALLOWED in "${CORE_ONLY_MUTATORS[@]}"; do [[ "$NAME" == "$ALLOWED" ]] && SKIP=1 && break; done
  [[ -n "$SKIP" ]] && continue
  UNCALLED_MUTATORS+="$LOCATION $SYMBOL"$'\n'
done <<< "$FINDINGS"
# **범위는 `Sources/` 전부다**(#225). 예전엔 `Core/PokemonChat.swift` 한 파일만 훑었는데, 그건
# 결함이 *발견된* 파일이지 부류가 사는 범위가 아니었다 — 범위를 넓히자 `CompanionStore.swift`
# 에서 8건이 나왔고 그중 셋(`ensureStarterCandidates`·`chooseStarter`·`beginIncubatingFocusEgg`)은
# 이미 죽은 제품 경로였다. 경로를 `Core/` 로 한정하지도 않는다: 실측상 결과가 같은데 예외만 하나
# 늘고, 스토어가 아닌 곳에 새로 생기는 mutator 를 놓칠 자리를 남긴다.
# 이 가드가 **구조적으로 못 보는** 반대쪽도 있다: 짝이 아예 없는 mutator(켜기만 있고 끄기가
# 없는 것)는 "호출부 0곳" 이 될 수 없다. `docs/reference/defect-log.md` 의 같은 항목을 본다.
if [[ -n "$UNCALLED_MUTATORS" ]]; then
  echo "✗ 아무도 부르지 않는 mutator 가 있습니다 — 세이브에 쓰기만 하고 화면이 부르지 않으면" \
       "그 값은 영원히 기본값입니다(앨범이면 방문자 카드에 빈 필드로 나갑니다)." \
       "화면을 붙이거나 API 를 삭제하세요" \
       "(화면에서 부르지 않는 것이 맞다면 CORE_ONLY_MUTATORS 에 이유와 해제 조건을 적어 넣으세요)." >&2
  echo "$UNCALLED_MUTATORS" >&2
  exit 1
fi
echo "✓ 없음"
