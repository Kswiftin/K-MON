---
summary: "포켓몬 대화가 실행할 수 있는 일의 전부와, 그 목록이 닫혀 있음을 무엇이 보장하는가 — 6겹 경계와 각 겹을 지키는 테스트."
read_when:
  - 대화에 새 도구를 더하거나 기존 도구를 빼려 할 때
  - `[[tool:...]]` 마커 문법·인자 클램프·승인 구분을 손댈 때
  - "대화가 X 를 할 수 있게 해 달라" 는 요청을 받았을 때 (대개 답은 "그 겹에 넣을 수 없다" 다)
  - 실행기에 새 의존성을 붙이거나, 도구가 어느 개체에 작용하는지를 바꿀 때
  - 대화 CLI 를 띄우는 자리(작업 디렉터리·환경변수·설정 소스)를 손댈 때
---

# 대화 도구 샌드박스

**모델은 도구를 갖지 않는다.** 이 문장이 설계 전부다.

대화 CLI(`claude`·`codex`)는 도구를 전부 끈 계약으로 돈다. 모델이 할 수 있는 건 답변 **텍스트**에
`[[tool:pokedoro.status]]` 같은 마커를 적는 것뿐이고, 그 마커를 읽어 실행하는 주체는 앱이다.

그래서 코딩·검색·컴퓨터 제어는 "막힌 기능" 이 아니라 **없는 기능**이다. 목록 밖 이름은 판정에서
거부되는 게 아니라 애초에 호출로 파싱되지 않는다 — 거부 목록을 늘려 가며 방어하지 않는다.

## 실행할 수 있는 일의 전부

| 도구 | 인자 | 승인 | 하는 일 |
|---|---|---|---|
| `pokedex.lookup` | 도감 번호 `1..1025` | 불필요 | PokéAPI 종 정보(분류·서식지·특성·도감 설명) |
| `pokedoro.status` | 없음 | 불필요 | 타이머 + **모험 루프**(none/running/ready·구역·진행률) + 알 재고 |
| `bag.list` | 없음 | 불필요 | 소유 아이템과 개수 |
| `roster.list` | 없음 | 불필요 | 팀 목록 — 인덱스·이름·레벨·이로치·활성 여부 |
| `dex.progress` | 없음 | 불필요 | 도감 진행도 — 종·타입·이로치 각 축의 `현재/다음 목표` |
| `challenge.status` | 없음 | 불필요 | 오늘 던전(클리어 여부·체력 예산)·배지·미션 |
| `memory.record` | **없음**(본문은 앱이 채운다) | 불필요 — 아래 참조 | 방금 한 답변을 기억 앨범에 남긴다 |
| `pokedoro.start` | `25` \| `50` \| `90` | **필요** | 집중 세션 시작(모험 출발 + 타이머) |
| `pokedoro.stop` | 없음 | **필요** | 집중 세션 종료 — **진행 중인** 모험은 보상 없이 취소된다(끝난 모험은 먼저 정산된다) |
| `adventure.claim` | 없음 | **필요** | 끝난 모험을 정산(별의조각·경험치·알) |
| `item.use` | `ItemKind` case 이름 | **필요** | 아이템 1개를 그 종류의 진짜 사용 경로로 |
| `evolution.accept` | 없음 | **필요** | 대기 중인 진화를 수락 |
| `companion.switch` | `roster.list` 가 찍은 인덱스 | **필요** | 다른 동료를 활성으로 |

숫자를 말하지 않는 자리가 둘이다. 능력치는 활성 개체의 대화에서만 싣고, `challenge.status` 의
`budget` 은 주인이 나와 있는 개체이고 타입까지 받았을 때만 숫자다(아니면 `unknown`) — 던전 예산은
동행 타입으로 상성 보정을 받으므로 남의 타입이나 미로드 상태로 계산하면 **그럴듯하게 틀린 숫자**가
된다. 빈 값은 모델이 말을 아끼게 하지만, 틀린 숫자는 안 들킨다.

