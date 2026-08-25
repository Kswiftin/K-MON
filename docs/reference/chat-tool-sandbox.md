---
summary: "포켓몬 대화가 실행할 수 있는 일의 전부와, 그 목록이 닫혀 있음을 무엇이 보장하는가 — 5겹 경계와 각 겹을 지키는 테스트."
read_when:
  - 대화에 새 도구를 더하거나 기존 도구를 빼려 할 때
  - `[[tool:...]]` 마커 문법·인자 클램프·승인 구분을 손댈 때
  - "대화가 X 를 할 수 있게 해 달라" 는 요청을 받았을 때 (대개 답은 "그 겹에 넣을 수 없다" 다)
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
| `pokedoro.status` | 없음 | 불필요 | 집중 타이머의 현재 상태 |
| `pokedoro.start` | `25` \| `50` \| `90` | **필요** | 집중 세션 시작(모험 출발 + 타이머) |
| `pokedoro.stop` | 없음 | **필요** | 집중 세션 종료 |

넷이 전부다. 목록은 `PokemonChatTool` 한 곳에 있고 프롬프트가 광고하는 이름도 여기서 나온다 —
두 벌이면 한쪽만 바뀌어 모델이 없는 도구를 부르거나 있는 도구를 영영 모른다.

## 5겹 경계

| 겹 | 무엇을 막나 | 어디 | 지키는 테스트 |
|---|---|---|---|
| 1. 제공자 인자 | CLI 내장 도구·MCP·사용자 설정 전부 차단 | `PokemonChatProviderSafety.arguments` | `testClaudeProviderDisablesBuiltInToolsAndMCPConfiguration`, `testCodexProviderIgnoresConfigurationAndUsesReadOnlySandbox` |
| 2. 화이트리스트 | 목록 밖 이름은 호출로 파싱되지 않는다 | `PokemonChatToolParser` | `testOnlyTheFourDeclaredToolsParseAsCalls` |
| 3. 인자 클램프 | 분은 세 값으로 접히고, 도감 번호는 범위 안 정수뿐 | 같은 파일 | `testFocusMinutesAreClampedToTheThreeOfferedLengths`, `testSpeciesLookupRejectsAnythingThatIsNotADexNumberInRange` |
| 4. 승인 게이트 | 상태를 바꾸는 도구는 사용자 1탭 뒤에만 | `PokemonChatStore.resolvePending` | `testApprovedTimerCallExecutesOnlyForItsOwnCompanion`, `testApprovalGatedToolPausesTheLoopInsteadOfAskingAgain` |
| 5. 응답 가드 | 코드펜스·"as an AI"·terminal 유출 시 리다이렉트 | `PokemonChatReplyGuard` | `testRoleBreakingReplyIsReplacedBeforeDisplayOrPersistence` |

겹 1 은 **차단되지 않은 제공자를 실행하지 않는다**는 원칙까지 포함한다. 도구를 끌 수 없는 CLI 는
`.blocked(.unverifiedToolContract)` 로 남는다 — 근거는 `opencode-isolation.md`.

## 왜 MCP 서버를 쓰지 않았나

모델에 진짜 도구를 주려면 앱이 MCP 서버를 띄우고 `--mcp-config` 로 붙여야 한다. 그러면 **검증해야 할
격리 계약이 하나 더 생긴다** — OpenCode 를 차단시킨 것과 같은 부류의 부채다. 마커 방식은 실행 주체가
처음부터 앱이라 검증할 계약이 없다.

대가는 왕복이다. 도구 결과를 모델에게 돌려주려면 CLI 를 한 번 더 띄워야 한다.

## 왕복 상한

한 번의 전송이 CLI 를 띄우는 횟수는 `PokemonChatStore.maxToolRounds + 1` 로 고정이다.
상한 숫자는 **한 곳에만** 둔다(`let rounds = 0...maxToolRounds`) — 범위와 "마지막인가" 판정이
각각 숫자를 들면 서로를 가려서, 한쪽을 넓혀도 아무 테스트가 안 깨진다(2026-08-25 주입에서 확인).

마지막 요청 뒤에는 도구를 돌리지 않는다. 결과를 전할 턴이 없는 실행은 부작용만 남긴다.

## 도구를 더하려면

1. `PokemonChatTool` 에 case 와 `promptLine` 을 넣는다. 프롬프트는 저절로 따라온다.
2. `PokemonChatToolCall` 에 **검증을 마친** 인자로 case 를 넣는다 — 잘못된 값을 담은 호출이
   만들어질 수 없어야 한다. 클램프는 생성 시점 한 곳에만 둔다.
3. `needsApproval` 을 정한다. **상태를 바꾸면 무조건 `true`.**
4. `PokemonChatToolbox.run` 에 실행을 넣고 `(line:succeeded:)` 를 정직하게 돌려준다.
   거절과 실패가 같은 값이면 승인 카드에서 둘이 구분되지 않는다.
5. 거부 케이스를 `testOnlyTheFourDeclaredToolsParseAsCalls` 에 **더한다** — 새 도구가 목록을
   넓힌 만큼 목록 밖도 다시 확인한다.
6. 새 가드는 결함을 주입해 빨개지는지 본다. 라인 커버리지는 증거가 아니다 —
   `xcrun llvm-cov show <bin> -instr-profile=<profdata> <file>` 로 `^0` 을 직접 본다.

## 넣지 말아야 할 것

- **임의 문자열을 그대로 받는 인자.** 경로 조각·URL·명령이 될 수 있는 값은 도구의 인자가 아니다.
- **승인 없는 상태 변경.** "사용자가 부탁했으니까" 는 모델의 판단이지 사용자의 승인이 아니다.
- **도구 결과를 대화 기록에 넣는 것.** 사용자가 기계 문자열을 읽게 된다. 결과는 다음 요청에만 실린다.
- **코딩·파일·셸·범용 검색.** 이 앱의 대화에는 그 요구가 없다. 필요해지면 그건 다른 제품이다.
