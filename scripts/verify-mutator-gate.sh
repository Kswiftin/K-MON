#!/usr/bin/env bash
#
# verify-mutator-gate.sh — mutator 스윕(`mutator-sweep.sh`)의 **결함 주입 시험**.
#
# 왜 필요한가: 통과만 보면 게이트가 무엇을 지키는지 구별할 수 없다. 스윕이 초록인 것은
# ① 죽은 mutator 가 없어서일 수도 있고 ② 판정이 아무것도 안 보고 있어서일 수도 있다.
# 실제로 후자가 #233 이었다 — 이름 단위 산술이라 살아 있는 동명 함수가 죽은 선언을 가렸다.
# 그래서 판정을 사람 기억이 아니라 **주입 → 종료코드**로 남긴다.
# (`docs/reference/defect-log.md` 의 "결함 주입으로 확인했다" 를 스크립트로 굳힌 것이다.)
#
# CI 에는 넣지 않는다 — 케이스마다 소스를 주입하고 빌드해서 게이트 본체보다 느리고, 게이트가
# 자기 검증을 자기 안에서 돌리는 재귀가 된다. 스윕 판정을 손볼 때 사람이 돌린다.
#
# 사용:  ./scripts/verify-mutator-gate.sh
# 종료코드: 0 = 전 케이스 기대와 일치 · 1 = 어긋난 케이스 있음
set -uo pipefail
cd "$(dirname "$0")/.."

PROBE_DIR="Sources/PokeTokenBar/GateProbe"
PROBE_FILE="$PROBE_DIR/Probe.swift"
TEST_PROBE="Tests/PokeTokenBarLocalTests/GateProbeTests.swift"

cleanup() { rm -rf "$PROBE_DIR" "$TEST_PROBE"; }
trap cleanup EXIT
cleanup   # 앞선 실행이 죽은 채 남긴 것이 있으면 먼저 치운다

FAILED=0
PASSED=0

# 주입 헬퍼 — 케이스마다 디렉터리를 다시 만든다. `cleanup` 이 디렉터리째 지우므로 필요하다:
# 없으면 두 번째 케이스부터 리다이렉션이 실패하고 **주입 없이 초록**이 되어 하네스가 자기
# 자신에게 거짓 확신을 준다(첫 실행에서 실제로 케이스 3·4a·5 가 그렇게 통과했다).
inject() { mkdir -p "$PROBE_DIR"; cat > "$PROBE_FILE"; }

# run_case <설명> <red|green>
#   red   = 스윕이 주입한 결함을 잡아 실패해야 한다
#   green = 스윕이 통과해야 한다(오탐 없음)
run_case() {
  local description="$1" expected="$2" output rc verdict
  # **주입이 실제로 있었는지 먼저 확인한다.** 이것이 없으면 주입에 실패한 케이스가 초록으로
  # 통과해 "게이트가 통과했다" 와 "검사할 것이 없었다" 를 구별할 수 없다 — 이 하네스가
  # 존재하는 이유와 같은 부류의 사고다.
  if [[ ! -s "$PROBE_FILE" ]]; then
    FAILED=$((FAILED + 1))
    printf '  ✗ %s — 하네스 결함: 주입 파일이 없습니다(%s)\n' "$description" "$PROBE_FILE"
    return
  fi
  output=$(./scripts/mutator-sweep.sh 2>&1); rc=$?
  if [[ $rc -eq 0 ]]; then verdict="green"; else verdict="red"; fi
  if [[ "$verdict" == "$expected" ]]; then
    PASSED=$((PASSED + 1))
    printf '  ✓ %s (기대 %s)\n' "$description" "$expected"
  else
    FAILED=$((FAILED + 1))
    printf '  ✗ %s — 기대 %s, 실제 %s\n' "$description" "$expected" "$verdict"
    printf '%s\n' "$output" | sed 's/^/      | /'
  fi
  cleanup
}

