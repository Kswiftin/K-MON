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
# 남는 형태가 grep 이다. 대상은 **`save()` 를 부르는 비-private 함수** 다 — 세이브를 바꾸는
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
# **주석 줄은 빼고 센다.** 이 저장소의 문서 주석은 API 이름을 끊임없이 인용하므로, 원문 그대로
# 세면 `/// setPeerAlias(...) 는 …` 한 줄이 그 mutator 를 영원히 "호출됨" 으로 만든다 —
# 게이트가 잡으려는 바로 그 부류를 산문 한 줄로 통과시키는 셈이다. 줄 끝 주석은 코드를 함께
# 지울 위험이 있어 건드리지 않는다(줄 전체가 주석인 경우만 지운다).
SWIFT_CODE=$(find Sources/PokeTokenBar -name '*.swift' -exec cat {} + | sed '/^[[:space:]]*\/\//d')
while read -r NAME; do
  [[ -z "$NAME" ]] && continue
  # `debug` 접두는 **이름 하나하나가 아니라 규칙으로** 건너뛴다. 이 저장소의 `debug…` 는 전부
  # `/// 테스트 전용` 이 붙은 시딩 훅이라(화면에서 부르지 않는 것이 정상이다), 이름을 박아 두면
  # `debugSetFoo` 가 하나 늘 때마다 allowlist 가 같이 자란다 — 그때마다 손대는 목록은 결국
  # 아무도 안 읽는다. 관례를 규칙으로 올려 목록을 "진짜 예외" 에만 쓴다.
  #
  # **접두만으로는 면제하지 않는다 — `Tests/` 에 호출부가 있어야 한다.** 이름만 보고 통과시키면
  # 규칙 자체가 우회로가 된다(죽은 mutator 에 `debug` 를 붙이면 사라진다). 그리고 아무도 안 쓰는
  # 시딩 훅도 죽은 코드이므로 걸러야 한다 — 접두 규칙의 근거가 "테스트가 쓴다" 이니, 그것을 검사한다.
  # 해제 조건: 없다. 이 조건이 규칙의 본문이다.
  [[ "$NAME" == debug* ]] && grep -rqE "\b${NAME}\(" Tests && continue
  SKIP=""
  for ALLOWED in "${CORE_ONLY_MUTATORS[@]}"; do [[ "$NAME" == "$ALLOWED" ]] && SKIP=1 && break; done
  [[ -n "$SKIP" ]] && continue
  # 호출부는 파일을 가리지 않는다 — 같은 파일 안에서만 불리는 것(`appendLocalMessage`)도
  # 도달 가능하다. 선언 줄 수와 등장 횟수가 같으면 아무도 부르지 않는 것이다.
  CALLS=$(printf '%s\n' "$SWIFT_CODE" | grep -oE "\b${NAME}\(" | wc -l | tr -d ' ')
  DECLS=$(printf '%s\n' "$SWIFT_CODE" | grep -oE "func ${NAME}\(" | wc -l | tr -d ' ')
  [[ "$CALLS" == "$DECLS" ]] && UNCALLED_MUTATORS+="$NAME"$'\n'
