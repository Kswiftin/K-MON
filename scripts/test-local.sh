#!/usr/bin/env bash
#
# test-local.sh — Xcode 없이 로컬에서 테스트를 **실행**한다.
#
# 왜 있나: Command Line Tools 만 있는 Mac 에는 `XCTest.framework` 이 없어 `swift test` 가
# `no such module 'XCTest'` 로 멈춘다. 그런데 swift-testing(`Testing.framework`)은 CLT 안에
# 들어 있다 — 링커·런타임 경로 세 개를 알려 주기만 하면 그대로 돈다. 그래서 이 스크립트는
# ⓐ XCTest 타깃을 목록에서 빼고(PTB_NO_XCTEST=1) ⓑ 그 경로들을 붙여 swift-testing 타깃을 돌린다.
#
# 한계: 여기서 도는 것은 `Tests/PokeTokenBarLocalTests` 뿐이다. `Tests/PokeTokenBarTests` 의
# XCTest 는 Xcode 가 있는 머신이나 CI(macos-15)에서만 돈다. 타입체크만 하려면
# `scripts/typecheck-tests.sh`.
#
# 사용:  ./scripts/test-local.sh [swift test 에 넘길 추가 인자]
set -euo pipefail
cd "$(dirname "$0")/.."

FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
INTEROP="$(xcode-select -p)/Library/Developer/usr/lib"

if [[ ! -d "$FRAMEWORKS/Testing.framework" ]]; then
  echo "✗ Testing.framework 을 못 찾았다: $FRAMEWORKS"
  echo "  Command Line Tools 가 최신인지 확인한다: xcode-select --install"
  exit 1
fi

# -F/-rpath 셋 다 필요하다. 하나만 빠져도 증상이 다르다:
#   -F 없음        → 컴파일 실패 (no such module 'Testing')
#   -rpath 프레임워크 없음 → dlopen 실패 (@rpath/Testing.framework)
#   -rpath interop 없음   → dlopen 실패 (@rpath/lib_TestingInterop.dylib)
PTB_NO_XCTEST=1 swift test \
  -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
  -Xlinker -F -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$INTEROP" \
  "$@"