능력치 여섯 칸은 **도구가 아니다.** 프로필(시스템 프롬프트)이 타입·기술·다음 진화를 싣는 자리에
같이 실린다 — 도구로 만들면 왕복 한 번과 광고 줄 하나를 더 쓰면서 같은 값을 준다. 개체의 값이라
`chatProfile` 은 **활성 개체의 대화에서만** 채운다(`currentStats` 가 활성 개체의 레벨·성격으로
계산하므로, 종만 맞춰 싣는 타입과 달리 남의 프로필에 실으면 그럴듯하게 틀린 숫자가 된다).

열이 전부다. 목록은 `PokemonChatTool` 한 곳에 있고 프롬프트가 광고하는 이름도 여기서 나온다 —
두 벌이면 한쪽만 바뀌어 모델이 없는 도구를 부르거나 있는 도구를 영영 모른다.

### 인자는 전부 닫혀 있다

목록을 넓혀도 "임의 문자열을 그대로 받는 인자" 규칙은 그대로다. 새 인자 셋이 각각 닫힌 방법:

- `item.use` — `ItemKind(rawValue:)` 로만 만들어진다. 목록 밖 이름은 거부되는 게 아니라 **호출이
  되지 않는다.** 그래서 `bag.list` 는 현지화된 이름이 아니라 **rawValue** 를 찍는다 — 모델이
  되돌려 줄 수 있는 값이어야 한다(`불꽃의돌` 을 주면 파싱에서 떨어지고 사용자에겐 침묵으로 보인다).
- `companion.switch` — `roster.list` 가 찍은 정수 인덱스. UUID 를 문자열로 넘기면 그게 곧 임의
  문자열 인자다. 범위 판정은 파서가 아니라 **로스터를 아는 실행기**가 한다 — 파서가 그때그때의
  로스터 크기를 알면 파싱이 앱 상태에 의존하게 된다.
- `memory.record` — 인자가 **없다.** 마커는 `[[tool:memory.record]]` 뿐이고, 본문은 가드를 통과한
  답변으로 `PokemonChatStore.send` 가 채운다. 모델이 기억 문구를 직접 쓰게 하면 그건 임의 문자열
  인자이고, 그 문자열이 다음 요청의 컨텍스트로 되돌아온다(자기 오염). 가드가 답변을 갈아치웠다면
  기록도 남기지 않는다.

### 대상을 인자로 받지 않는 도구는 **그 개체의 대화에서만** 돈다

대화 창은 활성 개체뿐 아니라 로스터에서 **박스 개체로도 열린다**(`PokemonRosterView`). 실행기는
`CompanionStore` 를 통째로 들고 있어서, 방어가 없으면 모든 도구가 "지금 나와 있는 개체" 에 작용한다 —
박스 피카츄 창에서 승인했는데 활성 파이리가 사탕을 먹는다(2026-08-27 결함, `defect-log.md`).

그래서 실행은 **대화의 주인**(`run(_:owner:)`)을 반드시 받는다. 프로토콜에 기본값을 두지 않는다 —
안 넘기면 컴파일이 안 되는 편이, 부르는 자리가 활성 개체를 암묵 대상으로 삼는 것보다 낫다.

분류는 `PokemonChatToolCall.actsOnTheActiveCompanion` 한 곳이고 가드도 한 곳에서 읽는다. case 마다
두면 다음에 더하는 도구가 조용히 빠진다.

- **주인만** — `pokedoro.start`·`pokedoro.stop`·`adventure.claim`·`item.use`·`evolution.accept`
- **누구의 대화에서도** — 읽기 도구 전부, 그리고 `companion.switch`(인자로 대상을 지목하므로 남의
  대화에서도 뜻이 분명하다), `memory.record`(활성 개체가 아니라 **주인** 앨범에 적는다)

예외는 취향이 아니라 성질이다. 뭉뚱그려 막으면 박스 개체가 "나를 데리고 나가 줘" 라고 말할 수 없다.

### 성공할 수 없는 질문은 카드로 띄우지 않는다

승인 게이트는 "사용자가 눌러야 실행된다" 이지, "무엇이든 물어봐도 된다" 가 아니다. 박스 개체
대화에서 집중 시작을 물으면 실행기가 거절할 것이 **처음부터 정해져 있다** — 카드를 띄우면 사용자는
탭 한 번을 버리고 실패 문구를 받는다.

