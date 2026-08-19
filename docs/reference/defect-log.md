---
summary: "결함 대응 프로토콜로 축적된 구체 규칙 — 한 번 겪은 부류의 실수를 다시 겪지 않기 위한 원장."
read_when:
  - 결함·회귀·공백을 고치는 중 (프로토콜 4단계의 '부류 스윕'·'영구 캡처' 근거)
  - 동시성/await·옵셔널 판정·캐시 무효화·외부 로그 포맷을 건드릴 때
  - 메뉴바·플로팅 펫 등 상시 표시 애니메이션의 성능을 손볼 때
  - 세이브 이전/병합·외부 파일 입력 경로를 만들 때
  - 컴파일러 warning·CI 게이트를 손볼 때 (게이트 없는 warning 은 쌓인다)
---

# 결함 대응 축적 규칙

`CLAUDE.md` §결함 대응 프로토콜의 4단계(근본원인 → 부류 스윕 → 회귀 테스트 → 영구 캡처)를 거쳐
남은 규칙들이다. 각 항목은 실제로 겪은 회귀에 묶여 있다.

## 판정·데이터
- **다국어 목록에서 "마지막 = 최신"은 맞아도 "최신 = 쓸 수 있는 값"은 아니다.** PokéAPI
  `flavor_text_entries` 는 버전그룹 오름차순이라 루프로 덮어쓰면 최신만 남는데, 소드·실드에서 *삭제된*
  기술은 그 최신 항목이 설명이 아니라 "사용할 수 없는 기술입니다" 안내문이다(실측 `move/return`:
  ultra-sun 까지는 진짜 설명, sword-shield 부터 안내문). 그래서 멀쩡히 습득한 기술의 설명 자리에
  안내문이 떴다. 순서대로 덮어쓰되 **안내문 항목은 건너뛴다** — 그러면 가장 최신의 진짜 설명이 남는다
  (`PokeAPIClient.flavorTexts`, 순회는 오래된 것부터다).
  판정은 **접두사로** 한다 — "사용할 수 없" 부분일치로 보면 금지어("4턴 동안 사용할 수 없게 만든다")
  같은 진짜 설명까지 지운다(거짓양성 가드 `MoveHoverTests.testRealDescriptionsMentioningUnusableAreNotDropped`).
  정규화 없이 비교하면 안 잡힌다. PokéAPI 는 굽은 따옴표(`’`)와 전각 공백(U+3000)을 쓴다.
- **파서를 고쳤으면 이미 세이브에 박힌 값도 다시 받아야 한다 — 단 "조회했지만 없다"까지 다시 받으면 안 된다.**
  보강 조건이 `descriptions == nil` 이면 잘못된 값이 *들어 있는* 개체는 영영 안 고쳐진다 — 사용자에겐
  "고쳤다는데 그대로"로 보인다. 조건을 "없거나 오염됐으면"(`CompanionStore.needsDescriptionRefresh`)으로
  넓히되, **빈 컨테이너를 "없음"과 같이 취급하면 반대로 수렴하지 않는다**: 안내문뿐인 기술은 조회 결과가
  빈 dict 라 로드할 때마다 다시 받게 된다. `nil`(안 받아봤다) / `[:]`(받아봤지만 쓸 게 없다) 를 구분한다.
  **미완 스윕(2026-08-19)**: 같은 패턴이 `CompanionStore.backfillMissingDexNames` 에 남아 있다 —
  `where entry.names == nil` 이라, `dexResolveChainNames` 가 chainOrder 일부만 담긴 dict 를 저장하면
  빠진 종이 도감에 `#134` 로 영구히 남는다. 고칠 때 "완전한 map 일 때만 저장"과 위의 수렴 문제를
  같이 봐야 한다(부분 저장을 막으면 이름 없는 종은 매번 재조회가 된다).

