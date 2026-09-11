#!/usr/bin/env bash
# BLE 프로브(이슈 #342 0단계). 앱 타깃과 분리해 swiftc 로 따로 세운다 — rogue-sim.sh 와 같은
# 이유다. 실측 도구지 배포물이 아니라서 Package.swift 에 넣으면 릴리스 빌드와 서명 경로까지
# 건드린다. 앱 코어에 의존하지 않으므로 컴파일도 몇 초면 끝난다.
#
#   맥 A:  scripts/ble-probe.sh advertise --name PROBE-A
#   맥 B:  scripts/ble-probe.sh scan --seconds 60 --csv .build/ble-probe/baseline.csv
#
# 두 맥 모두 전원을 연결하고 `caffeinate -di` 로 묶는다. 잠들면 광고가 끊긴다.
#
# Bluetooth 권한: 맨 CLI 는 자기 권한이 없어 **실행한 터미널 앱의 권한**을 쓴다. 첫 실행에
# macOS 가 터미널에 묻는다. 묻지도 않고 `central state=5` 인데 표본이 0이면 터미널의 블루투스
# 권한이 꺼진 것이다(시스템 설정 → 개인정보 보호 및 보안 → 블루투스).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=.build/ble-probe
mkdir -p "$OUT"

if [ Tools/BLEProbe/main.swift -nt "$OUT/ble-probe" ]; then
  echo "▶ swiftc — ble-probe"
  if ! swiftc -O -o "$OUT/ble-probe" Tools/BLEProbe/main.swift >"$OUT/build.log" 2>&1; then
    grep -E ' error' "$OUT/build.log" | head -20
    echo "전체 로그: $OUT/build.log"
    exit 1
  fi
fi

"$OUT/ble-probe" "$@"
