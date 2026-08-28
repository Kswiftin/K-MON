#!/usr/bin/env bash
# 웨이브 런 밸런스 시뮬레이터. 앱 타깃을 건드리지 않고 코어만 따로 컴파일해 판을 돌린다.
#
#   scripts/rogue-sim.sh --runs 200 --seed 7
#
# Package.swift 에 타깃을 더하지 않는 이유: 앱은 단일 타깃이라 소스를 나눠야 하고, 그 분할이
# 릴리스 빌드(build-app.sh)와 서명 경로까지 건드린다. 시뮬레이터는 밸런스를 재는 도구지
# 배포물이 아니므로 swiftc 로 따로 세운다.
#
# 첫 실행은 PokéAPI 를 두드려 느리다. 받은 스냅샷은 .build/rogue-sim/snapshots.json 에 쌓여
# 다음 실행부터 재사용된다(앱 캐시와 별개 파일).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=.build/rogue-sim
mkdir -p "$OUT"

# SwiftUI 프레임워크 탐색 경로로 SwiftPM 산출물 디렉터리가 필요하다 — 코어가 UI 헬퍼를 참조한다.
FRAMEWORKS=.build/arm64-apple-macosx/debug
if [ ! -d "$FRAMEWORKS" ]; then
  echo "▶ swift build (프레임워크 경로 준비)"
  swift build >/dev/null
fi

echo "▶ swiftc — 코어 + 시뮬레이터"
# 경고는 로그로 보낸다 — 코어 전체를 한 번에 컴파일해서 앱 빌드가 이미 아는 경고까지 다 나온다.
if ! swiftc -DDEBUG -O -o "$OUT/rogue-sim" \
  Sources/PokeTokenBar/Core/*.swift \
  Sources/PokeTokenBar/UI/SpriteLoader.swift \
  Sources/PokeTokenBar/UI/SpriteAnimation.swift \
  Tools/RogueSim/main.swift \
  -F "$FRAMEWORKS" >"$OUT/build.log" 2>&1; then
  grep -E ' error' "$OUT/build.log" | head -20
  echo "전체 로그: $OUT/build.log"
  exit 1
fi

DYLD_FRAMEWORK_PATH="$FRAMEWORKS" "$OUT/rogue-sim" "$@"