그래서 `PokemonChatStore.send` 는 카드를 만들기 전에 `canRun` 으로 묻고, 될 수 없으면 카드를
띄우지 않고 거절 사유를 **모델에게** 돌려준다(모델이 그 턴에 사람 말로 설명한다).

판정은 `PokemonChatToolbox.ownerRefusal` 한 곳이고 `canRun` 과 `run` 이 함께 읽는다 — 두 벌이면
"카드를 안 띄우는 조건" 과 "실행을 막는 조건" 이 갈라져도 아무 테스트가 안 깨진다.

`canRun` 이 보는 건 **구조적 불가능**뿐이다(주인 게이트). "가방에 사탕이 없다" 처럼 상태에 따른
실패를 미리 보면 실행기 전체가 두 벌이 되고, 그건 사용자가 봐야 하는 정직한 실패다.

### 칩은 실행하지 않는다 — 문장을 채울 뿐이다

대화 화면의 칩 줄은 지금 성공할 수 있는 상태 변경을 먼저 보여 준다(`PokemonChatAction` ·
`availableActions(owner:)`). 그래도 **실행 경로는 여전히 마커 하나다**: 칩을 누르면 입력칸에
사람 말이 채워지고, 사용자가 전송하고, 모델이 마커를 적어야 승인 카드가 뜬다.

칩이 `PokemonChatToolCall` 을 직접 만들면 승인 게이트의 **형제 경로**가 생긴다 — 겹 2·3
(화이트리스트·인자 클램프)을 지나지 않는 호출이 카드에 도달하고, "대화가 도구를 돌렸다" 는 지표가
대화 없이도 올라간다. 그래서 칩 문구에 마커를 넣는 것도 금지다(테스트가 고정한다).

제안 판정은 **실행 가능성의 부분집합**이다. `availableActions` 는 주인 게이트를 `canRun` 에서
그대로 빌려 쓰고 상태 준비 여부(`isReady`)만 더한다. 반대로 넓히면 — 실행기가 받아 주는 모든
구간을 제안하면 — 화면이 버튼을 안 그리는 구간까지 대화만 넓어져 `already in rest` 부류가
되돌아온다. 덜 제안하는 건 조용하고, 더 제안하는 건 거짓 약속이다.

### 실패는 사유를 싣는다

거절을 한 줄로 뭉개면 모델은 왜 안 되는지 모른 채 같은 호출을 반복하고, 사용자에게는 아무 일도 안
난 것으로 보인다(분을 버리지 않고 접는 것과 같은 이유). 지금 갈라 두는 사유:

- `tool refused: no active companion` / `... not the active companion`
- `pokedoro start refused: already in focus` / `... already in rest` — 화면은 타이머가 도는 동안
  시작 피커를 **아예 안 그린다**. 휴식 단계도 `isRunning` 이고 그 구간엔 모험이 이미 정산돼 없으므로,
  모험만 보는 게이트는 휴식을 조용히 덮어썼다 — 화면이 못 하는 일을 대화만 할 수 있었다.
- `pokedoro start refused: adventure in progress` / `... adventure reward unclaimed`
- `pokedoro stop refused: nothing running` — 아무것도 안 도는데 "집중을 끝냈어" 는 거짓이다
  (`FocusTimer` 는 저장되지 않아 앱을 다시 연 직후가 항상 그 상태다).
- `adventure none ready` · `evolution none pending` · `item <kind> unavailable`
- `evolution refused: conditions no longer met` · `memory not recorded`

성공도 **위임한 쪽이 받아들였을 때만**이다. 실행기 자신의 가드만 확인하면(빈 본문인가 / 대기 중인
진화가 있는가) 앨범이 180자 초과로 버린 기억이나 시간대 조건이 무너진 진화가 성공으로 나가고,
모델은 그걸 사실로 말한다. 거절을 값으로 올리거나(`PokemonMemoryAlbum.record` 는 `Bool` 을
돌려준다) 관측 가능한 결과로 판정한다(`acceptEvolution` 전후의 `activeStageIndex`).