# ── 케이스 1: **이 이슈의 트리거 브랜치.** 살아 있는 동명 mutator 옆에 죽은 것 하나.
# `send` 는 이 트리에 9개 선언(대부분 private)·120등장이 있다. 이름 단위 산술은 그 등장
# 횟수가 죽은 선언의 0곳을 메워 초록으로 통과한다 — 선언 위치로 세면 빨강이어야 한다.
echo "▶ 케이스 1: 살아 있는 동명 함수(send) 옆의 죽은 mutator"
inject <<'SWIFT'
final class GateProbeMaskedStore {
    private var flag = false
    private func save() { _ = flag }
    // 아무도 부르지 않는다. 이름만 살아 있는 `send` 들과 겹친다.
    func send(_ value: Bool) { flag = value; save() }
}
SWIFT
run_case "동명 죽은 mutator" red

# ── 케이스 2: 유일한 이름의 죽은 mutator. 옛 게이트가 원래 잡던 것 — 회귀하지 않는지.
echo "▶ 케이스 2: 유일한 이름의 죽은 mutator"
inject <<'SWIFT'
final class GateProbeUniqueStore {
    private var flag = false
    private func save() { _ = flag }
    func gateProbeSetUniquelyNamedFlag(_ value: Bool) { flag = value; save() }
}
SWIFT
run_case "유일 이름 죽은 mutator" red

# ── 케이스 3: 호출부가 있는 mutator. 오탐이 없어야 한다.
echo "▶ 케이스 3: 호출부가 있는 mutator (오탐 없음)"
inject <<'SWIFT'
final class GateProbeCalledStore {
    private var flag = false
    private func save() { _ = flag }
    func gateProbeSetCalledFlag(_ value: Bool) { flag = value; save() }
}
enum GateProbeCaller {
    static func press(_ store: GateProbeCalledStore) { store.gateProbeSetCalledFlag(true) }
}
SWIFT
run_case "호출부 있는 mutator" green

# ── 케이스 4: `debug` 접두 규칙. 접두만으로 면제하지 않고 **Tests 에 호출부가 있어야** 한다.
echo "▶ 케이스 4a: debug 접두 + Tests 호출부 있음"
inject <<'SWIFT'
final class GateProbeDebugStore {
    private var flag = false
    private func save() { _ = flag }
    /// 테스트 전용 시딩 훅.
    func debugGateProbeSetFlag(_ value: Bool) { flag = value; save() }
}
SWIFT
cat > "$TEST_PROBE" <<'SWIFT'
import Testing
@testable import PokeTokenBar

@Test func gateProbeSeedsFlag() {
    GateProbeDebugStore().debugGateProbeSetFlag(true)
}
SWIFT
run_case "debug 접두 + Tests 호출부" green

echo "▶ 케이스 4b: debug 접두 + Tests 호출부 없음"
inject <<'SWIFT'
final class GateProbeDebugStore {
    private var flag = false
    private func save() { _ = flag }
    /// 테스트 전용 시딩 훅 — 그런데 아무 테스트도 부르지 않는다.
    func debugGateProbeSetFlag(_ value: Bool) { flag = value; save() }
}
SWIFT
run_case "debug 접두 + Tests 호출부 없음" red

# ── 케이스 5: 프로토콜 요구사항으로만 불리는 구현. 직접 참조는 0곳이지만 도달 가능하다 —
# 선언 위치로 세는 판정이 override 관계를 안 따라가면 여기서 **없는 결함으로 CI 를 세운다**.
echo "▶ 케이스 5: 프로토콜 경유로만 불리는 mutator (오탐 없음)"
inject <<'SWIFT'
protocol GateProbeSink {
    func gateProbeAccept(_ value: Bool)
}
final class GateProbeSinkImpl: GateProbeSink {
    private var flag = false
    private func save() { _ = flag }
    func gateProbeAccept(_ value: Bool) { flag = value; save() }
}
enum GateProbeProtocolCaller {
    static func feed(_ sink: GateProbeSink) { sink.gateProbeAccept(true) }
    static func make() -> GateProbeSink { GateProbeSinkImpl() }
}
SWIFT
run_case "프로토콜 경유 mutator" green

echo
if [[ $FAILED -gt 0 ]]; then
  echo "✗ 결함 주입 $FAILED 건이 기대와 어긋났습니다 (통과 $PASSED)." >&2
  exit 1
fi
echo "✓ 결함 주입 $PASSED 건 전부 기대와 일치."
