#!/usr/bin/env bash
#
# verify-signing-identity.sh — 번들이 **매 버전 같은 앱으로 보이는지** 검사한다.
#
# macOS 는 TCC(알림·로컬 네트워크) 승인을 앱의 designated requirement 에 묶는다. ad-hoc 서명의
# DR 은 `cdhash H"..."` 라 바이너리가 1바이트만 달라도 값이 바뀌고, 그러면 macOS 는 업그레이드된
# 앱을 **처음 보는 다른 앱**으로 판단해 권한을 처음부터 다시 묻는다. 사용자에게는 "버전 올릴 때마다
# 권한 창이 뜬다" 로 보인다.
#
# 이 부류는 `swift test` 가 관측할 수 없다 — 결함이 소스가 아니라 **번들 속성**에 있기 때문이다.
# 그래서 게이트가 스크립트다. CI(release.yml)와 로컬이 이 한 벌을 같이 쓴다.
#
# 사용:  ./scripts/verify-signing-identity.sh [경로]      # 기본 build/Pokédoro.app
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-build/Pokédoro.app}"

fail() { echo "   ✗ $1" >&2; exit 1; }

[[ -d "$APP" ]] || fail "번들이 없습니다: $APP"

echo "==> 서명 신원 검사: $APP"

codesign --verify --deep --strict "$APP" 2>/dev/null \
    || fail "서명이 깨졌습니다 (codesign --verify --deep --strict 실패)."

details="$(codesign -d --verbose=4 "$APP" 2>&1 || true)"
requirement="$(codesign -d -r- "$APP" 2>&1 || true)"

if grep -qF 'Signature=adhoc' <<<"$details"; then
    cat >&2 <<'ADHOC'
   ✗ ad-hoc 서명입니다.
     DR 이 cdhash 라 빌드마다 앱 신원이 바뀌고, macOS 는 매 버전을 다른 앱으로 봅니다
     → 알림·로컬 네트워크 권한 창이 업그레이드마다 다시 뜹니다.
     고치는 법: ./scripts/create-signing-cert.sh 실행 후 ./scripts/build-app.sh 재실행.
ADHOC
    exit 1
fi

grep -qF 'certificate leaf = H' <<<"$requirement" \
    || fail "DR 이 인증서에 묶여 있지 않습니다. 안정적 신원이 아닙니다:
     $requirement"

echo "   ✓ 안정적 서명 신원 — 버전이 올라가도 같은 앱으로 인식됩니다"
echo "     $(grep -F 'designated =>' <<<"$requirement" || true)"
