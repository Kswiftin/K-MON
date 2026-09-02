#!/usr/bin/env bash
#
# typecheck-tests.sh — Xcode 가 없는 머신에서 **테스트 소스의 타입체크**만 돌린다.
#
# 왜 있나: Xcode 없이 Command Line Tools 만 있는 Mac 에서는 `swift test` 가
# `no such module 'XCTest'` 로 멈춘다. 테스트 타깃이 컴파일조차 되지 않으니, 테스트가 실제로
# 존재하지 않는 심볼을 부르고 있어도(파일명을 타입명으로 착각, 이름 바뀐 API 등) 로컬에서
# 아무 신호가 없고 PR CI 에서 처음 터진다. 그 부류로 CI 를 두 번 깨뜨린 뒤 만든 스크립트다.
#
# 무엇을 하나: XCTest 최소 스텁(단정은 전부 빈 몸)을 만들고, `import XCTest` /
# `@testable import PokeTokenBar` 를 걷어낸 테스트 소스를 앱 소스와 **한 모듈로** 타입체크한다.
# 테스트는 실행되지 않는다 — 단정이 참인지는 CI(macos-15)가 진짜 XCTest 로 확인한다.
#
# 먼저 볼 것: swift-testing 으로 쓴 테스트는 Xcode 없이 **실제로 실행된다**
# (`scripts/test-local.sh`). 이 스크립트는 그쪽으로 옮기지 않은 XCTest 소스가
# 컴파일되는지만 본다 — 단정이 참인지는 여전히 확인하지 못한다.
#
# 사용:  ./scripts/typecheck-tests.sh
# 종료코드: 0 = 타입체크 통과(에러·warning 없음), 1 = 진단 있음
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Sparkle(바이너리 프레임워크)은 SwiftPM 빌드 산출물에서 찾는다 — 없으면 먼저 빌드해 둔다.
FRAMEWORKS="$(ls -d .build/*/debug 2>/dev/null | head -1 || true)"
if [[ -z "$FRAMEWORKS" || ! -d "$FRAMEWORKS/Sparkle.framework" ]]; then
  echo "▶ Sparkle.framework 이 없어 swift build 를 먼저 돌린다"
  swift build >/dev/null
  FRAMEWORKS="$(ls -d .build/*/debug 2>/dev/null | head -1)"
fi

cat > "$WORK/xctest-stub.swift" <<'STUB'
// XCTest 최소 스텁 — 타입체크 전용. 단정은 아무것도 검사하지 않는다.
import Foundation

open class XCTestCase {
    public init() {}
    // 실제 XCTestCase 가 가진 멤버는 스텁에도 둔다 — 빠지면 같은 이름의 테스트 헬퍼가 로컬에서만
    // 해석되고 CI 에서 상위 멤버와 겹쳐 터진다(`run()` 헬퍼가 그렇게 CI 를 깨뜨렸다).
    open func run() {}
    open func invokeTest() {}
    open func perform(_ test: AnyObject) {}
    open var name: String { "" }
    public var continueAfterFailure: Bool = true
    open func setUp() {}
    open func tearDown() {}
    open func setUpWithError() throws {}
    open func tearDownWithError() throws {}
    public func measure(_ block: () -> Void) {}
    public func expectation(description: String) -> XCTestExpectation { XCTestExpectation() }
    public func wait(for: [XCTestExpectation], timeout: Double) {}
    public func fulfillment(of: [XCTestExpectation], timeout: Double) async {}
    public func addTeardownBlock(_ block: @escaping () -> Void) {}
}
public final class XCTestExpectation: @unchecked Sendable { public init() {}; public func fulfill() {} }
public func XCTAssert(_ e: @autoclosure () throws -> Bool, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertTrue(_ e: @autoclosure () throws -> Bool, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertFalse(_ e: @autoclosure () throws -> Bool, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertNil(_ e: @autoclosure () throws -> Any?, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertNotNil(_ e: @autoclosure () throws -> Any?, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertEqual<T: FloatingPoint>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, accuracy: T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertNotEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertGreaterThan<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertGreaterThanOrEqual<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertLessThan<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertLessThanOrEqual<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTFail(_ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTUnwrap<T>(_ e: @autoclosure () throws -> T?, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let v = try e() else { throw NSError(domain: "stub", code: 1) }
    return v
}
public func XCTAssertThrowsError<T>(_ e: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line, _ handler: (Error) -> Void = { _ in }) {}
public func XCTAssertNoThrow<T>(_ e: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTSkipUnless(_ e: @autoclosure () throws -> Bool, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) throws {}
public func XCTSkipIf(_ e: @autoclosure () throws -> Bool, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) throws {}
public func XCTSkip(_ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) throws {}
public struct XCTSkipError: Error { public init() {} }
public func XCTAssertIdentical(_ a: @autoclosure () throws -> AnyObject?, _ b: @autoclosure () throws -> AnyObject?, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {}
STUB

# `import XCTest` 자리에 Foundation/SwiftUI/AppKit 을 넣는다 — 테스트는 이 심볼들을 XCTest 가
# 끌어오는 것에 얹혀 쓰고 있어서, 그냥 지우면 URL·FileManager 부터 못 찾는다.
for f in Tests/PokeTokenBarTests/*.swift; do
  sed -e 's/^import XCTest$/import Foundation\nimport SwiftUI\nimport AppKit/' \
      -e 's/^@testable import PokeTokenBar$//' "$f" > "$WORK/$(basename "$f")"
done

echo "▶ swiftc -typecheck (앱 소스 + 테스트 소스 $(ls Tests/PokeTokenBarTests/*.swift | wc -l | tr -d ' ')개)"
DIAG=$(swiftc -typecheck -swift-version 6 -DDEBUG -F "$FRAMEWORKS" \
  $(find Sources/PokeTokenBar -name '*.swift') "$WORK"/*.swift 2>&1 | grep -E ": (error|warning):" | sort -u || true)

if [[ -n "$DIAG" ]]; then
  echo
  echo "✗ 진단 $(wc -l <<< "$DIAG" | tr -d ' ')건 — 고친 뒤 다시 실행하세요." >&2
  echo "$DIAG" >&2
  exit 1
fi
echo "✓ 테스트 소스 타입체크 통과 — 단정이 참인지는 CI 가 확인한다(로컬에서 테스트를 실행한 게 아니다)."