### 종료는 **진행 중인** 모험만 버린다

`cancelFocusAdventure` 는 완료 여부를 보지 않는다. `FocusTimer` 는 저장되지 않으므로 앱을 닫았다
열면 타이머는 idle 이고 모험만 남아 있고(정산 대기 구간), 화면은 그 구간에 "보상 받기" 만 그리고
취소 버튼을 아예 그리지 않는다. 대화의 `pokedoro.stop` 은 그 구간에서도 눌릴 수 있으므로,
`stopFocusSession` 이 **먼저 정산한 뒤** 취소한다(`startFocusAdventure` 와 같은 순서다 — 정산
진입점은 `claimAdventure` 한 곳뿐이다). 승인 카드가 "진행 중인 모험은 보상 없이 취소돼" 라고
말하려면 그 문장이 어느 구간에서도 참이어야 한다.

### `memory.record` 만 승인이 없다

"상태를 바꾸면 무조건 승인" 규칙의 유일한 예외다. 근거는 둘이다.

1. **저장되는 문장을 모델이 정하지 않는다.** 남는 건 사용자가 화면에서 방금 읽은 답변 그대로다.
2. 앨범에 전체 삭제가 있고, 승인을 붙이면 대화가 매번 카드로 끊긴다.

이 예외는 여기까지다. 인자를 받는 기억 도구를 만들거나, 지우는 도구를 더하려면 승인이 필요하다.

## 6겹 경계

| 겹 | 무엇을 막나 | 어디 | 지키는 테스트 |
|---|---|---|---|
| 0. 실행 디렉터리 | 자식의 cwd 는 **앱 소유 빈 디렉터리**다 — CLI 의 프로젝트 루트가 사용자 파일에 닿지 않는다 | `PokemonChatWorkspace` | `testTheChatCLIRunsInTheAppOwnedDirectoryNotWhateverCWDTheAppInherited`, `testAnUnusableStateDirectoryStillYieldsARunnableWorkingDirectory` |
| 1. 제공자 인자 | CLI 내장 도구·MCP·사용자 설정 파일 전부 차단 | `PokemonChatProviderSafety.arguments` | `testClaudeProviderDisablesBuiltInToolsMCPAndUserSettings`, `testCodexProviderIgnoresConfigurationAndUsesReadOnlySandbox` |
| 2. 화이트리스트 | 목록 밖 이름은 호출로 파싱되지 않는다 | `PokemonChatToolParser` | `testOnlyTheDeclaredToolsParseAsCalls` |
| 3. 인자 클램프 | 분은 세 값으로 접히고, 도감 번호·로스터 인덱스는 정수뿐, 아이템은 `ItemKind` case 뿐 | 같은 파일 | `testFocusMinutesAreClampedToTheThreeOfferedLengths`, `testSpeciesLookupRejectsAnythingThatIsNotADexNumberInRange` |
| 4. 승인 게이트 | 상태를 바꾸는 도구는 사용자 1탭 뒤에만 | `PokemonChatStore.resolvePending` | `testApprovedTimerCallExecutesOnlyForItsOwnCompanion`, `testApprovalGatedToolPausesTheLoopInsteadOfAskingAgain` |
| 4b. 주인 게이트 | 승인 카드가 가리킨 개체와 실행 대상이 갈라지지 않는다 | `PokemonChatToolbox.run(_:owner:)` | `testToolsThatActOnMeRefuseFromABoxedCompanionsChat`, `testTargetedAndReadOnlyToolsStillWorkFromABoxedCompanionsChat`, `testApprovalPathCarriesTheProposalsCompanionIntoTheExecutor` |
| 5. 응답 가드 | 코드펜스·"as an AI"·terminal 유출 시 리다이렉트 | `PokemonChatReplyGuard` | `testRoleBreakingReplyIsReplacedBeforeDisplayOrPersistence` |

겹 1 은 **차단되지 않은 제공자를 실행하지 않는다**는 원칙까지 포함한다. 도구를 끌 수 없는 CLI 는
`.blocked(.unverifiedToolContract)` 로 남는다 — 근거는 `opencode-isolation.md`.

