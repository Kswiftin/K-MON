// MutatorGate — "세이브에 쓰기만 하는 API" 를 **선언 위치 단위**로 찾는다.
// `scripts/mutator-sweep.sh` 가 부르고, 정책(예외 목록·`debug` 접두 규칙)은 그 스크립트가 쥔다.
// 이 도구는 사실만 낸다: 어느 선언이 세이브를 바꾸는데 아무도 참조하지 않는가.
//
// **왜 인덱스 스토어인가** (#233). 이전 판정은 이름 단위 산술이었다 —
// `등장 횟수 == 선언 줄 수` 면 죽은 것으로 봤다. 스윕 범위가 `Sources/` 전부로 넓어지자
// 같은 이름이 여러 타입에 사는 일이 흔해져서(`send` 9선언/120등장, `record` 6, `delete`·
// `tick`·`clamped` 3) **살아 있는 동명 함수의 호출부가 죽은 선언의 0곳을 메웠다.** grep 은
// `store.send(...)` 가 9개 `send` 중 어느 선언으로 해석되는지 알 수 없다 — 타입 추론이 필요하다.
//
// SwiftPM 이 매 빌드마다 `.build/<triple>/debug/index/store` 에 인덱스를 이미 쓴다. 거기엔
// 선언마다 USR 이 있고 참조마다 그 USR 이 달려 있다 — 즉 필요한 데이터가 공짜로 있었다.
// (swift-syntax 만으로는 이 결함을 못 고친다: 선언 위치는 정밀해지지만 호출부 해석이 안 돼
// 이름 풀링이 그대로 남는다. Periphery 는 상류가 archived 라 CI 를 묶을 수 없다.)
//
// **이 도구가 못 보는 것** (게이트 주석과 defect-log 에 같은 목록을 남긴다):
//  - 프로토콜/상위 메서드 경유 호출은 요구사항 USR 로 기록된다 → 구현이 둘 이상이면 한쪽만
//    실제로 불려도 나머지가 살아 있는 것으로 보인다(동적 디스패치의 천장, periphery 도 같다).
//  - 서로만 부르는 죽은 뭉치(A→B→A)는 양쪽 다 참조가 있어 통과한다.
//  - 접근자(`didSet`·set)에서 `save()` 를 불러도 후보가 아니다 — 오늘의 클래스(=함수)를 그대로 뒀다.
//  - 인덱스가 낡으면 답이 거짓이 된다 → 스윕 스크립트가 빌드 신선도를 먼저 검사한다.
import Foundation
import IndexStoreDB

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("MutatorGate: \(message)\n".utf8))
    exit(2)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else {
    fail("usage: MutatorGate <index-store-path> <source-root> [--verbose]")
}
let storePath = arguments[0]
let sourceRoot = URL(fileURLWithPath: arguments[1]).standardizedFileURL.path
let verbose = arguments.contains("--verbose")
    || ProcessInfo.processInfo.environment["MUTATOR_GATE_VERBOSE"] == "1"

// `libIndexStore.dylib` 는 툴체인에 들어 있다(Xcode 든 오픈소스 툴체인이든). 경로를 박지 않고
// DEVELOPER_DIR 로 받는다 — 스윕 스크립트가 `xcode-select -p` 를 넘긴다.
let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
    ?? "/Applications/Xcode.app/Contents/Developer"
let dylibPath = "\(developerDir)/Toolchains/XcodeDefault.xctoolchain/usr/lib/libIndexStore.dylib"

let database: IndexStoreDB
do {
    let library = try IndexStoreLibrary(dylibPath: dylibPath)
    database = try IndexStoreDB(
        storePath: storePath,
        databasePath: NSTemporaryDirectory() + "mutator-gate-\(getpid())",
        library: library,
        waitUntilDoneInitializing: true,
        listenToUnitEvents: false
    )
} catch {
    fail("인덱스 스토어를 열 수 없습니다(\(storePath)): \(error)")
}
database.pollForUnitChangesAndWait()

// MARK: - 소스 읽기

/// 선언 줄 텍스트. 파일이 사라졌으면 nil — **낡은 인덱스 유닛을 걸러내는 자리다.**
/// (결함 주입 하네스가 넣었다 지운 프로브가 스토어에 유닛으로 남아, 없는 파일의 선언을
/// 유령으로 올릴 수 있다.)
var lineCache: [String: [String]] = [:]
func sourceLine(path: String, line: Int) -> String? {
    if lineCache[path] == nil {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        lineCache[path] = text.components(separatedBy: "\n")
    }
    guard let lines = lineCache[path], line >= 1, line <= lines.count else { return nil }
    return lines[line - 1]
}

