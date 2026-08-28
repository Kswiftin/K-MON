#!/bin/bash
# Pokédoro.app 번들 조립 + /Applications 설치
set -euo pipefail
cd "$(dirname "$0")/.."

# 로컬 수동 빌드용 폴백. 릴리스는 태그에서 KMON_VERSION 을 주입하므로(release.yml) 배포 산출물은
# 이 값을 쓰지 않는다 — 최신 릴리스와 맞춰 두지 않으면 손으로 빌드한 앱만 옛 버전으로 뜬다.
DEFAULT_VERSION="2.17.0"
VERSION="${KMON_VERSION:-$DEFAULT_VERSION}"
SOURCE_COMMIT="${KMON_SOURCE_COMMIT:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
# GitHub App OAuth Client ID는 공개 식별자다. 포크/별도 배포는 환경 변수로 자신의 App ID를 덮어쓴다.
GITHUB_OAUTH_CLIENT_ID="${KMON_GITHUB_OAUTH_CLIENT_ID:-Iv23liq1OgHiJotI0l65}"
# 테스트 빌드는 자기를 갱신하지 못하게 한다. `development` 프리릴리스는 버전이 릴리스 채널보다
# 낮아서(2.7.x vs 2.15.x) 업데이터를 켜 두면 실행 직후 정식 릴리스로 자신을 덮어쓴다 — 방금 깐
# 테스트 빌드가 조용히 사라지고, 그걸 모른 채 "고친 게 안 들어갔다" 를 디버깅하게 된다.
UPDATER_ALLOWED="true"
if [[ "${KMON_DISABLE_UPDATER:-0}" == "1" ]]; then
    UPDATER_ALLOWED="false"
    echo "==> 업데이터 비활성 빌드(KMON_DISABLE_UPDATER=1) — 이 앱은 스스로 갱신하지 않는다"
fi
APP_NAME="Pokédoro"
EXECUTABLE="PokeTokenBar"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> swift build -c release"
swift build -c release

echo "==> $APP 조립"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp ".build/release/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
# 심볼 strip — 릴리스 바이너리 1.84MB → 0.80MB(-57%). codesign 전에 수행(서명 무효화 방지).
strip -rSTx "$APP/Contents/MacOS/$EXECUTABLE" 2>/dev/null || strip -rSx "$APP/Contents/MacOS/$EXECUTABLE"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Sparkle is a dynamic framework. ditto preserves its versioned symlinks and the
# signed updater helpers; cp without the right options can silently flatten them.
ditto ".build/release/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.github.chattymin.poketokenbar</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>KMONSourceCommit</key><string>$SOURCE_COMMIT</string>
    <key>KMONGitHubOAuthClientID</key><string>$GITHUB_OAUTH_CLIENT_ID</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>SUFeedURL</key><string>https://github.com/Kswiftin/K-MON/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key><string>wF6hVA8cXA/NHj0fWmwxPKU4VWwiqQU1u5iXfOs7YwA=</string>
    <key>SUVerifyUpdateBeforeExtraction</key><true/>
    <key>SUEnableAutomaticChecks</key><false/>
    <key>SUAllowsAutomaticUpdates</key><$UPDATER_ALLOWED/>
    <key>SUAutomaticallyUpdate</key><$UPDATER_ALLOWED/>
    <key>NSLocalNetworkUsageDescription</key><string>Discover Pokédoro rooms for ranked battles and Pokéathlon with up to four friends.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_ptbbattle._tcp</string>
        <string>_kmonroom._tcp</string>
        <string>_kmontrade._tcp</string>
    </array>
</dict>
</plist>
PLIST

# 크래시/OOM(exit≠0) 시 자동 재실행 LaunchAgent(KeepAlive) — SMAppService.agent 가 등록해 launchd 가
# 워치독으로 동작. 정상 종료(exit 0: 사용자 종료·업데이트)엔 재실행 안 함(SuccessfulExit=false).
# ProgramArguments 는 brew 설치 경로(/Applications) 고정. codesign 전에 생성해 서명 seal 에 포함.
mkdir -p "$APP/Contents/Library/LaunchAgents"
cat > "$APP/Contents/Library/LaunchAgents/io.github.chattymin.poketokenbar.login.plist" <<AGENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>io.github.chattymin.poketokenbar.login</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/$APP_NAME.app/Contents/MacOS/$EXECUTABLE</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key><false/>
    </dict>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
AGENT

echo "==> codesign"
SIGN_IDENTITY="${CODESIGN_IDENTITY:-K-MON Release}"
# 안정적 Keychain ACL 을 위해서는 인증서 존재가 아니라 유효한 codesigning identity 가 필요하다.
if security find-identity -v -p codesigning | grep -F "\"$SIGN_IDENTITY\"" >/dev/null; then
    # 안정적 자체 서명 신원 → 재빌드해도 Keychain "항상 허용" 과 TCC 승인이 유지된다.
    codesign --force -s "$SIGN_IDENTITY" "$APP"
elif [[ "${PTB_ALLOW_ADHOC:-0}" == "1" ]]; then
    # 명시적으로 요청했을 때만. ad-hoc 은 DR 이 cdhash 라 빌드마다 앱 신원이 바뀐다.
    echo "   ⚠ PTB_ALLOW_ADHOC=1 → ad-hoc 서명."
    echo "     이 빌드는 macOS 에 '처음 보는 앱' 으로 보입니다 — 알림·로컬 네트워크 권한을 다시 묻습니다."
    codesign --force -s - "$APP"
else
    # 예전에는 여기서 조용히 ad-hoc 으로 폴백했다. 그 폴백이 "버전을 올릴 때마다 권한 창이 뜬다" 의
    # 원인이었다 — 개발자는 경고 한 줄을 빌드 로그에서 놓치고, 사용자는 매번 다시 승인했다.
    # 릴리스 전용이던 PTB_REQUIRE_STABLE_SIGN 게이트를 기본값으로 올린 것이다(CI 는 계속 세팅한다).
    cat >&2 <<UNSIGNED
   ✗ '$SIGN_IDENTITY' 유효 codesigning identity 가 없습니다 → 중단합니다.

     ad-hoc 으로 서명하면 DR 이 cdhash 라 빌드마다 앱 신원이 바뀌고, macOS 는 매 버전을
     다른 앱으로 보아 알림·로컬 네트워크 권한을 처음부터 다시 묻습니다.

     한 번만 실행하세요:  ./scripts/create-signing-cert.sh
     그래도 ad-hoc 이 필요하면:  PTB_ALLOW_ADHOC=1 ./scripts/build-app.sh
UNSIGNED
    exit 1
fi

# 서명이 안정적인지는 의도가 아니라 산출물로 확인한다. CI(release.yml)와 같은 한 벌을 쓴다.
if [[ "${PTB_ALLOW_ADHOC:-0}" != "1" ]]; then
    ./scripts/verify-signing-identity.sh "$APP"
fi

if [[ "${KMON_SKIP_INSTALL:-0}" == "1" ]]; then
    echo "완료: $APP (설치 생략)"
else
    echo "==> 기존 인스턴스 종료 + /Applications 설치"
    pkill -x "$EXECUTABLE" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    rm -rf "/Applications/PokeTokenBar.app"
    cp -R "$APP" /Applications/
    echo "완료: open /Applications/$APP_NAME.app"
fi
