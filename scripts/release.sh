#!/usr/bin/env bash
# release.sh — 검증된 main 커밋에 시맨틱 버전 태그를 붙여 GitHub Actions 릴리즈를 시작한다.
#
# 사용: ./scripts/release.sh 2.7.0
#
# 앱 빌드, Sparkle 서명, appcast 생성, GitHub Release 공개는 release.yml 하나만 담당한다.
# 로컬과 CI가 서로 다른 바이너리를 배포하거나 Asset 없는 Release를 먼저 공개하지 않도록
# 이 스크립트는 버전 태그를 안전하게 만드는 일 외에는 하지 않는다.
set -euo pipefail
cd "$(dirname "$0")/.."

# macOS에서 xcode-select가 Command Line Tools를 가리키면 SwiftPM이 XCTest를 찾지 못한다.
# 전역 설정은 바꾸지 않고 이 릴리스 명령과 자식 프로세스에만 전체 Xcode를 사용한다.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

VERSION="${1:?사용: release.sh <version>  (예: 2.7.0)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "✗ 버전 형식 오류: $VERSION (x.y.z 형식만 허용)" >&2
  exit 1
}

# 손빌드 기본값(`build-app.sh` 의 DEFAULT_VERSION)은 배포 산출물에 쓰이지 않지만, 안 올리면
# 손으로 빌드한 앱만 옛 버전으로 뜬다. RELEASE.md 체크리스트에만 있던 탓에 2.24.0 에서 그대로
# 새어나갔다(태그는 v2.24.0, 파일은 2.23.5) — 사람 기억 대신 여기서 막는다.
BUILD_DEFAULT=$(sed -n 's/^DEFAULT_VERSION="\(.*\)"$/\1/p' scripts/build-app.sh)
[[ "$BUILD_DEFAULT" == "$VERSION" ]] || {
  echo "✗ scripts/build-app.sh 의 DEFAULT_VERSION($BUILD_DEFAULT)이 릴리스 버전($VERSION)과 다릅니다." >&2
  echo "  DEFAULT_VERSION=\"$VERSION\" 으로 올린 뒤 커밋하세요." >&2
  exit 1
}

BRANCH=$(git branch --show-current)
[[ "$BRANCH" == "main" ]] || {
  echo "✗ main 브랜치에서 실행하세요 (현재: $BRANCH)" >&2
  exit 1
}
[[ -z "$(git status --porcelain)" ]] || {
  echo "✗ 커밋되지 않은 변경이 있습니다." >&2
  exit 1
}

echo "▶ origin/main 동기화 확인"
# development는 수동 프리릴리즈에서만 이동하는 롤링 태그다. 여기서 전체 태그를 fetch하면
# 로컬의 이전 development와 충돌해 안정 릴리스가 시작조차 못 하므로 main만 갱신한다.
git fetch --no-tags origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || {
  echo "✗ 로컬 main과 origin/main이 다릅니다. 먼저 pull 하세요." >&2
  exit 1
}

TAG="v$VERSION"
if git rev-parse "$TAG" >/dev/null 2>&1 || git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "✗ 이미 존재하는 태그입니다: $TAG" >&2
  exit 1
fi

echo "▶ 릴리스 전 테스트 게이트"
./scripts/test-gate.sh

echo "▶ $TAG 태그 생성 및 push"
git tag -a "$TAG" -m "K-MON $TAG"
git push origin "refs/tags/$TAG"

echo "✓ GitHub Actions가 $TAG 빌드·서명·Release 생성을 진행합니다."
echo "  https://github.com/Kswiftin/K-MON/actions/workflows/release.yml"