### 겹 0 — 목록을 닫아도 **실행 환경**은 안 닫힌다

도구를 전부 끈 계약은 모델이 무엇을 부를 수 있는지만 정한다. 자식 프로세스가 **어디서** 도는지는
따로 정해야 한다. 정하지 않으면 앱의 cwd 를 물려받고, 메뉴바 앱의 cwd 는 `/` 다 — CLI 의 프로젝트
루트가 디스크 전체가 되어 시작 스캔이 `~/Desktop`·`~/Documents` 를 밟는다. macOS 는 자식의 파일
접근을 **책임 프로세스**(= 앱)로 돌리므로 사용자에겐 "Pokédoro 가 데스크탑에 접근하려 합니다" 가
뜬다. 한 번의 전송이 CLI 를 `maxToolRounds + 1` 번까지 띄우므로 창은 대화 도중 계속 뜬다.

권한 창을 끄는 스위치는 없다. `NSDesktopFolderUsageDescription` 은 문구만 바꾼다 — **안 밟는 것**만이
답이고, 그래서 이건 문구 문제가 아니라 경계다.

### 겹 1 은 설정 파일까지 닫는다 (`--setting-sources ""`)

`--safe-mode` 만으로는 부족하다. 실측(`--debug-file`)에서 훅·플러그인은 실제로 꺼졌지만
(`Skipping plugin hooks`, `Found 0 total hooks`) 사용자 설정의 env 는 그대로 실렸고
(`settingsEnv keys: ECC_DISABLED_HOOKS,CLAUDE_CODE_ENABLE_TELEMETRY,OTEL_…`), 실행마다 사용자의
`~/.claude/settings.json` 에 permission 규칙을 **쓰기까지** 했다(`Applying permission update …
destination 'userSettings'`). 대화 한 번이 사용자의 개발 환경 설정을 고치는 건 격리가 아니다.

`--setting-sources ""` 를 더하면 `settingsEnv keys: none` 이 되고 그 쓰기가 사라진다. 인증은
설정 파일이 아니라 keychain·`~/.claude` 자격증명에서 오므로 그대로 동작한다(실측 확인).
codex 는 `--ignore-user-config --ignore-rules` 로 처음부터 닫혀 있었다 — **같은 부류를 한쪽
제공자에만 적용해 둔 상태**였다.

## 왜 MCP 서버를 쓰지 않았나

모델에 진짜 도구를 주려면 앱이 MCP 서버를 띄우고 `--mcp-config` 로 붙여야 한다. 그러면 **검증해야 할
격리 계약이 하나 더 생긴다** — OpenCode 를 차단시킨 것과 같은 부류의 부채다. 마커 방식은 실행 주체가
처음부터 앱이라 검증할 계약이 없다.

대가는 왕복이다. 도구 결과를 모델에게 돌려주려면 CLI 를 한 번 더 띄워야 한다.

## 왕복 상한

한 번의 전송이 CLI 를 띄우는 횟수는 `PokemonChatStore.maxToolRounds + 1` 로 고정이다(현재 3+1).
상한을 2 에서 3 으로 올린 이유는 `bag.list` → `item.use` 처럼 **읽고 쓰는 2단 체인**이 생겨서다 —
2 라운드면 마지막 턴에 실행이 잘려 모델이 가방을 보고도 아무것도 못 쓴다.
상한 숫자는 **한 곳에만** 둔다(`let rounds = 0...maxToolRounds`) — 범위와 "마지막인가" 판정이
각각 숫자를 들면 서로를 가려서, 한쪽을 넓혀도 아무 테스트가 안 깨진다(2026-08-25 주입에서 확인).

마지막 요청 뒤에는 도구를 돌리지 않는다. 결과를 전할 턴이 없는 실행은 부작용만 남긴다.

## 프롬프트 예산