done < <(awk '
  # **파일이 바뀌면 상태를 버린다.** 여러 파일을 한 번에 넘기므로, 안 지우면 앞 파일 마지막 함수의
  # `name`·`priv` 가 다음 파일 첫 줄까지 살아남아 엉뚱한 이름에 `save()` 가 붙는다 — 아래 한 줄과
  # 똑같은 부류의 사고를 파일 경계에서 한 번 더 내는 셈이다.
  FNR == 1 { name = ""; priv = 0 }
  # **여기도 주석 줄을 뺀다.** 아래 `SWIFT_CODE` 의 sed 와 같은 규칙이어야 한다 — 세는 쪽만 주석을
  # 빼고 **찾는 쪽이 원문을 읽으면** 산문에 적힌 `save()` 가 앞 함수를 mutator 로 만든다. 실측으로
  # `gainExperience`·`hatchIfNeeded`·`nextAchievementTier`·`stableIdentifier` 네 개가 그렇게 올라왔고
  # (`DeviceID.swift` 의 "`save()` 가 자주 불리는데…" 한 줄이 `stableIdentifier` 를 올렸다),
  # 넷 다 호출부가 있어서 우연히 통과했다. 호출부 0곳인 첫 유령이 나오면 게이트가 세이브를
  # 건드리지도 않는 함수를 지우라고 CI 를 세운다.
  /^[[:space:]]*\/\// { next }
  # `static`·`nonisolated`·`override` 가 앞에 붙은 선언도 잡아야 한다. 놓치면 `name`·`priv` 가
  # **앞 함수의 값으로 남아**, 그 안의 `save()` 가 엉뚱한 이름에 붙는다(잡아야 할 것을 가리거나,
  # mutator 도 아닌 이름으로 빌드를 깨뜨린다).
  #
  # 같은 이유로 `[(<]` 다 받는다 — 제네릭 선언(`func send<T: Encodable>(`)을 놓치면 그 함수의
  # `save()` 가 앞 함수 이름에 붙는다(범위 확대로 제네릭 7개가 사정권에 들어왔다).
  # `priv` 판정도 접미 수식어를 넘어서 본다: `private func` 인접만 보면 `private static func` 105개가
  # 전부 **비-private 로 오인**돼, 그중 하나가 `save()` 를 부르는 순간 없는 결함으로 CI 가 선다.
  # 이름에 숫자도 받는다 — `[A-Za-z_]+` 만 보면 `fnv1a`·`localIPv4` 가 `fnv`·`localIPv` 로 잘려
  # 존재하지 않는 이름을 세게 된다(자른 이름은 호출부도 선언부도 못 찾아 오탐이 된다).
  /func [A-Za-z_][A-Za-z0-9_]*[(<]/ {
    priv = ($0 ~ /(private|fileprivate) [a-z ]*func/)
    match($0, /func [A-Za-z_][A-Za-z0-9_]*/); name = substr($0, RSTART + 5, RLENGTH - 5)
  }
  /save\(\)/ && name != "" && !priv && !seen[name] { print name; seen[name] = 1 }
' $(find Sources/PokeTokenBar -name '*.swift') | sort -u)
# **범위는 `Sources/` 전부다**(#225). 예전엔 `Core/PokemonChat.swift` 한 파일만 훑었는데, 그건
# 결함이 *발견된* 파일이지 부류가 사는 범위가 아니었다 — 같은 awk 를 넓히자 `CompanionStore.swift`
# 에서 8건이 나왔고 그중 셋(`ensureStarterCandidates`·`chooseStarter`·`beginIncubatingFocusEgg`)은
# 이미 죽은 제품 경로였다. 경로를 `Core/` 로 한정하지도 않는다: 실측상 결과가 같은데 예외만 하나
# 늘고, 스토어가 아닌 곳에 새로 생기는 mutator 를 놓칠 자리를 남긴다.
# 이 가드가 **구조적으로 못 보는** 반대쪽도 있다: 짝이 아예 없는 mutator(켜기만 있고 끄기가
# 없는 것)는 "호출부 0곳" 이 될 수 없다. `docs/reference/defect-log.md` 의 같은 항목을 본다.
# **범위 확대로 커진 눈먼 곳이 하나 더 있다 — 이름이 겹치는 mutator.** 판정이 이름 단위 산술
# (`CALLS == DECLS`)이라 같은 이름이 여러 타입에 있으면 서로를 가린다: 실측으로 `send` 8선언
# (그중 7개가 private) / 118등장, `record` 6, `delete`·`tick`·`clamped` 3, `prune`·
# `clearSharedPinnedMemory` 2다. 살아 있는 동명 함수의 호출부가 죽은 쪽의 0곳을 메워 통과한다.
# 한 파일만 볼 때는 거의 없던 형태이고, 제대로 막으려면 타입 단위 파싱이 필요하다(grep 의 천장).
# 해제 조건: 이름이 아니라 선언 위치로 세는 도구(SourceKit·swift-syntax)를 붙일 때 옮긴다(#233).
if [[ -n "$UNCALLED_MUTATORS" ]]; then
  echo "✗ 아무도 부르지 않는 mutator 가 있습니다 — 세이브에 쓰기만 하고 화면이 부르지 않으면" \
       "그 값은 영원히 기본값입니다(앨범이면 방문자 카드에 빈 필드로 나갑니다)." \
       "화면을 붙이거나 API 를 삭제하세요" \
       "(화면에서 부르지 않는 것이 맞다면 CORE_ONLY_MUTATORS 에 이유와 해제 조건을 적어 넣으세요)." >&2
  echo "$UNCALLED_MUTATORS" >&2
  exit 1
fi
echo "✓ 없음"