- **옵셔널 tautology.** 옵셔널 필드라도 *생산자가 항상 채우면* `x != nil` 은 항상 참이다. "값이 있나"는
  의미값으로 검사한다(예: `totalTokens > 0`, 또는 진짜 nil 가능한 필드 `activeBlock`). — weekTotal 회귀(#56).
- **JSON `null` 은 "값 있음"이 아니다.** `obj["x"] != nil` 은 `NSNull` 에도 참이라 `intValue` 가 0 을 돌려주고,
  그 0 으로 캐시분을 빼면 토큰이 통째로 사라진다. 숫자 필드는 `NSNull`·문자열·부재를 모두 nil 로 만드는
  추출기(`intOrNil`/`doubleOrNil`)로 읽고, 대체 스펠링 폴백은 그 nil 로 판단한다.
  **숫자만의 문제가 아니다** — 존재 판정에도 같은 함정이 있다. `json["claudeAiOauth"] == nil` 로 계정 OAuth
  유무를 보면 `"claudeAiOauth": null`(로그아웃 상태)이 "있음"으로 판정돼 재로그인 안내 대신 엉뚱한 메시지가
  나간다. 기대 타입으로 캐스팅되는지로 판단한다(`(json["x"] as? [String: Any]) == nil`). 회귀 가드는
  부재·`null`·정상 셋을 모두 넣어야 한다 — 부재와 정상만 넣으면 통과하면서 `null` 을 못 잡는다.
- **관대 디코딩(`lenient`/`Lossy`)을 유지하려면 신뢰경계의 값 범위 검증이 짝으로 와야 한다.** 관대 디코딩은
  "한 필드가 깨져도 도감을 안 날린다"를 얻는 대신 "말이 안 되는 값도 통과시킨다"를 떠안는다. 자기 앱이 쓴
  파일만 읽을 땐 무해하지만, **외부 파일을 읽는 경로가 생기는 순간 그 트레이드오프가 라이브가 된다** —
  `Int.max` 같은 값이 그대로 저장되면 이후 산술이 Swift 오버플로 트랩으로 프로세스를 죽이고, 재기동해도
  같은 파일을 읽어 다시 죽는다(`load()` 의 `.corrupt` 복구는 디코드가 *성공*하므로 발동 안 함 → 파일을
  손으로 지우기 전까지 앱 사용 불가). 방어는 다운스트림 산술 지점마다가 아니라 **값이 들어오는 경계 한
  곳**에서(`SaveTransfer.sanitized`). 자르는 대상은 산술에 쓰이는 수치뿐 — 도감·인벤토리 *항목*은 잘라내면
  데이터 손실이다. (딥리뷰 2026-08-03: SIGTRAP 재현.)
- **같은 규칙이 세이브 파일이 아니라 *외부에서 오는 모든 수치*에 적용된다 — 파싱 경계도 포함.** 위 규칙을
  "세이브 파일"로 좁게 읽은 탓에 사용량 로그 파서(`LocalUsageReader`)의 `intValue` 가 무방비로 남았고,
  같은 SIGTRAP 이 Codex·Claude·Gemini 세 경로에서 재현됐다(딥리뷰 2026-08-04). 사용량 로그도 앱이 쓴 게
  아니라 **CLI 가 쓴 외부 파일**이다 — 손편집·전송 손상·업스트림 버그가 그대로 들어온다.
  방어 지점은 추출기 하나(`LocalUsageReader.intValue`/`intOrNil`)이고, **상한을 `Int.max` 로 잡으면 안 된다**:
  클램프 자체는 통과해도 `output + thoughts` 처럼 파싱 직후 더하는 곳에서 다시 트랩난다. 합산 여유가 있는
  상한(`maxParsedTokenValue`)을 쓴다. 회귀 가드는 프로바이더별로 **테스트를 쪼개라** — 트랩은 프로세스를
  끝내므로 한 테스트에 몰면 뒤 케이스가 아예 실행되지 않는다.

- **`?? 기본값` 은 "값이 없다"를 "값이 이거다"로 바꿔 화면에 거짓을 만든다 — 그리고 라인 커버리지에
  잡히지 않는다.** 위의 `nil`/빈 값 구분과 같은 부류인데, 이쪽은 디코딩이 아니라 *표시* 에서 터진다.
  이벤트 스트림을 로그 문구로 접을 때 `damage ?? 0` 을 쓰면 데미지 이벤트가 없는 행동(빗나감,
  위력 없는 변화기, 아직 안 들어온 상태이상 부여)이 **"0 데미지"** 로 렌더된다 — 맞았는데 0 인 것처럼
  읽히는, 없는 정보를 지어낸 문구다. 옵셔널은 `guard let` 으로 갈라 "숫자가 없는 문구"를 따로 두고,
  기본값으로 메우지 않는다(`BattleLog.Action.text`).
  **커버리지가 이걸 못 잡는 이유**: `?? 0` 은 한 줄 안의 region 이라 그 줄이 실행되면 라인은 세어지고,
  `??` 왼쪽만 밟혀도 초록이다. 새로 넣은 `BattleLog.swift` 는 라인 커버리지 91% 로 게이트를 통과한
  상태에서 `.resisted` 분기가 **0회**였고, `?? 0` 두 곳은 한 번도 nil 을 안 밟았다.
  `llvm-cov --show-regions | grep '\^0'` 으로 직접 봐야 드러난다. **새 enum case 는 만드는 쪽(엔진)만 테스트하면 렌더러 쪽이 0회로 남는다**:
  엔진 테스트가 `.resisted` 를 검증해도 접기 테스트가 그 case 를 먹이지 않으면 렌더 분기는 죽어 있다(#51).

## 외부 로그·사용량 소스

- **외부 로그 포맷은 *상위 소스의 writer* 로 검증한다 — 내 픽스처는 증거가 아니다.** 새 프로바이더 파서를
  쓸 때 "이렇게 생겼을 것"으로 픽스처를 만들면 파서와 픽스처가 같은 오해를 공유해 테스트가 전부 통과하면서
  실사용은 0 을 표시한다(#133: 봉투 래퍼 키를 `update` 로 봤으나 실제는 `params`, `timestamp` 는 ISO 문자열이
  아니라 Unix `u64` 초 — 실제 라인은 한 건도 안 잡혔다). 순서: ① 업스트림에서 *쓰는* 코드(직렬화 구조체·serde
  계약 테스트)를 열어 키·타입·의미를 확정 ② 그 계약으로 픽스처 작성 ③ 가능하면 실파일 1건 캡처. 특히
  **같은 스펠링이 표면마다 의미가 다를 수 있다**(Grok `inputTokens`=캐시 포함 durable wire vs `input_tokens`=캐시
  제외 헤드리스 투영) — 별칭으로 합치면 캐시분을 두 번 빼거나 두 번 더한다.
- **사용량 소스의 "복사·재기록" 경로를 먼저 찾아라 (이중집계·재날짜화).** 세션 fork·재생·서브에이전트는 같은
  지출을 여러 파일에 남기거나 시각을 다시 찍는다. 규칙: ① dedup 키는 *턴 자체* 의 전역 유일 id(파일·세션 경로를
  섞지 마라 — 복사본이 별건이 된다) ② 시각은 *기록* 시각이 아니라 *턴* 시각(fork 는 봉투 timestamp 를 새로
  찍는다 → 주/월 합계가 포크 시점으로 몰린다) ③ 부모에 접혀 들어오는 자식(서브에이전트) 세션은 제외.
- **로그 루트는 한 곳이 아니다.** Claude 사용 로그는 CLI 기본 위치 말고도 `CLAUDE_CONFIG_DIR`(콤마 다중),
  XDG 스타일 `~/.config/claude/projects`, 그리고 Claude Desktop 임베디드 세션(`local-agent-mode-sessions`/
  `claude-code-sessions` 아래 세션마다 자체 `.claude/projects`)에 남는다. 루트 추가는
  `LocalUsageReader.claudeProjectRoots` 한 곳에서만 한다. 임베디드 루트 탐색은 `.claude` 가 **hidden** 이라
  `skipsHiddenFiles` 를 켜면 조용히 0건이 된다 — 회귀 가드
  `testEmbeddedRootsFindHiddenClaudeProjectsDirs` 가 그 브랜치를 밟는다.
- **GUI 앱은 셸 환경을 상속하지 않는다 — 환경변수로 설정되는 경로는 셸에 물어봐야 한다.** Finder/launchd 로
  뜬 `.app` 의 `ProcessInfo.processInfo.environment` 에는 `~/.zshrc` 의 export 가 없다. 그래서
  `CLAUDE_CONFIG_DIR` 같은 값을 프로세스 환경에서만 읽으면 **CLI·`swift test` 에서는 통과하고 배포된 앱에서만
  0 을 표시**해 재현이 안 된다. 레포에 이미 같은 부류의 해법이 있다(`BinaryLocator.shellResolve` 가 PATH 때문에
  `zsh -ilc` 를 띄운다) — 새 환경변수도 `BinaryLocator.shellEnvironmentValue` 로 조회한다. 단 셸 spawn 은
  실측 ~0.44s 라 **프로세스 생애 1회만**(`static let` lazy) 캐시하고, 주기적으로 갱신되는 캐시(TTL)에 묶지 마라 —
  그 값을 안 쓰는 대다수 사용자까지 갱신마다 비용을 문다.
- **디렉터리 탐색은 깊이만 막으면 폭이 안 막히지만, 이름 기반 가지치기는 더 위험하다.** 깊이 가지치기는
  `> maxDepth` 가 아니라 `>= maxDepth` 에서 걸어야 한 단계 더 내려가지 않는다(전자는 상한+1 까지 방문).
  깊이 상한은 **실제 레이아웃 깊이를 테스트로 고정**하고 여유를 둔다 — 경계에 붙여 두면 상위 소스가 한 단계
  중첩하는 순간 조용히 0건이 된다(`testEmbeddedRootsDepthBoundaryMatchesRealLayoutWithHeadroom`).
  **이름으로 가지치는 목록에는 사용자 작업 트리가 될 수 있는 이름을 절대 넣지 마라** — 이름 하나가 *조상*
  으로 걸리면 그 아래 전부가 사라진다. 실측 회귀: 폭을 줄이려고 `uploads`·`outputs`·`build`·`target` 을
  넣었는데, `uploads`·`outputs` 는 실제 세션 레이아웃에 존재하는 디렉터리고 그 안에서 돌린 Claude 세션은
  정당한 루트다 → 원래 고치려던 "조용한 0건"을 그대로 재생산했다. 목록은 패키지·VCS 내부처럼 사용자 코드가
  아닌 것만(`node_modules`·`.git`·`venv`·`.venv`) 두고, 폭 제어의 주 수단은 깊이 상한으로 둔다.
- **가지치기·필터 테스트는 양방향으로 단언하라.** "제외돼야 할 것이 제외됐나"만 보면 "포함돼야 할 것이 함께
  잘렸나"를 못 잡는다. 위 회귀가 정확히 그렇게 통과했다 — `testEmbeddedRootsDoNotDescendIntoBulkDirectories`
  는 `node_modules` 가 잘리는 것만 확인했고, 같은 목록이 정당한 루트를 자르는 건 아무도 안 봤다. 짝이 되는
  가드가 `testEmbeddedRootsFindRootsUnderWorkDirectoryNames` 다.
- **락을 쥔 채 외부 프로세스를 기다리지 마라.** 캐시 갱신 락 안에서 로그인 셸 spawn(최대 8초 대기)이나
  파일시스템 전체 탐색을 하면, `UsageStore` 가 taskGroup 으로 병렬 fetch 하는 다른 프로바이더까지 그 뒤에
  줄 선다. 결과가 idempotent 하면 **계산은 락 밖에서** 하고 락은 필드 대입에만 쥔다(경합 시 중복 계산이
  블로킹보다 낫다).
- **자식 프로세스 출력은 드레인하되, 드레인에 별도의 짧은 상한을 두지 마라.** 파이프 버퍼(64KB) 데드락을
  막으려 백그라운드 드레인으로 바꾸면서 세마포어에 2초 상한을 걸었더니, **종료를 무한정 기다리던 이전 동작에서
  값을 얻던 경우가 nil 이 됐다**(실측 회귀). 셸이 exit 해도 rc 가 띄운 백그라운드 잡(zsh-async·zinit turbo 등)이
  stdout write end 를 쥐고 있으면 EOF 가 늦게 온다 — 드레인은 **전체 타임아웃의 남은 예산**을 줘야 한다
  (실측: 고정 2초 → nil / 남은 예산 → 4.03초에 값). 그리고 포기할 땐 `handle.close()` 로 리더를 깨워라 —
  안 닫으면 `readDataToEndOfFile` 에 박힌 워커 스레드가 호출마다 하나씩 영구히 쌓인다(재시도가 타이머로
  반복되는 상주 앱에서는 하루 수백 개).
- **두 개의 완화책을 동시에 바꾸면 각각은 옳아도 조합이 회귀가 된다.** 이름 가지치기 목록을 줄이면서(정확성)
  깊이 상한을 함께 올렸더니(여유) 열거량이 수백 배로 뛰었다 — 각 변경은 단독으로는 무해했고, 폭을 잡던 것이
  이름 목록이었는데 그걸 줄이는 순간 깊이가 유일한 제어가 됐기 때문이다. 완화책을 조정할 땐 **어느 쪽이 실제로
  비용을 잡고 있었는지 측정**하고 한 번에 하나씩 바꾼다. 최종값은 측정으로 정한다(실측: 깊이 6=놓침,
  7=전부 찾음·방문 100, 8·9=방문 그대로 → 7 이 "놓치지 않는 최소값이면서 비용이 안 느는 지점").
- **`precondition` 은 릴리스 빌드에서도 앱을 죽인다 — 테스트 전용 시임을 지키는 데 쓰지 마라.** 잘못 써도
  결과가 "테스트가 엉뚱한 대상을 본다"에 그치는 실수를 SIGTRAP 으로 키운다(`-Ounchecked` 아니면 안 사라짐).
  도달 불가한 곳이면 더더욱 값이 없다. 우선순위를 주석으로 적거나, 애초에 잘못 쓸 수 없는 시그니처로 바꿔라.
- **하위 레이어 호출이 비싼 초기화를 트리거하지 않는지 보라.** 안내 문구 하나를 고르려고 부른 함수가
  `static let` 첫 접근 → 로그인 셸 spawn 을 유발해, 자동 폴링 경로의 actor 를 수백 ms~수 초 막을 수 있다.
  값이 필요한 쪽(그 값을 실제로 쓰는 경로)에서 초기화를 트리거하고, 부수적 분기에서는 싼 소스
  (`ProcessInfo.environment`)만 본다.
- **유닛 테스트가 로그인 셸을 띄우면 hermetic 하지 않다.** 프로덕션 진입점(`claudeProjectRoots`)을 테스트에서
  직접 부르면 개발자의 `.zshrc` 가 실행되고, 그 기기에 `CLAUDE_CONFIG_DIR` 이 export 돼 있으면 결과가 달라진다.
  주입 시임(`computeClaudeProjectRoots(configDirValue:home:)`)으로 판정하고, 실환경 확인은 일회성 프로브로
  분리한다.
- **경로 dedup 은 심볼릭 링크를 풀고 대소문자를 무시해야 한다.** `standardizedFileURL` 은 `..`·`.` 만 정리하고
  링크는 그대로 둔다. `~/.config/claude` → `~/.claude` 링크 같은 구성에서 같은 트리를 두 번 열거·파싱하게 된다
  (합계는 전역 dedup 이 지키지만 스캔 비용과 캐시 blob 은 두 배). `resolvingSymlinksInPath()` 로 풀고
  비교 키는 소문자로 — macOS 기본 APFS 는 대소문자를 구분하지 않는다.
- **테스트 시임이 프로덕션 브랜치를 단락시키지 않는지 확인하라.** 다중 루트 순회를 넣고 시임은 단일 루트만
  받게 두면(`claudeRoot.map { [$0] }`) 기존 테스트 전부가 루프를 1회로 단락시켜, 실제로 도는 코드는 무테스트로
  남는다. 새 브랜치를 만들면 **그 브랜치를 밟는 시임**을 같이 만든다(`LocalUsageCache(claudeRoots:)` +
  `testMultipleRootsAreScannedAndDedupedAcrossRoots`, 단일 루트 대조군 포함).
- **파일 밖 상태에 의존하는 판정을 파싱 캐시 안에서 하지 마라.** `LocalUsageCache` blob 은 그 파일의
  `(path, mtime, size)` 로만 무효화된다. 옆 파일(예: Grok `summary.json` 의 `session_kind`)로 결정되는
  포함·제외를 파서 안에서 하면, 근거가 나중에 바뀌어도 파일이 안 바뀌어 판정이 영구히 굳는다. 그런 판정은
  파일 선택 단계(`collect(include:)`)에 둬 매 새로고침 재평가되게 한다.
- **캐시를 붙이는 순간 "다음 새로고침이 다시 읽는다"가 공짜가 아니다.** 부분 읽기(SQLITE_BUSY·손상 페이지)를
  버리는 가드는 **재시도가 실제로 오는 경우에만** 가드다. TTL 시절엔 만료가 재시도를 보장했지만
  `(path, mtime, size)` 키로 바꾸는 순간 그 보장이 사라진다 — 실패 결과를 *현재* signature 아래 blob 으로
  넣으면 파일이 가만히 있는 한 그 소스는 영구히 "사용량 없음"으로 읽힌다. 규칙: ① 읽기 결과를 `[]`·`nil` 로
  접지 말고 **실패와 빈 값을 구분하는 값**으로 돌려라(`LocalAntigravityUsageReader.ConversationRead`)
  ② 일시적 실패는 캐시에 **쓰지 말고** 이전 blob 을 *옛 signature 그대로* 이어받아 다음 스캔이 다시 읽게
  하라 ③ 영구적 사실(기대 테이블이 아예 없는 파일)만 빈 값으로 캐시한다 — 안 그러면 대화가 아닌 DB 를 매
  새로고침 재오픈한다. 같은 이유로 **창(window) 필터를 캐시 단위 안에 굽지 마라**: blob 은 그 창보다 오래
  살아서 다음 날 조용히 행이 빈다. 캐시는 무필터로 담고 조립 시점에 좁힌다(`assemble(_:since:)`).
  회귀 가드: `testIncompleteScanKeepsThePreviousRowsUnderTheirOldSignature`·
  `testUnreadableStoreIsNotCachedAsAnEmptyConversation`·`testDatabaseWithoutTheExpectedTableIsCachedAsEmpty`.
- **캐시 무효화 키에 *내 읽기가 건드리는 파일*을 넣지 마라.** WAL 의 `-shm` 은 읽기 전용 커넥션도 read mark 를
  쓴다. 키에 넣으면 스캔이 방금 쓴 blob 을 그 스캔 자신이 무효화해 **히트율이 영구히 0** 이 된다 — 교체하려던
  TTL 보다 나쁘다. 커밋은 `.db`(체크포인트)나 `-wal`(append) 에 반드시 남으므로 키는 그 둘의 최신 mtime +
  크기 합이면 충분하고, 같은 이유로 창 판정에도 `-shm` 은 무의미하다(그것만 새롭다 = 누가 *읽었다*).
  그리고 **stat 은 읽기 앞에서** 한다 — 뒤에서 하면 읽는 중에 들어온 커밋이 이미 최신처럼 보이는 signature 에
  굳어 영영 안 읽힌다. 회귀 가드: `testShmChurnDoesNotInvalidateTheBlob`·`testWalCommitInvalidatesTheBlob`.
- **실패가 흔적을 안 남기면 "안 썼음"과 구분되지 않는다.** 외부 소스 리더가 실패를 `[]`/`nil` 로 접으면 사용량
  0 과 같은 값이 된다. 프로바이더별 탭이 붙은 뒤엔 숫자가 조금 낮은 정도가 아니라 **탭이 통째로 사라진다**
  (`UsageStore` 는 `today != nil` 이거나 활성 블록이 있을 때만 스냅샷을 만든다). 로그를 남기되 세 가지를 지켜라:
  ① **판정은 순수 함수로 분리** — `AppLog.write` 는 `AppEnv.isBundledApp` 가드로 xctest 에서 조기 return 하므로
  로그 파일을 보는 테스트는 아무것도 커버하지 못한다(§알림의 같은 규칙). ② **양을 묶어라** — 읽을 수 없는
  소스는 매 새로고침 다시 읽히므로(기본 2분 = 720회/일) 대상마다 한 줄이면 2MB 로그가 하루에도 여러 번
  회전해 크래시 이력을 밀어낸다. 스캔당 상위 N개만 이름을 남기고 나머지는 개수로 접는다. ③ **영구적 사실은
  로그하지 마라** — "이 파일엔 그 테이블이 없다"는 바뀌지 않으므로 영원히 반복된다.
  회귀 가드: `testIncompleteScanDropsTheConversationAndNamesTheReason`·`testLossLogNamesAFewStoresAndCountsTheRest`·
  `testDatabaseWithoutTheExpectedTableIsNotReportedAsALoss`.

## 자격증명·Keychain

- **앱 소유 keychain 항목 금지.** 앱이 만든 keychain 항목은 코드서명(cdhash)이 바뀔 때마다(로컬 재빌드·
  실사용자 매 업그레이드) 항목 ACL 이 안 맞아 접근 허용 프롬프트를 유발한다 — **no-UI 쿼리로도 이 ACL
  프롬프트는 억제 안 됨**(#58). 토큰류는 인메모리 캐시 + 파일(`~/.claude/.credentials.json`) 재취득으로
  처리하고, 앱 전용 keychain 캐시 항목을 새로 만들지 말 것.
- **자동 폴링은 Claude 키체인을 절대 읽지 마라(키체인 읽기는 사용자 동작 전용).** no-UI 쿼리
  (`kSecUseAuthenticationUIFail`/`LAContext`)는 '인증' 프롬프트만 억제할 뿐 **잠긴·미승인 login 키체인의
  '암호 입력' 다이얼로그는 못 막는다** — 실측: 캐시 만료 폴 도중 `SecItemCopyMatching` 이 13초간 블록하며
  팝업(토큰 만료 시점마다 하루 몇 회, 아침 등). self-signed 앱은 '항상 허용' 승인도 불안정. → 타이머 경로
  `fetch(allowKeychainPrompt: false)` 는 캐시+파일만 쓰고 키체인은 건드리지 않는다(`OAuthLimitsProvider`
  의 `guard allowKeychainPrompt` 가 키체인 읽기 앞에 위치). 키체인 읽기는 명시적 사용자 버튼
  (설정 갱신·팝오버 `claudeLimitsRefreshRow`, `refreshLimitTokenFromKeychain`)에서만. 캐시 토큰이 살아있는
  동안은 자동 폴이 그 토큰으로 한도를 계속 갱신하고, 만료되면 stale 표시 후 사용자가 갱신한다. 회귀 가드:
  `testAutoRefreshUsesNoPromptPathManualUsesPromptPath`. (완전 근절은 Developer ID notarization 으로
  '항상 허용' 승인을 안정화하는 것뿐 — 신뢰된 서명 신원이라야 ACL 승인이 지속된다. 미도입.)
- **자격증명 "없음"과 "계정 로그인 없음"은 다른 안내다.** Claude Code 2.1.x 의 `Claude Code-credentials`
  항목이 MCP 서버 OAuth(`mcpOAuth`) 상태만 담고 계정 토큰(`claudeAiOauth`)은 안 담는 경우가 있다. 이때
  파싱 실패를 형식 오류로 뭉뚱그리면 "재로그인하면 된다"를 안내 못 해 한도 섹션이 원인 불명으로 사라진다.
  → `LimitsError.credentialMissingAccountOAuth` 로 구분해 재로그인 안내를 띄운다
  (`OAuthCredentialData.isAccountOAuthMissing`).

## 동시성

- **비동기 완료가 "그 사이 교체된 대상"에 착지하지 않게 하라 — 상태를 통째로 바꾸는 경로를 새로 만들면
  진행 중인 await 를 전수 점검한다.** 이 레포가 세 번 겪은 부류다(#136·#138 스프라이트, 그리고 세이브
  불러오기 중 부화). `isHatching` 같은 중복 실행 락은 *같은 작업의 재진입*만 막을 뿐, await 창에서 상태가
  **다른 주체로 교체되는 것**은 못 막는다. 방어는 두 형태 중 하나로 통일한다: ① `activeGeneration` 을
  진입 시 캡처하고 mutation 직전 재검사(`hatchCore`·`revealDitto`·`loadCurrentLine`) ② 대상을 id 로 다시
  찾아 없으면 무시(`dexChainNames` 의 `firstIndex(where: id)`). 회귀 가드는 sleep 이 아니라 신호(actor +
  continuation)로 await 지점을 정확히 잡아 재현한다 — `testImportDuringHatchDiscardsTheHatch`.
  **세대는 호출 체인에서 *가장 이른* await 앞에서 캡처하라 — 안쪽 함수에서 캡처하면 가드가 자동 통과한다.**
  딥리뷰 실측: `hatchCore` 에만 가드를 넣었더니 `hatchIfNeeded` 의 `chooseBase()` 창에 들어온 교체를 못
  막았다. `hatchCore` 는 *교체 이후*의 세대를 캡처하므로 `activeGeneration == generation` 이 항상 참이 된다
  (출발할 때 봐야 할 시계를 도착해서 보는 격). 가드를 넣을 땐 그 함수 위의 await 까지 거슬러 확인하고,
  회귀 테스트도 **그 await 를 실제로 지나는 진입점**으로 써라 — `hatch(baseID:)` 경로 테스트는
  `chooseBase()` 를 안 지나 통과하면서 아무것도 지키지 않았다(`testImportDuringSpeciesRollDiscardsTheHatch`).

## 표시·UI
- **호버 상태를 `mouseExited` 로 지우지 마라 — 주기 갱신이 있는 화면에서는 커서가 그대로여도 온다.**
  60초 방치 틱이 팝오버를 다시 그리면 AppKit 이 트래킹 영역을 재설치하는데, 그때 이탈 이벤트만 오고
  **재진입은 안 온다**(커서가 안 움직였으므로). 이탈에서 상태를 비우면 마우스를 올려둔 채 설명이
  사라진다. 들어온 값으로 *바꾸기만* 하고 이탈은 무시한다 — 행 A→B 이동 시 A 이탈이 B 진입보다 늦게
  오는 순서 뒤집힘도 같은 규칙으로 막힌다(`MoveListView.hoverState`).
- **`.help()` 툴팁은 유일한 표시 경로가 될 수 없다 — NSPopover 안에서는 아무것도 안 뜬다.** SwiftUI 의
  `.help()` 는 `NSView.toolTip` 도 툴팁 rect 도 남기지 않고, **마우스 트래킹 영역을 0개** 만든다(프로브:
  `.help()` 0개 / `.onHover` 1개). 그래서 팝오버 안에서 기술 행에 마우스를 올려도 설명이 끝내 안 나왔다.
  판별하려면 렌더한 뒤 `NSView.trackingAreas` 를 센다 — "툴팁 문자열이 맞게 조립되는가"를 검증하는 테스트는
  **문자열만 보고 표시 경로는 안 보므로** 전부 통과하면서 화면엔 아무것도 없는 상태를 통과시킨다
  (`MoveLocalizationTests` 가 정확히 그랬다). 사용자가 꼭 봐야 하는 정보는 화면에 직접 그리고, `.help()` 는
  *덤*으로만 단다. 회귀 가드는 대조군(`.help()` 만 단 뷰의 트래킹 0개)을 같은 테스트에 넣어 어서션이
  판별력을 갖는지 남긴다 — `MoveHoverTests.testMoveRowsInstallHoverTracking`.
  부류 스윕(2026-08-19): 남은 `.help()` 대부분은 화면에 라벨이 이미 있거나(`Label` 텍스트·링크 제목·필터 안내)
  관례적 아이콘(gear·power)이라 정보 손실이 없다. **다만 하나 남았다** — `DexSpeciesCell.tooltip` 의
  희귀도(`rarityLabel`)는 칸 어디에도 안 그려져 툴팁에만 있다(✨·육성중 배지는 화면에 있다).
  `.accessibilityLabel` 이 같이 걸려 있어 VoiceOver 로는 읽히고, 희귀도 필터(`RarityTally`)로 걸러 보면
  간접 확인은 된다. 다만 칸만 보고 아는 방법은 없으므로, 도감 칸에 희귀도를 그리기 전까지
  이 부류는 아직 안 끝났다.
- **호버로 채우는 슬롯은 높이를 고정하되, 줄 예산은 실제 최장 문자열로 재서 정한다.** 설명 길이를 따라
  늘어나면 행 사이로 마우스를 옮길 때마다 아래 콘텐츠가 밀려 팝오버 안이 떨린다. 높이는 숫자 상수가 아니라
  *같은 폰트의 더미 줄* 에서 유도한다(자리표시자 행과 같은 이유 — 상수는 폰트·OS 따라 어긋난다).
  줄 수는 **감이 아니라 측정**이다: 처음 잡은 2줄은 PokéAPI 최장급 설명(157자)에서 3줄을 요구해 마지막 줄이
  통째로 사라졌고, `.help()` 가 죽어 있으니 잘린 뒤를 볼 방법도 없었다. 높이 *고정* 만 검증하는 테스트는
  이 잘림을 오히려 못 박는다 — "최장 문자열이 예산 안에 들어가는가"를 따로 검증한다
  (`MoveHoverTests.testLongestRealDescriptionIsNotTruncated`).
- **앱 언어와 시스템 로케일은 다른 축이다 — SwiftUI 가 스스로 만드는 문장은 로케일을 따른다.**
  `L` 문구는 `AppLanguage` 를 따르는데 `Text(_, style: .relative)` 는 `Locale.current` 를 따라, 한국어
  Mac 에서 앱을 영어로 쓰면 "Catch log" 옆에 "3시간 46분" 이 붙는 한 화면 두 언어가 된다. 팝오버 루트
  (`PopoverView.body`)에서 `.environment(\.locale, companion.language.displayLocale)` 로 내려 8곳
  (한도 7 · 포획 로그 1)을 한 번에 맞춘다. **`body` 안에서 줘야 한다** — `rootView` 조립 시점에 주면
  설정에서 언어를 바꿔도 팝오버를 다시 열기까지 안 바뀐다. 경계: 이 환경값은 SwiftUI 가 생성하는
  문장에만 걸리고 `TokenFormatter` 처럼 포매터를 직접 만드는 코드는 여전히 시스템 로케일을 쓴다
  (ko/en/ja 는 천 단위 구분자가 같아 차이가 안 보인다). 회귀 가드 `DisplayLocaleTests` 는 코드 비교로
  끝내지 않고 **그 로케일이 실제로 해당 언어의 상대 시각을 만드는지**까지 본다 — 코드만 비교하면
  `.current` 로 잘못 매핑해도 통과한다.
- **`.task(id:)` 키와 그 안의 재로드 가드는 같은 축 집합을 써야 한다.** 두 곳이 어긋나면 태스크는
  재실행되는데 안의 작업만 조용히 건너뛴다 — 실패가 화면에만 남고 로그엔 안 남는다. `SpriteView` 는
  `.task(id:)` 에 `종+shiny` 를 담고 내부 가드는 `loadedID`(종)만 비교해, 도감의 이로치 토글
  (종 고정·shiny 만 뒤집힘)에서 색이 바뀌지 않았다 — 재렌더 플래시를 막던 가드가 토글을 삼킨 것.
  판정은 순수 함수로 빼고(`SpriteView.needsReload` — `frameDelay` 와 같은 이유) 축마다 회귀 테스트를
  둔다(`SpriteShinyReloadTests`, 양방향 토글). 부류 스윕 확인분: `menuSpriteKey`("id-shiny" 포함)·
  `SpriteStore.cacheKey`(3축)·`DexEntryRow`(항목+언어) 안전 — `SpriteView` 만 결함이었다.
  같은 상태를 두 곳에 나눠 들면 재발하므로, 축을 늘릴 땐 `SpriteSubject` 처럼 주체 하나로 모으는 쪽이
  낫다(현재는 `loadedShiny` 가 subject 밖에 있어 반영 시점을 손으로 맞춘다).
- **지연 백필로 채워지는 데이터는 화면마다 트리거가 필요하다 — 새 화면은 그 트리거를 물려받지 않는다.**
  `DexEntry.names` 는 나중에 생긴 필드라 그 전 졸업분은 `nil` 이고, 포획 로그가 행이 뜰 때
  `dexResolveChainNames` 로 채워 왔다. 종 격자는 저장분만 읽어서 구버전 저장분이 `#41` 로 남았고,
  하필 격자가 기본 화면이라 로그를 눌러야 고쳐지는 상태가 됐다 — 자가치유가 *다른 화면*에 달려 있으면
  그 화면을 안 여는 사용자에게는 치유가 없다. 파생 화면을 새로 만들 땐 원본 화면이 하던 **조회·백필까지**
  같이 옮겼는지 본다(`DexGridView.task` → `backfillMissingDexNames`). 폴백(`#id`)은 저장하지 말 것 —
  저장하면 이름이 영구히 번호로 굳는다(`testBackfillRetriesAfterAnOfflineAttempt`).
  부류 스윕 확인분: 저장분을 읽는 소비자는 `DexEntryRow`(자체 백필 보유)와 격자뿐이고,
  `activeDexEntry`·`graduate()` 의 `line.names` 는 소비가 아니라 생성 지점이라 무관.
- **영구 기록과 임시 상태를 한 목록에 섞을 땐 임시 쪽에 표식이 필요하다.** 도감·수집 화면은 "쌓이기만
  한다"는 약속을 주는데, 현재 키우는 개체에서 파생된 항목은 알을 새로 사면(`buyEgg` 는 `active` 만 버리고
  `dex` 는 안 건드린다) 또는 메타몽이 리빌하면(`pathIDs` 가 통째로 교체) 사라진다 — 총계가 줄어 결함처럼
  보인다. 포획 로그는 행에 `키우는 중` 뱃지가 있어 괜찮았지만 종 격자는 표식 없이 같은 모양이었다.
  판정 기준은 "현재 개체에 속하는가"가 아니라 **"졸업 기록이 있는가"** 다(`DexSpecies.isRaising` =
  `!isGraduated`) — 같은 라인을 다시 키우는 중이면 이미 확정분이라 표식 대상이 아니고, 이 분기가
  두 규칙이 갈리는 유일한 지점이라 회귀 테스트도 그 상태(졸업분 + 같은 라인 육성 중)로 쓴다.

- **컴팩트 표시는 오늘 사용한 프로바이더만.** 메뉴바(`menuLines`) 등 좁은 표시에서 한도·상태를 보일 땐
  `snapshots` 의 오늘 토큰>0 으로 게이트한다 — 설치만 되고 오늘 안 쓴 프로바이더(Codex 등)를 노출하지
  마라(#56 "미사용 프로바이더 탭" 계열의 표시 버전). 팝오버 상세 뷰는 전체 노출 유지(의도된 상세). 함정:
  Claude 한도(OAuth)·Codex 한도(프로세스)는 *설치/인증만 돼 있으면 오늘 사용과 무관하게 값이 존재*하므로
  `limits != nil`/`codexLimits != nil` 만으로 표시하면 미사용 프로바이더가 샌다.
- **다중 토글 UI 레이아웃은 조합표 전수로.** 토글/입력이 여러 개인 표시 레이아웃을 바꿀 때, 사용자
  지시가 여러 메시지에 걸쳐 진화하면 각 지시를 **전체 대체가 아니라 특정 조합(행)에 대한 제약**으로
  누적한다. 구현 전 **모든 토글 조합 → 기대 출력 표**를 만들어 누적 지시와 대조·확인하고, 각 조합을
  테스트로 고정한다(`testMenuLinesAllCombinations` 처럼). — 회귀: "토큰+비용 세로로"(2개 활성 케이스
  지시)를 전역 규칙으로 오해해 "3줄 금지"(3개 활성 케이스 제약)를 깨고 3줄을 만든 사례. 두 지시는 서로
  다른 조합에 관한 것이라 **둘 다 성립**해야 했다(2개→세로, 3개→토큰·비용 한 줄+한도 아랫줄). 최신
  지시가 이전 제약과 충돌해 보이면 조합별로 재조정하고, 못 풀면 조합표로 되물어라.
- **수동 관찰(withObservationTracking) 표면은 companion 직접 변이 경로까지 추적해야 한다.** SwiftUI
  표면(팝오버·플로팅 펫)은 읽는 속성을 자동 추적하지만, AppKit 수동 관찰(`AppDelegate`)은 *등록한 속성만*
  본다. 메뉴바 스프라이트 갱신이 `observeStore`(=`store.menuTitle`)에만 걸려 있으면 store 틱 없이
  companion 만 바뀌는 경로 — 사탕 진화·졸업(`useRareCandy`), 세이브 가져오기(`applySave`),
  `hatchIfNeeded`·`revealDitto` 의 async 완료 — 는 다음 사용량 폴링(기본 120s)까지 이전 포켓몬이
  메뉴바에 남는다(사탕 졸업 직후 잔상 리포트). 같은 부류의 선례가 `UsageStore.onRefresh` 주석(한도
  변경이 menuTitle 미변경으로 companion 에 안 전달)이다. 표시가 파생되는 원천(`currentSpeciesID`·
  `currentIsShiny`)을 직접 추적하는 관찰 루프를 별도로 건다(`AppDelegate.observeCompanionSprite`).
  회귀 가드: `testCandyGraduationFiresSpriteIdentityObservation` — AppDelegate 쪽 배선은 AppKit
  (NSStatusBar)이라 헤드리스 테스트 불가, 관찰 계약(변이가 발화하는지)을 CompanionStore 쪽에서 고정.
- **메뉴바(상태아이템) stale dim 금지.** 시간 기반 stale(=`isStale`)로 `appearsDisabled` 를 켜면
  슬립/런치 직후 refresh 완료 전 몇 초간 메뉴바가 회색이 돼 '고장/비활성'으로 오인된다(사용자 반복 지적,
  `&& lastUpdated != nil` 로 런치만 막는 건 슬립-후 stale 을 못 막음). '오래됨' 신호는 팝오버에서만.
- **UI 변경 → 스크린샷 stale** 은 `release.sh` 가 자동 경고(`CLAUDE.md` §릴리스) — 통과의례화 방지.
- **선언만 있고 어디에도 마운트되지 않은 View 는 그 안의 *로직*까지 죽인다.** `AdventureCard` 가
  어떤 화면에도 안 붙어 있었고, 하필 그 안에 `claimAdventure()`(모험 보상 정산)의 유일한 호출부가
  있었다 — 보상이 영영 안 들어오고 `state.adventure` 도 안 비워져 "모험 보내고 집중 시작" 버튼이
  영구 비활성이 됐다(#8). 단위 테스트는 스토어 함수를 직접 부르므로 이 부류를 **원리적으로** 못 잡는다.
  가드는 소스 스캔이다 — `AdventureClaimTests.testEveryDeclaredViewHasACallSite` 가 UI 파일의 모든
  `struct X: View` 선언에 호출부가 있는지 본다. 기존 미마운트분(포획 로그 잔재 3개)은 명시 목록으로
  고정해 **신규 발생만** 막는다. 부류 스윕에서 나온 그 3개(`StarterCard`·`DexSummaryHeader`·
  `DexEntryRow`)는 화면 자체가 없어진 잔재라 별건이다.
- **"상태가 남아 있음"과 "지금 진행 중"을 같은 플래그로 쓰지 마라.** 위 #8 의 게이트가
  `isAdventuring`(= `adventure != nil`)이었는데, 이 값은 *끝났지만 아직 정산 안 된* 모험에서도 참이라
  정산 경로가 막히는 순간 영구 잠금이 됐다. 판정은 의미 단위로 나눈다(`isAdventureInProgress` =
  `!run.isComplete(now)`). 회귀 테스트는 **정산 전/후 두 브랜치를 각각** 밟아야 한다 — 완료-미정산
  상태를 안 만들면 예전 코드도 통과한다. 소모성 상태를 만드는 진입 경로가 여럿이면(집중 모험·존 모험)
  선행 정산도 **경로마다** 건다.
- **NSPopover 는 넘친 콘텐츠를 스크롤이 아니라 클리핑으로 처리한다.** 접힌 섹션(DisclosureGroup)을
  펼치면 콘텐츠가 화면 가용 높이를 넘고, 폭만 고정돼 있으면 위(타이머)와 아래(푸터)가 잘려 나간다(#9).
  팝오버 루트는 **높이 상한 + 스크롤**을 짝으로 둔다(`PopoverMetrics.maxHeight(screenHeight:)`).
  주의 두 가지: ① `ScrollView` 는 제안받은 높이를 통째로 먹으므로 `.frame(maxHeight:)` **뒤에**
  `.fixedSize(horizontal: false, vertical: true)` 를 붙여야 짧은 탭에서 빈 여백으로 부풀지 않는다
  (순서가 바뀌면 항상 상한 높이가 된다 — 측정으로 확인). ② 비동기로 채워지는 목록은 로딩 자리표시자를
  **완성본 높이**로 잡아야 팝오버가 두 번 리사이즈되지 않는다(`MoveListView.placeholderHeight`).
  높이 상수는 실제 렌더 높이와 어긋날 수 있으니 `NSHostingController.sizeThatFits` 로 잠근다.
- **"화면에서 파생한 상한"에 화면보다 작은 고정 픽셀 천장을 같이 걸지 마라.** 위 #9 수정은 상한을
  `max(minHeight, min(hardMaxHeight, screenHeight - chrome))` 로 뒀는데, `hardMaxHeight` 가 720pt 라
  1440pt 짜리 화면에서도 팝오버가 720 에서 멈췄다. "기술 보기" 를 펼친 홈 탭은 약 760pt(접힘 626 +
  기술 4행 118) — 화면엔 두 배 가까운 자리가 남는데도 스크롤로 넘어가 헤더 첫 줄과 돌봄·모험 카드가
  잘려, 사용자에겐 클리핑 버그가 안 고쳐진 것처럼(그리고 돌봄·모험이 롤백된 것처럼) 보였다. 상한은
  가용 공간에서만 뽑고, 굳이 천장을 두려면 **실제 최대 콘텐츠보다 큰 값**임을 테스트로 고정한다.
  회귀 가드: `testTallScreenFitsTheExpandedHomeTabWithoutScrolling` — 1440pt 화면 상한이 펼친 홈 탭
  높이보다 큰지 본다. 기존 테스트는 상한 공식을 *자기 자신*(`hardMaxHeight`)과 대조해서 통과했다 —
  상수를 상수로 검증하면 그 상수가 현실과 안 맞는다는 사실은 영원히 안 드러난다.
- **뷰가 이미 언어 축(`store.language`)을 들고 있어도 리터럴은 조용히 남는다.** 기술 행만 한국어
  리터럴이라 en/ja 에서 같은 화면의 툴팁(현지화됨)과 어긋났다(#10). 같은 단어를 두 곳에서 따로 쓰면
  한쪽만 고쳐진다 — 라벨은 `L` 한 곳에서 파생하고 행·툴팁이 그것을 공유한다. 스윕 방법:
  `grep -rE '"[^"]*[가-힣]' Sources/**/UI/*.swift` 후 **언어 분기(ternary/`t(...)`) 밖**에 있는 것만
  남긴다. 회귀 가드는 en/ja 출력에 한글 코드포인트가 없는지 + ko 는 한국어가 유지되는지(대조군).

- **뷰가 문구를 *만들면* 그 문구는 테스트 밖에 있다.** 배틀 로그의 3언어 문장은 `BattleView.eventLine`
  의 if/else 사슬 안에서 조립됐다 — 뷰를 띄우지 않고는 볼 수 없으니 "빗나갔는데 0 데미지로 표시" 같은
  오구현을 잡을 방법이 없었고, 1v1 과 멀티가 같은 사건에 서로 다른 문구를 만들고 있었다(멀티 쪽은
  기술 이름도 급소도 안 나왔다). **결정은 순수 함수로 내리고 뷰는 그 결과만 그린다**(`BattleLog.lines`
  → `[Line]`, 뷰는 `Text(line.text)`). 그러면 문구·언어·접기 규칙이 단위 테스트에 들어온다(#51).
  같은 부류 후보: 스냅샷 카드·미션 카드처럼 뷰 안에서 조건부 문자열을 만드는 자리.

## 배포 산출물 이름 (앱 ↔ 스크립트 ↔ GitHub)

- **에셋 이름은 세 곳이 글자 그대로 같아야 하고, GitHub 은 비-ASCII 를 말없이 바꾼다.** 앱은
  `PokeTokenBar.zip` 을 찾고, `release.sh`·CI 는 `Pokédoro.zip` 을 올렸고, GitHub 은 그걸
  `Pokedoro.zip` 으로 정규화해 세 이름이 전부 달랐다 → 다운로드 URL 이 항상 nil 이라 앱 내 업데이트가
  **에러 없이** 죽는다(릴리스 페이지만 열려서 "업데이트가 원래 저런가 보다" 로 보인다). 이름은
  `UpdateChecker.releaseAssetName` 한 곳에서 파생하고 ASCII 로 둔다. 테스트가 못 잡은 이유가 전형적이다 —
  가짜 릴리스를 **테스트가 지은 이름**으로 만들어 자기 자신과 대조했다. 가드
  `testReleaseAssetNameMatchesWhatTheReleaseScriptsUpload` 는 배포 스크립트 원문을 읽어 대조한다.
- **체크섬 파일은 zip 옆에서 만들어라.** `shasum -a 256 build/X.zip > build/X.zip.sha256` 은 파일 안에
  `build/X.zip` 이라는 *빌드 머신 경로*를 적는다. 받는 쪽은 zip 옆에서 `shasum -c` 를 돌리므로 파일을
  못 찾아 검증이 항상 실패한다(실제 배포본 확인: `... build/Pokédoro.zip`). `(cd build && shasum ...)`
  로 상대 이름만 남긴다.

## 에너지 (상시 표시 애니메이션)

- **메뉴바 상태아이템 = idle CPU 저격수 (두 규칙 필수).** 실측: 라이브 앱 idle ~14% CPU → 수정 후 ~2%.
  ① **`statusItem.button.image` 대입은 반드시 `setDisableActions` 트랜잭션 안에서** (`AppDelegate.setStatusImage`).
  레이어 백드 `NSStatusBarButton` 은 이미지 대입마다 `NSStatusItemScene` 암묵적 전환 애니메이션
  (`updateSettings:transition:` → `NSAnimationContext runAnimationGroup:`)을 돌려 상태바를 재합성한다 —
  5fps 스프라이트 루프면 이 전환이 CPU를 먹는다. `CATransaction.begin()/setDisableActions(true)/commit()` 로
  즉시 반영해 전환을 없앤다(애니메이션은 유지). ② **`.transient` NSPopover 는 `contentViewController` 를
  평생 보유**해 닫혀도 `NSHostingView` 트리가 상주하며 매 디스플레이 사이클 재레이아웃된다(특히
  `Text(_, style:.relative)` 가 `requestUpdate` 로 self-invalidation → `StackLayout.placeChildren` 폭주). 위
  전환 CA 커밋이 이 레이아웃을 flush해 둘이 곱해진다. → `NSPopoverDelegate.popoverDidClose` 에서
  `contentViewController = nil`, 열 때 재생성(`buildPopoverContent`). ③ 메뉴 애니는 팝오버 열림 중 정지
  (`menuShouldAnimate` 에 `!popover.isShown`) — 팝오버 SpriteView가 이미 애니메이션하고, 트래킹 중 상태아이콘
  리드로우는 WindowServer 부하(데스크톱 비컨볼) 위험. **status-item 전용 앱은 occlusion 이 실제로 잘 안
  떠서**(앱이 status item 표시 중엔 occluded 안 됨) occlusion 게이팅은 보조 — 슬립/열림 게이팅이 실질 방어.
  검증 함정: bare/`open -n` 보조 인스턴스는 애니메이션이 안 돌아 14%를 **재현 못 함** → 실측은 설치된
  primary 앱 교체로만. **배터리(idle wakeup) 차원:** CPU% 낮아도 button.image 대입마다 레이어 dirty →
  CA 커밋 → WindowServer 디스플레이 사이클 왕복이 wakeup을 증폭한다(실측 ~47 wakeup/s). `setStatusImage`
  diff-gate(동일 프레임 객체 재대입 스킵 — 애니 프레임은 서로 다른 객체라 정상 통과) + GIF fps 하한 0.4s(≈2.5fps)
  + `Timer.tolerance` 0.5(코얼레싱)로 ~5 wakeup/s(−89%), 애니메이션 유지. 배터리-vs-AC/thermal 적응·CADisplayLink
  전환은 1인 로컬 노트북 기준 수확체감으로 판정, 미도입(필요 시 Agent Team 계획 참조). (Agent Team 조사 + 실측, 2026-07-22.)
- **항상 뜬 애니메이션 표면은 메뉴바와 같은 idle 규율을 공유한다.** 플로팅 펫(`FloatingPetPanel`)처럼 상시
  표시되는 두 번째 GIF 표면을 더할 땐 메뉴바 규율을 그대로 상속해야 회귀(#102 후속)를 안 만든다: ① GIF fps
  하한(`SpriteView(minFrameDelay:)` — 펫은 `FloatingPetView.frameFloor` 0.4s≈2.5fps, 팝오버 등 *일시적* 표시는
  0=네이티브) + `Task.sleep(for:tolerance:)` 코얼레싱, ② 저전력 모드 정적화(`FloatingPetController.shouldAnimate(lowPower:)`
  — `NSProcessInfoPowerStateDidChange` 관찰 후 콘텐츠 재구성), ③ 숨김/슬립 시 `contentView=nil` 로 프레임 루프 정지
  (팝오버 `popoverDidClose` 패턴). 회귀 가드: `FloatingPetEnergyTests`(fps 하한 clamp·`frameFloor>0`·팝오버 불변·
  low-power 정적화 순수 판정 — SwiftUI `.task` 타이밍 자체는 호스트 없이 xctest 불가라 순수 경로만 잠금). occlusion 게이팅은
  all-spaces/`.floating` 펫이 실제로 거의 안 가려져 메뉴바와 동일 수확체감으로 미도입. (#102 리뷰 지적 반영, 2026-07-22.)

## 알림

- **휘발성 필드를 dedup/identity 키에 쓰지 마라.** 매 fetch/refresh 마다 값이 변하는 필드(예: rolling
  한도 창의 `resets_at`)를 알림 중복방지 키에 넣으면 매번 새 키가 되어 dedup 이 무력화된다 — 주간 한도
  알림이 80·81·84…갱신마다 반복되던 회귀. 임계값 알림은 **엣지 트리거**(직전 tier 보다 높아진 순간만
  발화, 경고선 아래로 내려가면 재무장)로 구현하고, 판정은 부수효과(실 알림 전송·`.app` 번들 가드)와
  분리한 **순수 함수**(`UsageStore.evaluateLimitAlerts`)로 테스트한다 — 번들 가드 때문에 실 발화 경로는
  xctest 에서 조기 return 되어 커버 불가였던 게 무테스트의 원인.

## 상태 파일 이전·병합

- **상태 파일을 옮기거나 합칠 땐 "진행"과 "이 기기 장부"를 먼저 분류하라.** 같은 파일에 살아도 성격이
  다르다 — `usedSinceInstall`·`dex`·`inventory`·`candyGrantTier` 는 어느 기기에서든 참인 **진행**이고,
  `claimedTodayTokens`·`lastDate`·`installBaselineSet` 은 *그 기기가* 어디까지 적립했나를 적은 **로컬
  장부**다. 장부를 그대로 들여오면 옛 기기의 오늘 최고치가 문턱이 되어 `update` 의
  `todayTokens > claimedTodayTokens` 게이트가 이전 당일 내내 거짓 → 새 기기 사용분이 조용히 안 잡힌다
  (자정에 저절로 낫기 때문에 버그로 안 보인다). 반대로 계정 전역 근거로 만들어진 원장(`candyGrantTier`
  — 한도 창 key)은 **버리면** 같은 창에서 재지급된다. 이전·병합 경로를 만들 땐 필드를 전수로 이 두 부류에
  넣어 보고, 로컬 장부만 새 기기 기준으로 다시 잡는다(`SaveTransfer.rebasedForThisDevice`). 회귀 가드:
  `testTransferDayTokensStillCountAfterRebase` — 재정렬 없는 대조군을 같이 돌려 결함 조건이 살아 있는지도
  함께 확인한다(테스트가 트리거 브랜치를 실제로 밟는지 보증).

- **자기 자신과 비교하는 하위호환 테스트는 아무것도 지키지 않는다.** 무결성 canonical 은 "새 필드가
  기본값이면 아무것도 붙이지 않는다"는 규칙으로 구버전 세이브의 서명을 살려 둔다(무조건 붙이면 그 필드가
  없던 정상 세이브가 전부 조작 판정 → 진행 초기화). 그런데 그 규칙을 지키던 테스트가 모두
  (`testEmptyHistoriesKeepLegacyIntegrityCanonicalForm`·미션, 그리고 별도 브랜치의 트레이너 레벨)
  `hash(기본값) == hash(기본값)` 형태였다 — **조건부 append 를 무조건 append 로 바꿔도 비교 대상 양쪽이
  똑같이 바뀌어 그대로 통과한다.** 결함을 주입해 보기 전까지 전부 초록이었다. 고정된 기준 없이 자기
  자신과 대조하면 통과해도 지켜지는 게 없다. 지금은 해시가 아니라 입력 원문(`SaveTransfer.canonicalString`)을
  노출해 ① 필드별로 조각 부재를 직접 보고(`contains("|ms")`) ② 기본값 canonical 전체를 **동결 문자열**과
  대조한다(`testDefaultStateCanonicalFormIsFrozen`) — 후자는 목록을 손보지 않아도 새로 들어온 무조건
  append 를 자동으로 잡는다. 새 가드를 넣었으면 결함을 한 번 주입해 실패를 확인한다. (미션 필드 추가, 2026-08-18.)

## 클라이언트 신고값을 상한 아닌 권위로 쓰는 부류

- **재화가 오가는 새 경로를 만들 땐 "상한은 누가 정하고 실제 차감은 누가 하는가"를 분리해 배치하라.**
  관전자 베팅(포켓슬론)은 참가 시 클라이언트가 신고한 별조각 잔액(`LobbyParticipant.reportedStarPieces`)을
  **호스트의 상한 검사에만** 쓰고, 실제 차감은 각 클라이언트가 자기 세이브에서 한다
  (`CompanionStore.escrowStarPieces`). 조작된 클라이언트가 신고값을 부풀려도 남의 지갑엔 영향이 없고,
  자기 지갑에 돈이 없으면 차감이 실패한다. 정산도 같은 원칙이다 — 호스트가 원장과 우승자를 보내고
  각 클라이언트가 `PokeathlonPool.payouts` 를 **재계산해** 자기 몫만 지급하며, 내가 본 내 베팅과 호스트
  원장이 다르면 지급을 거부한다(`agreesWithSeenBet`). 새 재화 경로를 넣을 때 이 두 지점(상한 vs 권위,
  호스트 계산 vs 클라 재계산)이 같은 방식으로 놓였는지 확인한다.
  **남은 구멍(의도된 한계):** 조작된 클라이언트는 자기 차감을 건너뛴 채 호스트 원장에 판돈을 남길 수
  있다 → 승자들이 아무도 내지 않은 돈을 나눠 받아 별조각이 생성된다. 정직한 경로(로비에서 별조각을 쓴 뒤
  베팅)는 `placeBet` 의 현재-잔액 선검사로 막았고, 조작 클라이언트까지 막으려면 베팅마다 "차감 완료"
  확인 메시지를 왕복해야 한다(이슈 #4 후속). 관련 테스트: `PokeathlonPoolTests`, `StarPieceEscrowTests`.

## 검증이 변경보다 늦게 오는 부류 (throw 는 롤백이 아니다)

- **`mutating` 메서드가 throw 해도 그때까지의 변경은 호출자에게 남는다.** Swift 는 되돌려주지 않는다.
  `MultiplayerBattle.resolveRound` 는 사전 검증 루프에서 무브셋 **인덱스만** 보고 PP 는 해상 루프
  안에서 봤다 — 남지 않은 기술을 지목한 액션이 섞이면, 그보다 순서가 앞선 공격은 이미 HP·PP 에
  적용된 뒤에 throw 가 났다. 라운드가 **반쯤 적용된** 상태로 버려지고, 호스트
  (`MultiplayerRoomCenter.finishRoundIfReady`)의 catch 는 `scheduleTurnTimeout()` 을 부르지 않아
  (그건 성공 경로에만 있다) 방의 진행이 멈춘다. **상태를 바꾸는 루프에 들어가기 전에 검증을 끝낸다.**
- **"사전 검증 루프가 있다"는 "다 검증한다"가 아니다.** 위 결함은 검증 루프가 *존재하는데도* 생겼다.
  루프가 보는 항목과 해상이 요구하는 항목이 달랐다. 검증 루프를 늘릴 때는 해상 루프가 인덱싱·차감하는
  값을 하나씩 대조한다. 지금은 `BattleSide.canUse(moveAt:)` 한 곳이 인덱스와 PP 를 같이 본다.
- **와이어로 들어온 배열은 쌍을 이루는 배열과 길이가 맞는다는 보장이 없다.** 상대가 보내는 `pp` 는
  `moves` 와 별개 필드다 — 짧은 배열이 오면 예전 코드는 거절이 아니라 `pp[moveIndex]` 인덱스 범위
  초과였다. 파생 배열을 신뢰 경계 밖에서 받으면 **두 배열의 인덱스를 같이** 검사한다
  (`AdventureTests.testResolveRoundRejectsFighterWhosePPArrayIsTooShort`).
- **회귀 테스트는 부분 적용을 관측해야 한다.** "throw 했다"만 보면 이 부류를 못 잡는다.
  `testResolveRoundRejectsSpentMoveBeforeAnyDamage` 는 throw 뒤의 HP·PP·이벤트가 그대로인지 본다.
  (규칙 위반 액션을 **느린 쪽**에 둬야 앞선 공격이 먼저 적용된다 — 순서가 트리거의 일부다.)
  (배틀 Gen 2 Phase 0, 2026-08-19.)

## 테스트가 시스템 RNG 를 밟고 있는 부류

- **엔진에 결정적 RNG 가 있어도 한 군데라도 `randomElement()`/`Bool.random()` 이 남아 있으면
  그 경로는 재현되지 않는다.** 연습 배틀의 CPU 기술 선택이 그랬다. 로컬 전용이라 desync 는 없지만,
  **seed 를 고정한 회귀 테스트를 쓸 수 없다** — 상태이상·랭크업처럼 확률 분기가 늘어나는 기전은
  그 테스트 없이는 검증할 방법이 없다. 결정적 엔진을 만들었으면 그 위의 *선택* 도 같은 `rng` 에서 뽑는다.
- **그 사이 기존 테스트는 조용히 불안정해진다.** `testSwitchingIntoAFatalHitEndsTheBattle` 의 상대는
  `moves: nil` 이라 `MoveSpec.fallbackSet` 4개를 받는데(픽스처 주석은 "기술 하나만 준다"고 적혀
  있었다 — 주석이 틀렸다), 그중 몸통박치기를 뽑고 데미지 난수가 하한(0.85)이면 데미지 75 로
  대상의 76 HP 를 넘기지 못해 "맞고 쓰러진다" 단정이 깨진다. 실측: base 89.16 × 0.85 = 75.
  **초록이 곧 결정적이라는 뜻이 아니다.** 픽스처가 무작위 선택 위에 서 있으면 통과는 그날의 운이다.
- **결정성 단정은 한 판 비교로 충분하지 않다.** 후보가 N개면 우연히 같아질 확률이 1/N 이다.
  같은 seed 로 여러 판을 돌려 결과 집합이 1개인지 본다(`testPracticeBattleIsDeterministicForASeed`:
  4지선다 × 6턴 × 10판). (배틀 Gen 2 Phase 0, 2026-08-19.)

## 한 지갑에 지급하는 경로가 여럿일 때

- **정산이 반환하는 보상 객체는 그 정산이 늘린 지갑을 전부 설명해야 한다.** 트레이너 레벨과
  일간·주간 미션은 각각 다른 브랜치에서 만들어졌는데, 둘 다 `claimAdventure()` 안에서 같은
  `state.starPieces` 에 지급한다. 합치고 나니 미션 몫이 보상 객체에 실리지 않아, 화면이 알려준 값보다
  잔액이 더 늘었다. 지급 경로를 더할 땐 `accrueTrainerPoints` 처럼 **지급액을 반환하고** 호출부가 보상
  객체(`AdventureReward.trainerBonus`·`missionBonus`)에 실어야 한다.
- **완전설명 불변식은 부가 지급이 실제로 일어나는 경로에서 검사해야 의미가 있다.** 그 불변식을 지키던
  `testFocusSessionCompletionClaimsTheAdventure` 는 25분 세션이라 미션 목표(60분·2회)를 하나도 넘기지
  않는다 — 미션이 지갑에 몰래 더해도 초록이었다. 결함을 주입해 보니 이 테스트만 통과했다. 지금은 목표를
  넘기는 90분으로 그 분기를 밟는 `testRewardExplainsWalletEvenWhenAMissionCompletes` 가 따로 있고,
  `missionBonus > 0` 을 전제로 먼저 확인해 조건이 살아 있는지도 함께 보증한다.
- **두 시스템이 같은 지갑에 지급하면 "지갑 증가분 == 내 보상" 형태의 테스트는 전부 깨진다.** 깨진 값을
  더해서 맞추지 말고, 각자 자기 몫을 어떻게 떼어 볼지 정한다 — 보상 객체가 상대 몫을 알려주면 그걸 빼고
  (`reward.missionBonus`), 알려줄 객체가 없는 경로(졸업)는 상대를 무력화해 시드한다(트레이너 포인트를
  상한으로 두면 더 오를 곳이 없어 0 을 지급한다). (트레이너 레벨 × 미션 리베이스, 2026-08-19.)

## 스크롤 컨테이너가 있다고 스크롤되는 건 아닌 부류

- **팝오버 본체가 이미 `ScrollView` 다 — 탭 안에 또 세로 `ScrollView` 를 두면 안쪽은 스크롤되지 않고,
  격자에 들어가는 만큼만 보인 뒤 나머지는 도달 불가가 된다.** 소유 포켓몬 목록이 그랬다. 코드에는
  분명히 `ScrollView` 가 있어 리뷰에서 "넘치면 스크롤된다" 로 읽혔지만, 실제로는 21마리째부터 볼
  방법이 없었다. 도감(`DexGridView`)은 같은 이유로 진작 스크롤을 버리고 페이지식 고정 격자로 갔는데
  (그 주석에 "팝오버 재오픈 시 fitting size 가 줄어드는 기존 결함" 으로 남아 있다), 로스터만 남아
  있었다. 팝오버 탭 안에서 목록이 길어질 수 있으면 **스크롤이 아니라 페이지식**으로 만든다.
- **높이를 키우는 것은 이 부류의 처방이 아니다.** 격자 상한을 260 에서 520 으로 늘렸을 때 보이는
  마릿수가 9 에서 20 으로 늘어 고쳐진 것처럼 보였지만, 잘리는 지점만 옮겼을 뿐 도달 불가는 그대로였다.
  "몇 개까지 보이나" 가 아니라 **"마지막 하나에 도달할 수 있나"** 로 검증한다
  (`testEveryOwnedPokemonLandsOnSomePage`).
- **UI 결함은 컴파일과 단위 테스트를 통과한다.** 이 결함은 CI 초록으로 v2.7.7 에 실려 나갔다. 레이아웃을
  바꾸는 변경은 실행 화면을 한 번 봐야 한다 — 볼 수 없는 환경이면 그 사실을 PR 에 적고 머지 전에 눈을
  빌린다. (소유 포켓몬 페이지식 전환, 2026-08-19.)
- **남은 부류 후보(미검증):** 같은 중첩 구조가 `ShopView`(`.frame(height: 520)` + 가변 `shopEntries`),
  `BagView`, `BattleView` 에도 있다. 실제로 잘리는지는 실행 화면 확인이 필요하다.
## 면제 조건이 전제한 관문이 실제로는 비어 있는 부류

- **"저쪽에 이미 관문이 있으니 여기선 안 봐도 된다" 는 면제를 달 땐, 그 관문이 모든 경로에 있는지
  세어라.** 졸업 레벨 30 은 `a.totalForms > 1` 이면 면제였다 — 근거는 "진화를 거친 종은 그 마지막
  진화 요구 레벨이 이미 관문" 이라는 것이었고, 자동 진화 경로(`guard a.level >= requiredLevel`)만
  보면 맞는 말이다. 그런데 진화 경로가 하나 더 있었다: `useEvolutionItem` 은 레벨을 보지 않는다.
  500 짜리 돌 하나로 레벨 1 개체를 최종형으로 만들면 면제가 그대로 적용돼, 20,000 짜리 알과
  도감·트레이너 포인트·주간 졸업 미션을 한 번에 받아냈다. 개체는 박스에 버리면 그만이라 반복도 됐다.
- **면제는 "상태" 가 아니라 "지나온 경로" 로 판정해야 할 때가 있다.** `totalForms > 1` 은 결과만
  본다 — 어떻게 최종형이 됐는지는 말해주지 않는다. `MonState` 에 진화 방식이 남지 않아
  `pathIDs` 의 전이를 트리에서 되짚어 `use-item`·`trade` 가 섞였는지 본다(`grewIntoFinalByItem`).
  상태 하나로 두 경로를 구분하려 들면 이 부류가 또 나온다.
- **과잉 차단 대조군을 같은 커밋에 둔다.** "전부 레벨 30 요구" 로 고쳐도 악용 테스트 두 개는 초록이다.
  레벨 진화 개체가 면제를 유지하는지 보는 `testLevelEvolvedCompanionKeepsItsExemption` 이 있어야
  처방이 정확한 자리에 놓였는지 알 수 있다. (아이템 진화 졸업 게이트, 2026-08-19.)

## 컴파일러 warning · CI 진단

- **게이트가 없는 warning 은 쌓이고, 쌓인 warning 은 새 warning 을 가린다.** CI 가 warning 을
  통과시키는 동안 자체 코드 warning 4건이 조용히 쌓였다(컴파일 잡마다 반복돼 로그에는 127줄로 보였다).
  그 상태에서는 새로 생긴 warning 을 알아볼 방법이 없었다. 지금은 `test-gate.sh` 가 `swift test` 출력에서
  `(Sources|Tests)/PokeTokenBar…\.swift:줄:열: warning:` 을 뽑아 하나라도 있으면 실패한다.
  경로로 거르므로 의존성(`.build/checkouts`)의 warning 은 우리 빌드를 깨지 않는다.
  **한계는 명시해 둔다** — 재컴파일이 없는 warm build 는 컴파일러가 warning 을 다시 찍지 않아 로컬에서
  놓칠 수 있다. 신뢰 기준은 매번 cold build 인 CI 다. 로컬에서 볼 때는 `swift package clean` 뒤에 돌린다.
- **정규식 게이트는 합성 픽스처가 아니라 실제 CI 로그로 검증한다.** 이 정규식은 저장해 둔 실패 CI 로그
  (Swift 6.1.2, 절대경로, `-v` 가짜 warning 포함)에 그대로 걸어봤다 — 127줄에서 진짜 4건만 남고 가짜는
  하나도 걸리지 않았다. 로컬 Swift 6.2.4 는 진단 끝에 `[#DeprecatedDeclaration]` 같은 그룹 태그를
  덧붙이므로 정규식 끝은 열어 둬야 한다(`.*`) — 로컬 포맷만 보고 잠그면 CI 에서 안 잡힌다.
- **`swift build -v` 는 CI 에서 쓰지 않는다.** `-v` 를 켜면 SwiftPM 이 매니페스트 컴파일의 stderr 를
  `warning: '<패키지>': <swift-frontend 커맨드라인>` 으로 재출력한다 — 코드 문제가 아닌 가짜 warning 3건이
  생기고 Build 스텝 로그가 404KB 로 부풀었다(53줄이 저마다 컴파일러 커맨드라인 전문이다).
  평범한 `swift build` 가 실제 진단은 이미 다 찍는다.
- **같은 API 의 오버로드마다 deprecation 이 다르다 — 한 파일에서 warning 이 하나만 나면 그게 신호다.**
  `BattleNet.localIPv4` 의 두 `String(cString:)` 중 배열(`[CChar]`) 오버로드만 Swift 6 에서 deprecated 이다.
  포인터 오버로드는 유효하다. 그래서 `ifa_name` 을 읽는 포인터 호출은 조용하고 바로 아래 배열 호출만
  warning 이 났다. 고칠 때도 컴파일러가 권하는 `String(decoding:as:)`(널 종단을 직접 잘라야 해서 3줄)보다
  살아 있는 오버로드로 넘기는 쪽이 짧았다(`withUnsafeBufferPointer`).
- **테스트의 미사용 warning 은 대개 리팩터링 잔여물이다 — 한 줄 지우고 끝낼 일이 아니다.** 이번 3건 전부
  그랬다 — `CompanionTests` 의 `grad` 는 졸업이 사용자 액션으로 바뀐 뒤(#19) 쓸 데가 없어졌고,
  `BattleTests` 의 `var s` 에 달린 "keypath 대상 타입 고정용" 주석은 `NatureEffect.multiplier` 가
  `WritableKeyPath<BattleStats, Int>` 로 root 를 이미 고정하고 있어 오래전에 사실이 아니게 됐다.
  지우기 전에 왜 남았는지 한 번 보면 주석이 거짓말하는 자리가 같이 나온다.
  (자체 코드 warning 게이트 도입, 2026-08-19.)

## 아래쪽에 같은 가드가 또 있어서, 위쪽 가드를 지워도 아무 테스트가 안 깨지는 부류

- **결함을 주입했는데 전부 초록이면, 가드가 튼튼한 게 아니라 중복이라는 뜻일 수 있다.**
  `applySecondaryEffect` 는 상태를 걸 수 있는지 본 뒤에 확률을 굴린다. 그 앞 검사를 통째로 지워도
  테스트가 하나도 안 깨졌다 — `inflict` 가 어차피 한 번 더 거르기 때문에 **결과값이 안 바뀌기**
  때문이다. 바뀌는 것은 rng 소비량이다. 못 걸 상대에게 판정을 한 번 굴리면 그 뒤의 모든 난수가
  한 칸씩 밀린다.
- **관측 대상이 값이 아니라 rng 스트림이면, 스트림을 직접 본다.** 이 저장소에서 소비 순서는
  프로토콜이다(`BattleModel.resolveAttack` 주석). 그래서 "면역 상대를 때린 뒤의 rng 상태" 와
  "상태를 안 거는 기술로 때린 뒤의 rng 상태" 를 비교하고, 걸 수 있는 상대로 대조군을 둔다
  (`testSecondaryEffectSpendsNoRollOnATargetThatCannotBeAfflicted`).
- **중복 가드를 지우는 쪽이 답인지 먼저 따진다.** 여기서는 앞 검사를 남겼다 — 굴리고 버리는 쪽은
  나중에 자격 판정이 비대칭이 되는 순간 desync 가 되고, 그때는 원인을 찾기 훨씬 어렵다.
- **결함 주입은 "안 깨졌다" 로 끝내지 않는다.** 안 깨진 이유를 한 번 답해야 한다. 답이
  "결과가 같아서" 면 그 가드가 지키는 진짜 관측 대상을 아직 테스트하지 않은 것이다.
  (상태이상 2차효과, 2026-08-20.)

## 같은 기전을 한 모드에서만 고치는 부류

- **1v1 을 고치고 멀티를 안 고쳐도 1v1 테스트는 전부 초록이다.** 마비 스피드 25% 를
  `BattleSide.effectiveSpeed` 로 넣고 1v1 순서 계산에 배선했다. 멀티의 정렬 비교자
  (`MultiplayerBattle.resolveRound`)를 `stats.spe` 로 되돌리는 결함을 주입했더니 **아무 테스트도
  걸리지 않았다.** 같은 화상이 방에서는 아무 일도 하지 않는 것도 마찬가지였다.
- **모드가 셋이면 기전 회귀 테스트도 모드별로 있어야 한다.** 배틀 상태를 `BattleSide` 하나로 모은 게
  Phase 0 이었지만, 상태를 *공유한다*는 것과 세 모드가 그 값을 *읽는다*는 것은 다른 문제다.
  공유 접근자만 테스트하면 호출부가 옛 필드를 그대로 읽고 있어도 통과한다.
- **확률 tie-break 에 기대는 테스트는 결함을 놓친다.** 첫 판은 스피드 동률 두 명에 마비를 걸고
  "20개 seed 에서 늘 마비 안 된 쪽이 선공" 으로 썼는데, 결함 주입에도 통과했다. 마비된 쪽에 **확실히
  더 빠른 스피드**를 줘서 순서가 결정적으로 뒤집히게 고친 뒤에야 걸렸다
  (`testParalysisSlowsTheAttackerInMultiplayerToo`).
- **한계도 적어 둔다** — 인접한 두 줄(`leftSpeed`/`rightSpeed`) 중 **하나만** 되돌리는 결함은 여전히
  빠져나간다. 원소가 둘인 정렬에서 Swift 는 비교자를 한 번만 부르고, 그 한 번이 멀쩡한 쪽을 읽을 수
  있기 때문이다. 실제로 일어날 법한 결함(둘 다 안 고침)은 잡힌다.
  (상태이상 마비·잔뎀의 멀티 배선, 2026-08-20.)

## 라인 커버리지 99% 인데 새 분기가 한 번도 안 돈 부류 (재확인)

- **`BattleModel.swift` 는 라인 99.25% 였고, 그 안에서 새 분기 넷이 `^0` 이었다.**
  `Status.init(ailment:)` 의 paralysis·freeze·confusion 갈래(JSON 테스트가 burn 만 썼다)와
  혼란 자멸로 쓰러지는 갈래(자멸은 관측했지만 HP 가 넉넉해 한 번도 안 죽었다)다.
  게이트 숫자로는 어느 쪽도 드러나지 않는다 — 이미 이 문서에 있는 규칙이지만, 커버리지가 높을수록
  오히려 확인을 건너뛰기 쉬우니 다시 적어 둔다.
- **처방은 매번 같다** — 새 조건 분기를 넣었으면
  `xcrun llvm-cov show <bin> -instr-profile=<profdata> <file> --show-regions | grep '\^0'` 를 직접 본다.
  표 형태 매핑(`init?(ailment:)` 같은)은 갈래 하나가 아니라 **전 갈래를 도는 테스트**로 덮는다.
  (상태이상, 2026-08-20.)