도구 줄은 시스템 프롬프트에 그대로 실린다. `testSystemPromptStaysWithinTheChatBudgetWithAFullIdentity`
가 상한을 지키고, 도구를 더하면 **깨지는 게 정상**이다. 깨진 만큼만 올린다(1_600 → 2_100 → 2_500 →
2_800 → 2_860) — 넉넉히 잡으면 다음에 무엇이 새어 들어와도 아무도 모른다.

예산은 절마다 **긴 쪽으로** 잰다. 어느 쪽이 긴지는 절마다 다르다 — 별명·능력치·기술은 채워진 쪽이
길고(별명은 종 이름을 괄호로 함께 싣고, 나머지는 `not loaded` 열 글자를 대체한다), 타입·다음 진화는
비어 있는 쪽이 길다(`not loaded`·`not known` 이 한국어 이름보다 길다). 한쪽만 재면 실제 프롬프트가
상한을 넘는데도 게이트는 초록으로 남는다.

## 도구를 더하려면

1. `PokemonChatTool` 에 case 와 `promptLine` 을 넣는다. 프롬프트는 저절로 따라온다.
2. `PokemonChatToolCall` 에 **검증을 마친** 인자로 case 를 넣는다 — 잘못된 값을 담은 호출이
   만들어질 수 없어야 한다. 클램프는 생성 시점 한 곳에만 둔다.
3. `needsApproval` 을 정한다. **상태를 바꾸면 무조건 `true`.**
   그리고 `actsOnTheActiveCompanion` 을 정한다 — 대상을 인자로 받지 않고 "지금 나와 있는 나" 에
   작용하면 `true`. 둘 다 `switch` 가 망라적이라 빠뜨리면 컴파일이 안 된다.
4. `PokemonChatToolbox.run` 에 실행을 넣고 `(line:succeeded:)` 를 정직하게 돌려준다.
   거절과 실패가 같은 값이면 승인 카드에서 둘이 구분되지 않는다.
5. 거부 케이스를 `testOnlyTheDeclaredToolsParseAsCalls` 에 **더한다** — 새 도구가 목록을
   넓힌 만큼 목록 밖도 다시 확인한다.
6. 새 가드는 결함을 주입해 빨개지는지 본다. 라인 커버리지는 증거가 아니다 —
   `xcrun llvm-cov show <bin> -instr-profile=<profdata> <file>` 로 `^0` 을 직접 본다.

## 넣지 말아야 할 것

- **임의 문자열을 그대로 받는 인자.** 경로 조각·URL·명령이 될 수 있는 값은 도구의 인자가 아니다.
- **승인 없는 상태 변경.** "사용자가 부탁했으니까" 는 모델의 판단이지 사용자의 승인이 아니다.
  (`memory.record` 만 예외이며, 그 근거는 위에 적혀 있다 — 예외를 늘릴 때는 같은 강도의 근거를 댄다.)
- **놓아 주기·판매·구매처럼 되돌릴 수 없거나 재화를 쓰는 일.** 승인 카드 한 번으로 감당할 무게가
  아니다. `companion.release`·`shop.buy` 가 목록에 없는 이유이고, 거부 케이스로 고정돼 있다.
- **도구 결과를 대화 기록에 넣는 것.** 사용자가 기계 문자열을 읽게 된다. 결과는 다음 요청에만 실린다.
- **화면이 있어야 성립하는 일.** 던전 입장은 맵 이동이고 체육관 도전은 배틀 화면이다. 하루 한 판인
  자원을 승인 카드 한 번으로 태울 수 없다 — 대화는 `challenge.status` 로 **가리키는** 데까지다.
- **동행을 밀어내거나 되돌릴 수 없는 일.** 저장 알 품기(`beginIncubatingFocusEgg`)는 지금 동행을
  박스로 보내고, 졸업(`graduateCompanion`)은 도감으로 떠나보낸다. 거부 케이스로 고정돼 있다.
- **화면 설정.** 방해금지·정렬·필터·스프라이트 선명도는 사용자 취향이고, 실행기에 `AppSettings`
  의존성을 새로 붙일 값이 아니다.
- **코딩·파일·셸·범용 검색.** 이 앱의 대화에는 그 요구가 없다. 필요해지면 그건 다른 제품이다.
