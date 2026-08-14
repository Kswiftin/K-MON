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

VERSION="${1:?사용: release.sh <version>  (예: 2.7.0)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "✗ 버전 형식 오류: $VERSION (x.y.z 형식만 허용)" >&2
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
git fetch origin main --tags
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
echo "  https://github.com/2giduck/K-MON/actions/workflows/release.yml"
