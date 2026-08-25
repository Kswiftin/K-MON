---
summary: "OpenCode 를 포켓몬 대화 CLI 에서 차단해 둔 이유의 실측 기록 — 검증 날짜·버전·프로브 결과·재검증 한 줄."
read_when:
  - OpenCode(또는 새 CLI)를 대화 제공자로 켜려 할 때
  - `PokemonChatProviderSafety.availability` 의 `.blocked(.unverifiedToolContract)` 를 손댈 때
  - 상류 이슈 #10527·#22787 가 닫혔다는 소식을 들었을 때
---

# OpenCode 격리 계약 — 미검증(차단 유지)

**판정: 분기 B — 지원하지 않는다.** 계약이 성립하지 **않는다고 확인한 게 아니라, 확인 자체를
하지 못했다.** 이 둘을 구분해 적는다. 앱이 격리를 보장할 수 없으면 차단이 정직한 결과다.

| 항목 | 값 |
|---|---|
| 최근 검증 시도일 | 2026-08-25 (앞선 시도 2026-08-23) |
| `opencode --version` | `1.4.3` — 설치돼 있다. 2026-08-23 에는 미설치였다. |
| 프로브 결과 | 4종 모두 **미실행**. `./scripts/verify-opencode-isolation.sh` → `INCONCLUSIVE`, exit 2 |
| 막힌 지점 | **스모크 프로브 무응답.** 스크립트가 `HOME`·`XDG_CONFIG_HOME` 을 빈 임시 디렉토리로 갈아끼우므로 모델 인증도 함께 사라진다. |
| 앱 상태 | `availability(for: .opencode) == .blocked(.unverifiedToolContract)` — 피커에서 선택 불가 |

## 2026-08-25 에 바뀐 것

설치 여부는 더 이상 장벽이 아니다. 남은 장벽은 **스크립트 설계 자체**다 — 사용자 MCP 서버가
와일드카드로 막히는지 보려면 가짜 `$XDG_CONFIG_HOME/opencode/opencode.json` 을 심어야 하고,
그래서 실제 홈을 쓸 수 없다. 그런데 인증도 실제 홈에 있다. 격리와 인증이 같은 디렉토리를 두고
다툰다.

같은 실행에서 스크립트의 결함도 하나 드러났다: 프로브에 상한이 없어 인증 없는 머신에서 첫 호출이
**무한 대기**했다. 종료코드로 판정을 남기는 게 목적인 스크립트가 종료를 못 하면 목적이 깨진다.
`PROBE_TIMEOUT`(기본 60초)을 붙여 이제 `2` 로 끝난다.

다음에 이걸 다시 볼 사람에게: 인증 자료를 가짜 홈으로 복사하는 건 **사람이 판단할 일**이다.
자격증명을 임시 디렉토리에 복제하는 스크립트를 자동으로 돌리지 않는다.

## 왜 플래그로 못 끄는가

`opencode run` 의 문서화된 플래그에 도구·MCP 를 끄는 것이 **없다**. 상류에 열린 이슈로 남아 있다
— [#10527 `--disableMcp`](https://github.com/anomalyco/opencode/issues/10527),
[#22787 `--mcp`](https://github.com/anomalyco/opencode/issues/22787) (#7687 은 inactive 로 닫힘).
출처: [CLI 문서](https://opencode.ai/docs/cli/) · [설정 문서](https://opencode.ai/docs/config/).

## 후보 계약 (아직 실측되지 않음)

설정 파일은 교체가 아니라 **병합**되고 우선순위는 ① remote → ② 전역 `~/.config/opencode/opencode.json`
→ ③ `OPENCODE_CONFIG` → ④ 프로젝트 `opencode.json` → ⑤ `.opencode/` → ⑥ `OPENCODE_CONFIG_CONTENT`
→ ⑦ managed config → ⑧ macOS managed preferences 다.

```
OPENCODE_CONFIG_CONTENT='{"tools":{"*":false},"mcp":{},"permission":{"edit":"deny","bash":"deny","webfetch":"deny"}}' \
  opencode run --dir "$EMPTY_DIR" --format json "<프롬프트>"
```

- `OPENCODE_CONFIG` 는 **쓰면 안 된다** — ③ 이라 프로젝트 설정 ④ 가 덮는다.
- `--dir <빈 임시 디렉터리>` 로 ④·⑤ 를 아예 없앤다.
- `--auto` 는 **절대 붙이지 않는다** — 명시 거부하지 않은 권한을 자동 승인한다.

문서로 닫을 수 없는 네 가지가 남아 있고, 이것이 스크립트가 존재하는 이유다:
`"tools":{"*":false}` 와일드카드가 실제로 지원되는가 · 그것이 **이름을 모르는 MCP 서버의 도구까지**
덮는가 · ⑥ 이 정말 ④ 를 이기는가 · 프롬프트가 stdin 인가 argv 인가.

## 재검증 (한 줄)

```bash
./scripts/verify-opencode-isolation.sh    # 0 = 4/4 통과 · 1 = 프로브 실패 · 2 = 시험 불가
```

`0` 이 나오면 그때 `availability(for: .opencode)` 를 `.verified` 로 바꾸고, **통과시킨 바로 그
JSON·인자**를 실행 계약으로 쓴다. 스크립트의 프로브 로직은 스텁으로 검증했다 — 탈출하는 스텁에서
`bash`·`precedence` 가 FAIL 로 잡히고 exit 1 이 난다(빈 통과를 못 한다).

## 무엇이 바뀌면 다시 볼 것인가

- 상류 이슈 #10527 또는 #22787 이 닫히거나 `run --no-tools` 류 플래그가 생긴다 → 플래그 기반 계약은
  병합 우선순위보다 훨씬 안전하다. 다시 본다.
- `opencode` 를 설치하고 모델 인증을 붙였다 → 스크립트를 돌린다. 지금 막힌 건 이것뿐이다.

## 잔여 위험 (계약이 성립해도 남는다)

- **버전 종속.** 플래그가 아니라 설정 병합 우선순위에 기댄 계약은 상류 릴리스가 조용히 깰 수 있다.
  그래서 판정을 사람 기억이 아니라 재실행 가능한 스크립트로 남긴다.
- **managed config(⑦)·macOS managed preferences(⑧)** 는 앱이 이길 수 없는 채널이다. 관리자 통제
  영역이므로 잔여 위험으로 문서화하고 끝낸다.