func isUnderSourceRoot(_ path: String) -> Bool { path.hasPrefix(sourceRoot) }

/// `private`·`fileprivate` 선언은 클래스가 아니다 — 세이브를 바꾸는 **API** 가 경계다.
/// 인덱스는 가시성을 노출하지 않으므로 선언 줄을 읽는다. 수식어가 사이에 끼는
/// `private static func` 를 놓치지 않게 이전 판(awk)과 같은 정규식을 쓴다.
func isPrivateDeclaration(path: String, line: Int) -> Bool {
    guard let text = sourceLine(path: path, line: line) else { return false }
    return text.range(of: "(private|fileprivate) [a-z ]*func", options: .regularExpression) != nil
}

func isFunctionKind(_ kind: IndexSymbolKind) -> Bool {
    switch kind {
    case .instanceMethod, .staticMethod, .classMethod, .function: return true
    default: return false
    }
}

// MARK: - 후보: `save()` 를 부르는 함수

// 이전 판은 "본문에 `save()` 텍스트가 있는 func" 이었다. 텍스트라서 산문 주석 한 줄이
// 앞 함수를 mutator 로 만들었고(유령 4개), 접근자 안의 `save()` 가 엉뚱한 함수에 붙었다.
// 인덱스는 호출을 호출로 본다: `save()` 정의의 호출 occurrence 마다 `.calledBy` 관계가
// 부르는 쪽 심볼을 가리킨다.
let saveDefinitions = database.canonicalOccurrences(
    containing: "save(",
    anchorStart: true,
    anchorEnd: false,
    subsequence: false,
    ignoreCase: false
).filter { $0.symbol.name == "save()" && isUnderSourceRoot($0.location.path) }

if saveDefinitions.isEmpty {
    fail("`save()` 정의를 인덱스에서 찾지 못했습니다 — 스토어가 비었거나 범위가 틀렸습니다.")
}

var candidateUSRs: Set<String> = []
for saveDefinition in saveDefinitions {
    for call in database.occurrences(ofUSR: saveDefinition.symbol.usr, roles: .call) {
        guard isUnderSourceRoot(call.location.path) else { continue }
        for relation in call.relations where relation.roles.contains(.calledBy) {
            candidateUSRs.insert(relation.symbol.usr)
        }
    }
}

// MARK: - 판정: 이 선언을 참조하는 곳이 있는가

/// `Sources/` 안의 참조 수. 자기 안의 재귀 호출은 도달성이 아니므로 뺀다.
func referenceCount(ofUSR usr: String, selfUSR: String) -> Int {
    database.occurrences(ofUSR: usr, roles: [.reference, .call]).filter { occurrence in
        guard isUnderSourceRoot(occurrence.location.path) else { return false }
        return !occurrence.relations.contains { $0.symbol.usr == selfUSR }
    }.count
}

struct Finding {
    let path: String
    let line: Int
    let name: String
}

var findings: [Finding] = []
for usr in candidateUSRs {
    let definitions = database.occurrences(ofUSR: usr, roles: .definition)
        .filter { isUnderSourceRoot($0.location.path) }
    for definition in definitions {
        let location = definition.location
        guard isFunctionKind(definition.symbol.kind) else { continue }
        // 파일이 없으면 낡은 유닛이다 — 판정하지 않는다.
        guard sourceLine(path: location.path, line: location.line) != nil else { continue }
        guard !isPrivateDeclaration(path: location.path, line: location.line) else { continue }

        // 프로토콜 요구사항·상위 메서드로만 불리는 구현은 참조가 그쪽 USR 에 기록된다.
        // 따라가지 않으면 **없는 결함으로 CI 를 세운다**(결함 주입 케이스 5).
        var countedUSRs = [usr]
        for relation in definition.relations where relation.roles.contains(.overrideOf) {
            countedUSRs.append(relation.symbol.usr)
        }
        let total = countedUSRs.reduce(0) { $0 + referenceCount(ofUSR: $1, selfUSR: usr) }

        if verbose {
            let relative = location.path.replacingOccurrences(of: sourceRoot + "/", with: "")
            print("· \(relative):\(location.line)\t\(definition.symbol.name)\trefs=\(total)")
        }
        if total == 0 {
            findings.append(Finding(path: location.path, line: location.line, name: definition.symbol.name))
        }
    }
}

// 이름이 아니라 위치로 정렬한다 — 같은 이름이 여러 곳에 있는 것이 이 도구의 존재 이유다.
for finding in findings.sorted(by: { ($0.path, $0.line) < ($1.path, $1.line) }) {
    print("\(finding.path):\(finding.line)\t\(finding.name)")
}
