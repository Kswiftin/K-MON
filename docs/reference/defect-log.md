---
summary: "결함 대응 프로토콜로 축적된 구체 규칙 — 한 번 겪은 부류의 실수를 다시 겪지 않기 위한 원장."
read_when:
  - 결함·회귀·공백을 고치는 중 (프로토콜 4단계의 '부류 스윕'·'영구 캡처' 근거)
  - 동시성/await·옵셔널 판정·캐시 무효화·외부 로그 포맷을 건드릴 때
  - 메뉴바·플로팅 펫 등 상시 표시 애니메이션의 성능을 손볼 때
  - 세이브 이전/병합·외부 파일 입력 경로를 만들 때
  - 외부 API(PokéAPI 등) DTO 에서 조건 필드를 새로 읽기 시작할 때
  - 컴파일러 warning·CI 게이트를 손볼 때 (게이트 없는 warning 은 쌓인다)
  - 코드서명·Info.plist·엔타이틀먼트 등 **번들 속성**을 손볼 때 (`swift test` 가 못 보는 부류)
  - 외부 실행 파일의 설치 경로를 코드에 적을 때
  - 외부 프로세스를 띄울 때 (cwd·환경변수처럼 **안 정하면 부모의 것을 물려받는** 값)
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

- **`?? 기본값` 은 "값이 없다"를 "값이 이거다"로 바꿔 화면에 거짓을 만든다.** 디코딩이 아니라 *표시* 에서
  터지는 부류다. 로그를 접을 때 `damage ?? 0` 을 쓰면 데미지 이벤트가 없는 행동(빗나감·변화기)이
  **"0 데미지"** 로 렌더된다 — 맞았는데 0 인 것처럼 읽히는, 없는 정보를 지어낸 문구다. 옵셔널은
  `guard let` 으로 갈라 "숫자가 없는 문구"를 따로 두고 기본값으로 메우지 않는다(`BattleLog.Action.text`).
- **`max(1, …)` 하한은 "때린 경우"에만 쓴다 — 아니면 안 때린 것까지 때린 것으로 만든다.** 데미지 하한이
  **위력 0 인 변화기까지** 1 이상으로 올려, Gen 2 식의 `+2` 가 살아남아 상태기가 2 데미지를 넣었다
  (`resolveAttack` 의 `move.power > 0`). `moveSet` 은 `power > 0` 으로 걸러도
  `canonicalLevelUpMoves`(→ `learnedMoves`)는 안 거른다 — **한쪽 경로만 필터가 있으면 필터는 없는 것과
  같다.** (변화기 데미지, 2026-08-20.)
- **`?? 0` 으로 접은 "값 없음"은 그 자리에서 안 터지고 세 함수 뒤에서 조용히 죽는다.** PokéAPI 는
  위력이 상황에 따라 변하는 공격기에 `power: null` 을 준다(1~5세대 37개). `MoveSpec.from` 의
  `dto.power ?? 0` 이 그걸 0 으로 접자, 엔진의 `power <= 0` 게이트가 **공격기를 변화기로 오인**해
  데미지를 0 으로 확정했다 — 일렉트릭볼·지구던지기·자이로볼이 PP 만 태우고 로그에 기술명 한 줄만
  남겼다. 상성도 안 탔다(전기가 물에게 2배로 안 들어감). `?? 0` 은 "없음"과 "0" 을 같은 값으로
  만들고, 그 둘을 가르는 코드는 **다른 파일에** 있었다. 처방은 두 갈래다: 계산할 수 있는 기술은
  실제로 계산하고(`VariableDamage`), **아직 못 하는 기술은 무브셋 후보에서 뺀다** — 못 고치면
  권하지도 않는 쪽이 낫다. (가변 위력, 2026-08-24.)
- **"규칙에 예외가 하나 있다" 를 규칙 전체를 뒤집어 표현하면, 예외 하나를 지키려고 여덟 개를 깬다.**
  변화기 상성 처리가 그랬다. 전기자석파가 땅에 실패해야 한다는 **한 기술** 때문에 "상태를 거는
  변화기는 전부 상성표를 본다" 로 규칙을 세웠고, 그 결과 이상한빛(고스트→노말)·노래(노말→고스트)·
  최면술(에스퍼→악)까지 같이 막혔다 — 해당 12개 중 8개가 오동작. 노말↔고스트 면역은 **데미지
  기술의 규칙**이라 변화기는 원래 안 탄다. 처방은 규칙을 뒤집고 **예외를 id 로 명시**하는 것
  (`MoveSpec.typeBlockedStatusMoveIDs`). 예외가 하나면 예외 목록을 만들어라 — 규칙을 예외에
  맞추지 마라. (변화기 상성, 2026-08-24.)
- **문구는 "그 배율이 실제로 쓰였을 때만" 붙인다.** 위 수정으로 전기자석파가 상성표를 보게 되자
  물 타입 상대에게 "효과가 굉장했다" 가 붙었다 — 깎을 데미지가 없어 2배가 아무 데도 안 쓰이는데
  마비가 2배로 걸린 것처럼 읽힌다. 급소도 같다. **무효(0배)만 남긴다** — 그건 배율이 아니라
  "실패했다" 는 뜻이라 사용자가 알아야 한다.
- **"실패"도 줄을 남겨야 한다 — 데미지 0 은 무반응과 구별되지 않는다.** 위 작업 중 레벨이 높은 상대에게
  쓴 일격필살을 `.fixedHP(0)` 으로 접었더니, `applyAttack` 이 데미지 0 에는 이벤트를 안 내서 고치려던
  그 무반응이 그대로 재현됐다(프로브가 잡았다). 실패 경로는 **면역과 같은 줄**(`.immune`)로 낸다.
  데미지 값으로 실패를 표현하지 마라 — 0 은 "안 맞았다"·"무효다"·"실패다"를 전부 삼킨다.
- **같은 판정을 경로마다 따로 두면 경로마다 다른 답이 난다 — 승패는 특히 그렇다.** 배틀 승패가 세 곳
  (`connectionDropped`·`advanceFainted`·`didIWin`)에 각자 박혀 있었고 그중 둘이 이기지 않은 쪽에 승리를
  줬다. 판정은 **모드를 인자로 받는 순수 함수 하나**로 모으고 각 경로는 한 줄로 위임한다
  (`MultiplayerBattle.outcome(for:fighters:mode:)`·`BattleEngine.disconnectOutcome`). 게스트가 인스턴스를
  갱신하지 않는 구조(방은 `fighters` 배열만 브로드캐스트한다)라 **static** 이어야 한다 — 인스턴스
  프로퍼티로 두면 게스트 판정이 개시 시점 상태에 굳는다.
- **결과 타입에 "아무도 안 이겼다" 자리가 없으면 무승부가 승리로 접힌다.** `result: Bool?` 의 nil 은 이미
  "진행 중"이라 동시 전멸을 담을 값이 없었고, `advanceFainted` 가 상대 전멸을 먼저 보고 `return` 해
  무승부가 승리가 됐다(체육관 배지까지 지급). 동시 전멸은 **도달 가능한 상태다** — `resolveTurn` 은 두
  공격이 끝난 뒤 잔뎀을 넣으므로 "내 공격이 상대 마지막을 눕히고 잔뎀이 내 마지막을 눕히는" 턴이 있다.
  승/패/무를 값으로 가진 타입(`BattleOutcome`)을 쓰고, 보상·배지는 `.win` 에서만 나가게 한다.
  또 **"당사자가 아니다"도 결과가 아니다** — 관전자도 라운드 브로드캐스트를 받으므로 전투원 여부 가드가
  없으면 싸우지도 않은 배틀의 기록이 남는다(`outcome` 이 nil 을 돌려 그 자리를 막는다).
- **네트워크 끊김을 승리로 접으면 양쪽이 이기고, 판돈도 양쪽 지갑에 동시에 들어간다.** 두 피어는 각자
  *자기* 연결의 죽음을 보므로 `iWon: true` 로 접으면 네트워크가 한 번 끊길 때 둘 다 몰수승을 선언하고
  둘 다 판돈을 정산받는다 — 어느 지갑에서도 빠져나가지 않으므로 별의조각 총량이 늘어나고, 지고 있을
  때 네트워크를 끊는 게 이득이 된다. 판정은 **양쪽이 공유하는 상태에서** 뽑아라(남은 HP 비율) —
  그러면 두 쪽 결론이 자동으로 반대가 되어 "둘 다 승리"가 원리적으로 불가능하다. 동률은 무효로 두고
  정산 자체를 건너뛴다. 명시적 기권 메시지는 다른 경로다(그건 상대가 스스로 진 것). 비교는 `Double`
  나눗셈이 아니라 교차곱으로 — 두 피어가 같은 값을 봐야 하는 판정에서 반올림이 갈리면 그게 desync 다.
- **guard 하나가 성격이 다른 두 자원을 같이 막으면 막고 싶던 것만 막히지 않는다.** 랭크전 정산이
  판돈을 못 낼 때 `guard … else { return 0 }` 으로 빠져나갔고, 그 뒤에 있던 **LP 차감까지** 건너뛰었다 →
  지갑을 판돈 아래로 비워 두면 절대 LP 를 잃지 않는 무손실 랭크가 됐다. 화폐(별의조각)와 실력 지표(LP)는
  다른 자원이다. 조기 return 을 쓸 때는 **그 뒤에 남은 부수효과가 무엇인지** 보고, 성격이 다르면 갈라라.
- **정산을 결과 시점에 두면 "결과를 안 보는 것"이 회피 수단이 된다.** 랭크전 판돈이 배틀 끝에 움직여서
  지고 있을 때 앱을 종료하면 내 쪽 정산이 아예 돌지 않아 판돈을 안 냈다(상대는 승리 처리로 받으니
  총량이 늘었다). 대가는 **앱이 확실히 살아 있는 시점**에 걷는다 — 개시 시점 에스크로 + 미결 기록을 세이브에
  남기고, 다음 기동이 그 기록을 패배로 마감한다(`CompanionStore.escrowRankedBattle`/
  `settleAbandonedRankedBattleIfNeeded`). 크래시와 고의 종료는 로컬에서 구분할 수 없으므로 환급으로 두면
  회피가 그대로 살아난다. 세이브 필드를 추가하면 `SaveTransferTests` 의 분류 테스트와
  `SaveTransfer.canonicalString`(구버전 서명 호환 — 기본값이면 붙이지 않는다)을 같이 손대야 한다.
- **화면이 약속하는 보상과 실제 지급을 같은 곳에서 확인하라.** 방 배틀은 `battleReward` 로 "+20 ✨"을
  띄웠는데 `grantBattleReward` 는 `let dust = 0` 으로 아무것도 지급하지 않았다(경제 재조정에서 지급만
  빠지고 표시가 남은 것으로 보인다). 표시용 값을 지급 경로와 **다른 함수에서** 계산하면 둘이 조용히
  갈라진다. 회귀 가드는 소스 스캔이다(`testTheRoomResultCoversDrawAndSpectators` 가 `battleReward` 부재를
  단언한다) — 렌더 테스트를 세울 수 없는 화면에서는 이게 가장 싼 고정이다.
- **자기 신고 수치는 상한이 없으면 산술을 죽인다 — 그렇다고 클램프가 신고 자체를 검증해 주지는 않는다.**
  관전자 베팅 수용 검사가 `bet.amount <= member.reportedStarPieces` 만 봤고 그 잔액은 참가자가 스스로
  신고한다. `Int.max` 한 건이 원장에 들어가면 `payouts` 의 `pot * bet.amount` 가 오버플로 트랩으로
  프로세스를 죽인다. 상한은 **합산 여유**로 정한다(관전자 정원 × 상한² < Int.max → 10^9 은 부족, 10^8 을
  쓴다). 같은 부류로 와이어 `BattleRank.points` 도 경계에서 잘랐다. 단 **클램프는 위생일 뿐이다** —
  상대가 자기 랭크를 높게 주장하면 승리 LP·판돈이 정상 범위 안에서 커진다. 공유 원장 없는 P2P 에서는
  서명·서버 없이 못 막는다(미해결로 남김).
- **클램프는 트랩을 옮기기도 한다 — 잘린 값이 다음 산술의 0 분모가 되는지 본다.** 베팅 금액을
  `max(0, …)` 로 자르자 오버플로는 막혔지만 **0 원 베팅이 원장에 남았고**, 우승자에 걸린 게 그것뿐이면
  `payouts` 의 `pot * amount / backed` 가 `backed == 0` 으로 0 나눗셈 트랩이 됐다(같은 공격자, 다른 트랩).
  경계 클램프를 넣을 때는 **잘린 값이 흘러가는 산술을 한 번 따라가고**, 그 산술 자리에서도 무의미한 값을
  제외한다(`filter { $0.amount > 0 }`). 호스트측 수용 검사(`amount > 0`)는 와이어 원장에는 걸리지 않는다.
- **"상태가 같으니 결론도 반대"는 턴 경계에서만 참이다(미해결).** 1v1 끊김 판정은 두 피어가 같은 배틀
  상태를 본다는 전제로 남은 HP 비율을 비교한다. 그런데 `resolveIfReady` 는 **두 선택이 모이는 즉시**
  각자 해상하므로 한쪽 `.move` 만 도착한 채 링크가 죽으면 상태가 한 턴 어긋나고, 그 창에서는 양쪽이
  모두 "내가 앞선다"를 볼 수 있다 → 판돈이 두 지갑에 동시에 들어간다(막으려던 그 결함의 좁은 재발).
  결정론적 상태를 판정 근거로 쓰려면 **어느 시점의 상태인지도 합의돼야 한다** — 턴별 ack 또는 합의된
  턴 인덱스 기준 판정이 필요해 와이어 계약 변경 사안으로 남긴다.
- **`?? 0`·`max(1, …)` 은 한 줄 안의 region 이라 라인 커버리지에 잡히지 않는다.** 왼쪽만 밟혀도 그 줄은
  초록이다. `BattleLog.swift` 는 라인 91% 로 게이트를 통과한 상태에서 `.resisted` 분기가 **0회**였고
  `?? 0` 두 곳은 한 번도 nil 을 안 밟았다. `llvm-cov --show-regions | grep '\^0'` 으로 직접 본다.
  **새 enum case 는 만드는 쪽(엔진)만 테스트하면 렌더러 쪽이 0회로 남는다** — 엔진 테스트가 `.resisted`
  를 검증해도 접기 테스트가 그 case 를 먹이지 않으면 렌더 분기는 죽어 있다(#51).

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
- **폴백 사슬은 "어느 축을 먼저 포기하는가" 가 곧 증상이다.** 등 스프라이트를 넣을 때 `SpriteLoader`
  의 사슬이 이로치를 먼저 포기해, 등 에셋이 없는 종의 이로치가 **일반색 정면**으로 떨어졌다
  (`(이로치,등) → (일반,등) → (일반,앞)` — `(이로치,앞)` 을 영영 안 시도한다). 축이 둘 이상이면
  포기 순서를 명시하고 그 순서를 테스트한다: 지금은 `(이로치,등) → (이로치,앞) → (일반,앞)`.
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

- **`mutating` 메서드가 throw 해도 그때까지의 변경은 호출자에게 남는다.** `MultiplayerBattle.resolveRound`
  는 사전 검증에서 무브셋 **인덱스만** 보고 PP 는 해상 루프에서 봤다 — 규칙 위반 액션이 섞이면 앞선
  공격이 이미 HP·PP 에 적용된 뒤 throw 가 나 라운드가 **반쯤 적용된** 채 버려졌다.
  **상태를 바꾸는 루프에 들어가기 전에 검증을 끝낸다.**
- **"사전 검증 루프가 있다"는 "다 검증한다"가 아니다.** 루프가 보는 항목과 해상이 요구하는 항목이
  달랐다. 검증을 늘릴 때는 해상 루프가 인덱싱·차감하는 값을 하나씩 대조한다.
  지금은 `BattleSide.canUse(moveAt:)` 한 곳이 인덱스와 PP 를 같이 본다.
- **와이어로 들어온 배열은 쌍을 이루는 배열과 길이가 맞는다는 보장이 없다.** `pp` 는 `moves` 와 별개
  필드라, 짧게 오면 거절이 아니라 `pp[moveIndex]` 범위 초과였다. 같은 부류로 1v1 은 상대 기술 인덱스를
  `moveIndex < 4` 라는 **상수**로 세고 있었다 — 기술이 2개인 무브셋에 3 이 오면 `opp.pp[3]` 크래시다.
  경계 검사는 상수가 아니라 **실제 배열**로 한다(`canUse`).
- **거절 경로가 타이머를 다시 걸지 않으면 방이 멈춘다.** `finishRoundIfReady` 의 `scheduleTurnTimeout()`
  이 성공 경로에만 있어서, 게스트가 보낸 엉뚱한 `targetID` 하나로 throw 가 나면(마감 경로에서 나면
  다시 걸릴 타이머가 없다) 진행이 영구히 멈췄다. **catch 도 다음 마감을 건다.**
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
- **보상 객체가 설명해도 화면이 안 그리면 사용자에겐 설명이 없다 — 그리고 알림은 화면이 아니다.**
  `AdventureReward` 는 만렙 환산분(`overflowBonus`)까지 정확히 들고 있었는데, 그 값을 사람에게
  전하는 코드는 `notifyCompanionEvent` 하나뿐이었다. 그 함수는 `AppEnv.isBundledApp` **그리고**
  방해금지 해제 **그리고** `companionNotifications` 토글, **셋 다** 참일 때만 나간다 — 셋 중 하나만
  꺼도 지급이 통째로 무설명이 된다(만렙 모험이 7,200 대신 10,800 ⭐ 를 주는데 이유가 어디에도 없었다).
  완전설명 계약은 보상 객체에서 끝나지 않는다: **지갑을 바꾸는 값은 창 안에 항상 보이는 표면을 하나
  가져야 하고, 알림은 그 표면의 대체가 아니라 덤이다.** (#82 → #192, 2026-09-02.)
- **정산 결과를 뷰의 `@State` 로 받으면 사용자가 버튼을 누른 경로만 설명된다.** `claimAdventure()` 를
  부르는 곳은 넷인데(기동 복구 · 다음 모험 시작 시 자동 정산 · "보상 받기" 버튼 · 집중 세션 완료) 앞의
  둘은 반환값을 받을 뷰 자체가 없다. 표시용 마지막-정산은 **정산 함수 안**(`CompanionStore.lastClaim`)
  에서 채운다 — 지급 계산을 `claimAdventure()` 한 곳에만 두는 것과 같은 이유다.
- **배너를 조건 분기 *안*에 두면 그 분기를 벗어나는 순간 안 보인다.** 집중 세션 완료 배너는
  `FocusTimerView` 의 idle 분기 안에 있었는데, 세션이 끝나면 `FocusTimer.tick` 이 곧바로
  `startRest()` 를 불러 `isRunning` 이 참이 된다 — 정산을 알리는 바로 그 순간에 배너가 그려지지 않는
  분기로 넘어갔다. "정산했으면 보인다" 는 분기와 무관해야 하므로 if/else **밖**에 둔다.
- **배타 선택(`A > 0 ? A : B`)은 A 와 B 가 동시에 생기는 입력에서 한쪽을 조용히 지운다.** 이상한 사탕
  피드백이 `converted > 0 ? converted : RareCandy.xp` 였다. 만렙(전량 환산)과 상한 아래(전량 적립)
  두 대조군은 이 식으로도 통과하지만, 사탕 하나가 상한을 **걸치면** 두 몫이 같이 생겨 들어간 경험치가
  화면에서 사라진다. 결함을 주입해 보니 걸침 테스트 **하나만** 빨개졌다 — 양 극단 테스트 두 개는
  경계를 지키지 않는다. 두 값은 각각 세고(`candyFeedbackXP` · `candyFeedbackStardust`) 표시도 각각 한다.
- **뷰가 *건네받아* 들고 있는 값은 스토어를 비우는 것만으로 안 내려간다 — 비움(consume)과 무효화
  (invalidate)를 가른다.** 1회성 피드백은 뷰가 값을 자기 `@State` 로 옮기고 스토어를 소비하는 계약이라,
  세이브 가져오기가 `lastClaim = nil` 만 해서는 **이미 화면에 떠 있는 남의 세이브 정산액**에 닿지
  못했다. 뷰가 다시 건네받게 하려면 seq 도 올려야 한다. 규칙이 네 벌(연출 · 사탕 · 민트 · 정산)로
  흩어져 있어서 한 벌만 고치고 나머지를 빠뜨렸다 — `OneShotFeedback<Value>` 한 자리로 모으고
  `consume()`(뷰가 재생을 끝냈다: 값만 비움) 과 `invalidate()`(값이 무효가 됐다: seq 도 올림) 을
  타입에서 갈랐다. `applySave` 는 이제 `invalidateTransientFeedback()` 하나만 부른다.
  회귀: `testImportingASaveTellsTheViewToDropTheBanner`.
- **뷰 안 `if` 로만 존재하는 조립은 테스트가 걸 자리가 없다.** 정산 배너의 네 줄(알 · 정산액 · 환산분 ·
  사탕)이 `FocusTimerView` 의 `if` 네 개였다. 지급 하나를 통째로 빼도 1,960개 테스트가 전부 초록이었고
  **line coverage 도 못 걸렀다** — `if x { y }` 는 조건만 평가되면 실행으로 세니 블록이 한 번도 안 돌아도
  통과한다. 조립을 `AdventureReward.bannerLines` 라는 **순수 함수**로 빼면 "어떤 지급이 줄을 얻는가" 가
  값이 되어 단언할 수 있다. 뷰에는 그 값을 그리는 일만 남긴다.
  회귀: `testEveryPayoutOnOneClaimGetsItsOwnBannerLine` + 대조군 2개.
- **"띄우기" 와 "내리기" 를 서로 다른 `onChange` 에 두면 실행 순서에 진다.** 배너를 새 세션 시작 때
  내리려고 `onChange(of: timer.phase)` 에서 지우면, 모험 시작 정산(`startFocusSession` →
  `startFocusAdventure` 가 이전 모험을 정산한 **뒤** `startFocus`)이 같은 갱신에서 들어오기 때문에
  핸들러 순서에 따라 그 정산이 뜨지도 못하고 지워진다. SwiftUI 는 `onChange` 사이의 순서를 보장하지
  않는다 — **지우는 쪽을 이벤트가 아니라 값 비교로 바꾼다**: 안내를 채울 때 `timer.sessionStartSeq` 를
  함께 적어 두고, 그 값이 현재와 어긋나면 그리지 않는다. 순서와 무관하게 같은 답이 나온다.
  회귀: `testStartingAFocusSessionAdvancesTheSequenceThatDropsTheBanner`(완료는 계기가 **아님**도 함께 고정).
- **저장된 필드의 뜻은 마이그레이션 없이 바꾸지 않는다 — 읽는 화면이 없으면 바꿀 이유도 없다.**
  `AdventureRecord.stardust` 를 "기본 지급액" 에서 "지갑 증가분 전부" 로 바꿨다가 되돌렸다. 배열은 이미
  디스크에 있고 마이그레이션이 없어서, 옛 행과 새 행이 **다른 것을 뜻한 채** 한 배열에 섞인다.
  게다가 `recentAdventures` 는 소비처가 0개라 그 "수정" 은 화면에 보이지도 않았다. 의미 변경은
  **읽는 쪽이 생기는 시점에** 마이그레이션과 함께 한다.
  회귀: `testHistoryStoresTheBaseStardustOnlyUntilAMigrationSaysOtherwise` — 결정을 못 박는 테스트라,
  빨개지면 회귀가 아니라 결정이 바뀐 것이다.
- **부류 스윕 미완 (의도적, #200).** 같은 지갑에 지급하면서 반환값을 버리는 자리가 여덟 곳 더 있다
  (진화 · 레이스 · 배틀 · 던전 · 던전 스윕 · 졸업 3건). 근본 처방은 `accrueTrainerPoints` ·
  `recordMission` · `recordSeason` · `recordAchievement` 에서 `@discardableResult` 를 떼어 **컴파일러가
  호출부를 열거하게** 하는 것이다 — `awardExperience` 가 이미 그 계약이고, 형제 넷만 경고 없이 버릴 수
  있는 상태가 이 부류를 남겼다. 다섯 기능에 걸쳐 각자 표면을 정해야 해서 #200 으로 뺐다.

## 1회성 보상의 멱등 가드가 서명 밖에 있는 부류

- **"이미 받았다"를 기록하는 필드는 무결성 canonical 에 들어가야 한다.** `gymBadges` 는 체육관 첫 승리
  보상의 **유일한** 멱등 가드인데(`recordGymVictory` 의 `guard !state.gymBadges.contains`) 서명에서
  빠져 있었다 — 세이브에서 배지 키 한 줄을 지우면 같은 체육관에서 알을 다시 받는다. `shinyEggCharges`
  도 같았다(손으로 올리면 확정 이로치가 공짜). 형제 필드인 `trainer`·`missions`·`pendingRanked` 는
  같은 이유로 이미 서명돼 있었는데, 나중에 추가된 두 필드만 따라오지 않았다.
- **찾는 방법이 정해져 있다.** `SaveTransfer.canonicalString` 이 읽는 필드와 `CompanionState` 의 필드
  목록을 대조해 **보상·재화·1회성 플래그**인데 canonical 에 없는 것을 찾는다. 새 필드를 더할 때 묻는
  질문은 "이 값을 지우거나 올리면 뭔가를 다시 받을 수 있나" 다. 그렇다면 조건부 append 대상이다.
- **가드가 사는지는 "지우면 잡히나"로 검증한다.** 값을 올려 보는 테스트만 두면 집합형 필드에서
  **삭제** 방향을 놓친다(재지급은 삭제로 일어난다). `testDeletingAGymBadgeAfterSigningIsDetected` 가
  그 방향을 밟는다. `Set` 순회 순서는 실행마다 다르므로 canonical 은 반드시 정렬한다
  (`testGymBadgeSignatureDoesNotDependOnSetOrder`).
- **append 는 조건부여야 한다.** 무조건 붙이면 그 필드가 없던 시절의 정상 세이브가 전부 조작 판정돼
  진행이 초기화된다. 기본값 canonical 동결 테스트(`testDefaultStateCanonicalFormIsFrozen`)와
  `testDefaultStateGainsNoNewCanonicalSegments` 가 짝으로 지킨다.
- **조건부 append 는 "이전 배포에 없던 필드" 에만 통한다 — 그래서 `integrityVersion` 을 올린다.**
  없던 필드는 구세이브에서 항상 기본값이라 세그먼트가 안 붙어 구서명이 그대로 맞는다. 반면
  `gymBadges`·`shinyEggCharges` 는 **이미 배포된 필드**라 값이 든 정상 세이브에 세그먼트가 붙어
  구서명과 어긋난다 → 배지를 딴 사람 전원 초기화. 방어는 `integrityVersion` 상향뿐이다(낮은 버전은
  검사 면제, 다음 저장에서 갱신). canonical 을 건드릴 때 묻는 순서는 **①이 필드가 이전 배포에
  있었나 ②있었다면 버전을 올렸나** 다.
  `testASaveSignedBeforeTheCanonicalChangeIsNotJudgedTampered` 가 그 면제 분기를 직접 밟는다.
  (도감 완성 목표 작업 중 발견, 2026-08-21.)
- **필드를 canonical 에서 빼는 것도 같은 부류다 — 넣을 때만 버전을 올리는 게 아니다.** 돌봄을
  삭제하며 `care`·`care2`·`health`·`disc`·`sleep` 세그먼트가 사라지자, 돌봄 값이 든 **이미 배포된**
  세이브의 서명을 새 빌드가 재현할 수 없게 됐다 → 돌봄을 써 본 사용자 전원 조작 판정. 방향만 반대일
  뿐 `gymBadges` 와 같은 결함이라 방어도 같다(7 → 8). 묻는 순서에 한 줄을 더한다: **③이 필드를 뺐나.**
  **기억이 아니라 테스트로 막는다** — `testEveryConditionalCanonicalSegmentPrefixIsFrozen` 이
  조건부 세그먼트를 전부 켠 상태의 **접두 어휘**를 동결한다. 기존
  `testDefaultStateCanonicalFormIsFrozen` 은 기본값만 봐서 이 삭제를 한 건도 못 잡았다(조건부
  세그먼트는 기본값 canonical 에 애초에 없다). 값이 아니라 접두를 얼리는 이유는 값 fixture 의
  유지비가 가드값을 넘기 때문이다.
- **버전 리터럴을 박은 테스트는 남의 정당한 상향에 깨진다.** `AchievementTests` 가
  `XCTAssertEqual(SaveTransfer.integrityVersion, 7)` 로 "업적은 상향이 불필요했다"를 주장했는데,
  그 명제는 숫자가 아니라 **기본값 상태에 세그먼트가 안 붙는다**는 사실이다. 절대값을 박아 두면
  무관한 필드가 버전을 올릴 때마다 무관한 테스트가 빨개져, 진짜 회귀와 구분이 안 된다.
  단언은 주장하려는 사실을 직접 겨눈다(`canonicalString(CompanionState())` 에 `ach` 세그먼트 부재
  + 값이 들면 붙는 대조군). (돌봄·포켓몬 대화 제거 중 발견, 2026-08-25.)
- **수령 플래그가 없으면 "진행도를 읽는 필드" 전부가 멱등 가드다.** 도감 목표는 저장 필드 없이 차집합
  으로 지급해 가드가 단조성뿐인데, 진행도가 읽는 `DexEntry.isShiny`·`chainOrder`·`types` 는 서명 밖
  이었다(`dex` 줄은 `baseID:finalID:rarity`). 하나를 **내려** 적으면 진행도가 되감겨 다음 졸업이 같은
  보상을 재지급한다. 넣을 값은 원자 필드가 아니라 **파생 진행도 숫자**(`dg종|타입|이로치`) 다 —
  목표 id 를 넣으면 카탈로그 목표값 조정이 정상 세이브를 전부 조작 판정으로 만들어 밸런스 손잡이가
  세이브 파괴 손잡이가 된다. 세 방향(이로치 내리기·라인 자르기·타입 지우기)을 각각 밟는 테스트가
  `OneShotRewardSignatureTests` 에 있다.
- **"서명에 안 넣는다" 는 근거는 재검증한다.** `types` 를 뺀 이유로 적혀 있던 "백필이 저장하는 순간
  기존 서명이 무효가 된다" 는 성립하지 않았다 — 백필도 `save()` 를 지나며 재서명된다. 실제 제약은
  위의 배포 규칙 하나뿐이다. (2026-08-21.)
- **그 구멍은 막지 않는다 — 상한이 다른 문에서 정해진다.** `isTampered` 는 `integrityVersion` 이
  낮으면 검사를 면제하니 그 값을 낮게 써 넣으면 어떤 서명도 무력해진다. 그런데 **불러오기는 애초에
  무결성을 검사하지 않는다**(남의 세이브는 이 기기 서명을 가질 수 없다) — 같은 이득이 파일 선택 한
  번으로 늘 열려 있어 하한을 둬도 조작 상한은 그대로다. 반대로 하한을 세이브 밖(UserDefaults)에 두면
  다운그레이드 사용자의 정상 세이브를 초기화하는 오탐만 새로 생긴다. **막아서 얻는 건 없고 데이터
  손실 위험만 늘어** 그대로 뒀다 — 근거는 `testImportIsNotSubjectToTheIntegrityCheck`. 무결성 검사가
  막는 건 "로컬 파일 손편집" 이고 "작정한 치팅" 이 아니다. (2026-08-22.)

## 파생 진행도를 화면용 목록으로 계산하면 되감기는 부류

- **누적 진행도는 영구 기록(`state.dex`)에서만 센다.** 화면용 `dexEntries`·`dexSpecies` 는 활성·박스
  개체를 합성해 넣으므로(`livingDexEntries`) 알을 새로 사면 그 개체가 사라져 **진행도가 줄어든다.**
  진행도가 줄 수 있으면 "완료 집합의 차집합으로 1회 지급" 이 무너져 같은 목표가 두 번 지급된다.
- **저장하지 않는 진행도는 단조성이 계약이다.** 저장 필드 없이 파생값으로 지급을 판정할 때는 "이 값이
  줄어들 수 있는 경로가 있나"를 먼저 답한다. `testRaisedButUngraduatedPokemonDoNotCountTowardGoals`
  가 그 경로를 직접 밟는다(졸업 전 개체가 있어도 진행도 0).
- **네트워크 파생값은 `nil`(모름)과 `[]`(없음)을 구분한다.** `DexEntry.types` 를 오프라인 졸업에서
  `[]` 로 저장하면 백필이 "이미 아는 값" 으로 보고 영영 재시도하지 않아 그 개체의 타입이 영구 누락된다.
  `testGraduatingWithoutTypeDataStoresNilNotEmpty` 가 그 구분을 고정한다.
- **지급 기준과 표시 기준이 다르면 화면에 밝힌다.** 도감 헤더는 총계(키우는 개체 포함)와 목표 줄(졸업
  기록만)을 나란히 보여줘 "12종" 과 "종 9/10" 이 모순으로 읽혔다. 한쪽으로 통일하는 대신 갈라지는 몫을
  문구에 넣는다(`12종 (3 육성중)`) — 총계를 졸업 기준으로 내리면 격자 칸 수와 헤더가 어긋난다.
  `testDexHeaderTotalAccountsForRaisingSpecies` 가 `총계 − 육성중 = 종 진행도` 를 고정한다. (2026-08-21.)

## 표시용 캐시를 그대로 영구 저장하면 남의 값이 박히는 부류

- **화면 캐시에는 "누구의 값인가" 가 없다.** `currentTypes` 는 타입 배지용 캐시였고 개체가 바뀌어도
  (부화·박스 교체·불러오기·졸업) 리셋되는 곳은 `switchCompanion` 한 곳뿐이었다 — 표시는 다음 조회가
  고치니 무해했다. 그 값을 졸업이 `DexEntry.types` 로 **영구 저장**하기 시작한 순간, 오프라인 졸업
  한 번이 이전 종의 타입을 도감에 박고 `types != nil` 이라 백필도 재시도하지 않는다.
- **리셋 지점을 늘리지 말고 읽는 자리에서 막는다.** 개체 교체 경로는 계속 늘어나고 하나만 빠뜨리면
  결함이 그대로 돌아온다. 캐시에 소유자 태그를 달고(`loadedTypesSpeciesID`) 읽을 때 대조한다.
- **테스트가 못 걸른 이유는 조회 경로가 주입 불가였기 때문이다.** `PokeAPIClient.shared` 를 직접 부르면
  스텁이 끼어들 수 없어 테스트에서 그 값은 늘 비어 있다 — 결함 분기를 밟을 방법이 없다. 저장까지 가는
  조회는 `PokeProviding` 을 지나게 한다(기본 구현이 실 클라이언트라 기존 스텁은 안 깨진다).
- **소유자 태그가 있어도 대조 상대가 고정돼 있으면 새 읽는 자리에서 다시 샌다.** `currentTypes` 는
  `loadedTypesSpeciesID == currentSpeciesID` 로 활성 표시에는 안전했지만, 임의의 `MonState` 를 받는
  `chatProfile(for:)` 가 그대로 읽자 박스 개체에 활성 종의 타입·기술이 들어갔다. 태그 검사는
  "활성 개체에 최신인가"가 아니라 **"이번에 요청한 개체의 종인가"** 를 답해야 한다. 개체별 값은
  `MonState` 에서 읽고, 표시 캐시는 요청 종이 소유자와 일치할 때만 재사용한다.
- **프로필 리터럴 테스트는 조립 경로를 증명하지 않는다.** 기존 `PokemonChatTests` 는 완성된
  `PokemonChatProfile` fixture만 검증해 `CompanionStore.chatProfile(for:)` 의 잘못된 출처를 한 번도
  밟지 않았다. 활성 종 A의 캐시를 채운 뒤 다른 종 B를 요청하는 트리거와, 활성 개체·같은 종 박스 개체
  대조군을 함께 둬 "전부 비우기"도 막는다. (`PokemonChatTests`, 2026-08-23.)
  `DexEntryTypeSourceTests` 가 트리거(1단계 타입 적재 → 최종형 졸업)와 대조군을 함께 밟는다.
  (2026-08-21.)

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
- **"상한까지만 그리고 남은 수를 문구로 알린다"도 이 부류의 처방이 아니다.** 중첩 `ScrollView` 를
  걷어내며 상대 목록에 상한 5명 + "그 밖에 n명 더" 문구를 넣었는데, 여섯 번째 트레이너에게 신청할
  방법은 여전히 없었다. 높이를 260 에서 520 으로 늘렸을 때와 똑같은 실수다 — 잘리는 지점을 옮기든
  잘렸다고 알려 주든 마지막 하나에는 닿지 못한다. **잘렸다고 알려 주는 것과 끝까지 닿게 만드는 것은
  다른 일이다.** 게다가 그 문구는 "가까운 순으로 표시됩니다"라고 말했지만 `BattleNet` 은 이름순으로
  정렬하고 Bonjour 에는 거리 정보 자체가 없다 — 잘림을 변명하려다 거짓말까지 붙었다.
  처방은 이 부류가 원래 쓰던 페이지식 그대로고, 판정 기준도 "마지막 하나에 도달할 수 있나" 그대로다
  (`testEveryNearbyTrainerLandsOnSomePage`). 같은 부류를 훑다가 포켓슬론 릴레이 방 목록에도
  상한도 페이저도 없다는 걸 찾아 함께 고쳤다.
  (`BattleView.peerPageCount` · `PokeathlonView.roomPageCount`, 2026-08-20.)
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

- **Xcode 없는 머신에서는 테스트가 "실패"하지 않는다 — 아예 컴파일되지 않아 아무 신호가 없다.**
  Command Line Tools 만 있는 Mac 은 `swift test` 가 `no such module 'XCTest'` 로 멈춘다. 그래서 테스트가
  존재하지 않는 심볼을 부르고 있어도(파일명 `BattleNet.swift` 를 타입명으로 착각 — 실제 클래스는
  `BattleCenter`) 로컬에서는 초록도 빨강도 없고 PR CI 에서 처음 터진다. 그 부류로 CI 를 두 번 깨뜨렸다.
  영구 캡처는 `scripts/typecheck-tests.sh` 다 — XCTest 최소 스텁(단정은 빈 몸)을 만들고 테스트 소스를
  앱 소스와 한 모듈로 `swiftc -typecheck` 한다. **단정이 참인지는 검사하지 않는다**(테스트를 실행하는
  게 아니다) — 잡는 것은 "부르는 심볼이 실재하는가" 하나이고, 그게 이 환경에서 유일하게 못 보던 것이다.
  스텁을 쓸 때 실제 XCTest 시그니처와 다르면 없던 에러가 생긴다: `XCTFail` 은 `Void` 를 돌려줘야 하고
  (`return XCTFail(...)` 관용구가 이미 쓰인다), `XCTestExpectation` 은 `Sendable` 이어야 하며,
  `import XCTest` 를 지울 때 그 자리에 `Foundation`·`SwiftUI`·`AppKit` 을 넣어야 한다 —
  테스트들이 `URL`·`FileManager` 를 XCTest 가 끌어오는 것에 얹혀 쓰고 있다.
  (#79 퍼즐 던전 작업 중 도입, 2026-08-21.)
  **이 스크립트가 못 잡는 것도 적어 둔다** — 타입체크는 "심볼이 있나" 만 본다. `CompanionState` 에
  필드를 더할 때 `SaveTransferTests.testEveryCompanionStateFieldIsClassifiedForTransfer` 가 요구하는
  **분류**(진행 / 로컬 장부 / 계정 원장 / 기기 환경설정)는 단정이라 CI 에서만 걸린다. 새 필드를 넣었으면
  그 테스트의 목록과 `SaveTransfer.rebasedForThisDevice` 를 같이 손대야 한다 — 던전 진행도가 그 예로,
  날짜 키가 로컬 날짜 문자열이라 계정 원장이고 **같은 날이면 정산 플래그를 OR 로 합쳐야** 한다
  (맥 A 에서 클리어해 내보낸 세이브를 아직 안 푼 맥 B 로 불러오면 같은 날 보상이 두 번 나간다).

- **로컬 Swift 가 CI 보다 앞서면 로컬 초록은 CI 초록의 근거가 아니다 — 신형이 *더 적게* 잡는다.**
  개발 Mac 은 Xcode 26 / Swift 6.3, CI 러너 `macos-15` 는 Swift 6.1.2 다. 6.3 이 통과시키는 두 부류를
  6.1.2 는 **에러로** 막는다: (1) non-Sendable 타입의 `static let` (`[MemoryHomeRoomStyle: [ItemKind:
  NSImage]]`) 은 "concurrency-safe 하지 않다"로 거부되고, (2) 튜플 산술을 한 식에 몰아 넣은 클로저
  (`(0..<48).map { ($0 % 8, $0 / 8) }.sorted { abs(…)+abs(…) < abs(…)+abs(…) }`) 는 타입 체커 시간
  초과로 죽는다. PR #161 이 이 둘로 `swift build` 에서 에러 4건을 냈는데 **같은 커밋이 로컬에선 18초에
  초록**이었다. warning 게이트로는 못 본다 — warning 이 아니라 컴파일 에러이고, 로컬 컴파일러는 애초에
  진단을 만들지 않는다.
- **그 처방이 반대 방향으로 게이트를 깨는 것까지가 이 부류다.** 컴파일러가 권하는 첫 수는
  `nonisolated(unsafe)` 인데(6.1.2 통과, 선례 `CrashReporter.logFD`), macOS 26 SDK 에선 `NSImage` 가
  이미 `Sendable` 이라 6.3 이 "불필요한 표시" warning 3건을 낸다 → **로컬 `test-gate.sh` 가 빨강**이 된다.
  한 툴체인만 보고 고르면 다른 쪽이 깨진다. 양쪽 다 조용한 선택은 `@MainActor` 다 — 6.1.2 는
  격리를 인정하고 6.3 은 잉여 표시로 보지 않는다. 방을 그리는 곳은 전부 SwiftUI 뷰라 비용도 없다.
  딸린 대가 둘: 테스트 클래스에 `@MainActor` 가 필요하고(`MemoryHomePixelArtTests`), 중첩 구조체의
  암묵적 memberwise `init` 은 메인 액터가 아니라서 **기본값이 부르는 함수는 `nonisolated`** 여야 한다
  (`Palette.sky` → `skyRamp`, 이걸 빼먹으면 "main actor-isolated default value in a nonisolated context").
- **이 부류는 CI 가 유일한 심판이다.** 로컬에 Xcode 26 하나뿐이면 6.1.2 를 재현할 수단이 없다. 게다가
  6.1.2 는 첫 에러 묶음 뒤 emit-module 에서 멈추므로 **한 번 고쳐도 남은 에러는 다음 런에서 처음
  드러난다** — 한 번에 다 나올 거라 가정하지 않는다. 부류 스윕은 PR 변경 파일의 `static let` 전수
  확인으로 대신했다(나머지는 전부 값 타입이라 안전). 툴체인 격차 자체를 없애려면 러너를 `macos-26`
  으로 올리면 되지만, 같은 러너가 `publish-development` 에서 배포 앱을 서명·빌드하므로 배포 표면이
  같이 바뀐다 — 별도 판단 사항으로 남긴다. (2026-08-30, PR #161.)

## 호스트 로케일이 테스트 기대값에 새는 부류 (로컬 초록 / CI 빨강)

- **새 세이브의 언어는 `AppLanguage.systemDefault` 라 호스트 로케일을 따라간다.** 개발 Mac 은
  `ko-KR`, GitHub 러너는 영어다. 그래서 실 `CompanionStore` 를 만들어 한국어 이름을 기대하는 테스트는
  **로컬에서만** 통과한다. #107 의 `PokemonChatTests` 두 개가 그랬다 — `profile.types` 가 로컬에선
  `["전기"]`, CI 에선 `["Electric"]` 이었다. 리터럴 fixture(`PokemonChatProfile.fixture`)는 `language`
  를 직접 받아 안전하고, **스토어를 통과하는 순간부터** 로케일에 딸려간다.
- **같은 파일의 다른 단언이 통과한 것이 false confidence 였다.** `mon()`·`move()` 픽스처가
  `["ko": 같은값, "en": 같은값]` 이라 이름 단언은 어느 로케일에서도 통과했다 — 기술 이름을 `.ko` 로
  비교하는 테스트가 바로 옆에 있는데도 신호가 없었다.
- **처방은 스토어 생성 직후 언어를 못 박는 것이다** (`store.setLanguage(.ko)`). 기대값을
  `store.language` 로 바꾸면 로케일 독립이 되지만 "요청 언어의 이름이 실렸는가"를 더 이상 묻지 않는다.
- **영구 캡처는 기억이 아니라 게이트다.** `test-gate.sh` 가 `swift test` 뒤에 같은 `.xctest` 번들을
  `xcrun xctest -AppleLanguages "(en-US)" -XCTest All` 로 한 번 더 돌린다(≈9초). `swift test` 는
  테스트 바이너리에 인자를 넘기지 못해서 이 경로를 쓴다. 계측 바이너리가 저장소 루트에
  `default.profraw` 를 떨구지 않도록 `LLVM_PROFILE_FILE` 을 임시 경로로 돌려 커버리지 산출물과 분리한다.
  가드 검증: `setLanguage(.ko)` 를 주석 처리하니 게이트가 CI 와 **같은 두 실패**로 죽었다.
  (`scripts/test-gate.sh`, 2026-08-23.)

## 가드가 중복이라 하나를 지워도 아무 테스트가 안 깨지는 부류

- **결함을 주입했는데 전부 초록이면, 가드가 튼튼한 게 아니라 중복이라는 뜻일 수 있다.**
  `applySecondaryEffect` 는 상태를 걸 수 있는지 본 뒤에 확률을 굴린다. 그 앞 검사를 통째로 지워도
  테스트가 하나도 안 깨졌다 — `inflict` 가 어차피 한 번 더 거르니 **결과값이 안 바뀐다.**
  바뀌는 것은 rng 소비량이다. 못 걸 상대에게 판정을 한 번 굴리면 그 뒤의 모든 난수가
  한 칸씩 밀린다.
- **관측 대상이 값이 아니라 rng 스트림이면, 스트림을 직접 본다.** 이 저장소에서 소비 순서는
  프로토콜이다(`BattleModel.resolveAttack` 주석). 그래서 "면역 상대를 때린 뒤의 rng 상태" 와
  "상태를 안 거는 기술로 때린 뒤의 rng 상태" 를 비교하고, 걸 수 있는 상대로 대조군을 둔다
  (`testSecondaryEffectSpendsNoRollOnATargetThatCannotBeAfflicted`).
- **중복 가드를 지우는 쪽이 답인지 먼저 따진다.** 여기서는 앞 검사를 남겼다 — 굴리고 버리는 쪽은
  나중에 자격 판정이 비대칭이 되는 순간 desync 가 되고, 그때는 원인을 찾기 훨씬 어렵다.
- **결함 주입은 "안 깨졌다" 로 끝내지 않는다.** 안 깨진 이유를 한 번 답해야 한다. 답이
  "결과가 같아서" 라면 그 가드가 지키는 진짜 관측 대상을 아직 테스트하지 않은 것이다.
  (상태이상 2차효과, 2026-08-20.)
- **같은 상한을 두 표현이 각각 들면 서로를 가린다.** 대화 도구 루프가 `for round in 0...maxToolRounds`
  와 `guard round < maxToolRounds` 를 둘 다 들고 있었다. 어느 쪽을 넓혀도 다른 쪽이 먼저 걸려
  **프로바이더 호출 수가 안 바뀐다** — 주입 두 번이 모두 초록이었다. 숫자를 하나만 두고 나머지를
  거기서 파생시킨다(`let rounds = 0...maxToolRounds` + `guard round != rounds.upperBound`).
  그러면 두 가드가 각각 다른 테스트를 빨갛게 만든다: 범위는 "왕복 상한", upperBound 판정은
  "결과를 전할 턴이 없으면 실행하지 않는다". 두 성질이 다르면 **숫자도 파생 관계여야 한다** —
  같은 값을 두 번 적는 순간 둘 중 하나는 죽은 가드다. (포켓몬 대화 도구, 2026-08-25.)

## 같은 기전을 한 모드에서만 고치는 부류

- **1v1 을 고치고 멀티를 안 고쳐도 1v1 테스트는 전부 초록이다.** 마비 스피드 25% 를
  `BattleSide.effectiveSpeed` 로 넣고 1v1 순서 계산에 배선했다. 멀티의 정렬 비교자
  (`MultiplayerBattle.resolveRound`)를 `stats.spe` 로 되돌리는 결함을 주입했더니 **아무 테스트도
  걸리지 않았다.** 같은 화상이 방에서는 아무 일도 하지 않는 것도 마찬가지였다.
- **모드가 셋이면 기전 회귀 테스트도 모드별로 있어야 한다.** 배틀 상태를 `BattleSide` 하나로 모은 게
  Phase 0 이었지만, 상태를 *공유한다*는 것과 세 모드가 그 값을 *읽는다*는 것은 다른 문제다.
  공유 접근자만 테스트하면 호출부가 옛 필드를 그대로 읽고 있어도 통과한다.
- **확률 tie-break 에 기대는 테스트는 결함을 놓친다.** 처음엔 스피드 동률 두 명에 마비를 걸고
  "20개 seed 에서 늘 마비 안 된 쪽이 선공" 으로 썼는데, 결함을 주입해도 통과했다. 마비된 쪽에 **확실히
  더 빠른 스피드**를 줘서 순서가 결정적으로 뒤집히게 고친 뒤에야 걸렸다
  (`testParalysisSlowsTheAttackerInMultiplayerToo`).
- **한계도 적어 둔다** — 인접한 두 줄(`leftSpeed`/`rightSpeed`) 중 **하나만** 되돌리는 결함은 여전히
  빠져나간다. 원소가 둘인 정렬에서 Swift 는 비교자를 한 번만 부르고, 그 한 번이 멀쩡한 쪽을 읽을 수
  있기 때문이다. 둘 다 안 고치는, 실제로 일어날 법한 결함은 잡힌다.
  (상태이상 마비·잔뎀의 멀티 배선, 2026-08-20.)
- **한 모드에만 넣은 UI 예외는 다른 모드에서 조작 불가로 나타난다.** 발버둥 버튼을 1v1
  (`BattleArenaView`)에만 넣어서, 멀티는 PP 가 전부 마르면 네 칸이 다 비활성인 채 마감(30초)까지
  아무것도 할 수 없었다. 로그 칸도 멀티만 고정 높이·`lineLimit` 이 없어 긴 줄이 버튼을 밀어냈다 —
  같은 칸은 **한 뷰(`BattleLogBox`)로 공유**한다.
- **volatile 상태는 물러날 때 지운다.** 교체에서 맹독 강등만 처리하고 혼란(`confusionTurns`)을
  남겨 둬, 다시 나온 포켓몬이 옛 카운터로 계속 혼란이었다. 한 지점(`switchMine`)에서 주 상태와
  volatile 을 **같이** 본다.
- **같은 커밋에서 그 파일을 만졌는데도 스윕에서 빠진다.** `bee4a84` 가 LAN 프레임 길이 헤더의
  `load(as:)` → `loadUnaligned(as:)` 를 `BattleNet`·`MultiplayerRoomCenter` 두 곳에서 고쳤는데,
  **같은 커밋이 다른 이유로 편집한** `MemoryHomeVisitCenter` 는 그대로 남았다(그 파일이 이 브랜치에서
  새로 생긴 네 번째 프레이머였다). "고친 파일 목록" 과 "그 부류가 사는 파일 목록" 은 다르다 —
  부류 스윕은 반드시 **grep 으로 전수**한다. 고친 두 곳을 보고 "이 브랜치는 정리됐다" 고 믿은 게 원인.
- **왜 테스트가 못 걸렀나**: ① 이 줄을 밟으려면 살아 있는 `NWConnection` 두 개가 필요하고
  ② 정렬 검사가 `_debugPrecondition` 이라 릴리스 arm64 는 대개 그냥 통과한다 ③ 라인 커버리지로도
  구별이 안 된다 — 테스트가 그 줄을 실행하면 `load` 든 `loadUnaligned` 든 똑같이 세어진다.
  **영구 캡처**: `test-gate.sh` 의 **비정렬 로드 스윕** — `Sources` 에 `.load(as:` 가 하나라도 있으면
  실패한다(주석 줄은 제외 — 규칙을 설명한 주석에 가드가 걸리는 부류를 피한다).
  (`MemoryHomeVisitCenter`·`scripts/test-gate.sh`, 2026-08-29.)

## 회수를 성공 분기에만 걸어 두는 부류 (끝나는 길은 하나가 아니다)

- **증상**: `MemoryHomeVisitCenter` 가 받아들인 연결을 `connections` 에 넣고 **성공 분기에서만**
  뺐다. 거절(프로토콜 불일치·이름 불량·비공개 전환·동행 없음·차단된 피어)과 프레임 읽기 실패 네
  갈래는 `cancel()` 만 하고 딕셔너리 항목을 남겼다. 공개 호스트는 앱이 사는 내내 듣고 있으므로
  거절 한 번마다 항목이 하나씩 영구히 쌓였다.
- **원인**: 회수 규칙이 **호출부마다** 흩어져 있었다. 끝나는 길이 다섯인데 그중 하나에만 적어 뒀으니
  나머지 넷이 샌 것이고, 길을 하나 더 만들면 또 샌다. 처방은 종료 회수를 연결 자신의
  `stateUpdateHandler` **한 곳**에 두는 것이다(`track(_:key:whenReady:)`) — `.cancelled`/`.failed` 는
  모든 종료 경로가 반드시 지나가는 지점이다. 호출부의 수동 `removeValue` 두 곳은 지웠다: 규칙이
  두 곳에 있으면 다시 갈라진다.
- **왜 테스트가 못 걸렀나**: `connections` 가 `private` 이라 "새는지" 를 관측할 창이 아예 없었다.
  `valid(_:)` 를 `private` 로 두지 않은 것과 같은 이유로 `trackedConnectionCount`(파생값이라 상태가
  갈라지지 않는다)를 열었다.
- **테스트를 쓰다 만난 함정 둘 — 둘 다 "빨간불인데 아무것도 안 밟은" 부류다.**
  ① **죽은 포트로는 검증되지 않는다.** `NWConnection` 은 거부당하면 `.failed` 가 아니라 `.waiting`
  으로 **재시도하며 머문다**(살아 있으므로 계속 추적하는 게 맞다). 죽은 포트 테스트는 수정이 들어간
  뒤에도 계속 빨간불이라, 하마터면 멀쩡한 수정을 되돌릴 뻔했다.
  ② **`NWListener.port` 는 준비 전엔 `nil` 이 아니라 `0`(`.any`) 이다.** `port == nil` 로만 폴링하면
  0번 포트로 붙으러 가 `EADDRNOTAVAIL(49)` 로 끝난다 — 테스트는 실패하지만 **검증하려던 경로는 한 번도
  안 밟는다**. `rawValue != 0` 까지 봐야 한다. 상태 핸들러에 임시 print 를 넣어 `waiting(49)` 를
  직접 보고서야 알았다 — 실패 메시지만 읽었으면 엉뚱한 곳을 고쳤다.
- **가드 검증**: 회수 두 줄을 `break` 로 주입하니 테스트가 빨간불(1 ≠ 0), 되돌리니 초록.
  주입 시 5.4초(폴링 소진) → 정상 0.22초라 **걸린 시간 자체가 신호**다.
  (`MemoryHomeVisitCenter`·`MemoryHomeR4CardTests`, 2026-08-29.)

## 신뢰경계 검증기가 자기가 말한 필드를 다 안 보는 부류

- **증상**: `MemoryHomeVisitCenter.valid(_:)` 는 "신뢰경계 클램프" 라고 주석까지 달려 있는데,
  `placedDecor` 는 12개로 자르면서 `showcaseFurniture` 는 **개수 상한이 없었다**. 원소가 전부 진짜
  가구여도 통과하므로, 16KB 프레임에 들어가는 ~1000개를 보내면 방문 시트가 그걸 `ForEach` 로 한 줄에
  전부 그린다. 사진의 스타일 문자열 넷(`frame`·`background`·`composition`·`trainerStyle`)도 길이가
  열려 있었다.
- **주입 위험은 없었다 — 과장하지 않는다.** 네 문자열은 렌더에서 알려진 리터럴과만 비교되고 나머지는
  기본값으로 떨어진다(`StickerPhotoFrame(rawValue:) ?? .heart`, `background == "forest" ? … : 기본`).
  화면에 텍스트로 찍히는 건 `caption` 뿐이고 그건 이미 60자로 잘렸다. 남는 문제는 길이뿐이다.
  리뷰가 "주입 위험" 으로 올린 걸 **렌더 경로를 직접 따라가 확인한 뒤** 등급을 내렸다.
- **왜 못 걸렀나**: 이 검증기의 **부정 테스트가 `profileMessage` 하나뿐**이었다. 나머지 필드는 "통과하는
  카드" 로만 확인돼서, 상한을 통째로 지워도 깨지는 테스트가 없었다. 부정 검증이 없는 가드는 없는 가드다.
- **영구 캡처**: 필드별 부정 테스트 6종(`testValidRejects…`). 그중 둘(진열장 개수·스타일 문자열 길이)은
  **작성 시점에 빨간불**이었고 나머지 넷은 초록이었다 — 그 대비가 "무엇이 진짜 공백이었나" 를 그대로
  보여 준다.
  (`MemoryHomeVisitCenter`·`MemoryHomeR4CardTests`, 2026-08-29.)

## 라인 커버리지 99%인데 새 분기가 한 번도 안 돈 부류 (재확인)

- **`BattleModel.swift` 는 라인 99.25%였고, 그 안에서 새 분기 넷이 `^0` 이었다.**
  `Status.init(ailment:)` 의 paralysis·freeze·confusion 갈래(JSON 테스트가 burn 만 썼다)와
  혼란 자멸로 쓰러지는 갈래(자멸은 관측했지만 HP 가 넉넉해 한 번도 안 죽었다)다.
  게이트 숫자로는 어느 쪽도 드러나지 않는다 — 이미 이 문서에 있는 규칙이지만, 커버리지가 높을수록
  오히려 확인을 건너뛰기 쉬우니 다시 적어 둔다.
- **처방은 매번 같다** — 새 조건 분기를 넣었으면
  `xcrun llvm-cov show <bin> -instr-profile=<profdata> <file> --show-regions | grep '\^0'` 를 직접 본다.
  `init?(ailment:)` 같은 표 형태 매핑은 갈래 하나가 아니라 **전 갈래를 도는 테스트**로 덮는다.
  (상태이상, 2026-08-20.)
- **뷰 안의 `private` 분기표는 화면에 뜬 갈래만 실행된다.** `StatusBadge` 의 `tint` 는 7갈래인데 그중
  여섯이 `^0` 이었다 — 배지를 그리는 테스트가 화상 하나만 띄웠기 때문이다. 처방은 표를 **뷰 밖으로**
  빼는 것이다(`Status.badgeTint`). 그러면 전 갈래를 도는 테스트가 가능해진다. 뷰 안에 두면
  "그 색을 쓰는 화면을 렌더하는 테스트"가 색마다 하나씩 필요해진다. (배틀 필드, 2026-08-20.)
- **표본이 평온하면 분기를 밟지 않는다.** 예산 검증의 표본이 상태 없음·이로치 아님·PP 넉넉함이면
  상태 배지·별표·PP 경고·발버둥·기절 갈래가 전부 `^0` 으로 남는다. 레이아웃 표본은 **최악 케이스로
  채운다** — 배지 두 개, 이로치, 기절 슬롯, 양쪽 actor 의 로그, PP 전소진, 만료된 마감까지.
  (배틀 필드, 2026-08-20.)

## 고정 높이 칸은 넘친 내용을 숨기지 않는다 (보고 높이 ≠ 그리는 높이)

- **`frame(height:)` 는 *보고하는* 높이만 고정한다.** 내용이 넘치면 칸 밖에 그려지고, 아래 이웃 위에
  겹친다. 그래서 `sizeThatFits` 기반 예산 검증은 **줄 수를 열 배로 늘려도 전부 통과한다** — 실제로
  로그를 4줄에서 40줄로 주입했을 때 아무 테스트도 실패하지 않았다. 겹치는 대상이 기술 버튼이라
  증상은 "후반 턴에 조작이 사라진다"가 된다.
- **처방 두 겹.** ① 칸이 자기가 그리는 줄 수를 담는지 **산수로** 검증한다(1줄 실측 높이 × 줄 수 +
  줄간격 + 패딩 ≤ 칸 높이). 대조군(예: 40줄)을 같은 테스트에 넣어야 "지금 값이 우연히 맞았을 뿐"
  인지 구별된다. ② 그 위에 `.clipped()` 를 둬서 가드를 넘어선 경우에도 조작을 가리지 않게 한다.
  이 가드는 넣자마자 커밋된 값에서 실패했다 — 9pt 4줄은 60pt 가 필요한데 칸이 58pt 였다.
  (배틀 로그 칸, 2026-08-20.)

## `GeometryReader` 안의 계산은 측정 패스에서 실행되지 않는다

- **`sizeThatFits` 는 `GeometryReader` 의 클로저를 부르지 않는다.** 실제 레이아웃에만 돈다. 그래서
  그 안에서 쓰는 계산(HP바 비율의 0 나눗셈 가드)은 **그 케이스를 그리는 테스트를 추가해도**
  `--show-regions` 에서 미실행으로 남는다. 뷰 안의 `private` 분기표와 같은 부류의 사각지대인데,
  이쪽은 "렌더 테스트를 추가하면 된다"는 처방이 통하지 않아 더 조용하다.
- **처방**: 계산을 뷰 밖 순수 함수로 뺀다(`HPReadout.ratio`). 그러면 0 나눗셈·클램프를 직접 검증할
  수 있다. NaN 프레임 폭은 SwiftUI 레이아웃을 통째로 무너뜨리므로 이 가드는 실패 비용이 크다.
  (`CombatantBar`, 2026-08-20.)

## 소스 스캔 가드가 규칙을 설명한 주석에 걸리는 부류

- **금지 심볼을 파일 전문 `contains` 로 찾으면 그 규칙을 문서화한 주석이 먼저 걸린다.**
  "배틀 화면에 중첩 `ScrollView` 금지"를 기계로 막으려고 소스에서 `ScrollView` 를 찾았더니, 규칙을
  설명하는 주석 두 곳이 잡혀 방금 통과한 코드가 실패했다. 가드가 사실상 "이 규칙을 적어 두지 말라"가
  된다.
- **처방**: 주석을 벗기고 **구성 형태**(`ScrollView {` / `ScrollView(`)로 본다. 금지 심볼 가드를 새로
  쓸 때마다 같은 문제가 생기므로, 판정 전에 주석 제거 단계를 넣는 것을 기본으로 둔다.
  (`BattleFieldTests.testTheBattleFieldSourceHasNoScrollView`, 2026-08-20.)
- **같은 부류가 커버리지 감사에서도 났다.** 미실행 리전 표시(캐럿 + 0)를 설명하는 주석에 그 표시를
  그대로 적었더니, `--show-regions | grep` 이 주석을 리전으로 세어 "미실행 4개"로 보고했다.
  실제로는 3개였다. **감사 스크립트가 grep 하는 문자열은 주석에 적지 않는다** — 말로 적는다.
  (2026-08-20.)
- **가드를 넓히면 기존 위반이 먼저 나온다 — 그게 정상이고, 고칠 것은 코드다.** 스캔 대상을
  `BattleView.swift` 까지 넓힌 순간, 이 브랜치와 무관한 위반이 드러났다: 상대 목록이 팝오버 본체
  `ScrollView` 안에서 또 `ScrollView` + `maxHeight: 180` 을 써서 여섯 번째 트레이너부터 신청할
  방법이 없었다. defect-log 가 `BattleView` 를 "그 부류 미검증 후보"로 적어 둔 그 자리다 —
  후보로만 남겨 두면 아무도 확인하지 않으므로, 가드를 넓히는 쪽이 목록을 늘리는 쪽보다 낫다.
  처방은 스크롤을 지우고 상한까지만 그린 뒤 넘치는 수를 문구로 알리는 것(도감 페이저의 축소판).
  (2026-08-20.)

## 자리를 차지한다고 그린 건 아닌 부류 (레이아웃 예산 ≠ 화면 확인)

- **`sizeThatFits` 검증은 전부 "얼마나 넓고 높은가"만 본다.** 아무것도 그리지 않는 뷰, 색이 하나뿐인
  뷰, 콘텐츠가 죽은 여백에 밀린 뷰가 모두 통과한다. 실제로 겪은 것: 필드 + 선택 패널이 409pt 인데
  창이 460pt 라, 호스팅 뷰가 콘텐츠를 세로 중앙에 놓아 헤더 위에 25pt 죽은 띠가 생겼다. 예산
  검증(≤ 460)은 당연히 통과했고, 오프스크린 래스터를 **눈으로 봐야** 드러났다.
- **처방 두 가지.** ① 고정 크기 컨테이너는 남는 자리를 어디로 보낼지 정한다(`alignment: .top`) —
  가운데 정렬은 슬랙을 위아래로 반씩 갈라 위쪽 여백을 만든다. ② 뷰를 한 번 래스터화해 **표본 색이
  여러 개인지** 검사하는 테스트를 둔다(`testTheArenaActuallyRastersSomethingRatherThanABlankBox`).
  `NSView.cacheDisplay(in:to:)` 면 창을 띄우지 않고도 찍히며, `KMON_SNAPSHOT_DIR` 이 있으면 PNG 로
  떨어뜨려 사람이 그대로 확인할 수 있다 — 라이브 대전을 잡지 않고도 "화면 1회 확인"이 성립한다.
  (배틀 필드, 2026-08-20.)

## 진행도 숫자로 "새 스트림"을 가르는 부류 (0 과 0 은 구별되지 않는다)

- **"짧아졌으면 새것"은 아직 아무것도 소비하지 않은 순간에 무너진다.** 배틀 재생기가 새 배틀을
  `events.count < playedCount` 로 판정했는데, 다음 배틀이 시작되는 시점엔 둘 다 0 이라 갈아타지
  못했다 — 새 배틀의 만피 대신 **이전 배틀의 HP** 가 첫 데미지가 들어올 때까지 화면에 남는다.
  처방은 경계를 숫자가 아니라 뜻으로 읽는 것이다: **빈 스트림은 언제나 새 스트림이다**(따라잡을
  것이 없으니 원본 값이 곧 화면 값이다). (`BattleAnimator.sync`, 2026-08-20.)
- **먼저 쓴 테스트가 결함 지점을 우회했다.** 같은 "새 배틀"을 검증하는 테스트가 이미 있었지만,
  그 테스트는 `.off`(즉시 소진)로 재생을 먼저 비워 `playedCount` 가 4 인 상태에서 갈아탔다 —
  `0 < 4` 라 통과한다. 결함은 **재생이 시작되기 전(0)** 에만 난다. 상태 전이를 검증할 때는 전이
  시점의 **진행도까지** 케이스로 나눈다(아직 0 / 진행 중 / 다 끝남). (2026-08-20.)
- **취소 가드도 같은 이유로 한 번도 안 돌 수 있다.** 재생을 끊는 테스트가 태스크가 **시작되기 전에**
  끊어서, 루프 안의 `Task.isCancelled` 분기가 `--show-regions` 에서 `^0` 으로 남았다(정작 위험한
  것은 이미 뽑아 둔 스텝이 살아남아 뒤늦게 값을 덮는 경우다). 비동기 취소를 검증할 땐 **재생
  한가운데임을 먼저 단언한 뒤** 끊는다. (`BattleAnimatorTests`, 2026-08-20.)

- **묶음 경계에서만 자르는 테스트는 알갱이 크기를 못 잡는다.** LAN 로그가 턴 배치로 접힌 뒤
  재생 진행도(평평한 이벤트 수)로 자르게 됐는데, 검증을 **첫 배치의 끝**에서만 해서 "배치 단위로
  자르는" 잘못된 구현도 통과했다(경계에서는 두 방식의 결과가 같다). 결함을 일부러 주입해 보고서야
  드러났다. 묶음 위에서 평평한 개수로 자를 땐 **경계 안쪽**(진행도 1)도 케이스로 넣고, 평평한
  스트림이 묶음들을 이어 붙인 것과 같다는 불변식도 같이 단언한다.
  (`BattleLogSource.netBattle`, 2026-08-21.)

## 잠갔는데 잠긴 것처럼 안 보이는 부류

- **`.disabled(true)` 는 `.buttonStyle(.plain)` + 직접 그린 배경을 흐리게 만들지 않는다.** 재생 중
  기술 4칸을 잠갔는데 타입색이 그대로라, 눌러 보고서야 잠긴 걸 알 수 있었다(PP 가 마른 칸만
  흐렸다). 자리·높이 예산 테스트는 전부 통과한다 — 잠금은 크기가 아니라 **색**이라서다. 처방은
  잠금 상태를 배경 불투명도에 같이 태우고(`isEnabled && tier.isSelectable`), 오프스크린 래스터를
  PNG 로 떨어뜨려 두 상태를 눈으로 비교하는 것이다(`KMON_SNAPSHOT_DIR`). (`MoveGridView`, 2026-08-20.)

- **잠금을 흐리게 그리는 책임은 잠금을 아는 컴포넌트에 둔다.** 같은 부류를 스윕할 때 `MoveGridView`
  는 안에서(`isEnabled && tier.isSelectable`) 처방했는데 `SwitchStripView` 는 **호출부에서**
  `.opacity(acceptsInput ? 1 : 0.45)` 로 처방했다 — 컴포넌트를 다른 화면에서 한 번 더 쓰는 순간
  그 화면은 잠긴 줄이 안 흐리다. 처방은 컴포넌트 안으로 내리는 것이다. (`SwitchStripView`, 2026-08-21.)

## 즉시 소진 경로가 돌고 있는 재생을 안 끊는 부류

- **"기다림 없이 전부 적용" 은 이미 뜬 타이머를 끄는 것까지가 처방이다.** 재생 중에 속도가 `.off`
  로 바뀌면(설정 변경·저전력 진입) `drain()` 이 남은 스텝을 즉시 적용하고 끝냈는데, 돌고 있던
  `play()` 태스크를 끊지 않아 이미 뽑아 둔 스텝이 뒤늦게 살아났다 — ① `isPlaying` 이 다시 켜져
  **끄기인데 입력이 잠기고** ② 옛 HP 가 최종값을 덮고 ③ `playedCount` 가 스트림 길이를 넘어(4 →
  6) 다음 턴 이벤트가 HP 투영에서 조용히 빠졌다. `seed()` 에는 `task?.cancel()` 이 있고 `drain()`
  에만 없었다 — **상태를 종점으로 밀어 놓는 경로는 전부 같은 취소를 지나야 한다.**
  회귀는 재생 한가운데임을 폴링으로 단언한 뒤 `.off` 로 갈아타 잡는다
  (`testSwitchingToOffMidPlaybackDoesNotLetTheOldStepsComeBack`, 2026-08-21.)
- **끄기 설정은 값만 끄고 보간을 남기면 끈 게 아니다.** HP바에 `.animation(.easeOut(0.4), value:
  side.hp)` 를 상시로 걸어, 재생을 끄거나 저전력이어도 바는 0.4초 흘렀다. 끄기가 있는 이유가
  저전력·접근성이라 "안 움직이는 화면" 이 약속인데, 값 경로만 끄고 애니메이션 modifier 를 그대로
  두면 그 약속이 깨진다. 처방은 보간 자체를 재생 상태에 태우는 것(`animatesHP: overlay.isPlaying`).
  (`CombatantBar`, 2026-08-21.)

## 표시 상태가 "누구의" 상태인지 모르는 부류

- **actor 키만으로 든 표시 상태는 개체가 바뀌는 턴에 엉뚱한 개체를 그린다.** 재생기가 표시 HP 를
  `[BattleActor: Int]` 로 들었더니, 기절 자동 출전 턴에 엔진이 활성 칸을 다음 개체로 넘긴 뒤 그
  개체의 바를 **이전 개체의 HP** 로 깎아 그렸다(만피 121 이 25 → 0 으로 내려가고, `isAlive`
  가 false 라 흐린 '쓰러진' 스프라이트까지 붙었다). 재생이 끝나면 `reconcile()` 이 스냅하면서
  정상 동작인데도 매 교체·기절 턴마다 결함 로그를 쌓았다 — **경고가 정상 동작에서 울리기 시작하면
  진짜 어긋남이 묻힌다.** 처방은 두 갈래다: ① 표시 상태가 **팀과 활성 칸까지** 들고(`ReplaySide`),
  ② 개체 전환을 **스트림의 이벤트로** 만들어(`BattleEvent.sendOut(actor, teamIndex:)`) 재생기가
  그 시점에 갈아타게 한다. 활성 칸이 이벤트에 없으면 재생기는 "언제 갈아타야 하는지" 를 알 방법이
  없다. (`BattleAnimator`, 2026-08-21.)
- **들어오는 개체의 상태를 엔진의 최종 팀에서 읽으면 결과가 샌다.** 자기 교체 턴에 `.sendOut` 을
  보고 `engineTeam[index]` 를 그대로 화면에 올리면, 그 개체가 **그 턴에 맞은 데미지까지 이미
  반영된** 값이라 출전과 동시에 바가 깎여 있고 이어지는 `.damage` 스텝이 한 번 더 들어간다.
  표시용 팀을 재생기가 따로 들고 있으면(벤치 개체는 그 턴에 바뀌지 않으므로) **지난 배치 끝의 값이
  곧 출전 시점의 값**이다. (`BattleReplay.apply`, 2026-08-21.)
- **미룬 값과 안 미룬 값을 섞으면 미룬 쪽이 무의미해진다.** HP·로그만 재생 진행도로 미루고 상태
  배지·PP·기절 흐림은 엔진 최종값을 그려서, 화상 배지가 재생 첫 프레임부터 떠 있고 쓴 기술 PP 는
  이미 줄어 있었다 — 로그가 결과를 먼저 알려 주는 것과 똑같은 결함이다. 다만 처방이 "이벤트로
  상태를 재구성" 은 아니다(엔진 규칙이 두 벌이 되고 `statusCounter` 처럼 이벤트만 보고는 알 수
  없는 값이 있다). **미는 것은 HP·활성 칸뿐, 나머지는 배치가 끝날 때 엔진 값으로 한 번에 스냅**
  하고, 그래서 `reconcile()` 의 비교 대상도 HP 로 좁힌다. (`ReplayStep.sides`, 2026-08-21.)

## 상태 전이가 같은 동기 블록에 있어 중간 상태를 아무도 못 보는 부류

- **이벤트를 append 한 뒤 같은 블록에서 국면을 넘기면 그 이벤트는 화면에 한 프레임도 안 나온다.**
  턴 해상이 `battle` 을 갱신한 직후 `phase = .finished` 로 바꿨더니, SwiftUI 는 한 번만 다시 그려
  arena 가 마지막 배치를 보지 못했다 — `onChange` 가 안 돌고 **결정타·기절이 결과 화면으로
  스냅했다.** 재생기를 만든 이유가 바로 그 턴인데 그 턴만 재생에서 빠졌다. 처방은 결과를 값으로
  미뤄 두고(`pendingFinish`) 재생이 따라잡았다고 알릴 때 국면을 넘기는 것이다. 이때 **알릴 주체가
  없는 경로(팝오버가 닫혀 있음)** 를 반드시 같이 처방한다 — 안 하면 배틀이 `.battling` 에 갇힌다:
  ① `seed()`(따라잡기)도 알림을 부르고 ② 센터에 한 번짜리 마감(`BattleReplay.budget + 여유`)을 둔다.
  그리고 미뤄 둔 값은 **국면이 바뀔 때 버린다**(`didSet`) — 항복·새 배틀이 먼저 국면을 옮겼는데
  옛 마감이 뒤늦게 깨어나면 항복 화면을 실제 결과로 덮어쓴다. (`BattleCenter`, 2026-08-21.)
- **묶음을 "그 시점 문맥" 으로 고정하려고 일찍 만들면 뒤에 붙는 이벤트가 묶음에서 빠진다.** 로그
  이름 문맥을 자동 출전 **전에** 고정하려고 배치를 그 자리에서 만들었는데, 자동 출전 이벤트를
  스트림에 추가하면서 배치는 그걸 못 담아 평평한 스트림과 개수가 어긋났다 — 진행도 자르기가 그만큼
  밀린다. 고정할 것은 **문맥 값**이고 묶음은 이벤트가 다 모인 뒤 만든다. 불변식은
  `eventBatches.flatMap(\.events) == events` 로 단언한다. (`resolveChosenActions`, 2026-08-21.)

## 연출이 원인과 결과를 같이 보여 주지 못하는 부류

- **알림 문구를 자기 스텝 동안만 띄우면 원인이 결과보다 먼저 사라진다.** 엔진 순서가
  `.crit` → `.damage` 라 '급소에 맞았다!' 가 0.3초 뜨고 사라진 **뒤에** HP바가 움직였다 — 큰
  데미지의 이유가 화면에 같이 있는 순간이 한 번도 없다(이벤트가 많은 턴은 예산 압축으로 문구가
  60ms 도 못 뜬다). 처방은 문구를 **다음 문구가 뜰 때까지** 유지하는 것이다
  (`BattleReplay.popped(_:carrying:)`). 연출의 지속 시간은 자기 이벤트가 아니라 **그 이벤트가
  설명하는 결과가 끝날 때까지**로 잡는다. (2026-08-21.)

## 판정 하나가 두 축을 보게 되면 기존 테스트가 다른 축 때문에 통과한다

- **수렴 판정("다시 받아야 하는가")에 축을 더하면 기존 테스트가 새 축 때문에 실패하거나 새 축
  덕분에 통과한다.** `needsDescriptionRefresh` 에 랭크 축을 더해 `needsDetailRefresh` 로 넓히자,
  "빈 설명은 다시 받지 않는다"를 지키던 테스트가 **랭크 축이 nil 이라** 실패했다.
  반대가 더 위험하다 — 새 축이 늘 참이면 설명 판정이 죽어도 초록이다.
- **처방**: 축이 여러 개인 판정의 테스트는 **보지 않는 축을 "받아봤음"으로 고정한다**(`statChanges = []`).
  고정값을 넣는 줄에 왜 고정하는지 한 줄 적어 둔다 — 안 적으면 다음 사람이 지운다.
- 같이 지킬 것: 세이브 보강 판정은 **받을 수 없는 값**을 참으로 만들면 안 된다. 합성 기술(id ≤ 0)은
  `moveDetail(id:)` 가 거절하는 id 라, 참으로 답하면 로드마다 헛도는 조회가 영구히 남는다.
  (`CompanionStore.needsDetailRefresh`, 2026-08-20.)

## 아무 호출부도 없는 분기는 라인 커버리지에서 안 보인다

- **`switch` 를 도우미로 만들면 실제로 쓰이는 case 는 일부다.** `BattleSide.rawStat` 은 7개 case
  인데 데미지 경로가 쓰는 건 4개였고 스피드·명중·회피는 호출부가 없었다. 파일 라인 커버리지
  99.44% 로 게이트를 통과했고, `--show-regions` 의 미실행 표시로만 드러났다.
- **처방 두 가지.** ① 미실행 case 는 **호출부를 만들어 없앤다**(`effectiveSpeed` 가 `stats.spe` 를
  직접 읽던 것을 `rawStat(.spe)` 로 돌렸다 — 중복도 같이 사라진다). ② 그래도 남는 case(Swift 의
  exhaustive switch 가 강제하는 것)는 값을 직접 검증해 의미를 못 박는다.
- **같은 감사에서 확률 분기의 실패 쪽도 미실행이었다.** 2차효과를 100%·0% 로만 테스트해 "판정이
  실패하는" 경로를 한 번도 밟지 않았다 — 굴림을 안 하는 구현도 통과한다.
  확률이 붙은 기전은 **중간 확률(20%)로 seed 를 순회해 두 결과가 다 나오는지** 본다.
  (`BattleSide.rawStat` · `BattleEngine.applyStatChanges`, 2026-08-20.)
- **새로 쓴 파일도 같은 감사를 받는다 — "방금 썼으니 다 쓰인다" 는 근거가 아니다.**
  `PokemonChatToolCall.tool` 은 호출부가 하나도 없는 채로 커밋 직전까지 갔다. 파일 라인 커버리지는
  게이트를 통과했고 `--show-regions` 만 `^0` 으로 드러냈다. 새 로직 파일을 넣을 때는 게이트 배열
  등록과 **region 확인을 한 묶음으로** 한다. (`PokemonChatTools.swift`, 2026-08-25.)

## 신뢰경계 검사를 한 경로에만 두면 형제 경로가 무검사로 남는다

- **범위 검사는 "그 값을 새로 쓰기 시작한 경로"에만 붙기 쉽다.** `statChance` 검사를 4인 방
  (`MultiplayerValidation`)에만 넣었더니, 같은 무브셋을 받는 1v1 LAN 핸드셰이크는 타입·레벨만
  봐서 `statChance: 5000` 이 무검사로 엔진에 들어갔다.
- **처방**: 경계 검사는 **모든 수신 경로가 지나는 한 함수**로 뽑고 각 guard 가 그걸 부른다.
  새 필드는 **받는 경로를 전부 grep** 한다. (`BattleNet` `.challenge`/`.accept`, 2026-08-20.)

## 총폭 검증은 "누가 잘렸는가"를 못 잡는다

- **`frame(maxWidth:)` 로 잡힌 화면은 총폭 단정을 늘 통과한다.** "일곱 축이 다 붙어도 팝오버를
  안 넘는다" 를 검증했지만, 안 넘는 건 상위 `frame` 이 보장한 것이고 실제로 밀려 잘리는 건
  **옆 칸(HP 표기)** 이었다.
- **처방**: 한 줄에 칸을 더할 땐 `layoutPriority` 로 **누가 먼저 잘릴지**를 코드에 적는다.
  총폭 단정은 "안 커진다" 만 증명한다. (`StageArrows` · `CombatantBar`, 2026-08-20.)

## 리베이스가 만드는 부류 — 한쪽이 추출한 헬퍼, 다른 쪽이 호출부에 넣은 규칙

- **`main` 이 공통 로직을 헬퍼로 추출하는 동안 내 브랜치가 같은 규칙을 호출부에 인라인으로 넣으면,
  충돌에서 어느 쪽을 골라도 경로 하나가 무규칙으로 남는다.** 교체 정리는 `main` 이
  `BattleEngine.prepareForSwitch` 로 뽑았고 내 브랜치는 랭크 리셋을 팀 연습 호출부에 넣었다 —
  HEAD 를 고르면 랭크가 안 지워지고, 내 쪽을 고르면 LAN 교체(`BattleNet.switchSlot`)만 랭크를
  들고 나온다. 핸드셰이크 무브셋 검사도 같은 모양이었다(`validLineup` 추출 vs 호출부 두 곳 인라인).
- **처방**: 충돌 해소는 "한쪽 고르기" 가 아니라 **규칙을 추출된 헬퍼 안으로 옮기는 것**이다.
  그러면 리베이스 뒤에 늘어난 호출부(LAN 교체·선봉 밖 슬롯)까지 같이 덮인다. 해소 뒤에는 헬퍼
  **자체**를 단언하는 테스트를 남긴다 — 호출부만 단언하면 규칙이 다시 인라인으로 내려가도 초록이다.
- **컴파일이 안 잡는 짝**: 새 enum case(`BattleEvent.boost`)와 다른 브랜치가 추가한 exhaustive
  `switch`(`BattleReplay` 3곳)는 git 이 충돌로 못 보고 빌드에서만 드러난다. 리베이스 뒤 빌드는
  해소의 일부다.
- **주입으로 확인한 것**: 새 가드를 지우고 테스트를 돌렸더니 라인업 테스트가 **통과했다** —
  `teamSize: 2` 가 지원 크기(1/3/6)가 아니라 크기 가드에서 먼저 걸려 무브셋 검사에 닿지도 못했다.
  경계 검사 테스트는 **검사에 실제로 닿는 입력**으로 잡고, 같은 입력의 정상 케이스를 위에 같이
  둔다(거절이 의도한 이유로 났는지 그때만 보인다). (2026-08-21.)

## 응답이 대상을 알려주는데 부호로 추정하면 자기 대상 기술이 뒤집힌다

- **`stat_changes`·`meta.ailment` 에 대상이 없다고 해서 응답 전체가 모르는 게 아니다.** PokéAPI
  `/move` 는 `target` 을 늘 준다. 그걸 안 읽고 부호로 대상을 추정하자 두 부류가 정반대로 걸렸다:
  잠자기(`status` + `ailment: sleep` + `target: user`)는 `ailmentChancePercent` 가 100 을 주고
  `applySecondaryEffect` 가 늘 상대에게 걸어 **회복 없는 필중 100% 수면기**가 됐고(CPU 는 PP 남은
  기술을 균등 무작위로 고르므로 매 턴 4분의 1 확률로 나온다), 저주(자기 스피드 −1 + 공격·방어 +1)는
  부호 규칙이 스피드 감소만 상대에게 보내 자기 버프 둘 + 상대 디버프 하나가 됐다.
- **못 걸린 이유**: 부호 규칙 테스트가 부호가 **하나뿐인** 표본(칼춤 +2 / 울음소리 −1)만 썼다.
  섞인 표본이 없으면 "부호가 대상을 정한다" 가 성립하는 입력만 검증한다.
- **처방**: 추정 규칙을 넣기 전에 **응답에 답이 있는지 먼저 본다**. 그래도 못 가리는 조합
  (부호 섞임)은 **통째로 건너뛴다** — 절반만 걸면 완전히 뒤집힌 결과가 되고, 안 걸면 아무 일도
  안 일어난다. 그리고 무브셋 선택기(`pickStatusMove`)는 **엔진의 게이트와 같은 값**을 봐야 한다 —
  엔진이 건너뛰는 기술을 칸에 앉히면 PP 만 태운다.
  (`MoveSpec.targetsUser` · `hasAmbiguousStatTargets`, 2026-08-21.)

## 경계에서 값만 막고 **키**를 안 막으면 메시지 전체가 디코딩에서 죽는다

- **`[BattleStat: Int]` 를 그대로 디코딩하면 모르는 키 하나가 파이터 — 곧 라운드 메시지 전체 — 의
  디코딩을 던진다.** 랭크 값은 `clamped` 로 막았는데 키는 안 막아서, 호스트가 `"stages": {"hp": 1}`
  을 보내면 게스트가 그 라운드에서 멈춘다(`DecodingError.dataCorrupted: Could not convert key to
  type BattleStat`). 클램프 테스트는 **아는 키**만 넣어서 이 경로를 한 번도 안 밟았다.
- **처방**: 와이어에서 오는 dictionary 는 **키를 문자열로 받아** 아는 이름만 남긴다
  (`BattleStat(rawValue:)` + `reduce`). 인코딩은 그대로 두면 JSON 모양이 바뀌지 않는다.
  같이 볼 것: 개수 상한은 **중복을 막지 않으면 뜻을 잃는다**(`+2 공격` 일곱 개는 7 ≤ 7 을 통과해
  한 방에 최대 랭크다). (`MultiplayerFighter.init(from:)` · `MultiplayerValidation.validMoves`,
  2026-08-21.)

## 대가를 모델링하지 않은 기술은 대가 없는 이득이 된다

- **응답에 있는 효과만 구현하면, 응답에 **없는** 대가는 조용히 면제된다.** 배가르기는 PokéAPI 에
  `stat_changes: [attack +6]` 로만 오고 최대 HP 절반이라는 대가는 어디에도 없다 — 그대로 통과시키니
  첫 턴 공짜 +6 공격이 됐다(CPU 도 무작위로 쓴다). 저주의 Ghost HP 반감도 같은 부류다.
- **처방**: 대가가 구현되지 않은 이득은 **엔진에서** 접는다(`statChangePercent` 가 0). 선택기
  (`pickStatusMove`)에만 게이트를 두면 변화기를 걸러내지 않는 `learnedMoves` 경로로 같은 기술이
  들어와 그대로 적용된다 — **게이트는 값을 쓰는 곳에 둔다.**
- 문턱(`|변화| >= 3`)은 휴리스틱이라 `ponytail:` 로 상한과 승급 경로를 적어 뒀다. 테스트에는 **대조군
  (±2 짜리 칼춤)** 을 같이 둔다 — 문턱이 변화기를 통째로 막아 기능이 죽는 쪽도 실패로 잡힌다.
  (`MoveSpec.hasUnpricedGain`, 2026-08-21.)

## 조기반환이 뒤에 오는 효과를 통째로 삼키는 부류

- **`return` 으로 끝내는 실패·종료 분기는 그 아래 전부를 건너뛴다.** `applyAttack` 이 기절에서
  조기반환해, 상대를 쓰러뜨린 턴의 **자기** 랭크 상승(고대의힘 부류)이 사라졌다 — 본가는 KO 여부와
  무관하게 오른다. 두 피어가 같은 조건을 보므로 desync 도 아니고 테스트도 초록이라, 랭크를 올릴
  기회가 KO 여부에 따라 무작위로 없어지는 걸 아무도 못 봤다.
- **처방**: 종료 이벤트(`.faint`)는 **맨 뒤로 미루고** 효과는 그 앞에서 다 본다. 대상이 사라져서
  못 거는 몫만 그 함수 안에서 걸러낸다(`defender.isAlive ? changes : changes.filter { $0.change > 0 }`)
  — 호출부에서 통째로 끊으면 자기 몫까지 같이 죽는다.
- **테스트는 양방향**이다: ① KO 낸 턴에도 자기 랭크가 오르는지 ② **쓰러진 상대**에게는 안 걸리는지.
  ①만 두면 필터를 지운 구현(쓰러진 개체에 `.boost` 를 내는)도 통과한다. 이벤트 **순서**(`.boost`
  가 `.faint` 앞)도 같이 단언한다 — 순서가 뒤집히면 로그가 "쓰러진 뒤에 랭크가 올랐다" 로 읽힌다.
  (`BattleEngine.applyAttack` · `applyStatChanges`, 2026-08-21.)

## 절차 문서가 스크립트 축소를 따라가지 못한 부류

- **스크립트에서 기능을 걷어낼 때 그 기능을 지시하던 문서가 같이 갱신되지 않으면, 문서는 존재하지
  않는 절차를 지시한다.** `release.sh` 가 태그 전용으로 축소된 뒤에도 `RELEASE.md` 와
  `docs/reference/release-workflow.md` 는 `--check-only`, `PTB_NOTES_FILE`, VERSION 범프, cask 갱신,
  gh-pages 랜딩, `scripts/e2e.sh` 를 계속 지시했다 — 옵션도 파일도 브랜치도 없다. 2.9.0 릴리스를
  문서대로 시작하면 첫 명령에서 막힌다.
- 코드 결함보다 늦게 발견된다: 문서는 실행되지 않으므로 CI·테스트 어디에도 걸리지 않고, 다음 릴리스
  담당자가 실패할 때까지 조용하다. 게이트가 **사라진 것 자체**가 더 위험하다 — "신규 기능 = 신규 에셋"
  하드 게이트가 함께 없어졌는데 문서는 여전히 게이트가 막아 준다고 적혀 있었다.
- **처방**: 스크립트에서 단계를 지울 때 그 단계 이름으로 `docs/`·`*.md` 를 grep 해 같은 커밋에서
  갱신한다. 그리고 문서에 **"이건 이제 사람이 지킨다"** 를 명시한다 — 없어진 게이트를 조용히 두면
  체크리스트가 지켜지는지 아무도 확인하지 않는다.
  (`RELEASE.md` · `docs/reference/release-workflow.md`, 2026-08-21.)

## 외부 DTO 에서 안 읽은 필드는 조건을 "뭉갠다" — 없어지는 게 아니라 넓어진다

- **파싱하지 않은 구분 필드는 그 구분이 사라진 채로 남는다.** PokéAPI 진화 조건에서 `held_item`
  (왕의징표석·금속코트 등 "도구를 지닌 채 교환")을 읽지 않았더니, 그 진화가 `trigger == "trade"`
  하나로만 표현돼 **순수 교환 진화와 구별되지 않았다** — 연결의끈 하나로 야도킹·킹크로스까지 공짜로
  진화됐고, 정작 그 도구들은 앱에 없었다. 필드를 빼먹은 결과가 "그 진화를 못 한다"가 아니라
  "아무 아이템으로나 된다"였다.
- **못 걸러낸 이유**: 픽스처가 `held_item` 이 **없는** 노드만 썼다. 연결의끈이 통하는 경로만 확인해서,
  통하면 **안 되는** 경로는 한 번도 밟지 않았다(조건이 넓어진 결함은 성공 케이스만 보면 안 보인다).
- **처방**: 조건 필드를 새로 읽기 시작하면 ① 파싱 → 트리 재구성(`EvoNode.keepingAnimatedSprites()`)
  → Codable 왕복까지 값이 살아 있는지 직접 단언하고(중간 재구성이 필드를 조용히 `nil` 로 떨어뜨린다),
  ② 조건을 **좁힌 쪽**(이제 통하면 안 되는 아이템)과 **넓힌 쪽**(전용 아이템으로 열린다)을 양방향으로
  테스트한다. 그리고 트리거 문자열로 분기하던 판정을 전부 함께 훑는다 — 졸업 레벨 면제 가드
  (`grewIntoFinalByItem`)가 `use-item`/`trade` 두 문자열만 봐서, `level-up` + 지닌물건(예리한손톱)
  진화가 "레벨로 키운 개체"로 오인돼 아이템 진화 착취 경로가 다시 열릴 뻔했다.
  (`PokeAPIClient.evoNode` · `EvolutionItemRule` · `CompanionStore.grewIntoFinalByItem`, 2026-08-21.)
- **같은 부류 — 대표 특성의 `is_hidden`.** `/pokemon/{id}`의 특성 목록에서 `is_hidden`을 읽지 않고
  첫 slot만 고르면 특성이 없어지는 게 아니라 **숨은 특성까지 대표 후보로 넓어진다**. 대화 페르소나는
  `is_hidden == false`인 항목만 남긴 뒤 최소 slot을 고르고, 회귀 테스트는 숨은 특성을 목록 앞·더 낮은
  slot에 놓아도 일반 특성을 선택하는지 직접 밟는다. 부류 스윕에서 `PokemonDTO.is_default` 미파싱도
  확인했지만 현재 앱은 기본 폼 species id 1~649만 요청하므로 동작을 뭉개지 않는다. 폼 범위를 넓힐 때는
  이 필드를 먼저 DTO와 테스트에 올려야 한다.
  (`PokemonAbilitiesDTO` · `PokemonSpeciesIdentity.primaryAbilitySlug`, 2026-08-23.)

## 쓸 수 없는 대상에만 쓰이는 아이템을 상점에 올리면 함정 구매가 된다

- **에셋 범위 필터가 아이템 유효성의 숨은 전제다.** 앱은 애니메이션 스프라이트가 있는 종(1~649,
  `PokemonAssets.animatedSpeciesIDs`)만 다루고, 범위 밖 종은 `EvoNode.keepingAnimatedSprites()` 가
  진화 트리에서 아예 지운다. 그래서 대상 종이 범위 밖인 진화 아이템은 **어떤 진화도 열지 못하는데
  상점에는 정상적으로 뜬다** — 사는 순간 500 별의조각이 사라지고 쓸 곳은 없다. #89 에서 향기주머니·
  휘핑팝을 넣다가 잡았다(대상 마이앵·나룸퍼프 682~685, 6세대).
- **아이템 쪽만 보면 완벽해 보인다**: PokéAPI 에 실재하는 아이템이고, 스프라이트도 있고, 이름·가격·
  소모 동작도 다른 아이템과 똑같다. 결함은 아이템에 있는 게 아니라 **아이템과 종 범위의 관계**에
  있어서, 아이템 목록 리뷰로는 안 걸린다("PokéAPI 에 있는 아이템이니 맞다" 로 통과한다).
- 진화가 안 되는 것보다 나쁘다. 진화 경로가 없는 종은 조용하지만(#89 가 고친 것), 살 수 있는 아이템은
  사용자가 **재화를 쓰고 나서** 아무 일도 안 일어나는 것을 발견한다.
- **처방**: 상점에 올리는 아이템은 **대상 종 id 를 명시적으로 적고** 그 id 가 에셋 범위 안인지
  테스트로 막는다(`ModelLogicTests.testEveryHeldItemHasATargetInsideTheSpriteRange` — 대상 목록을
  손으로 적게 만드는 것 자체가 게이트다). 범위가 넓어질 때 함께 넣도록 제외 이유를 `ItemKind` 선언
  옆에 남긴다 — 이유가 없으면 다음 사람이 "빠졌네" 하고 다시 넣는다.
  **같은 질문을 기존 아이템에도 해야 한다**: 지역폼 전용 아이템(`iceStone`)은 이 부류일 가능성이
  있는데 #89 범위 밖이라 검증하지 않고 남겼다 — 실제 진화체인 응답으로 확인이 필요하다.
  (`ItemKind` · `PokemonAssets.animatedSpeciesIDs`, 2026-08-21.)

## 새 로직 파일은 게이트 배열에 넣지 않으면 커버리지에서 빠진다

- **`test-gate.sh` 의 `LOGIC_CORE` 는 손으로 적는 목록이다.** 새 순수 로직 파일을 넣지 않으면 커버리지
  숫자에 아예 등장하지 않아, 무테스트여도 게이트가 초록이다. 2.9.0 직전 `GymLeague.swift`(카탈로그·
  배지 키·첫 승리 보상 병합, 147줄)가 그 상태였다 — 같은 릴리스에 들어온 `DexGoals.swift`·
  `BattleReplay.swift` 는 목록에 있었으니 "새 파일은 넣는다"는 규칙이 아니라 그때그때였다.
- 여기서 파일이 빠진 건 커버리지 하락으로 보이지 않는다. TOTAL 이 오히려 올라가므로(측정 대상이
  적어서) 숫자만 보면 상태가 좋아진 것처럼 읽힌다.
- **처방**: `Sources/PokeTokenBar/Core/` 에 파일을 추가하는 PR 은 `LOGIC_CORE` 를 같이 본다.
  결정적으로 단위 테스트 가능한지가 기준이고, 넣은 뒤 TOTAL 이 임계값 위인지 확인한다
  (`GymLeague.swift` 는 라인 80.77%, 추가 후 TOTAL 85.10% → 85.07%).
  (`scripts/test-gate.sh`, 2026-08-21.)

## 기능을 되살릴 때 삭제가 건드린 자리를 전수로 되짚지 않는 부류

- **삭제는 코드만 지우지 않는다.** #115 가 대화를 지우며 함께 지운 것: `AppSettings.retiredKeys`
  (사용자 prefs 정리), `CLAUDE.md` 문서 인덱스 행, `test-gate.sh` 의 `LOGIC_CORE` 행,
  `docs/reference/opencode-isolation.md` 와 그 검증 스크립트, defect-log 안의 파일 포인터,
  `SaveTransfer` 의 3파일 백업 묶음, `AppLanguage.resolveProse`. 되살릴 때 코드만 복원하면
  **기능은 도는데 게이트·문서·정리 경로가 없는** 상태가 된다.
- **처방: 삭제 커밋의 `--stat` 을 목록으로 쓴다.** `git show <삭제커밋> --stat` 이 건드린 파일
  전부를 한 번씩 열어 "이 파일에서 지운 것이 이 기능 것인가" 를 답한다. 기억으로 되짚으면
  코드가 아닌 자리(스크립트 배열·문서 행)가 반드시 남는다.
- **되살린다고 전부 되돌리지는 않는다.** 삭제 PR 이 같이 고친 **정당한** 것은 그대로 둔다 —
  `flavor_text_entries` 를 부화 경로에서 뺀 것, 대표 특성 규칙을 한 곳으로 옮긴 것, 상태
  디렉토리 생성. 되돌릴 것과 남길 것을 파일별로 판단하지 않으면 고쳐진 결함이 같이 살아난다.
  (포켓몬 대화 원복, 2026-08-25.)

## 매 세션 로드되는 지침에 죽은 규약이 남는 부류

- **`CLAUDE.md` 가 존재하지 않는 코드와 문서를 규약으로 가리키고 있었다.** "확장 규약(새
  프로바이더/툴 추가 시)" 이 `UsageProvider` · `UsageStore.init(providers:)` ·
  `BinaryLocator.commonToolDirectories()` · `LocalUsageReader.claudeProjectRoots` 를 손댈 지점으로
  지정하고 `docs/reference/provider-extension.md` 를 참조 문서로 인덱스했는데, 사용량 추적 코드와 그
  문서는 게임으로 방향을 바꾼 커밋(`2179921`)에서 함께 사라졌다. `grep` 결과 0건.
- 이건 다른 죽은 문서보다 비싸다 — `CLAUDE.md` 는 **매 세션 전문이 로드**되므로 없는 심볼을 찾다가
  헛돌거나, 규약을 지키려고 있지도 않은 구조를 새로 만들 수 있다. 어느 테스트·게이트도 문서가 가리키는
  심볼이 실재하는지 보지 않는다.
- **처방**: 코드를 대량으로 걷어내는 커밋은 그 심볼 이름으로 `CLAUDE.md`·`docs/`·`*.md` 를 grep 해
  같은 커밋에서 규약을 걷는다. 참조 문서 인덱스에 줄을 추가할 때는 그 파일이 실제로 있는지 확인한다
  (인덱스만 남고 파일이 없는 상태가 이번 경우다).
  (`CLAUDE.md`, 2026-08-21.)
## 광고·핸드셰이크에 굽는 값은 굽는 순간의 스냅샷이다

- **Bonjour TXT 레코드에 랭크를 리스너 생성 때 한 번만 굽고 있었다**(`BattleNet.startListener`).
  랭크전에서 이기든 지든 광고는 옛 점수를 계속 실어, 근처 트레이너 목록엔 세션이 끝날 때까지
  stale 랭크가 보였다(#85). 값을 굽는 코드와 값이 바뀌는 코드가 서로를 모르는 게 원인이다 —
  광고는 `start()` 에서 한 번, 랭크는 배틀 정산·세이브 이전에서 수시로 움직인다.
- **테스트가 못 잡은 이유**: 애초에 `BattleNet` 을 세우는 테스트가 없었고(실 `NWListener` 를 띄우면
  로컬 네트워크 권한이 필요하다), 있었더라도 "리스너를 만들고 레코드를 읽는" 형태면 결함이 그대로
  있는데 통과한다. 확인해야 하는 건 **랭크가 바뀐 뒤**의 광고값이다.
- **처방**: 외부에 광고·전송하는 파생값은 (1) 재발행 함수를 따로 두고 (2) 원본이 바뀔 때 그 함수를
  부르는 관찰을 붙인다(`withObservationTracking` 은 1회성이라 콜백에서 재등록). 발행 지점은 주입
  가능한 seam 으로 빼 두면 네트워크 없이 회귀 테스트가 가능하다
  (`BattleNet.refreshAdvertisedRank` / `rankRecordPublisher`, `RankAdvertisementTests`).
- **부류 스윕**: 같은 패턴은 `MultiplayerRoomCenter.startHosting` 의 서비스 이름 — 활동 종류와
  트레이너 이름을 방 개설 순간에 굽는다. 활동은 방 수명 동안 고정이라 무해하고, 방을 열어 둔 채
  트레이너 이름을 바꾸면 옛 이름이 광고된다(방 수명이 짧아 미수정으로 남긴다).
  (`BattleNet.swift`, 2026-08-21.)
## 프레임워크의 시간 표시 위젯은 목표를 지나면 방향을 바꾼다

- **`Text(date, style: .timer)` 는 카운트다운이 아니라 "차이 표시"다.** 목표 시각을 지나면 남은
  시간을 0 에서 멈추는 대신 *경과* 시간을 세어 올린다. 보관 알 자동 부화 줄이 이걸 그대로 써서,
  카운트다운이 0 에 닿은 뒤 0:01, 0:02… 로 되올라갔다(#86 — "부화시간 0됐는데 늘어나는 버그").
  진행바(`eggProgress`)는 `min(1, max(0,…))` 로 잠겨 있으니 되감기는 값은 항상 **파생 시간 표시**
  쪽이다.
- 예정 시각을 지나도 곧바로 부화하지 않는 건 정상이라 이 구간은 늘 생긴다: 부화 트리거는 60초
  방치 틱(`CompanionStore.refreshLifecycle`, tolerance 5초)이고, 종 추첨은 네트워크가 필요해
  오프라인이면 실패하고, 등급 보증에 미달한 롤은 알을 그대로 두고 다음 틱으로 미룬다. 즉 "지났지만
  아직"이 몇 초에서 몇 시간까지 이어질 수 있고, 그 사이 프레임워크 위젯만 혼자 매초 다시 그린다.
- **못 잡은 이유**: 남은시간을 다루는 코드는 전부 바닥이 잡혀 있었다(`FocusTimer.remaining` 의
  `max(0,…)`, `MenuBarStatus.remainingClockText`, 배틀 턴 타이머, 포켓애슬론 카운트다운) — 이 한
  곳만 계산을 프레임워크에 넘겨 우리 코드에 바닥을 잡을 자리가 없었다. 테스트는
  `nextStoredEggHatchAt != nil`(카운트다운이 뜨는지)까지만 봤고 **그 시각을 지난 뒤 무엇이 그려지는지**
  는 어느 테스트도 밟지 않았다. 뷰 안에 있는 표시 로직은 애초에 테스트 대상이 아니었다.
- **처방**: 남은시간 표시는 우리 순수 함수를 지난다 — `StoredEggCountdown.resolve(readyAt:now:)` 가
  0 이하를 숫자가 아닌 `.due`("곧 부화") 상태로 접고, 뷰는 그 결과만 그린다. 같은 화면의 모험
  카운트다운이 이미 쓰던 형태이기도 하다(`isComplete(at:)` 면 타이머 대신 "보상 받기" 버튼).
  회귀 테스트는 5분 창 전체를 1초 간격으로 훑어 **표시가 단조 비증가**이고 `.due` 이후 숫자로
  돌아가지 않음을 잠근다(`StoredEggCountdownTests`).
- **부류 스윕(2026-08-21)**: `style: .timer` 사용처는 두 곳뿐이었고, 모험 쪽(`FocusTimerView:55`)은
  `isComplete(at:)` 가드 안에 있어 0 에서 버튼으로 바뀐다. UI 의 남은시간 산술
  (`BattleField:601`, `BattleView:494`, `PokeathlonView:422`)은 모두 `max(0,…)` 또는 `> 0` 분기로
  바닥이 잡혀 있다. 남은 규칙: **표시할 시간차를 프레임워크에 계산시키지 않는다.**
  (`Sources/PokeTokenBar/Core/StoredEggCountdown.swift` · `Sources/PokeTokenBar/UI/FocusTimerView.swift`,
  2026-08-21.)
## 상한 클램프가 누적 지점마다 흩어지면 한 곳은 반드시 빠진다

- **경험치 상한(990,000,000 = Lv.100)이 리터럴로 세 누적 지점에 흩어져 있었고, 이상한 사탕 경로만
  클램프가 없었다**(#81). 화면은 `level = min(100, …)` 이라 멀쩡해 보이지만 저장값은 상한 위였고,
  `SaveTransfer.sanitized` 가 그 값을 조용히 되돌려 **세이브를 옮긴 사람과 안 옮긴 사람의 데이터가
  갈렸다**. 도달 불가 케이스도 아니다 — 해안 모험 한 번이 108,000,000 이라 열 번이면 상한이다.
- 같은 상수를 흩어 놓은 대가가 하나 더 있었다: `sanitized` 는 **박스 개체만** 잘랐고 활성 개체의
  경험치는 무검증이었다. 손편집 세이브의 `Int.max` 에 사탕 XP 를 더하는 순간 Swift 오버플로 트랩으로
  프로세스가 죽는다(재기동해도 같은 파일을 읽어 다시 죽는 그 부류).
- **처방**: 상한이 걸린 값은 **클램프가 붙은 입구 하나**만 남긴다(`MonState.gainExperience(_:)`).
  누적 지점은 그 함수를 부르고 직접 `+=` 하지 않는다. 상수도 한 곳(`PokemonBalance.maxLevel` ·
  `experiencePerLevel` · `maxLevelExperience`)에 두고 검사 코드까지 그 상수를 쓴다 — 리터럴이 남아
  있으면 상한을 바꿀 때 검사 쪽만 옛 값으로 남는다.
- **곁가지**: 구간 진행도 getter 는 **상한에서 나머지가 0** 이 된다. `990_000_000 % 10_000_000 == 0`
  이라 만렙 개체의 막대가 텅 비어 보였다. 형제 구현(`experienceToNextLevel` · `TrainerLevel.progress`)은
  둘 다 최고 레벨 가드가 있었고 이 하나만 없었다 — **형제 구현이 셋이면 셋을 나란히 놓고 본다.**
- 회귀 테스트는 정확히 상한값과 상한 초과 시도를 밟아야 한다. 낮은 레벨에서 적립하는 테스트는
  클램프를 한 번도 지나지 않고 통과한다.
  (`CompanionModel.swift` · `CompanionStore.swift` · `SaveTransfer.swift`, 2026-08-21.)

## 세 갈래 중 두 갈래만 번역하는 부류 (가드가 표기 하나만 알면 스윕이 끝나지 않는다)

- **코드가 언어를 직접 갈랐다** — `store.language == .ko ? "한국어" : "English"`. 세 언어인데
  삼항은 두 갈래뿐이라 **일본어 사용자에게 영어가 나간다.** `BattleView` 주석이 이 부류를 이미
  적어 뒀지만 주석은 새 코드를 막지 못해 UI 8개 파일에 **115곳**이 쌓였다.
- **테스트가 못 잡은 이유**: 문구는 렌더 결과라 단위 테스트가 값을 단언하지 않고, 레이아웃
  테스트는 높이·폭만 봤다. ko 로 개발하고 ko 로 확인하면 영원히 안 보인다.
- **1차 스윕이 흘린 것**: `language == .ko` 문자열만 찾은 스캔이 같은 결함의 다른 표기 두 곳을
  통과시켰다 — `case (.ko, …)`(`FocusTimerView.title`), `languageProvider() == .ko`
  (`FloatingPetPanel`). **가드를 표기에 맞추면 스윕 범위도 그 표기까지만 좁아진다.**
- **처방**: 뷰에서도 `L.t(ko, en, ja)` 를 쓴다. 인자 세 개가 필수라 한 칸을 비우면 컴파일이 막는다.
  일회성 문구를 프로퍼티로 올리면 `Localization.swift` 가 뒤덮이므로, 두 화면이 같은 말을 쓸 때만
  승격한다.
- **영구 캡처**: `LanguageSplitGuardTests` 가 `Sources/**` 를 훑어 한 파일의 **`.ko` 와 `.ja`
  등장 횟수가 다르면 실패**한다. 표기가 아니라 대칭을 보므로 삼항·튜플 `switch`·provider 비교를
  한 규칙으로 덮고 `Core/` 도 포함한다. 주석 줄은 제외한다(규칙을 설명하는 주석이 패턴을 담고
  있어 제외하지 않으면 가드가 자기 설명에 걸린다). 두 표기를 각각 되살려 실패를 확인했고, 파일
  목록이 비면 실패하는 단언도 뒀다. 한계: `.ko` 만 쓰는 헬퍼가 늘면 오탐이 난다 — 오탐은 빌드를
  막고 끝나지만 미탐은 배포되므로 그쪽으로 기울여 뒀다.
  (`Sources/**/*.swift` · `Localization.swift`, 2026-08-22.)
- **페르소나 언어 폴백은 이름과 문장이 다르다.** 이름 한 단어는 요청 언어가 없으면 영어로 폴백해
  식별 가능성을 유지하지만(`resolveName`), 도감·특성 설명 문장 전체는 정확한 요청 언어가 없으면
  생략한다(`resolveProse`). 둘을 `CompanionModel.swift`에서 나란히 두고 같은 테스트에서 영어 전용
  딕셔너리를 각각 통과시켜, 한쪽 규칙을 다른 쪽으로 복사하면 깨지게 했다. 스윕 결과 배틀 기술 설명의
  en→임의 값 폴백은 빈 툴팁보다 이름 있는 설명이 나은 UI 정책이라 유지했고, 대화 프롬프트의 prose
  경로에는 같은 폴백이 더 없었다.
  (`AppLanguage.resolveName` · `resolveProse`, 2026-08-23.)

## 표시값을 담은 값 타입의 `==` 가 신원만 비교하면 갱신이 사라진다

- **`BattlePeer.==` 가 `serviceName` 만 비교했다.** 신원 판정으로는 맞지만 상대가 레벨을 올려
  광고가 갱신돼도 두 값이 같다고 나온다. 동등성으로 갱신을 판단하는 쪽(SwiftUI 뷰 비교,
  `onChange(of:)`)이 붙으면 실시간 갱신이 조용히 삼켜진다 — 그 갱신이 기능의 존재 이유였다.
- **처방**: 신원은 `id` 가 맡고 `==` 는 표시값까지 비교한다. 회귀는 같은 `serviceName` + 다른
  `trainerLevel` 로 `id` 는 같고 `==` 는 다름을 함께 단언한다.
- **곁가지 — 상한값이 곧 최장 문구는 아니다.** 최악 폭 가드가 `BattleRank.maximumPoints` 를
  최악으로 가정했는데, 최고점은 `Challenger · 99 LP`(18자)이고 진짜 최악은 티어 이름이 더 긴
  `Grandmaster · 10 LP`(19자)다. 최악은 문구 길이로 골라야 한다.
  (`BattleNet.swift` · `PopoverLayoutTests.swift`, 2026-08-22.)

## 버전이 갈리는 상대의 값을 내 상수로 그리는 부류

- **광고된 업적 단계를 내 카탈로그 상한으로 클램프하고 내 분모로 그렸다.** 카탈로그는 조절
  손잡이라 언젠가 늘어나고, 그 뒤 18/20 인 상대가 구버전 화면에서 `16/16`(완료)으로 보인다.
  진행도를 보여주는 기능이 거짓을 말하는데 클램프가 그걸 가린다.
- **처방**: 분자와 함께 **분모도 광고**한다(`achievementCeiling`). 읽는 쪽은 상대의 분모로 그리고
  분모를 안 보낸 구버전만 내 카탈로그로 폴백한다. 분모도 신고값이라 표시 상한으로 자른다 —
  자릿수가 늘면 카드가 밀린다.
- **타이밍이 본질이다.** 이 키는 카탈로그가 바뀌기 **전에** 배포돼 있어야 효과가 있다. 나중에
  넣으면 그 사이 버전들은 이미 틀리게 그린다.
- 회귀: 새 분모(18/20)·분모 없음·적대적 분모·분자 없음을 각각 밟고, 옛 클램프를 주입해 실패를 봤다.
  (`PeerAdvertisement.swift`, 2026-08-22.)

## 네트워크 객체를 취소하지 않고 참조만 버리는 부류

- **`BattleNet` 의 리스너·브라우저 재시작 경로가 `cancel()` 없이 `= nil` 만 했다.** 실패한
  `NWListener`/`NWBrowser` 는 취소해야 큐·포트를 놓는다 — 24/7 앱에서 슬립 복귀마다 누적된다.
  형제인 `MultiplayerRoomCenter`·`LocalAppcastServer` 는 취소하고 있었으니 "같은 기전을 한
  모드에서만 고치는 부류" 의 재발이다.
- **처방**: 호출부가 아니라 `startListener`/`startBrowser` **입구**에서 취소한다. 재시작은 반드시
  입구를 지나므로 새 경로가 생겨도 덮인다.
- **테스트 없음(한계)**: 실패 상태를 만들려면 실 네트워크가 필요하고, 테스트 바이너리는 로컬
  네트워크 권한이 없어 리스너가 `.ready` 조차 못 간다. 근거는 단일 입구라는 구조다. 같은 이유로
  정지 API 는 두지 않았다 — 프로덕션 호출부가 없어 그 API 자체가 무검증으로 남는다.
  (`BattleNet.swift`, 2026-08-22.)

## 신뢰경계에서 숫자만 자르고 **문자열**을 빼 두는 부류

- **세이브에서 온 문자열은 길이 상한이 없었다.** `sanitized` 는 수치·배열·집합 크기를 촘촘히
  클램프하면서 `seasonKey`·`missions.dayKey/weekKey`·`adventureWeekKey`·`lastCandyDate`·
  `activeSecondsDate`·`trainerName`·별명·`gymBadges`/`collectedFinals` 원소는 그대로 통과시켰다.
  임의 길이 문자열은 무결성 canonical(**매 저장의 해시 입력**)과 화면·LAN 전송에 그대로 실린다.
  실측: 100KB 문자열 9개 → canonical 700KB.
- **찾는 방법**: `CompanionModel` 의 `lenient(String.self, …)`·`Set<String>`·`nickname` 목록과
  `sanitized` 가 실제로 자르는 필드를 대조한다. 새 문자열 필드를 더할 때 묻는 질문은 "이 값이 canonical
  이나 화면·wire 로 나가나" 다.
- **상한은 입력 경로와 같은 상수여야 한다.** 경계가 더 짧으면 방금 입력한 정상 이름이 다음 로드에서
  잘린다 — `setTrainerName`·별명 설정과 `SaveTransfer.maxNameLength` 를 한 상수로 묶었다.
  원장 키는 `SaveTransfer.clampedKey` 하나로 세 원장이 같은 규칙을 쓴다.
  (`testOversizedStringsFromASaveAreClampedAtTheBoundary`, 2026-08-22.)

## `TimeZone.current` 는 프로세스 첫 값에 캐시된다 — 시간대를 다시 읽는 건 `Calendar(identifier:)`

- **`calendar.timeZone = .current` 는 "시간대를 매번 읽는다" 가 아니다.** 시즌 달력을 `static let` →
  계산 프로퍼티로 바꿔 시간대 변경을 따라가게 한 뒤, 같은 의도로 원장 키에 `timeZone = .current` 를
  넣었더니 **거기서 다시 굳었다**: 실측으로 `NSTimeZone.default` 를 바꿔도 `TimeZone.current` 는
  첫 값(Asia/Seoul)을 계속 준 반면 `Calendar(identifier:)` 는 매번 새 값을 읽었다.
- **처방**: 시간대를 명시적으로 대입하지 않고 `Calendar(identifier: .gregorian)` 를 그때 만든다.
  세 원장 키와 시즌 만료가 **같은 접근자**(`SeasonBoard.gregorian`)를 쓰게 해 갈라질 자리를 없앴다.
- **가드**: `testLedgerKeysFollowTimeZoneChanges` — 같은 순간을 UTC+14/UTC-11 에서 굽는다. 이 가드가
  `.current` 대입을 실제로 잡았다(작성 당시 실패 → 원인 발견).
- 곁가지: `DateFormatter` 는 호출당 16.3µs, 성분 조립은 1.6µs(실측). 뷰 body 에서 읽는 경로라 포맷터를
  캐시하는 대신 없앴다 — 캐시는 위의 시간대 함정을 되살린다.

## 로테이션·순환 콘텐츠는 "세트 비교" 가 아니라 **인접 비교**로 검사한다

- **세트 배열이 서로 다르면 통과하는 테스트는 절반 중복을 못 잡는다.** 시즌 세트 1·2 가 `focus900` 을
  공유해 **연속 두 달**에 같은 집중 목표가 나왔는데, `testConsecutiveSeasonsDifferAndCycleAtTheRotationLength`
  는 배열 전체를 비교하므로 초록이었다. 순환 콘텐츠의 계약은 "다르다" 가 아니라 "인접이 겹치지 않는다".
- **처방**: `testAdjacentSeasonsShareNoGoal` — 세트 i 와 i+1(마지막↔첫 포함)의 id 집합이 disjoint.
  (2026-08-22.)

## 완료마다 알림 한 통이면 한 정산이 배너를 여러 개 띄운다

- **한 번의 모험 정산이 트레이너 레벨업·일간·주간 미션·시즌 챌린지·업적을 동시에 완료시킬 수 있다.**
  완료 항목마다 `notifyCompanionEvent` 를 부르면 배너가 6개 연달아 뜬다(시즌 도입 전에도 4개였다).
- **처방**: 원장별로 완료 목록을 모아 **한 통**으로 묶는다(`CompanionStore.mergedCompletion` — 이름은
  가운뎃점, 보상은 합산). 새 문구를 만들지 않고 기존 "이름 — 별의조각 N" 문장을 재사용한다.
- **테스트 가능한 자리로 뽑는다.** `notifyCompanionEvent` 는 `AppEnv.isBundledApp` 가드에 막혀 테스트에서
  아무것도 관측할 수 없다 — 병합 규칙을 순수 함수로 분리해야 검사할 수 있다
  (`testCompletionsInOneSettlementMergeIntoASingleNotice`, 2026-08-22.)

## 주기 축만 다른 두 원장에 같은 진행도 규칙을 복제하는 부류

- **`MissionBoard` 와 `SeasonBoard` 가 record·normalize·canonical 규칙을 통째로 복제했다.** 클램프가
  곧 멱등 가드인데 그 규칙이 두 곳에 있으면 한쪽만 고쳐져 미션과 시즌이 다르게 동작한다.
- **처방**: `protocol Goal` + `Array<Goal>.advance/normalized` + `Dictionary.canonicalCounts` 로 규칙을
  한 곳에 두고, 주기 축(일·주 vs 월)만 각 원장이 갖는다. **canonical 문자열은 바이트 단위로 동일해야
  한다** — 달라지면 정상 세이브가 전부 조작 판정된다(`testDefaultStateCanonicalFormIsFrozen` 이 가드,
  2026-08-22.)

## 보증 배지를 상태와 무관하게 상시로 그리는 부류

- **초록 자물쇠 "도구·MCP 격리" 가 AI 미선택·차단 제공자 선택 상태에서도 떠 있었다**
  (`PokemonChatView.statusBar`). 없는 보증을 광고하는 쪽이 배지를 아예 안 그리는 쪽보다 나쁘다 —
  사용자는 격리를 믿고 대화를 보낸다.
- **테스트가 못 잡은 이유**: 배지는 렌더 결과라 단위 테스트가 값을 단언하지 않고, 제공자 차단
  테스트(`testProvidersWithoutAVerifiedToolFreeContractAreBlocked`)는 **모델만** 보고 화면을 안 봤다.
  모델이 초록이어도 화면은 거짓말할 수 있다.
- **처방**: 배지를 해석 결과에 태운다 — `if provider != nil` 일 때만 그린다. 판단(`availability`)은
  커버리지 게이트 안(`PokemonChat.swift`)에 두고 뷰는 표시만 한다. (2026-08-23.)

## 선택 가능한 비활성 항목은 사용자를 실패로 안내하는 부류

- **피커에 `OpenCode (disabled)` 가 선택 가능한 항목으로 있었다.** `(disabled)` 라고 *쓰는* 것은
  아무것도 비활성화하지 않는다. 골라진 뒤에야 경고가 뜨니, 사용자는 이미 실패한 상태에서 배운다.
  853 부류(잠갔는데 잠긴 것처럼 안 보인다)의 피커판.
- **처방**: 목록을 `allCases` 로 만들고 차단 항목에 자물쇠 + `.disabled(true)`. 목록에서 **지우지는
  않는다** — 지우면 왜 못 쓰는지 알 길이 없다. 보이되 고를 수 없어야 한다.
- **덧붙는 부류: 서로 다른 사유를 한 문장으로 뭉개기.** "미지원 또는 실행 파일 못 찾음" 은 사용자가
  할 수 있는 일을 못 알려 준다 — 전자는 없고 후자는 설정에서 경로 지정이다. 사유를 나눠야 안내가
  된다(`PokemonChatBlockReason`). (2026-08-23.)

## 외부 CLI 계약을 "확인 못 했다" 와 "확인했더니 안 된다" 로 나눠 적지 않는 부류

- **OpenCode 격리 계약은 실측하지 못했다 — CLI 가 설치돼 있지 않아서다.** 이걸 "실패" 로 적으면
  나중에 누구도 다시 재보지 않는다. 반대로 "미확인" 을 근거로 차단을 풀면 무방비로 나간다.
- **처방**: 판정을 사람 기억이 아니라 **종료코드**로 남긴다 —
  `scripts/verify-opencode-isolation.sh` 는 `0`(4/4 통과)·`1`(프로브 실패)·`2`(시험 불가)를 구분한다.
  실측 기록·재검증 방법·무엇이 바뀌면 다시 볼 것인지는 `docs/reference/opencode-isolation.md`.
  (2026-08-25 대화 기능과 함께 지웠다가 되살렸다. 남길 것은 파일이 아니라 **"미확인"과 "실패"를
  다른 종료코드로 가른다**는 규칙이다.)
- **플래그가 없는 CLI 의 계약은 버전 종속이다.** 설정 병합 우선순위에 기댄 격리는 상류 릴리스가
  조용히 깰 수 있다. 그래서 계약을 버전에 못 박고 재실행 스크립트를 같이 남긴다.
- **스크립트도 가드다 — 빈 통과를 확인한다.** 인증이 없으면 모든 프로브가 "도구를 못 썼다" 로
  통과해 거짓 합격이 난다. 그래서 스모크 프롬프트로 응답을 먼저 확인하고, 프로브 로직 자체는
  탈출하는 스텁으로 FAIL 이 잡히는지 검증했다. (2026-08-23.)
## `default:` 가 "특정 부류 전체"를 뜻하면 새 케이스는 조용히 그 부류가 된다

- 아이템 스위치들이 `default: // 진화 아이템 전체` 로 끝나 있었다(`BagView` 의 `canUse`·`effectHint`·
  `performUse`, `Localization.itemDescription`, `ItemKind` 의 `spriteName`·`shopPrice`). 케이스 30개를
  스위치마다 나열하지 않으려는 선택이라 그 자체론 합리적이다. 문제는 **진화 아이템이 아닌 케이스를
  새로 넣을 때** 드러난다 — 하트비늘(#97)을 명시하지 않으면 가방이 "진화 가능할 때 사용" 을 띄우고
  탭이 `useEvolutionItem` 으로 흘러가며, 설명은 `evolutionRule == nil` 분기를 타 **빈 문자열**이 된다.
- **컴파일러가 절반만 잡는다.** `itemName` 은 `default:` 가 없어 `switch must be exhaustive` 로 즉시
  걸렸지만, `default:` 가 있는 나머지 여섯 곳은 아무 경고 없이 통과했다. "빌드가 되니 다 넣었다"는
  판단이 여기서 깨진다.
- **처방**: 비진화 아이템은 `.rareCandy, .mint, .shinyCharm, .heartScale` 처럼 **명시 케이스로** 넣고,
  `default:` 주석에 그 분기가 뜻하는 부류를 적어 둔다. 새 아이템을 넣을 때는
  `grep -n "default:" ` 로 `ItemKind` 스위치 전체를 훑는다(현재 7곳).
- 회귀 가드는 "진화 경로로 새지 않는다"를 직접 밟는다 —
  `HeartScaleTests.testHeartScaleIsNotTreatedAsEvolutionItem`(`canUseEvolutionItem`·`useEvolutionItem`
  이 거절하고 재고가 그대로) + `testHeartScaleCopyExistsInAllThreeLanguages`(설명이 빈 문자열이면 실패).
  설명 누락은 화면을 봐야 아는 결함이라 문구 테스트가 세 언어 전부를 훑는 편이 싸다.
  (`CompanionModel.swift` · `Localization.swift` · `BagView.swift`, 2026-08-21.)
## `.task(id:)` 의 id 에 없는 값이 바뀌면 화면은 옛 데이터로 남는다

- 기술 목록은 `.task(id: "\(개체 id)-\(레벨)")` 로 다시 읽는다. 지금까지 무브셋이 바뀌는 유일한 경로가
  레벨업이라 **레벨이 항상 같이 바뀌었고**, 그래서 이 id 로 충분해 보였다. 하트비늘(#97)은 레벨을
  건드리지 않고 무브셋만 바꾸는 첫 경로다 — 학습을 수락해도 목록이 옛 기술 네 개를 그대로 보여 준다.
- **부류**: `.task(id:)`·`onChange(of:)` 의 키는 "무엇이 바뀌면 다시 해야 하는가"의 **완전한** 목록이어야
  한다. 키에 안 들어간 축을 바꾸는 경로가 나중에 하나 생기면 화면만 조용히 뒤처진다. 기존 테스트는
  전부 레벨업 경로라 이 공백을 밟지 않는다.
- **처방**: 상태를 바꾸는 쪽(`acceptMoveLearning`)이 표시 값(`displayedMoves`)까지 맞춘다 — 뷰의 재조회
  키에 축을 하나 더 매다는 방식은 다음 경로에서 또 빠진다. 회귀 가드는 레벨을 바꾸지 않는 학습 뒤
  `displayedMoves` 를 직접 본다(`HeartScaleTests.testAcceptingRelearnUpdatesDisplayedMoves`).
  (`CompanionStore.swift` · `CompanionView.swift`, 2026-08-21.)
## 설계 목업이 있는 화면은 목업 줄 단위로 문구 함수를 만들어 게이트에 넣는다

- 퍼즐 던전(#79)은 순수 코어를 두껍게 잠갔다 — 365일 전수 클리어 가능성까지 테스트가 있다. 그런데
  설계 문서의 화면 목업 6줄(체력 게이지·서술 줄·방위가 붙은 출구·되돌아가기 표시·방 카운터·로그)
  중 **온전히 구현된 줄이 0개**인 채로 릴리스됐다. 실제로 플레이하면 출구 목록이 "미탐사"로 글자까지
  똑같아(오늘 맵은 한 방에서 "남동" 출구가 세 개) 무엇을 고르는지 알 수 없다 — 방문 순서를 고민하는
  퍼즐인데 방을 식별할 수 없으니 찍기가 된다.
- **왜 못 걸렀나**: 계산이 전부 뷰 안에 있었고, `test-gate.sh` 의 `LOGIC_CORE` 는 코어 파일만 센다.
  뷰는 커버리지 집계 대상이 아니라 **화면이 설계의 절반이어도 게이트가 초록**이다. 코어 테스트는
  통과하니 신뢰가 잘못 붙는다(프로토콜 1단계에서 말하는 false confidence 의 화면 버전).
- **처방**: 목업이 있는 화면은 목업 줄마다 **값 → 문구** 경로를 순수 파일로 빼고(`DungeonNarration.swift`)
  `LOGIC_CORE` 에 등록한다. 화면 코드에는 조립만 남긴다. 목업이 곧 테스트 목록이다.
  (`DungeonView.swift` · `DungeonNarration.swift` · `scripts/test-gate.sh`, 2026-08-24.)

## 이벤트에 주인이 안 적혀 있으면 "직후 한 건" 규칙으로 묶지 못한다

- 던전 로그를 방 단위로 묶을 때 `DungeonEvent.damaged(Int)` 는 통로 비용인지 방 내용인지 구분이
  없다. 처음엔 "방에 들어선 직후 한 건이 그 방 내용"으로 갈랐는데, **빈 방은 내용 이벤트를 하나도
  내지 않아** 다음 통로 비용이 빈 방 줄에 붙었다(구현 중 검증 하니스가 잡음). 빈 방은 14방 중 절반
  가까이라 흔한 경로다.
- **부류**: 소속을 값에 안 적고 **순서로 추론**하는 묶기. "직후 한 건"은 모든 종류가 정확히 한 건을
  낸다는 가정에 기대며, 아무 것도 내지 않는 종류 하나가 규칙을 조용히 깬다. 전투 로그
  (`BattleLog.lines`)는 이벤트마다 `actor` 가 박혀 있어 이 부류가 아니다 — 주인이 값에 있으면 안전하다.
- **처방**: 순서로 갈라야 한다면 조건을 **다음 이벤트**로 잡는다(`.entered` 가 뒤따르면 그 데미지는
  통로 비용 — 통로 비용은 항상 1 이상이라 방 내용 뒤에 입장이 바로 붙지 않는다). 회귀 가드는
  **빈 방 두 칸을 연달아 지나는 트리거**를 직접 재현한다
  (`DungeonNarrationTests.testTrailDoesNotChargeEmptyRoomForTheNextCorridor`).
  더 나은 근본 처방은 이벤트에 출처를 적는 것(`.damaged(Int, source:)`)이다 — 순서 추론이 아예 사라진다.
  (`DungeonNarration.swift`, 2026-08-24.)

## 되돌아올 수 있는 방의 비용은 "한 번만 내는 것"인지 값에 적어야 한다

- 층 던전에서 곁방은 본선 방에서 들어가 같은 통로로 되나온다. `DungeonRun.move` 는 방에 들어설 때마다
  방 내용을 적용했으므로, 교전 층의 곁방을 다녀오면 **부모 방의 본선 교전이 다시 붙었다**(검증
  하니스 실측: 왕복 비용이 통로 2회 + 곁방 내용이어야 하는데 부모 교전 데미지가 더 빠졌다). 설계의
  곁방 기대값(왕복 통로 3 기준 −2.1)과 "층 교전은 정확히 한 번" 보장이 둘 다 깨진다 — 교전 층에 달린
  곁방만 설계보다 10~20 비싸져, 곁방 판단이 층에 따라 다른 규칙으로 돈다.
- **왜 못 걸렀나**: 이전 구조(순환 그래프)에서는 방 재방문이 흔했고 재전투가 비용의 일부였다. 회복샘은
  "한 번만"(`usedSprings`)으로 잠겼는데 교전은 그 규칙이 없었고, 테스트는 되돌아오는 경로를 밟지 않았다
  (척추 일직선 걷기만 검증). 구조가 바뀌어 "되돌아옴"이 곁방 왕복 한 종류로 좁혀지자 그 한 종류가
  전부 결함이 됐다.
- **부류**: 재방문 가능한 방의 효과 중 **1회성인지 반복인지가 값에 적혀 있지 않은 것**. 샘·보물·교전은
  모두 1회성인데 셋 중 둘만 집합(`usedSprings`·`looted`)으로 잠겨 있었다.
- **처방**: 교전도 `fought` 집합으로 시도 안에서 방마다 한 번(`DungeonRun.move`). 회귀 가드는 **교전 층에
  매달린 곁방을 두 번 왕복하는 트리거**를 365일 안에서 골라 밟는다
  (`DungeonRunTests.testSpurIsARoundTripAndParentEncounterIsNotRefought` ·
  `testEncounterIsFoughtOncePerRun`; 가드를 빼면 두 번째 왕복 단정이 깨지는 것을 변이로 확인).
  `debugTeleport` 도 도착으로 쳐 교전을 치른 상태로 둔다 — 안 그러면 테스트가 "텔레포트 뒤 첫 되돌아옴"
  이라는 실제로는 없는 경로를 밟아 거짓 실패를 낸다. (`DungeonRun.swift`, 2026-08-25.)


## 전송 계층 정리가 UI 가 아직 그리는 세션 상태를 지우는 부류 (그리고 Bool 하나가 두 사실을 겸하면 진단이 거짓말한다)

- 대전 채팅이 "첫 대화 뒤 갑자기 **상대 앱 버전에서는 채팅을 지원하지 않습니다**"로 죽었다. 상대 버전은
  원인이 될 수 없다 — `rulesVersion` 이 다르면 대전 자체가 성립하지 않으므로(`handle(.challenge)`·
  `handle(.accept)`) **대전 중인 상대는 항상 채팅을 지원한다.** 실제 원인은 두 개였다.
- **① 정리 함수가 세션 상태까지 지웠다.** `dropConnection()`/`connectionDropped()` 가 대화 기록을 비웠는데,
  배틀이 끝나는 순간 `resolveIfReady` 가 그 정리를 지나고 결과는 재생 뒤로 미뤄진다(`deferFinish`,
  `BattleReplay.budget + 0.6` = 최대 3.0초). 그 사이 국면은 아직 `.battling` 이라 **대전 화면이 계속
  그려지고**, 방금 한 말이 사라진 빈 채팅 칸이 남는다. `connection = nil` 이 되는 자리는 4곳뿐이고
  (전수 확인) `.battling` 을 유지한 채 정리하는 경로는 이 하나다.
- **부류**: 소켓 종료 ≠ 세션 종료. 정리 함수는 **전송만** 닫고, 화면이 읽는 상태는 세션 경계
  (`beginBattle` · `dismissResult`)에서만 비운다. 형제 경로인 `MultiplayerRoomCenter` 는 이미 그렇게
  하고 있었다(배틀 시작·`leaveRoom` 에서만 리셋) — 같은 파일 안의 옳은 선례를 못 본 것이 공백이다.
- **② 사유가 둘인데 Bool 이 하나였다.** `chatIsAvailable` 이 "상대 빌드가 지원하나"와 "연결이 살아 있나"를
  겹쳐 담아, 정리가 지나간 뒤 뷰가 고를 수 있는 문구가 버전 탓 하나뿐이었다. 사용자에게 **원인을
  알려 주는 값은 사유별로 쪼갠다**(`peerSupportsChat` + `chatLockMessage`). 안 쪼개면 화면은 반드시
  없는 원인을 말한다.
- **테스트가 못 걸른 이유**: `BattleChatTests` 는 순수 조각(정규화·토큰버킷·히스토리 상한·와이어 왕복)만
  검증했고 상태 수명주기는 0건이었다 — 수신 루프가 `NWConnection` 을 요구해 상태기계를 밟을 수단이
  아예 없었기 때문이다. `handle(_:)` 을 internal 로 열어 **테스트가 실제 핸드셰이크·채팅 경로를 밟게** 했다.
  (`RankedStakeTests` 처럼 소스 문자열을 검사하는 폴백은 이 부류를 못 잡는다 — 어느 줄이 어느 국면에서
  도는지가 결함의 본체다.)
- **결함 주입에서 배운 것**: 되살린 결함을 `connectionDropped()` 쪽에만 넣었을 때는 **테스트가 통과했다**
  (공개 진입점 `forfeit()` 은 `dropConnection()` 만 지난다). 그래서 두 정리 경로가 `closeChatInput()`
  한 곳을 지나게 묶었다 — 형제 경로가 무검사로 남는 부류(위 §신뢰경계)의 같은 처방이다.
- 회귀 가드: `BattleChatTests.testTheConversationSurvivesTheSocketTeardownAndDiesWithTheSession`,
  `testAClosedSessionIsNotBlamedOnThePeerAppVersion`, `testAPeerBuildWithoutChatKeepsTheVersionMessage`.
  세 개 모두 결함을 되살려 빨간지 확인했고, 새 분기는 `llvm-cov --show-regions` 로 `^0` 이 없음을 봤다.
  (`BattleNet.swift` · `BattleView.swift` · `Localization.swift`, 2026-08-24.)

## 문구 보간에서 백슬래시가 빠지면 리터럴이 그대로 화면에 나간다

- `t("새 메시지 (count)개", "(count) new messages", "新着メッセージ (count)件")` — `\(count)` 의 백슬래시가
  빠져 세 언어 모두 화면에 `(count)` 를 그렸다. 컴파일은 통과한다(그냥 문자열이다), 타입 검사도 못 잡는다.
- **부류**: 인자를 받는 `L` 함수는 인자가 결과에 **실제로 들어갔는지**를 봐야 한다. "빈 문자열이 아니다"만
  검사하는 기존 문구 테스트(`AchievementTests` 방식)는 이 결함을 통과시킨다.
- **처방**: 전수 grep 으로 부류를 훑고(`grep -nE '"[^"]*[^\\]\((count|name|amount|…)\)'`, 이 저장소는 1건),
  회귀 가드는 세 언어에서 인자값 포함·리터럴 미포함을 같이 본다
  (`BattleChatTests.testTheNewMessageButtonShowsTheActualCount`).
  (`Localization.swift`, 2026-08-24.)

## 신뢰경계 상한을 축마다 따로 보면 **곱해서** 뚫린다

- 다단 히트(`min_hits`/`max_hits`)를 더하면서 상한을 축별로만 봤다: `위력 250`(통과) × `10 히트`(통과)
  = 한 턴 데미지 2500. 250 이 지키던 천장이 10배로 열리는데 세 검사 전부 초록이다. 흡수(`drain`)도
  같은 부류 — `100` 은 범위 안이지만 넣은 데미지를 그대로 돌려받아 매 턴 만피로 돌아간다.
- **부류**: 검증이 여러 축을 보게 되면 축의 **조합**이 만드는 값에도 상한이 있어야 한다. "필드마다
  `contains` 한 줄"은 곱·합으로 결합되는 축에서는 검증이 아니다.
- **처방**: 결합값에 직접 상한을 걸고(`power * (maxHits ?? 1) <= 250`) 상한 숫자는 **도감 최대치**를
  근거로 적는다(다단기 총합 최대 100, 흡수 최대 75 = 드레인키스). 가드는 축 하나만 극단으로
  민 케이스가 아니라 **전부 범위 안인 조합**을 쓴다
  (`BattlePhase5Tests.testStackedNewFieldsCannotSlipPastThePerFieldBounds`).
  (`MultiplayerValidation.validMoves`, 2026-08-25.)

## 본가에서 게이트와 한 몸인 확률을 게이트 없이 옮기면 배틀이 잠긴다

- 풀린치를 `meta.flinch_chance` 그대로 구현했다. 도감에서 30 을 넘는 값은 속임수(100) 하나뿐이고
  그 100% 는 "교체하고 나온 **첫 턴만**" 게이트와 한 몸이다. 게이트 없이 옮기니 우선도 +3 이 늘
  선공을 보장해 **상대가 배틀 내내 한 번도 움직이지 못한다**(냐옹이 레벨 1 습득기다).
- **부류**: 외부 데이터의 확률·배율을 그대로 쓰기 전에 **그 값이 극단인 항목**을 먼저 찾아, 그 항목이
  본가에서 무엇과 짝이 되어 있는지 본다. 평균적인 값(30%)만으로 테스트하면 극단값 하나가 기전을
  잠그는 걸 못 본다.
- **처방**: 게이트를 못 만들 땐 클램프에 **상한의 근거**를 적고(`ponytail:` 로 천장·해제 조건 명시),
  가드는 "확률이 접혔다"가 아니라 **행동 기회가 남는다**를 단언한다
  (`BattlePhase5Tests.testAHundredPercentFlinchMoveCannotLockTheOpponentOutOfTheBattle`).
  (`MoveSpec.flinchPercent`, 2026-08-25.)

## 값 하나를 두 게이트가 각자 판정하면 "같은 기준"이라는 주석만 남는다

- 도감 위력이 0 인 공격기(일렉트릭볼·지구던지기·자이로볼 …)를 `VariableDamage` 로 살렸는데,
  자동 무브셋(`pickFour`)은 `power > 0` 으로 갈라 그 부류를 **공격기 칸에도 변화기 칸에도** 못
  넣었다. 사용자 습득 경로(`canonicalLevelUpMoves`·하트비늘)는 `isUsable` 을 봐서 통과시켰으니,
  "같은 기준을 쓴다"는 주석을 달고 두 함수가 갈라져 있던 셈이다. 기전을 만든 커밋이 소비자
  하나만 고친 부류다 — `VariableDamage` 는 살렸고 `pickFour` 는 안 봤다.
- **부류**: 한 판정을 두 곳이 **각자 표현**하면(한쪽은 `power > 0`, 한쪽은 `damageClass`) 주석이
  동기화를 대신하지 못한다. 새 기전이 어떤 값의 의미를 바꿨으면(위력 0 = 변화기 → 공격기일 수도)
  **그 값을 읽는 전 지점을 grep** 한다. `power > 0` 은 "공격기냐"와 같은 뜻이 아니다.
- **처방**: 판정을 함수 하나로 올려(`VariableDamage.dealsDamage` 가 `isUsable` 을 **재사용**한다)
  갈라질 자리를 없앤다. 가드는 새 부류 **단독** 풀을 쓴다. 위력 있는 공격기를 같이 넣으면 옛
  분할에서도 초록이라 아무것도 안 지킨다
  (`BattleStageTests.testPickFourSelectsVariablePowerAttacks`).
  (`PokeAPIClient.pickFour`, 2026-08-25.)

## 축을 새로 만들면 그 축이 **정의**인 항목을 먼저 확인한다

- 반동 축(`drain` 음수)을 만들고 도감 기술은 `meta.drain` 으로 다 채웠는데, 반동이 정의인 유일한
  합성 기술 발버둥만 `drain` 이 `nil` 로 남았다. `moveDetail` 이 못 채우는 스펙이라
  (`id` 가 음수 → `needsDetailRefresh` 가 조기반환) 수렴 경로가 아예 없다. 결과는 대가 없는
  위력 50 무상성기 — PP 가 마른 쪽이 오히려 유리해진다.
- **부류**: 새 축은 **외부에서 오는 값**만 챙기고 앱이 직접 합성하는 값(`struggle`·`fallbackSet`)을
  빠뜨린다. 기존 테스트는 축을 직접 박은 스펙을 쓰니 그 구멍이 초록으로 덮인다.
- **처방**: 축을 더하면 그 축을 쓰는 합성 스펙을 grep 하고(`MoveSpec.struggle`·`fallbackSet`),
  가드는 합성 스펙을 **그대로** 엔진에 넣어 값을 단언한다
  (`BattlePhase5Tests.testStruggleCostsTheUserAQuarterOfTheDamageDealt`).
  (`MoveSpec.struggle`, 2026-08-25.)

## 읽는 사람이 없는 필드를 "정확히" 전파하려다 코드가 는다

- `AttackOutcome.isOneHitKO` 는 쓰기 6곳·읽기 0곳이었다. 주석에는 "상성·급소 문구를 붙이지 않는
  근거" 라고 적혀 있었지만, 실제 억제는 `fixedOutcome` 이 `effectiveness = 1`·`isCritical = false`
  로 못박아서 되는 것이었다 — 플래그는 아무 하중도 안 받고 있었다. 게다가 다단 루프가
  `AttackOutcome` 을 히트 결과에서 다시 만들기 때문에 **접어올림 코드가 필요했고**, 리뷰가
  "플래그가 유실된다" 를 결함으로 잡아 그 전파 코드를 실제로 늘렸다. 아무도 안 읽는 값을 정확히
  옮기려고 루프에 줄을 더한 셈이다.
- **부류**: "이 값이 유실된다" 는 리뷰 지적을 받으면 **고치기 전에 읽는 쪽을 grep** 한다. 읽기가
  0이면 정답은 전파가 아니라 삭제다. 필드의 존재 이유가 주석에만 있고 그 보장을 단언하는 테스트가
  없으면, 필드가 그 일을 하고 있는지 아무도 확인한 적이 없다는 뜻이다.
- **처방**: 주석이 주장하는 보장을 **먼저 테스트로 고정**하고(그 테스트는 결함 주입으로 RED 를
  확인한다 — 기전이 이미 동작하므로 "미구현 RED" 가 성립하지 않는다), 그다음 필드를 지운다.
  보장은 남고 전파 코드는 사라진다
  (`VariableDamageTests.testAOneHitKOSuppressesTheCritAndEffectivenessLines`).
  (`BattleEngine.AttackOutcome`, 2026-08-25.)

## 소스 스캔 가드는 창이 짧아지면 **있는 것을 없다고** 읽고, 복제하면 한쪽만 고쳐진다

- 스냅샷 생성 자리가 체중을 싣는지 소스에서 세는 가드가 호출부를 앞에서 400자만 훑었다. 특성 인자가
  붙으면서 체육관 스냅샷의 인자 목록이 그 창을 넘었고, 체중은 **멀쩡히 있는데** 가드가 없다고 실패했다.
  같은 회차에 특성용 스캔을 따로 만들 뻔했다 — 순회가 두 벌이면 다섯 번째 생성 자리가 생겼을 때
  한쪽만 고치게 된다.
- **부류**: 소스를 문자열로 훑는 가드는 대상 코드가 길어지면 **소리 없이** 무너진다. 고정 길이 창·
  고정 인자 순서·"다음 N줄" 같은 전제는 깨져도 컴파일이 통과하므로, 거짓 실패(운이 좋을 때)나
  거짓 통과(운이 나쁠 때)로만 드러난다.
- **처방**: 창은 인자 목록 최대치의 여유 배수로 잡고 **왜 그 값인지** 주석에 남긴다. 축이 늘면 스캔을
  복제하지 말고 **필수 인자 이름 배열**에 한 줄 더한다. 스캔이 자리를 하나도 못 찾는 경우도 단언한다 —
  0건은 "다 통과" 와 구별되지 않는다
  (`VariableDamageTests.testEveryBattleSnapshotSiteCarriesTheWireOnlyFields`).
  (`BattleSnapshot`, 2026-08-25.)

## 두 축을 가진 표는 `default` 가 서로 넘어오는지를 **교차**로만 잡을 수 있다

- 특성 표에 축이 둘 있다(타입 면역 `immuneMoveType`, 상태 면역 `blocks`). 각 축을 자기 축의
  특성으로만 테스트하니 라인 커버리지는 100% 인데 두 `default` 가름이 `--show-regions` 에서 `^0`
  이었다. 그 자리를 한 번도 안 밟았다는 건 **유연이 땅 기술을 막아도, 부유가 잠듦을 막아도** 아무
  테스트가 안 깨진다는 뜻이다 — 표 하나가 두 축을 다 덮는 전형적 오구현이 무방비였다.
- **부류**: 한 타입이 축을 둘 가지면 테스트는 축마다 "자기 것"만 확인하기 쉽다. 축이 서로 새는
  방향(A 축 항목이 B 축에서 참을 돌려주는)은 어느 축의 정상 테스트에도 안 걸린다.
- **처방**: 축이 둘이면 **교차 대조군**을 쓴다 — A 축 전용 항목을 B 축 경로에 넣어 아무 일도 없는지
  단언한다. 커버리지 숫자가 아니라 `--show-regions` 의 `^0` 이 이 구멍을 가리키는 유일한 신호다
  (`BattleAbilityTests.testTheTwoImmunityAxesDoNotLeakIntoEachOther`).
  (`BattleAbility`, 2026-08-25.)

## 한 지점에 모았다는 주석은 **그 지점을 안 지나는 갈래**를 셈에서 빼먹는다

- 상태 면역 특성을 `canBeAfflicted` 한 곳에 모으고 주석에 "여기 한 곳에서 갈린다" 라고 적었다.
  그런데 풀죽음만 `applySecondaryEffect` 가 `flinched` 를 **직접** 쓰고, `canBeAfflicted` 는
  `.flinch` 를 무조건 false 로 접는다 — 풀죽음은 그 "한 곳" 을 아예 안 지난다. 지금은 풀죽음을 막는
  특성이 없어 차이가 안 보이지만, 정신력(Inner Focus)을 `blocks` 에 더하면 **컴파일도 되고 읽히기도
  맞게 읽히는데 아무 일도 안 한다.**
- **부류**: "한 지점" 주장은 그 지점의 **호출부**를 세서 쓰는데, 같은 상태를 다른 필드로 표현하는
  갈래(주 상태 `status` 옆의 volatile `flinched`)는 호출부 목록에 안 나온다. 그래서 주석은 다 모은
  시점이 아니라 **대부분 모은 시점**에 쓰이고, 남은 갈래가 다음 사람의 함정이 된다.
- **처방**: "여기 한 곳" 을 적기 전에 그 판정이 쓰는 **필드 전체**를 grep 한다(`status` 만이 아니라
  `flinched`·`confusionTurns` 까지). 안 지나는 갈래가 남아 있으면 주석에 **이름을 대고** 적고,
  그 갈래를 태우려면 무엇을 먼저 옮겨야 하는지 `ponytail:` 로 남긴다 — "한 곳" 이라고만 적으면
  다음 사람은 표에 case 를 더하고 테스트 없이 넘어간다.
  (`BattleSide.canBeAfflicted`, 2026-08-25.)

## 실패와 면역을 같은 값으로 접으면 **그 값을 읽는 다음 기전**이 둘을 못 가른다

- `.noEffect`(체중 미조회·되받을 게 없음·레벨 초과)는 화면 문구를 면역과 같게 내려고
  `effectiveness = 0` 으로 접는다. 그런데 흡수 특성(저수·전기흡수)이 붙으면서 `applyAttack` 이
  **그 값 하나로** 회복을 가른다 — 물·전기 기술이 `.noEffect` 로 오면 "실패한 기술" 에서 회복한다.
  오늘 `.noEffect` 로 오는 기술이 격투·풀·강철·불꽃·에스퍼·땅·노말·얼음뿐이라 밟는 경로가 0 이고,
  그래서 테스트도 리뷰도 안 걸렸다.
- **부류**: 표시 목적으로 두 사건을 같은 값에 합치면, 나중에 그 값을 읽는 기전이 생겼을 때 합쳐진
  두 사건이 **같은 대우**를 받는다. 합칠 당시엔 읽는 쪽이 하나(문구)뿐이라 안전해 보인다.
- **처방**: 값을 합치기 전에 "이 값을 읽는 쪽이 앞으로 늘 수 있는가" 를 묻는다. 늘 수 있으면 원인을
  별도 필드로 남기고 문구만 같게 낸다. 이미 합쳤다면 도달 불가라도 **왜 지금 0 인지**(어떤 타입이
  없어서인지)를 주석에 적는다 — 그 전제가 깨지는 커밋이 그 줄을 지나가게 된다.
  (`BattleEngine.resolveSingleHit`, 2026-08-25.)


## `swift test` 가 못 보는 결함 — 번들 속성에는 게이트가 스크립트여야 한다

- **증상**: 버전을 올리거나 새로 설치할 때마다 알림·로컬 네트워크 권한 창이 다시 떴다.
- **원인**: `build-app.sh` 가 유효한 codesigning identity 를 못 찾으면 **조용히 ad-hoc 으로
  폴백**했다. ad-hoc 의 designated requirement 는 `cdhash H"..."` 라 바이너리가 1바이트만 달라도
  값이 바뀌고, macOS 는 TCC 승인을 DR 에 묶으므로 업그레이드된 앱을 **처음 보는 다른 앱**으로 본다.
  사용자는 매번 다시 승인했고, 개발자는 경고 한 줄을 빌드 로그에서 놓쳤다.
- **테스트·리뷰가 왜 못 걸렀나**: 결함이 소스가 아니라 **산출물의 속성**에 있다. `swift test` 는
  번들을 만들지도 서명하지도 않으므로 이 부류를 볼 수 있는 눈이 아예 없었다. 게이트는 릴리스
  경로(`release.yml` 의 인라인 grep)에만 있었고 **개발 경로에는 없었다** — 정작 매일 빌드하는 쪽이다.
- **부류**: 코드서명·Info.plist·엔타이틀먼트·번들 레이아웃처럼 **빌드 산출물에만 존재하는 성질**은
  단위 테스트로 못 잡는다. 그리고 "경고를 출력하고 계속하는" 폴백은 게이트가 아니다 — 로그는 아무도
  안 읽는다.
- **처방**: 그 부류의 게이트는 **스크립트**로 만들고, CI 와 로컬이 **같은 한 벌**을 쓴다
  (`scripts/verify-signing-identity.sh`, `build-app.sh` 가 서명 직후 호출, `release.yml` 이 같은
  스크립트 호출). 조용한 폴백은 중단으로 바꾸고, 우회는 명시적 환경 변수로만 연다
  (`PTB_ALLOW_ADHOC=1`). 인라인 grep 을 CI 에 다시 적으면 두 벌이 되어 한쪽만 느슨해져도 안 깨진다.
  (`scripts/build-app.sh`·`scripts/verify-signing-identity.sh`, 2026-08-25.)

## 외부 도구의 설치 경로를 손으로 적으면, 적은 사람의 환경만 지원된다

- **증상**: 대화 CLI 를 정상 설치한 사용자에게 "실행 파일을 찾지 못했습니다" 가 떴다. 기능 전체가
  없는 것처럼 보였다.
- **원인**: `standardPaths` 가 `/usr/local/bin`·`/opt/homebrew/bin`·`/usr/bin` 셋뿐이었다. npm·uv 가
  기본으로 쓰는 `~/.local/bin` 과 Claude Code 자체 설치 관리자의 `~/.claude/local` 이 빠져 있었다.
- **테스트·리뷰가 왜 못 걸렀나**: 목록을 **주어진 대로 뒤지는지** 만 시험하면(혹은 아예 안 하면)
  **목록에서 빠진 자리**는 영원히 안 잡힌다. 동작 테스트가 통과해도 결함은 목록 자체에 있다.
- **부류**: 외부 세계의 값(설치 경로·환경 변수 이름·CLI 플래그)을 코드에 적을 때, 동작 테스트는
  "적힌 것을 쓰는가" 만 증명하고 "적을 것을 다 적었는가" 는 증명하지 않는다. 종류별로 목록을 두 벌
  들면(여기선 CLI 마다 경로 배열) 새 자리가 한쪽에만 들어가 나머지는 계속 못 찾는다.
- **처방**: 목록은 **한 벌**로 두고 갈리는 부분만 파라미터로 뺀다(디렉터리 목록 × 바이너리 이름).
  그리고 **목록의 내용 자체를 고정하는 테스트**를 따로 둔다
  (`testTheSearchListCoversHowThesCLIsAreActuallyInstalled`) — 동작 테스트와 목적이 다르다.
  덧붙여 심볼릭 링크는 풀지 않는다: `~/.local/bin/claude` 는 버전 디렉터리를 가리키므로 대상 경로를
  저장하면 CLI 가 업데이트되는 순간 죽는다.
  (`PokemonChatProviderExecutableResolver`, 2026-08-25.)

## 목록에 "그 필드가 없는 행" 을 들이면, 기존 필터가 조용히 뜻을 바꾼다

- **증상 (될 뻔한 것)**: 도감을 보유 종만 그리던 화면에서 미포획 칸까지 열었다. 미포획 칸에는
  희귀도·이로치가 없다. 기존 희귀도 필터를 그대로 두면 "전설만 보기" 가 실루엣 600칸을 함께
  끌고 오거나(느슨한 판정), 반대로 필터를 켠 순간 실루엣이 통째로 사라져 고장으로 읽힌다.
- **원인의 부류**: 목록의 **행 집합을 넓히는 변경**은 그 목록에 걸린 **모든 필터의 정의역**을 함께
  넓힌다. 필터는 그대로 두었는데 뜻이 바뀐다 — 새 행이 그 축의 값을 안 갖기 때문이다. 새 필드를
  더할 때는 읽는 곳을 찾아 헤매지만(그건 grep 으로 잡힌다), **새 행**을 더할 때는 기존 조건식이
  문법적으로 멀쩡해서 아무 신호가 없다.
- **테스트가 왜 못 걸렀나**: 필터 판정이 뷰 안 `body` 의 `filter` 클로저에 있었다. 테스트는 그
  규칙을 **흉내 내는** 수밖에 없어서(같은 조건식을 테스트에 다시 적는 방식), 뷰와 테스트가 각각
  달라져도 둘 다 초록이다.
- **처방**: (1) 판정을 뷰 밖 값 타입으로 올린다(`CompanionStore.DexFilter.matches`) — 테스트가
  화면이 쓰는 바로 그 함수를 잰다. (2) 축마다 **미포획 행에 걸리는지**를 명시적으로 정한다:
  타입은 걸리고(잡기 전에도 아는 값), 희귀도·이로치는 안 걸린다. (3) 안 걸리는 축을 고른 순간
  범위가 좁아진다는 사실을 화면에 드러낸다 — "잡은 것만 보기" 가 켜진 채 잠기고 툴팁이 이유를
  말한다. 조용히 좁히면 사용자에겐 결함으로 보인다.
  (`DexFilter`·`DexGridView`, 2026-08-26.)

## 일회성 신호를 끄는 자리를 조건부로 그려지는 화면에 두면, 신호가 갇힌다

- **증상**: 홈 탭을 보다 창을 닫고 다시 열면 **매번** 친구 탭으로 튀었다. 한 번이 아니라 계속.
- **원인**: `pendingAttention` 은 "팝오버를 열 때 친구 탭으로 데려가라" 는 일회성 신호다. 세우는
  곳은 배틀 시작·신청 수신, 끄는 곳은 `BattleView.onAppear` 하나였다. 그 뒤 친구 탭에 관문
  (`FriendView`)이 생기면서 `BattleView` 는 **배틀이 진행 중일 때만**(`phase != .ready`) 그려지게
  됐다. 체육관 한 판을 끝내면 신호는 켜진 채 `phase` 가 `.ready` 로 돌아가고, 관문은 선택 화면을
  그린다 — 신호를 끌 화면이 영영 안 뜬다. 열 때마다 튀는 상태로 굳는다.
- **부류**: **화면 하나를 두 화면으로 쪼개는 변경**은 그 화면이 지고 있던 부수 책임(신호 끄기,
  타이머 멈추기, 읽음 표시)을 함께 옮겨야 한다. 쪼갠 쪽은 "무엇을 그리는가" 만 보고 옮기므로,
  `onAppear` 에 붙어 있던 책임은 조용히 조건부가 된다. 컴파일도 되고 테스트도 초록이다.
- **테스트가 왜 못 걸렀나**: 신호의 수명이 **뷰 계층에만** 있었다. 세우는 쪽은 Core, 끄는 쪽은
  View 라 어느 단위 테스트도 한 바퀴(세움 → 소비 → 다시 안 튐)를 돌 수 없었다.
- **처방**: (1) 읽는 일과 끄는 일을 **한 호출로 묶는다**(`consumePendingAttention()` → 켜져
  있었으면 끄고 true). "읽고 안 끄는" 경로가 문법적으로 사라진다. (2) 저장 프로퍼티는
  `private(set)` 으로 잠가 화면이 직접 못 끄게 한다. (3) 그래도 우회할 수 있으니 소스 스캔
  가드를 둔다 — UI 어느 파일에도 `pendingAttention = false` 가 없어야 한다.
  (`BattleCenter`·`PopoverView`, 2026-08-26.)

## 정사각 틀에 원본을 "채우면", 정사각이 아닌 원본은 조용히 늘어난다

- **증상**: 플로팅 펫이 뭉개져 보였다. 사용자는 "해상도가 낮다" 로 느꼈는데, 절반은 해상도가
  아니라 **가로세로 왜곡**이었다. 라플라스(원본 102×65)가 96×96 틀에서 세로로 57% 부풀었다.
- **원인**: `Image.resizable()` 뒤에 `.frame(width:height:)` 만 걸었다. `.aspectRatio(.fit)` 이
  없으면 원본을 그 틀에 **늘려 채운다**.
- **왜 오래 안 보였나**: 왜곡이 생기는 원본이 한 종류뿐이었다. 정적 스프라이트(96×96)와
  아이템(30×30)은 전부 정사각이라 같은 코드가 아무 일도 안 했다. 애니메이션 GIF 만 스프라이트
  경계로 잘려 있어 비정사각인데(표본 20종 중 18종), 그 경로는 **화면에서만** 보인다.
  원본 크기를 아는 사람이 없으면 "원래 저렇게 생겼나" 로 넘어간다.
- **부류**: **입력의 한 갈래만 어떤 성질을 어기는** 경우. 나머지 갈래가 그 성질을 우연히
  만족하면 잘못된 코드가 대부분의 경우에 정답을 낸다 — 테스트도 보통 그 다수 갈래로 짠다.
  "이 코드가 가정하는 성질이 무엇이고, 그걸 어기는 입력이 실제로 오는가" 를 데이터로 확인한다.
- **처방**: `.aspectRatio(contentMode: .fit)` 을 짝으로 건다. 그리고 가드를 둔다 —
  `SpriteView` 안의 `.resizable()` 개수와 `.aspectRatio(contentMode: .fit)` 개수가 같아야 한다.
  왜 필요한지 잊히지 않게 **실측 원본 크기 표**를 테스트에 같이 남긴다(전부 정사각이면 규칙이
  무의미해 보여 언젠가 지워진다).
  (`SpriteView`, 2026-08-26.)

## 화면이 "누구의 것" 인지를 실행기가 모르면, 승인 카드가 가리킨 개체와 실행 대상이 갈라진다

- **증상**: 박스에 있는 개체의 대화 창에서 "이상해씨한테 사탕 먹여 줘" 를 승인하면, 카드는 그 아이
  이름으로 물어보는데 **나와 있는 다른 개체**가 레벨업했다. 기억(`memory.record`)은 더 조용했다 —
  대화 주인의 앨범에는 아무것도 안 남고, 활성 개체 앨범이 남의 대화 문장으로 채워졌다.
- **원인**: 실행기(`PokemonChatToolbox`)가 `CompanionStore` 를 통째로 들고 `activeMonID` 를 암묵
  대상으로 삼았다. 대화 창은 활성 개체뿐 아니라 **로스터에서 박스 개체로도 열린다**
  (`PokemonRosterView`) — 실행기는 자기가 어느 창에서 불렸는지 알 방법이 없었다.
- **왜 테스트가 못 걸렀나**: 있었다. `testApprovedTimerCallExecutesOnlyForItsOwnCompanion` 이
  "스토어가 제안의 개체 ID 를 실행기에 넘긴다" 를 확인했다. 그런데 **프로덕션 클로저가 그 값을
  버렸다** — `{ call, _ in await toolbox.run(call) }`. 계약의 절반(넘긴다)만 시험하고 나머지
  절반(받아서 쓴다)은 시험하지 않아, 이름이 정확히 그 성질을 주장하는 테스트가 초록으로 남았다.
- **부류**: **값을 넘기는 쪽만 시험하고 받는 쪽이 그 값을 쓰는지는 시험하지 않는** 경우. 클로저·
  콜백·델리게이트로 값을 건네는 자리마다 생긴다(`_` 로 무시한 인자가 신호다). 테스트가 프로덕션과
  같은 모양의 클로저를 직접 써야 한다 — 스텁이 값을 성실히 쓰면, 프로덕션이 버려도 초록이다.
- **처방**: 대상을 프로토콜 인자로 올려 **기본값을 주지 않는다**(`run(_:owner:)`). 안 넘기면
  컴파일이 안 되므로 "잊는" 경로가 사라진다. 무엇이 주인을 필요로 하는지는 한 곳에서 분류하고
  (`PokemonChatToolCall.actsOnTheActiveCompanion`) 가드도 한 곳에서 읽는다 — case 마다 두면 다음에
  더하는 도구가 조용히 빠진다. 예외(`companion.switch`)는 취향이 아니라 성질로 정한다: 인자로
  대상을 지목하는 도구는 남의 대화에서도 뜻이 분명하다.
  (`PokemonChatTools`, 2026-08-27.)

## 정산이 "누가 나갔나" 를 안 들고 있으면, 교체 한 번으로 보상 귀속이 바뀐다

**미해결 — 범위 밖으로 남긴 기존 결함(2026-08-27 판단).** 고칠 때 이 항목을 근거로 쓴다.

- **증상**: 모험을 보낸 뒤 다른 동료로 교체하고 정산하면, **나가지 않은 개체**가 경험치를 받는다.
- **원인**: `switchCompanion` 은 `state.adventure` 를 건드리지 않고, `claimAdventure` 는
  `state.active` 에 경험치를 넣는다. 둘 다 "지금 나와 있는 개체" 를 대상으로 삼는데, 모험은
  *과거의* 개체가 나간 것이다.
- **왜 지금 안 고치나**: `AdventureRun` 이 들고 있는 건 `companionSpeciesID`(종 번호)뿐이다 —
  개체 UUID 가 없어 "나간 아이에게 준다" 를 **표현조차 못 한다**. 세이브 필드 추가 + 구버전 디코딩 +
  무결성 서명까지 따라오므로, 대화 도구 작업에 섞으면 리뷰 단위가 흐려진다.
- **부류**: **행위의 주체를 기록하지 않고 "현재" 로 대체하는** 경우. 비동기적으로 끝나는 일
  (모험·부화·타이머)마다 생긴다 — 시작과 정산 사이에 주체가 바뀔 수 있으면, 주체를 값에 적어야 한다.
  같은 부류를 이미 한 번 겪었다: 승인 카드가 개체 ID 를 들고 다니게 만든 이유가 정확히 이것이다
  (`PokemonChatToolProposal.companionID`).
- **지금 상태**: UI 도 같은 규칙이라 대화가 새 구멍을 만든 것은 아니다. 다만 `adventure.claim` 과
  `companion.switch` 가 둘 다 도구가 된 뒤로는 대화가 그 두 수를 연달아 제안할 수 있다.

## 취소가 "완료 여부" 를 안 보면, 정산을 기다리던 보상이 종료 한 번에 사라진다

- **증상**: 25분 집중을 걸고 앱을 닫았다 30분 뒤에 열면 타이머는 idle 이고 모험만 남는다(정산 대기).
  이 구간에서 대화의 `pokedoro.stop` 을 승인하면 **받을 수 있던 보상이 그냥 없어진다.** 카드는
  "진행 중인 모험은 보상 없이 취소돼" 라고 물어봤고, 진행 중인 모험은 없었다 — 사용자는 잃을 것이
  없다고 읽고 눌렀다.
- **원인**: `cancelFocusAdventure` 는 `state.adventure` 를 완료 여부와 무관하게 비운다.
  `stopFocusSession` 이 그걸 그대로 불렀다. 화면은 같은 구간에 취소 버튼을 **아예 그리지 않아**
  이 경로가 UI 에 없었고, 대화가 그 경로를 새로 열었다.
- **왜 테스트가 못 걸렀나**: 종료 테스트가 시작 **직후**(모험 미완료)에만 멈췄다. 정산 대기 구간은
  `TestClock` 을 모험 길이만큼 감아야 나오는데, 그걸 감는 테스트는 `pokedoro.start` 거절 쪽에만
  있었다. 승인 문구 테스트도 "모험" 이라는 단어가 들어 있는지만 봤다 — 문장이 **참인지**는 아무도
  안 봤다.
- **부류**: **취소·정리 경로가 "아직 안 받은 것" 을 확인하지 않는** 경우. 시작과 끝 사이에 값이
  쌓이는 일(모험·부화·타이머·집계)마다 생긴다. 같은 부류를 이미 겪었다: `completeFocusSession` 이
  `save()` 만 하고 정산을 빼먹어 보상이 안 들어왔다(#8). 정산 진입점이 하나면(`claimAdventure`)
  취소 경로는 그것을 **먼저 부르기만** 하면 된다.
- **처방**: `stopFocusSession` 이 `claimAdventure()` → `cancelFocusAdventure()` 순서로 부른다
  (`startFocusAdventure` 가 이미 같은 순서다). `claimAdventure` 는 완료된 run 만 정산하므로 진행 중
  취소는 그대로 보상 없이 취소된다 — 회귀 테스트가 **두 분기를 다** 밟는다
  (`testStoppingFocusSettlesAFinishedAdventureButStillCancelsARunningOne`). 승인 문구도 "진행 중인"
  이 뜻을 갖게 다시 적었다.
  (`PokemonChatTools`, 2026-08-27.)

## 인자를 나중에 채우는 도구를 루프에서 돌리면, 왕복을 다 태우고 결과를 잃는다

- **증상**: 대화가 `[[tool:memory.record]]` 를 붙일 때마다 CLI 가 **네 번** 떴다. 그리고 모델이
  다음 턴에 마커를 다시 붙이지 않으면 기억이 **아예 안 남았다**(앨범이 비어 있다).
- **원인**: `memory.record` 는 본문을 파서가 채우지 않는다 — 스토어가 루프 **뒤에** 가드를 통과한
  답변으로 채운다. 그런데 루프가 그 호출을 빈 본문으로 실행해 `memory not recorded` 를 모델에게
  돌려주고, 승인 도구가 아니므로 `break` 도 안 걸려 남은 왕복을 전부 썼다. 마지막 라운드의 답변에
  마커가 없으면 `call` 이 비어 루프 뒤 기록도 건너뛴다.
- **왜 테스트가 못 걸렀나**: 기억 테스트의 프로바이더가 **같은 답변을 무한 반복**했다
  (`CountingToolProvider`). 그래서 마지막 라운드에도 마커가 남아 `call` 이 채워졌고 앨범도 채워졌다 —
  결함 트리거는 "마커를 한 번만 붙이는 모델" 인데, 테스트는 그 경로를 밟을 수 없는 스텁을 썼다.
- **부류**: **같은 응답을 반복하는 스텁으로 다중 라운드 루프를 시험하는** 경우. 라운드마다 값이
  바뀌는 것이 루프의 존재 이유인데, 반복 스텁은 "마지막 라운드에 무엇이 남아 있나" 를 언제나
  성공으로 만든다. 루프 테스트에는 답변을 갈아 주는 프로바이더(`ScriptedToolProvider`)를 쓴다.
- **처방**: 루프가 `.memoryRecord` 를 만나면 실행하지 않고 즉시 나온다 — 기록은 루프 뒤 한 곳뿐이다.
  회귀 테스트는 답변이 바뀌는 프로바이더로 **왕복 수와 기록 유무를 함께** 본다
  (`testMemoryRecordCostsNoExtraRoundAndSurvivesAModelThatSaysItOnce`).
  (`PokemonChat`, 2026-08-27.)

## 위임한 곳이 조용히 거절하는데, 실행기는 자기 가드만 보고 성공을 돌려준다

- **증상**: 대화가 "방금 이야기를 기억해 둘게" 라고 하고 앨범엔 아무것도 없었다(답변이 180자를
  넘은 경우). 같은 부류로 "나, 진화했어!" 라고 하고 형태는 그대로인 경우도 있었다(카드가 떠 있는
  사이 시간대·요구 기술·요구 파티원 조건이 무너진 경우).
- **원인**: 실행기가 **자기 앞의 가드**만 확인하고(빈 본문인가 / 대기 중인 진화가 있는가) 실제 일을
  하는 쪽(`PokemonMemoryAlbum.record`, `CompanionStore.acceptEvolution`)이 받아들였는지는 보지
  않았다. 둘 다 `Void` 를 돌려주고 조건이 안 맞으면 **조용히 돌아간다** — 거절이 값으로 나오지
  않으니 부르는 쪽이 알 방법이 없다.
- **왜 테스트가 못 걸렀나**: 두 테스트 모두 **조건이 맞는 경로**만 밟았다(짧은 문장, 레벨이 충족된
  진화). 그러면 "실행기가 결과를 확인한다" 와 "자기 가드만 본다" 가 구분되지 않는다 — 두 구현이
  같은 초록을 낸다. 거절 케이스도 있었지만 그건 **실행기 자신의** 가드(공백 본문·대기 없음)라,
  위임한 쪽의 가드는 한 번도 안 밟혔다.
- **부류**: **`Void` 를 돌려주는 함수에 일을 넘기고 성공을 가정하는** 경우. 넘겨받는 쪽이 자기
  가드를 가진 자리마다 생긴다 — 특히 두 가드가 **다를 때**(실행기는 "비었나", 앨범은 "180자
  넘나") 짧은 값으로만 시험하면 둘이 같아 보인다. 도구 결과는 모델에게 **사실**로 나가므로 이
  부류는 곧 환각 생산이다.
- **처방**: 거절을 **값으로** 올린다(`record` 는 `@discardableResult -> Bool`), 값을 못 올리는
  곳은 **관측 가능한 결과**로 판정한다(`acceptEvolution` 전후의 `activeStageIndex`). 회귀 테스트는
  **위임한 쪽만 거절하는** 입력으로 잡는다 — 180자 초과 본문, 카드가 뜬 뒤 무너지는 진화 조건
  (`testAMemoryTheAlbumRefusesIsNotReportedAsRecorded`,
  `testEvolutionThatSilentlyFailsIsNotReportedAsAccepted`).
  (`PokemonChatTools`, 2026-08-28.)

## 같은 값을 쓰는 경로가 둘인데 저장소가 중복을 안 막으면, 앨범에 같은 줄이 두 번 남는다

- **증상**: 여섯 번째 메시지에서 모델이 `[[tool:memory.record]]` 를 붙이면 같은 문장이 앨범에 두 번
  남았다.
- **원인**: `PokemonChatStore.send` 가 같은 `safeReply` 를 두 경로로 쓴다 — 도구 경로와
  `lifetimeUserMessageCount % 6` 주기 기록. `record` 는 이벤트 기억만 `eventID` 로 중복을 막고 대화
  기억은 막지 않는다.
- **왜 테스트가 못 걸렀나**: 기억 테스트가 전부 **한 턴**만 보냈다(`% 6` 은 여섯 턴째에만 참). 두
  경로가 겹치는 턴 번호를 아무도 밟지 않았다.
- **부류**: **주기·임계값으로만 열리는 두 번째 경로**. 한 번의 호출로 시험하면 영영 안 열린다 —
  `% N`·`>= threshold`·"N번째" 가 붙은 자리는 그 N을 실제로 돌려야 한다.
- **처방**: 도구가 이미 남긴 턴에는 주기 기록을 건너뛴다. 회귀 테스트는 여섯 턴을 실제로 보낸다
  (`testTheSixthMessageDoesNotRecordTheSameMemoryTwice`).
  (`PokemonChat`, 2026-08-28.)

## 예산 게이트를 최악이 아닌 픽스처로 재면, 상한을 넘겨도 초록이다

- **증상**: 시스템 프롬프트 상한 테스트가 통과하는데 실제 프롬프트는 상한을 넘을 수 있었다.
- **원인**: 픽스처에 별명이 없고(`nickname: nil`) 배운 기술이 비어 있었다. 그 둘은 **채워지면 더
  긴** 절이다 — 별명은 종 이름을 괄호로 함께 싣고, 기술은 `not loaded` 열 글자를 최대 네 개의
  이름으로 바꾼다. 반대로 타입·다음 진화는 **비어 있을 때가 더 길다**(`not loaded`·`not known`).
- **왜 테스트가 못 걸렀나**: 이 테스트가 곧 그 게이트다. "종 정보를 가득 채운다" 를 최악이라고
  읽었는데, 최악은 절마다 방향이 다르다.
- **부류**: **한 방향으로만 채운 픽스처로 상한을 재는** 경우. 길이·크기 게이트는 절마다 어느 쪽이
  긴지를 따로 판단해야 한다.
- **처방**: 절마다 긴 쪽으로 채우고 실측값을 주석에 남긴다(실측 2_847 → 상한 2_860). 판단 근거는
  `chat-tool-sandbox.md` 의 "프롬프트 예산" 절에 남긴다.
  (`PokemonChatTests`, 2026-08-28.)

## 고정 브랜드 색을 글자에 쓰면, 배경이 모드를 따라갈 때 한쪽에서 사라진다

- **증상**: 다크 모드에서 **고른 탭의 글자만** 안 보였다. 알약(선택 표시)은 멀쩡히 보이는데 그 위
  글자가 배경에 묻혔다.
- **원인**: `PokedoroTheme.ink` 는 다크 네이비 **상수**라 모드를 따라가지 않는다. 뒤에 깔리는 알약은
  `controlBackgroundColor`(모드에 따라 뒤집힘) + 테마 파랑 18% 라 다크에서 거의 같은 색이 된다.
  대비 — 라이트 9.79:1, **다크 1.07:1**.
- **왜 안 걸렸나**: 테마가 "밝은 필드" 전제로 설계됐고, 라이트 모드로만 보면 아무 문제가 없다.
  색 대비는 **두 모드를 다 봐야** 드러나는 부류다. 컴파일러도 테스트도 색을 안 본다.
- **부류**: 고정 색과 적응 색을 **겹쳐 놓는 것**. 한쪽만 모드를 따라가면 어느 모드에선가 반드시
  대비가 무너진다. 배경이 적응색이면 전경도 적응색이어야 하고, 배경이 고정색이면(예: 랭크 배지의
  단색 틴트) 전경도 고정색(`.white`)이어야 한다 — **짝을 맞춘다.**
- **처방**: 글자는 `Color.primary`/`.secondary` 로. 브랜드 색은 배경(알약)이 이미 나르고 있어 글자에
  넣을 이유가 없었다. **`ink` 자체를 적응색으로 바꾸는 건 답이 아니다** — `PokeBallMark` 가 자기가
  그린 흰 원 위에 ink 로 선을 긋기 때문에, 다크에서 밝아지면 몬스터볼이 흰색 위 흰색이 된다.
  가드는 `.foregroundStyle(` 이 있는 **줄 전체**를 본다 — 결함이 있던 형태가
  `.foregroundStyle(선택 ? PokedoroTheme.ink : …)` 라, 함수 바로 뒤만 보는 스캔은 삼항을 놓친다
  (처음 쓴 가드가 실제로 그렇게 새서 고쳤다).
  (`PokedoroTabBar`, 2026-08-28.)

## 팝오버를 정확한 소스 뷰가 아니라 감싸는 큰 컨테이너에 붙이면, 첫 프레임이 튄다

- **증상**: 소유 포켓몬 탭에서 정보(`i`) 버튼을 누르면 상세정보 팝오버가 **하단에 한 번 떴다가
  오른쪽으로 튀었다.**
- **원인**: `.popover(item: $infoTarget)` 이 눌린 버튼이 아니라 **탭 전체를 감싸는 520pt VStack**
  에 붙어 있었다. SwiftUI 는 첫 프레임에 그 수정자가 붙은 뷰의 경계를 기준으로 팝오버 위치를
  잡는다(값이 뜬 시점엔 아직 어느 자식 뷰가 눌렸는지 모른다) — 다음 프레임에 실제 소스 앵커를
  알게 되며 재계산해 위치가 튄다.
- **부류**: `.popover`/`.sheet`/`.popoverTip` 같은 **소스-앵커 기반 프레젠테이션**을 실제 트리거
  뷰가 아니라 상위 컨테이너에 붙이는 패턴. 컴파일도 되고, 팝오버가 결국 뜨기는 하니 "작동은
  한다"로 보여 리뷰에서 안 걸린다. 증상은 오직 **첫 프레임의 위치**로만 나타난다.
- **부수 효과**: 같은 원인이 "열어 둔 채 다른 대상을 누르면 상세창이 유지되는가" 에도 걸려 있었다.
  앵커가 카드마다 다른데 팝오버 인스턴스가 상위에 하나뿐이면, 대상이 바뀔 때도 재앵커링이 애매해
  진다. 앵커를 정확한 트리거 뷰로 내리고 모든 트리거가 **같은 바인딩**을 공유하게 하면, 다른
  트리거를 누르는 순간 이전 것은 `isPresented=false`, 새 것은 `true` 로 동시에 바뀌어 손으로
  먼저 닫을 필요 없이 팝오버가 새 앵커·새 내용으로 자연히 옮겨간다 — 별도 처리가 필요 없었다.
- **처방**: 팝오버는 실제로 눌리는 뷰(버튼)에 직접 건다. 여러 트리거가 하나의 상세 상태를
  공유해야 하면 `item:` 대신 `isPresented:` + 공유 `Binding` 을 각 트리거 옆에서 자기 항목의
  id 와 비교해 계산한다(`infoTarget?.id == mon.id`). 회귀 가드는 렌더 없이 **소스에서** 확인한다 —
  옛 문자열 패턴(`popover(item: $전역상태)` 이 body 레벨에 있는 것)이 다시 나타나지 않는지,
  그리고 새 앵커가 실제 트리거 뷰 근처에 있는지.
  (`RosterMonCard`, 2026-08-28.)

## 자식 프로세스에 작업 디렉터리를 안 정하면, GUI 앱의 `/` 를 물려받아 디스크 전체가 루트가 된다

- **증상**: 포켓몬과 대화하는 도중 "Pokédoro 가 데스크탑/문서 폴더에 접근하려 합니다" 권한 창이
  **계속** 떴다. 대화는 파일과 아무 상관이 없는 기능이다.
- **원인**: 자식을 띄우는 유일한 자리(`PokemonChatCommandRunner.Job.start`)가
  `process.currentDirectoryURL` 을 정하지 않아 **앱의 cwd 를 물려받았다.** 메뉴바 앱의 cwd 는
  `/` 다(launchd·LaunchServices 가 그렇게 띄운다 — 실행 중 인스턴스에 `lsof -p` 로 확인). 그러면
  대화 CLI 의 프로젝트 루트가 디스크 전체가 되어 시작 스캔이 `~/Desktop`·`~/Documents` 를 밟고,
  macOS 는 자식의 파일 접근을 **책임 프로세스**(= 앱)로 돌려 앱 이름으로 창을 띄운다. 한 번의
  전송이 CLI 를 `maxToolRounds + 1`(=4) 번까지 띄우므로 창은 "계속" 떴다.
- **부류**: **도구 목록을 닫는 것과 실행 환경을 닫는 것은 다른 일이다.** 대화 샌드박스는 5겹의
  경계를 두고 목록·인자·승인·응답을 전부 닫아 뒀는데, 그 겹 전부가 "모델이 무엇을 부를 수 있나"
  만 본다. 자식이 **어디서** 도는지는 아무 겹도 안 봤다. 같은 부류는 환경변수·`TMPDIR`·표준입출력
  처럼 자식이 부모에게서 조용히 물려받는 값 전부다 — 안 정한 것은 "없는 것" 이 아니라
  "부모의 것" 이다.
- **왜 테스트가 못 걸렀나**: 겹 1 의 테스트가 **인자 배열 전체를 문자열로 고정**해서 초록이었다.
  인자는 완벽했다 — cwd 는 인자가 아니다. 격리 계약을 인자로만 재면 실행 환경은 영영 무검사로
  남는다. 그래서 회귀 가드는 `/bin/pwd` 를 **실제로 띄워** 자식의 cwd 를 읽는다.
- **함정**: `XCTAssertNotEqual(stdout, "/")` 로 쓰면 안 된다. `swift test` 의 cwd 는 저장소
  루트라 결함이 있어도 **언제나 통과한다**. 부모의 cwd 가 무엇이든 걸리게 하려면
  `XCTAssertEqual(stdout, <앱 소유 경로>)` 처럼 **양성으로** 고정해야 한다.
- **곁가지 (같은 스윕에서 나옴)**: `--safe-mode` 는 훅·플러그인만 끄고 사용자
  `~/.claude/settings.json` 의 env 를 그대로 실었고, 실행마다 그 파일에 permission 규칙을
  **쓰기까지** 했다(`--debug-file` 실측). codex 는 `--ignore-user-config --ignore-rules` 로
  처음부터 닫혀 있었다 — **같은 부류를 제공자 한쪽에만 적용해 둔 상태**였다. claude 에
  `--setting-sources ""` 를 더해 맞췄다.
- **처방**: 외부 프로세스를 띄우는 자리는 `currentDirectoryURL` 을 **명시**한다. 앱이 만든 빈
  디렉터리를 준다(`PokemonChatWorkspace`). 폴백 분기는 `static let` 안에 두지 말고 주입 가능한
  함수로 뺀다 — App Support 가 살아 있는 기계에서는 절대 안 돌아서 `llvm-cov` 에 `^0` 으로 남고,
  게이트는 90.65% 초록인 채 그 분기를 아무도 검증하지 않는다(실제로 이번에 `^0` 을 보고 뺐다).
  권한 창을 끄는 스위치는 없다 — `NSDesktopFolderUsageDescription` 은 문구만 바꾼다.
  (`PokemonChat.swift`, 2026-08-28.)

## 후보가 모자랄 때 "완화" 하면, 완화된 풀의 정렬이 그대로 따라온다

- **증상**: 웨이브 런 초반 야생의 세기가 널뛰었다. 레벨 2 야생이 어떤 종은 태클만, 어떤 종은
  그 종의 **최종기**를 들고 나왔다. 밸런스 값을 아무리 맞춰도 초반 판이 종 뽑기로 갈렸다.
- **원인**: `moveCandidates` 는 "현 레벨까지 배우는 기술"이 4개가 안 되면 학습표 **전체**로
  풀었는데, 정렬이 완화 전과 같은 **습득레벨 내림차순**이었다. 완화의 뜻은 "칸을 채운다" 인데
  정렬의 뜻은 "그 레벨의 주력을 앞에 둔다" 라, 완화된 순간 정렬이 정반대 일을 한다.
- **테스트가 왜 못 걸렀나**: 유일한 테스트가 `level: 50` 이었다. 그 레벨에선 후보가 4개를 넘어
  **완화 분기 자체를 밟지 않는다.** 완화는 저레벨에서만 도는데 저레벨 케이스가 없었다.
- **부류**: **fallback 이 정상 경로의 정렬·필터를 물려받는** 경우. 정상 경로에서 옳던 정렬이
  완화된 풀에서는 뜻이 뒤집힌다. 완화·폴백을 넣을 때는 "이 정렬/우선순위가 넓힌 풀에서도 같은
  뜻인가" 를 따로 묻는다. 컴파일도 되고 대부분의 입력에서 정상이라 조용하다.
- **처방**: 완화된 칸은 **가장 일찍 배우는 기술부터** 채운다(오름차순). 회귀 테스트는 완화
  분기를 밟는 레벨(`level: 2`)로 잡아 최종기가 두 번째 칸에 오지 않는지 본다.
  (`PokeAPIClient.moveCandidates`, 2026-08-28.)

## 조작 방어로 넣은 개수 절단을 자기 세이브 로드에도 걸면, 방금 얻은 개체가 다음 실행에 사라진다

- **증상**: 졸업시킨 포켓몬(악비아르)이 다음 앱 실행에서 박스에 없었다. 도감 기록과
  `collectedFinals` 는 남아 있어 "졸업은 됐는데 개체만 증발" 한 상태였다.
- **원인**: `SaveTransfer.sanitized` 의 `Array(s.boxedMons.prefix(100))`. 이 함수는 **불러오기
  경계**로 설계됐지만 `CompanionStore.load()` 가 자기 디스크 세이브에도 같은 함수를 걸고 있었다.
  박스는 상한 없이 뒤로 append 되므로(졸업·부화·교환), 100마리를 채운 뒤 얻은 개체는 항상
  잘리는 쪽에 있었다. 로그도 안 남는다 — 조용한 영구 유실이다.
- **테스트가 왜 못 걸렀나**: 박스 관련 테스트가 전부 1~2마리 픽스처였다. 절단 분기(101마리)를
  밟는 케이스가 없어서, "로드가 박스를 자른다" 는 사실 자체가 관측되지 않았다.
- **부류**: **신뢰경계용 방어를 신뢰 경로에 재사용**하는 경우. 값 클램프(범위 교정)는 양쪽에
  걸어도 무해하지만, **개수 절단은 데이터 삭제**라 출처를 구분해야 한다. 같은 함수 안에서도
  "교정" 과 "삭제" 는 다른 규칙이다. 절단 상한을 정할 때는 **정상 플레이가 그 값에 닿는지**도
  본다 — 실제 사용자 박스가 이미 100이었다.
- **처방**: `sanitized(_:origin:)` 으로 출처를 나눠 개수 절단은 `.importedFile` 에만 건다.
  잘라야 할 때는 **최신 쪽을 남기고**(박스는 뒤로 쌓인다) 몇 마리를 버렸는지 로그에 남긴다.
  상한은 1000 — 파싱 시간 방어는 `maxFileBytes`(8MB)가 이미 한다.
  회귀 테스트는 절단 분기를 밟는 101마리로 잡고, 졸업 경로도 함께 재현한다
  (`BoxCapacityTests`, 2026-08-28).

## 문자열 보간의 백슬래시 누락은 **컴파일러도 warning 게이트도 커버리지도** 못 잡는다

- **증상**: Memory Home 방문 시트가 상대 포켓몬의 종 번호 대신 `#(profile.speciesID)` 라는
  글자를 그대로 화면에 찍었다. `fb7e67e` 로 배포된 뒤 발견됐다.
- **원인**: `"\(x)"` 를 `"(x)"` 로 적었다. Swift 문법상 **완전히 유효한 리터럴**이라 컴파일러가
  할 말이 없다. 타입 에러도, warning 도 없다.
- **왜 리뷰가 못 걸렀나**: 그 줄이 같은 파일의 다른 `Text(...)` 보간과 눈으로 구별되지 않는다.
  차이가 문자 하나(`\`)뿐이고, 그 문자는 diff 에서 시선을 끌지 않는다.
- **왜 테스트가 못 걸렀나**: 문구를 만드는 코드가 `private struct MemoryHomeVisitSheet` 안의
  뷰 본문에 인라인으로 있었다. 그 시트는 **같은 LAN 의 두 번째 기기**로만 도달하므로 어느 단위
  테스트도 밟을 수 없었다. 기존 `MemoryHomeViewTests` 는 테마 표·뷰 생성·진단 opt-in 을 덮고
  있었는데, 전부 결함과 **다른 경로**라 초록불이 false confidence 로 작동했다.
- **왜 커버리지도 못 걸렀나**: 이건 라인 커버리지로 막을 수 없는 부류다. 그 줄은 렌더되면
  "실행"으로 세어지고, 찍힌 **내용**이 틀렸다는 사실은 커버리지가 볼 수 있는 정보가 아니다.
  퍼센트를 올려도 이 결함은 그대로 통과한다.
- **부류**: **컴파일러가 침묵하고 커버리지가 무의미한 오타**. 같은 부류로 화면 문구를 만드는
  인라인 표현식 전반이 해당한다. 기계로 막을 수 있는 형태가 grep 하나뿐이다.
- **처방**: (1) 문구 조립을 뷰 밖의 순수 함수로 뺀다(`MemoryHomeProfileCard.speciesLabel`,
  `MemoryHomeCardStyle`, `MemoryHomeMoodStyle`). LAN·화면 없이 값을 단정할 수 있게 된다.
  (2) `test-gate.sh` 에 소스 스캔 가드를 둔다 — `Sources`·`Tests` 에 `\` 없는 `#(` 가 하나도
  없어야 한다. 스윕 결과 코드베이스 전체에 이 한 줄뿐이었다. (3) 가드를 넣은 뒤 일부러 오타를
  주입해 실패하는지 확인한다. (`MemoryHomeView`·`MemoryHomeProfileCard`, 2026-08-28.)

## warm build 는 warning 을 숨기므로, **게이트가 빨간 채로 커밋이 쌓일 수 있다**

- **증상**: R4 작업을 위해 `swift package clean` 뒤 `test-gate.sh` 를 돌리자 자체 코드 warning
  4건으로 게이트가 즉시 실패했다. 전부 `MemoryHomeVisitCenter.swift` 의 `send`/`receive`
  제네릭 헬퍼(Swift 6 concurrency)였고, 이번 변경이 **건드리지 않은** 줄이었다.
- **확인 방법**: `git worktree add /tmp/... HEAD` 로 HEAD 를 따로 꺼내 cold build 했다. 같은
  4건이 같은 코드(줄만 이동)에서 나왔다 → 이번 변경이 아니라 **브랜치에 이미 있던 빨간불**이다.
  즉 `fb7e67e`·`ed31dce` 두 커밋이 cold 게이트를 통과하지 않은 채 올라갔다.
- **원인**: warning 검사는 `swift test` 의 **재컴파일 로그**를 읽는다. warm build 는 바뀐 파일만
  다시 컴파일하므로, 손대지 않은 파일의 warning 은 로그에 아예 안 찍힌다. 로컬에서는 계속
  초록불로 보인다. (이 함정 자체는 `test-gate.sh` 주석에 이미 적혀 있었는데도 걸렸다 — 적어 두는
  것만으로는 안 걸린다는 증거다.)
- **부류**: **게이트의 입력이 증분이면 게이트도 증분이다.** 로그·캐시·재컴파일 산출물을 읽는
  검사는 전부 같은 성질을 가진다. "게이트가 통과했다" 가 "지금 트리가 깨끗하다" 를 뜻하지 않는다.
- **처방**: (1) 릴리스 전 게이트는 반드시 `swift package clean` 뒤에 돌린다(`RELEASE.md` 3번
  항목과 같은 취지). (2) 내 변경이 원인인지 판정할 때는 **worktree 로 HEAD 를 따로 빌드**한다 —
  stash 는 작업 트리를 건드리므로 이쪽이 안전하다. (3) 신뢰 기준은 매번 cold 인 CI 다.
  (`test-gate.sh`·`MemoryHomeVisitCenter`, 2026-08-28.)

## 추적되지 않는 스펙 디렉터리는 **복구 경로가 없다**

- **증상**: R5 작업 도중 `docs/product/` 디렉터리 전체가 사라졌다 — `pokedoro-memory-home-prd.md`
  (R1~R4 스펙 전문)와 `pokemon-my-mini-home-idea.md`(원본 기획서 27항). 세션 초반에 두 파일을
  읽어 뒀기에 내용으로 복원할 수 있었지만, 그건 우연이었다.
- **원인**: 미확인. 그 세션에서 돈 명령(`git add`/`commit`, `swift build`/`test`, `test-gate.sh`,
  `perl -0pi` 소스 편집, `cp`) 중 `docs/` 를 지우는 것은 없다. 휴지통에도 없었다. **원인을 못
  찾았다는 사실 자체가 이 항목의 요점이다** — 원인을 못 막으면 결과를 복구 가능하게 만들어야 한다.
- **왜 git 이 못 지켰나**: `.gitignore` 가 `docs/*` 를 무시하고 `!docs/reference/` 만 되살린다.
  `docs/product/` 는 **한 번도 추적된 적이 없어** `git checkout`·`git stash`·reflog 어느 것도
  쓸 수 없었다. 백업이 없는 게 아니라 백업이라는 개념이 적용되지 않는 상태였다.
- **부류**: **의사결정의 근거가 되는 문서를 무시 목록 안에 두는 것.** 같은 부류로 `.claude/`
  아래의 `plans/`·`tdd/` 도 전부 해당한다(`.gitignore:37`). 코드는 커밋되는데 그 코드를 왜
  그렇게 만들었는지 적은 문서는 한 번의 실수로 사라진다. `docs/testing/*.tdd.md` 도 같다
  (추적 0건 확인).
- **처방 후보**(적용 안 함 — 저장소 공개 범위 결정이라 사람이 정해야 한다):
  (1) `!docs/product/` 를 `.gitignore` 에 추가해 스펙을 추적 대상으로 올린다. 대가는 그 문서가
  오픈소스 저장소에 공개된다는 것 — `docs/reference/` 가 "published" 인 것과 같은 취급이 된다.
  (2) 공개를 원치 않으면 `docs/product/` 를 리포 밖 별도 저장소나 동기화되는 위치로 옮긴다.
  (3) 아무것도 안 하는 선택도 가능하지만, 그건 "이 문서는 언제 사라져도 된다" 는 선언이어야 한다.
  (`docs/product/`·`.gitignore`, 2026-08-28.)

## 화면을 옮기면서 **일부만 이식하면**, 남은 기능은 테스트가 초록불인 채로 사라진다

- **증상**: 기획서의 다섯 기능(주크박스 §11·파도타기 §14·기분 반응 §17·계절 배지 §24·계절 결산
  §25)과 **방꾸미기 전체**(스타일 4종·12칸 격자·되돌리기·초기화)가 코드에는 있는데 앱에서 도달할
  수 없었다. 주크박스는 UI 가 아예 없어 `setJukeboxTrack` 을 테스트만 호출하고 있었다.
- **경위**: `eee5c86` 이 팝오버 `MemoryHomeView` 를 창 `MemoryHomeWindowView` 로 옮기며 일부만
  이식하고, 남은 쪽을 `@available(*, deprecated)` + **비-`View`** 로 남겼다. 그 뒤 `9de278f` 가
  R8 방꾸미기를 **그 죽은 타입에** 붙였다 — 같은 커밋이 새 창을 만들면서다. 창에는 legacy 3슬롯만
  남았다.
- **왜 테스트가 못 걸렀나**: 테스트가 검증한 것은 (1) 스타일 헬퍼의 세 언어 문구 (2) 앨범
  메서드의 지속성이다. **둘 다 호출자가 화면이 아니어도 통과한다.** 커버리지도 못 잡는다 —
  테스트가 그 줄을 실행하므로 100% 로 찍힌다. "이 기능에 도달할 수 있는가" 를 묻는 검증이 없었다.
- **부류**: **살아 있는 표현이 둘이면, 하나는 조용히 죽는다.** 같은 부류로 (a) 같은 데이터를
  두 화면이 그리는 경우 (b) legacy 필드와 신규 필드가 동시에 살아 있는 경우(바로 아래 항목)
  (c) `deprecated` 를 붙였지만 삭제하지 않은 타입 전부.
- **처방**: 옛 타입을 **삭제**했다(문서·기억이 아니라 구조). 그리고 `test-gate.sh` 에
  `Sources/PokeTokenBar/UI` 의 `@available(*, deprecated` 를 실패로 만드는 grep 게이트를 넣었다.
  화면을 옮길 때는 옛 화면을 남기지 말고, 남겨야 하면 **그 커밋에서** 이식 목록을 다 옮긴다.
  (`MemoryHomeView`·`MemoryHomePresenter`·`test-gate.sh`, 2026-08-29.)

## 조건이 "신규 필드가 비었나" 하나면, **일회성 이전은 일회성이 아니다**

- **증상**: legacy 3슬롯을 쓰던 세이브에서 방을 **초기화하고 재시작**하면 치운 가구가 되살아났다.
- **원인**: R7 → R8 이전의 조건이 `placedDecor.isEmpty` 하나였고, legacy `roomLayout` 을 아무도
  비우지 않았다. 초기화가 `placedDecor` 만 비우므로 다음 실행에서 이전이 **다시** 돌았다.
- **왜 테스트가 못 걸렀나**: 이전 테스트가 "이전 직후 3개가 남았다" 만 봤다. 결함은 그 **뒤에**
  일어나는 초기화 → 재시작 경로에 있었고, 그 경로를 밟는 테스트가 없었다.
- **부류**: **이전은 소비되어야 한다.** 원본을 비우지 않는 이전은 조건이 우연히 다시 참이 되는
  순간 재실행된다. 같은 부류: 캐시를 지우면 되살아나는 값, 읽고 나서 지우지 않는 큐, 두 표현이
  동시에 살아 있는 모든 필드 쌍("어느 쪽이 진짜인가" 가 매번 애매해진다).
- **처방**: 이전 직후 `roomLayout`·`furniturePositions` 를 비운다. 원본에 쓰던 API
  (`setFurniture`·`setFurniturePosition`)는 **삭제**했다 — 다음 실행에서 지워지는 필드에 쓰는
  API 를 남기면 그 자체가 결함이다. 회귀 테스트는 초기화 → 재시작을 그대로 밟는다.
  덧붙여 저장된 legacy 좌표를 읽는 가지가 `^0`(무실행)으로 남아 있어(측정 확인) 슬롯 기본
  위치로 덮어써도 통과하던 상태였다 — 그 가지도 테스트로 덮었다.
  (`PokemonChat.swift` `normalizeMemoryHomeAccess`, 2026-08-29.)

## 창(window) 라벨을 붙인 파생 통계는 **창·숨김·타이브레이크 셋을 다 지켜야** 참이 된다

- **증상**: 계절 결산이 세 축에서 거짓말을 했다. (1) `memoryCount` 가 **숨긴 기억**을 셌다 —
  같은 앨범의 `timeline`·`diary`·날짜 카드는 전부 `!isHidden` 으로 거르는데 결산만 안 걸렀다.
  (2) `mostChosenMood` 가 동률에서 **호출마다 다른 답**을 냈다(같은 프로세스 안에서 `fluttering`
  → `down` 으로 바뀌는 것을 실측). (3) `focusSessions` 는 **통산값**인데 "이번 계절" 라벨 아래
  있었다.
- **원인**: 셋이 서로 다른 실수처럼 보이지만 한 부류다 — **집계식이 라벨이 약속한 범위를
  지키는지 아무도 확인하지 않았다.** (1) 은 필터 누락, (2) 는 `max(by:)` 를 딕셔너리에 그냥
  걸어 순회 순서(해시 시드)가 승자를 정한 것, (3) 은 저장 구조상 좁힐 수가 없는데 좁힌 척한 것.
- **왜 테스트가 못 걸렀나**: 유일한 결산 테스트가 `memoryCount == 1` 한 줄이었고, 기억을 **하나만**
  넣었다. 숨김도 동률도 통산도 그 경로를 밟지 않는다 — 축이 하나뿐인 픽스처는 축이 어긋났는지
  물어볼 수가 없다. 커버리지는 100% 로 찍힌다(그 줄은 실행되므로).
- **부류**: **"이번 N"이라고 적은 숫자는 세 번 의심한다** — 창 안인가(기간 필터), 보여도 되는
  것인가(숨김·삭제 필터), 답이 하나인가(동률 타이브레이크). 같은 부류: 랭킹·"가장 많이 …"
  전부, `max(by:)`/`min(by:)` 를 `Dictionary` 나 `Set` 에 거는 모든 곳(순회 순서가 시드마다
  다르다), 그리고 **좁힐 수 없는 값에 기간 라벨을 붙이는 것**.
- **처방**: (1) `!isHidden` 필터 (2) 동률은 `rawValue`·`uuidString` 사전 순으로 못 박음
  (3) 좁힐 수 없으므로 **라벨을 고쳤다**("집중 통산 N회") — 없는 데이터를 지어내는 대신 화면이
  사실을 말한다. 새로 만든 `yearRecap` 은 같은 이유로 집중 횟수와 기분을 **아예 담지 않는다**
  (`completedFocusSessionIDs` 에 날짜가 없고, `moodByDayKey` 는 60일에서 잘린다).
  회귀 테스트는 세 축을 각각 밟는다 — 동률 테스트는 같은 입력으로 20회 호출해 답이 고정인지
  본다(1회만 보면 우연히 통과한다). 타이브레이크가 **실제 최다값을 덮어쓰지 않는지**도 따로
  본다(동률 테스트만 있으면 "항상 사전 순 1등" 이라는 오답도 통과한다).
  (`PokemonChat.swift` `seasonRecap`·`yearRecap`, `MemoryHomeYearRecapTests`, 2026-08-29.)

## 아무도 띄우지 않는 시트는 **컴파일도 테스트도 커버리지도 통과한다**

- **증상**: 위 "화면을 옮기면서 일부만 이식하면" 항목의 형제. `deprecated` 를 붙이지 않고도
  화면이 죽는 두 번째 형태가 **표시자가 없는 시트**다 — 타입은 살아 있고, 컴파일되고, 헬퍼
  테스트도 통과하는데, `.sheet` 로 여는 곳이 없어 사용자가 도달할 수 없다.
- **부류**: 선언은 유효한데 **호출자가 0개**인 UI 타입 전부. 같은 부류로 호출자 0개인
  `private` 헬퍼가 있다 — 이번에 `MemoryHomePresenter` 에서 둘(`companionGuestbookLine`·
  `roomInteraction`)을 찾아 삭제했다. 둘 다 새 코어 타입(`MemoryHomeCompanionTrace`·
  `MemoryHomeRoomLife`)이 대체한 뒤 남은 시체였고, Swift 는 미사용 `private` 메서드에
  warning 을 주지 않는다.
- **처방**: `test-gate.sh` 에 **도달 불가 시트 스윕**을 추가했다 — `Sources/PokeTokenBar/UI` 의
  `MemoryHome*Sheet` 중 `Name(` 로 생성하는 곳이 없으면 실패한다(선언 줄은 `struct Name: View {`
  라 자기 자신에 걸리지 않는다). 게이트를 넣고 **가짜 고아 시트를 주입해 실제로 실패하는지
  확인**했다 — 통과만 보면 아무것도 안 지키는 게이트를 구별할 수 없다.
  해제 조건: 도달 가능성을 검증하는 UI 테스트가 생기면 그때 그쪽으로 옮긴다.
  (`scripts/test-gate.sh`·`MemoryHomePresenter.swift`, 2026-08-29.)

## 아틀라스에서 rect 를 고르는 코드는 **몇 개를 골랐는지 아무도 안 센다**

- **증상**: Memory Home 미니룸의 가구 12 종이 번들 아틀라스의 **rect 3 개**를 돌려썼다.
  `lovelySofa` = `roomBed` = `retroTV` = `natureBench` 가 문자 그대로 같은 픽셀이라, 소파를 사서
  놓으면 방에 침대가 하나 더 생겼다. 같은 화면의 다른 두 결함도 한 부류였다 — 가구 아틀라스
  **전체**를 `scaledToFill()` 로 늘려 벽지로 깔았고(가구 그림이 뭉개진 채 벽에 박힘), 16px
  스프라이트를 62pt 프레임에 넣어 **3.875 배**로 확대했다(`.interpolation(.none)` 이어도 픽셀
  폭이 3px/4px 로 갈린다).
- **원인**: 아틀라스는 17×8 = 136 타일인데 코드가 3 개만 참조했다. rect 표는 "빠진 게 있다" 를
  스스로 말하지 못한다 — 딕셔너리에 12 개 키가 다 있으니 **누락처럼 안 보이고 중복처럼도 안
  보인다.** 값이 같은 것뿐이라 컴파일러도 warning 이 없다.
- **왜 테스트가 못 걸렀나**: 유일한 아트 테스트가 `for item in [.roomBed, .roomTable, .roomLamp]`
  로 **하드코딩 3 종**만 돌았다. 판매 목록은 `ItemKind.memoryHomeFurniture`(12 종)인데 테스트는
  그 목록을 안 썼다 — 나머지 9 종이 무검증으로 남았고, 게다가 **rect 가 서로 다른지는 아무도
  묻지 않았다.** 3 종이 통과하니 커버리지도 초록불이다(그 줄들은 실행되므로).
- **부류**: **카탈로그(enum·`allCases`·판매 Set)가 있는데 테스트가 원소를 손으로 나열하는 모든
  곳.** 손으로 적은 목록은 카탈로그가 늘어날 때 자동으로 안 늘어난다. 여기에 두 형제가 붙는다 —
  (a) **키는 다 있는데 값이 중복인 매핑**(색·좌표·URL·문구 테이블 전부. 값 자체를 비교해야
  잡힌다), (b) **픽셀 아트를 비정수 배율로 확대하는 것**(정수배가 아니면 nearest-neighbour 도
  픽셀 폭이 갈린다).
- **처방**: 테스트를 전부 `ItemKind.memoryHomeFurniture` 순회로 바꾸고, rect 표가 아니라 **잘라낸
  결과 픽셀**(`tiffRepresentation`)을 해시해 12 개가 전부 다른지 본다 — 좌표만 다르고 그림이 같은
  경우도 이쪽이 잡는다. 배율은 `MemoryHomeBundledArt.displaySize` 한 곳에서만 정하고, 뷰가 62pt
  같은 값을 직접 쓰지 못하게 했다.
  **가드 자체를 두 번 다시 짰다** — 처음 쓴 "배율이 정수인가" 는 `displaySize` 가 늘 정수 factor 를
  곱하므로 **무슨 rect 를 넣어도 통과**했다(자기참조 테스트). 실제 트리거는 rect 변 길이라, 변이
  상한(64/32pt)을 나누어떨어지는지로 바꿨다. 타일 확대 테스트도 기대값을 `tileDisplayScale` 에서
  유도하다가 같은 함정에 빠져 **절대 하한 32pt** 로 고쳤다. 새 가드 6 개 전부 결함을 주입해
  실패하는지 확인했다(중복 rect·24px 변·1 배 타일·벽=바닥·투명 타일·평평한 대비).
  (`MemoryHomeBundledArt.swift`·`MemoryHomePresenter.swift`·`MemoryHomeBundledArtTests`,
  `scripts/inspect-tileset.swift`, 2026-08-29.)
- **후속(같은 날)**: 이 처방은 오래가지 않았다 — 아트를 전부 자체 제작으로 바꾸면서 아틀라스와
  rect 표가 통째로 사라졌고, 위에 적힌 심볼·스크립트도 함께 삭제됐다. 아래 **"아트를 코드로
  옮기면 에셋 부류의 결함이 통째로 사라진다"** 항목을 보라. 여기 남긴 *부류*(카탈로그가 있는데
  테스트가 원소를 손으로 나열한다)는 그대로 유효하다.

## 길이를 맞춰주는 헬퍼는 **틀린 길이를 조용히 정답으로 만든다**

- **증상**: 미니룸 스프라이트를 문자 격자로 작화하던 중, 침대 헤드보드가 오른쪽 5칸이 비어 있었다.
  화분은 통째로 1픽셀 왼쪽으로 밀려 있었고, 화장대 서랍·하트램프 목·TV 손잡이도 같은 증상이었다.
  **총 8곳.** 전부 렌더를 봐도 "좀 이상한데" 이상으로는 안 보였다 — 한 칸 밀린 그림은 그냥 그림 같다.
- **원인**: 행을 `R(좌여백, 본문, 총폭)` 로 만들었고 이 헬퍼가 **남는 칸을 뒤에 투명으로 채운다**.
  본문 길이를 잘못 세면 부족분이 조용히 메워져 **행 폭은 언제나 정답**이 된다. 컴파일러도, 폭
  검증기도, 렌더도 문제를 신고하지 않는다. 오류가 "없는 것"이 아니라 "정상값으로 위장"된 것이다.
- **왜 테스트가 못 걸렀나**: 처음 만든 검증기가 정확히 헬퍼가 보장하는 것(= 모든 행의 폭이 같고
  16/32 이다)만 물었다. **헬퍼의 사후조건을 검사하는 테스트는 헬퍼가 있는 한 항상 통과한다.**
  이 부류는 커버리지로도 안 잡힌다 — 그 줄들은 전부 실행된다.
- **부류**: **길이·크기를 맞춰주는 모든 API 뒤의 입력 오류.** `padding`/`fill`/`resize`/`clamp`/
  `truncatingRemainder`/포맷 문자열 폭 지정자 전부. 형제 부류로 **기대값을 검사 대상 상수에서
  유도하는 테스트**가 있다 — 이번에도 두 번 밟았다(`displaySize` 가 늘 정수 factor 를 곱하므로
  "배율이 정수인가" 는 무조건 통과, 타일 크기 기대값을 `tileDisplayScale` 에서 유도해 상수를 1 로
  낮춰도 통과). 검증은 **헬퍼가 보장하지 않는 성질**을 물어야 한다.
- **처방**: 헬퍼 바깥의 불변식을 찾아 검사했다 — 미니룸 가구는 전부 좌우 대칭이므로 **비어 있는
  좌여백과 우여백이 같아야 한다**. 이 한 줄짜리 검사가 즉시 8곳을 이름과 행 번호까지 찍어 잡았고,
  같은 격자에 대해 폭 검증기는 계속 통과했다(= 두 테스트가 서로 다른 것을 지킨다는 증거).
  결함 주입으로 확인할 때도 이 대비를 그대로 재현했다 — 한 칸 민 행에 대해 대칭 가드는 실패,
  규격 가드는 통과. 자기참조 테스트 둘은 절대 기준으로 바꿨다(변 길이가 상한을 나누는가, 타일이
  최소 32pt 인가).
  (`MemoryHomePixelArtSprites.swift`·`MemoryHomePixelArtTests`, 2026-08-29.)

## 아트를 코드로 옮기면 **에셋 부류의 결함이 통째로 사라진다**

- **맥락**: 위 "아틀라스에서 rect 를 고르는 코드" 항목의 후속. 그 결함을 rect 를 다시 고르는 것으로
  고쳤다가, 이후 아트 전체를 자체 제작으로 바꾸면서 **원인 자체를 없앴다**.
- **무엇이 사라졌나**: 좌표표가 없으니 rect 중복·오선택이 불가능하다. 번들 리소스가 없으니
  `Bundle.module` 로드 실패 경로, `build-app.sh` 의 번들 복사 단계와 존재 검사 2건,
  `THIRD_PARTY_NOTICES.md` 의 CC0 해시 고정이 전부 필요 없어졌다. 런타임 리컬러(4색 최근접 매칭)도
  통째로 지웠다 — 이제 처음부터 스타일 색으로 그린다.
- **부류**: **바이너리 에셋은 리뷰할 수 없다.** PNG diff 는 "바뀜" 말고 아무것도 말해주지 않으므로,
  아트의 결함은 사람이 렌더를 볼 때까지 살아남는다. 텍스트로 표현 가능한 작은 아트(아이콘·타일·
  스프라이트·색 램프)는 소스에 두면 diff 리뷰·단위 테스트·결함 주입이 전부 가능해진다.
  같은 이유로 `scripts/generate-icon.swift` 가 앱 아이콘을 코드로 그린다 — 이번 변경은 그 선례를
  미니룸까지 넓힌 것이다.
- **비용**: 격자 데이터 약 300 줄. 로직이 아니라 데이터이고, 실질 리뷰 대상은 렌더 이미지다.
  (`MemoryHomePixelArt.swift`·`MemoryHomePixelArtSprites.swift`·`scripts/build-app.sh`·
  `THIRD_PARTY_NOTICES.md`, 2026-08-29.)

## 세이브 픽스처가 **디코딩에 실패해도** "기본값이 나온다" 단언은 초록이다

- **증상**: BGM(주크박스) 제거 후 "구 세이브가 손실 없이 열리는가" 회귀 테스트를 쓰자마자 빨개졌다.
  원인은 지운 키가 아니라 **픽스처 자체**였다 — `{"memories":{}}` 로 적었는데 `memories` 는
  `[UUID: [PokemonMemory]]` 이고, `JSONDecoder` 는 UUID 키 딕셔너리를 객체가 아니라 **배열**(키·값
  교대)로 읽는다. 그 픽스처는 **처음부터 한 번도 디코딩된 적이 없었다.**
- **왜 못 걸렀나**: 같은 픽스처를 쓰던 기존 테스트가 `guestbookEntries.isEmpty` 와
  `jukeboxTrack == .afterSchool` 을 봤다. 둘 다 **디코딩이 통째로 실패해 전부 기본값이 되어도 참**
  이다. "레거시 세이브가 열린다" 를 검증한다고 믿었지만 실제로는 "기본값은 기본값이다" 를
  검증하고 있었다.
- **부류**: **기본값과 구별되지 않는 단언은 아무것도 지키지 않는다.** 로드 경로 테스트는 픽스처에만
  있고 기본값에는 없는 값을 봐야 한다. 이 저장소의 앨범은 디코딩이 던지면 파일을 `.corrupt` 로
  밀어내므로, 그 백업 파일의 **부재**가 가장 싼 판별식이다.
- **처방**: 픽스처에 `publicNickname`·`roomStyle`·`moodByDayKey`·`visitTotal` 처럼 기본값과 다른 값을
  넣고, `FileManager.fileExists(atPath: url.appendingPathExtension("corrupt").path)` 가 거짓인지
  함께 단언한다. UUID 키 딕셔너리는 `[]` 로 적는다.
- **함정**: `roomStyle` 만은 픽스처 값이 그대로 나오지 않는다 — `normalizeMemoryHomeAccess()` 가
  `unlockedRoomStyles` 에 없는 스타일을 되돌린다(정상 동작). 둘을 같이 적어야 한다.
  (`MemoryHomeEntertainmentTests.swift`, 2026-08-30.)

## 한 기능 안에 달력이 둘이면, **소수 사용자에게만 하루가 어긋난다**

- **증상**: §18 크리스마스 카드가 `Calendar.current.dateComponents([.month, .day])` 로 12/25 를
  판정했다. 같은 기능의 다른 날짜 로직(`dayKey`·`seasonKey`·연말 결산)은 전부
  `SeasonBoard.gregorian` 을 쓴다.
- **부류**: **달력이 둘이면 사용자 설정 하나가 두 값을 갈라놓는다.** 비그레고리력 달력을 쓰는
  사용자에게만 카드가 결산·일기와 어긋나고 나머지 화면은 멀쩡하다 — 겪는 사람이 적어 리포트도
  안 온다. `seasonKey` 가 "포맷터를 하나 더 두지 않고 `dayKey` 를 자른다" 고 적은 것과 같은 이유다.
- **처방**: 월·일 판정은 `CompanionStore.dayKey($0).hasSuffix("-12-25")` 로 문자열을 자른다.
  `dayKey` 가 `%04d-%02d-%02d` 라 접미사 비교가 곧 월·일 비교이고, 달력이 하나로 유지된다.
  새 `newYear` 카드도 같은 원칙으로 `-01-01` 을 쓴다.
- **스윕이 두 곳을 더 찾았다** — 고치고 끝낼 결함이 아니었다:
  `MemoryHomeSeason.current` 가 `Calendar.current.component(.month:)` 로 계절을 정하고,
  `seasonRecap` 이 같은 달력으로 계절 시작 월·연을 계산하고 있었다. 즉 **계절 축 전체**가
  `dayKey` 와 갈라질 수 있었다. 둘 다 `SeasonBoard.gregorian` 으로 통일했다.
- **남겨도 되는 것**: `Sources/` 의 나머지 `Calendar.current` 는 **날짜 산술**(`byAdding`)과
  **시각 성분**(`.hour`) 이다. 달력 종류가 결과를 가르지 않는 용도라 그대로 둔다 — 판별식은
  "이 값이 `dayKey` 와 같은 날을 가리켜야 하는가" 다.
  (`PokemonChat.swift`·`MemoryHomeSeason.swift`, 2026-08-30.)

## 못 읽은 프레임에서 **수신을 다시 걸지 않으면**, 세션은 살아 보이는 채 귀를 닫는다

- **증상**: `PokemonTrade.receiveBody` 가 `try? decode` 실패 시 `return` 만 했다. `receiveLength`
  를 다시 걸지 않으므로 그 뒤로는 어떤 프레임도 읽지 않는다. 소켓은 열려 있고 `phase` 도 그대로라
  화면은 정상 협상 중으로 보이는데, 확인·취소·커밋이 **영원히 도착하지 않는다**.
- **부류**: **읽기 루프의 실패 분기가 루프를 다시 걸지도, 세션을 끝내지도 않는 부류.** 끊긴 연결은
  `stateUpdateHandler` 가 잡아 주지만, "연결은 멀쩡한데 내용을 못 읽은" 경우는 아무도 안 잡는다.
  둘 다 안 하는 분기는 화면상 **아무 일도 일어나지 않아** 리포트가 "그냥 멈췄어요" 로만 온다.
- **스윕 결과 — 형제 둘은 이미 옳았다**: `BattleNet:1838` 은 `connectionDropped()`,
  `MultiplayerRoomCenter:927` 은 `connection.cancel()` 로 **소리 내어** 끝낸다. 교환만 조용히
  리턴하는 유일한 지점이었다. 셋 중 하나만 다른 형태였다는 게 이 부류의 표식이다.
- **처방**: 교환은 **건너뛰고 다시 건다**(형제와 반대 방향). 길이 프리픽스 프레이밍이라 못 읽은
  페이로드가 스트림을 어긋내지 않고, 뒤 버전이 더한 **선택적** 프레임에 길이 열린다 — 교환 채팅이
  바로 그런 프레임이었다. 대신 `AppLog` 로 흔적을 남긴다. 판별식은 "이 프레임을 못 읽는 것이
  정상적인 버전 차이일 수 있는가" 다: 그렇다면 건너뛰고, 아니라면 형제처럼 끊는다.
- **테스트가 못 잡는 자리**: 이 분기는 살아 있는 `NWConnection` 안에서만 돌아 단위 테스트가 닿지
  않는다(저장소에 소켓 테스트가 없다). 커버리지에도 `0` 으로 남는다 — 리뷰와 위 스윕이 근거다.
  (`PokemonTrade.swift`, 2026-08-30.)

## 같은 플래그를 두 분기에서 세우면, **한쪽만 밟는 테스트가 전부 통과한다**

- **증상**: 교환 채팅의 `peerSupportsChat` 은 `.request`(신청받는 쪽)와 `.accept`(신청 거는 쪽)
  **두 곳**에서 세워진다. 처음 쓴 6개 테스트는 받는 쪽 경로만 밟았고 전부 초록이었다.
  `--show-regions` 가 `.accept` 쪽 대입을 실행 횟수 `0` 으로 드러냈다.
- **부류**: **핸드셰이크의 양쪽 역할이 같은 상태를 각자 세우는 부류.** 한쪽만 테스트하면 다른 쪽이
  `= true` 로 굳어 있어도 아무도 안 깨진다. 여기서는 그 결과가 "구버전 상대에게 채팅 프레임을 보내
  상대 세션을 멈추는 것" — 즉 위 결함의 트리거였다.
- **처방**: 형제 경로(`request()` → `.accept` 수신)를 별도 테스트로 밟는다. 확인 방법은
  **분기를 일부러 `= true` 로 굳혀 보는 것**이다(2건 실패 → 가드가 실제로 문다). 통과만 보면
  아무것도 안 지키는 테스트와 구별되지 않는다.
- **일반화**: 라인 커버리지 총계는 이걸 못 잡는다. 새 조건 분기를 넣었으면 총계가 아니라
  `xcrun llvm-cov show ... --show-regions` 에서 그 줄의 실행 횟수를 **직접** 본다.
  (`PokemonTrade.swift`, 2026-08-30.)

## 세션 상태를 **복사해 나가면**, 나중에 친 방어는 복사본에 닿지 않는다

- **증상**: 교환(`PokemonTradeCenter`)은 상대가 보낸 채팅의 `senderID`·`senderName`·`id` 를 전부
  다시 짓는데, 같은 블록(`chatMessages`/`chatHistory`/`chatRateLimiter`/`chatSenderID` + `sendChat`
  + accept)을 복사해 간 `BattleCenter` 와 `MultiplayerRoomCenter` 게스트 경로는 그대로 믿고 있었다.
  결과: (a) 상대가 매 프레임 `senderID` 를 갈아 끼우면 토큰 버킷이 새로 생겨 **속도 제한이 없고**,
  (b) 우리 `chatSenderID` 는 우리가 보내는 **모든 프레임에 실려 나가므로** 되받아 쓰면 화면이 상대
  말을 **내 말풍선으로** 그리고, (c) 상대 이름·`id` 는 아무도 안 잰다.
- **부류**: **같은 상태 블록이 세 클래스에 복제된 부류.** 한 곳에서 경계를 고쳐도 나머지는 그대로다.
  리뷰는 "고친 파일"만 보므로 복사본은 시야 밖에 남는다. 판별식은 "이 필드 묶음이 다른 파일에
  같은 이름으로 또 있는가" 다 — 있으면 고칠 때마다 셋 다 고쳐야 한다.
- **`id` 가 특히 위험한 이유**: `BattleChatMessage.id` 는 `Identifiable` 키이고 화면의 `ForEach`
  가 이 값으로 행을 가른다. 상대가 같은 값을 두 번 보내면 SwiftUI 가 중복 ID 로 목록을 무너뜨린다.
  상대가 고른 값을 화면 키로 쓰지 않는다 — 받는 쪽에서 새로 짓는다(`id:` 인자를 빼면 된다).
- **이름은 거부가 아니라 자른다**: 본문(`normalizedBody`)은 규격 밖이면 버리면 되지만, 이름은
  핸드셰이크가 정하는 값이라 거부하면 교환·대전 자체가 성립하지 않는다. `BattleChatPolicy
  .displayName` 이 공백을 접고 40자로 자른다. 프레임 상한은 1MB 인데 채팅 행과 협상 헤더 둘 다
  `lineLimit` 이 없어, 이름 하나로 패널 레이아웃이 무너진다.
- **영구 캡처**: `BattleChatTests` 의 "신뢰경계 (부류 스윕)" 확장이 **세 경로를 한 파일에서** 잰다.
  복사본이 넷째로 늘어도 여기서 갈라짐이 드러난다.
  (`PokemonTrade.swift`·`BattleNet.swift`·`MultiplayerRoomCenter.swift`, 2026-08-30.)

## 소켓을 **정상 종료**하면 `.failed` 는 오지 않는다 — 읽기 루프가 직접 끝내야 한다

- **증상**: 위 "못 읽은 프레임" 항목은 *디코드 실패* 분기만 고쳤다. `receiveLength`/`receiveBody`
  의 **EOF·짧은 읽기** 분기는 여전히 조용히 `return` 했다. 상대가 앱을 정상 종료하면 TCP 는 FIN 만
  남기고 상태는 `.ready` 에 머무르므로 `attach` 의 `guard case .failed` 가 영영 안 뜬다. 죽은 소켓
  위에 "교환 중" 이 그대로 남고 확인도 커밋도 오지 않는다.
- **부류**: **연결 종료를 `stateUpdateHandler` 하나에 맡기는 부류.** `.failed` 는 *비정상* 종료만
  가리킨다. 정상 종료를 아는 곳은 `data == nil` 을 받는 읽기 콜백뿐이다.
- **테스트가 못 걸른 이유 — 형제 경로가 초록을 만들어 준다**: 처음 쓴 소켓 테스트는 `accept()` 로
  프레임을 보냈다. 이미 닫힌 소켓에 쓰면 RST 가 돌아오고 그건 `.failed` 라, **결함을 되주입해도
  테스트가 통과했다**. 읽기 루프를 재는 테스트는 **우리 쪽에서 아무것도 보내면 안 된다**.
  이걸 잡은 건 통과 확인이 아니라 **결함 재주입**이다(CLAUDE.md 결함 대응 프로토콜 3).
- **처방**: `connectionDropped(_:)` 하나로 모은다 — `.failed` 핸들러와 읽기 루프의 모든 실패
  분기가 같은 곳으로 간다. 형제 `BattleNet.connectionDropped` 와 같은 모양이다.
  (`PokemonTrade.swift`, 2026-08-30.)

## 상대가 부르는 **날짜**를 파생 점수의 권위로 쓰는 부류

- **증상**: 교환으로 받은 개체의 `MonState.firstMetAt` 은 상대가 채워 보내는 값인데
  `performTrade` 가 그대로 앨범에 넣었다(`recordFirstMeeting` 은 **더 이른** 날짜를 채택한다).
  1970년을 박아 보내면 `pokeLog.daysTogether` 가 2만 일이 되고 친밀도 하트가 즉시 만점으로 굳는다.
- **부류**: 숫자·문자열은 경계에서 자르면서 **`Date` 는 그냥 통과시키는 부류.** 날짜는 그 자체로는
  무해해 보이지만 *파생 지표*(함께한 날수·정렬 순서·일기 묶음 dayKey)의 입력이라, 클램프 없이 들어오면
  점수와 화면 순서를 상대가 정하게 된다.
- **처방(1차 — 부족했다)**: 추억의 `createdAt` 과 개체의 `firstMetAt` 이 같은 창(`clampedDate`,
  10년)을 쓰게 했다. **이걸로는 안 막힌다.** `closenessHearts` 는 `1 + days/30 + …` 이라 **120일**
  이면 이미 만점이고 창은 3650일까지 열려 있다 — 잘린 값으로도 방금 받은 개체가 "함께한 3650일 ·
  ♥♥♥♥♥" 에 마일스톤 카드 넉 장(첫 만남·30일·100일·1주년)을 달고 나타났다.
- **처방(2차)**: 파생 지표의 입력이 되는 값은 **자르는 게 아니라 안 쓴다.** 받은 개체의
  `firstMetAt` 은 로컬 `clock()` 이다 — 나와 그 개체가 함께 보낸 날은 0일이다. 화면의 그 문구들은
  전부 "너와 이 포켓몬" 을 뜻한다. `clampedDate` 는 추억의 `createdAt` 에만 남는다(그건 일기의
  정렬 위치일 뿐 점수가 아니다).
- **일반화 — 클램프의 상한은 "그 값이 무해해지는 지점" 이어야 한다.** 상한을 눈대중으로 고르면
  파생 함수가 그 훨씬 안쪽에서 포화한다. 클램프를 넣을 땐 **소비자 함수를 열어 포화점을 계산**하고,
  회귀 테스트는 클램프된 값이 아니라 **파생 지표**(하트·일수)를 단언한다. 첫 판의 테스트는
  `firstMetAt >= floor` 만 봤고, 그래서 하한을 10년에서 100년으로 바꿔도 통과했다.
- **스윕 결과**: `turnEndsAt`·`challengeEndsAt`(`BattleNet`·`MultiplayerRoomCenter`)은 전부 로컬
  `Date()` 에서 세팅되고 피어 프레임에서 디코드되지 않는다 — 깨끗하다.
  **남은 인접 인스턴스(오늘은 무해):** `MemoryHomeProfileCard.featuredPhoto` 안의
  `MemoryHomePhoto.createdAt`·`id` 는 LAN 을 건너오는데 `MemoryHomeVisitCenter.valid` 가 안 본다.
  방문 시트가 그 날짜를 **그리지 않고** 방문한 사진을 저장하지도 않아 지금은 아무 데도 안 쓰인다.
  그 사진의 날짜를 화면에 올리거나 저장하는 순간 위와 같은 결함이 된다 — 그때 `valid` 에 함께 넣는다.
- **테스트가 못 걸를 뻔한 이유**: 첫 클램프 테스트는 적대적인 줄을 정상 100줄 **뒤에** 놓았다.
  건수 캡(`prefix(maxEntries)`)이 필드 검사보다 먼저 걸려 나머지 클램프를 한 번도 안 밟았고,
  **클램프를 통째로 지워도 통과했다**. 경계 테스트는 적대적인 입력을 *캡 안쪽*에 놓아야 하고,
  "그 줄이 검사 구간에 실제로 들어왔다" 는 단언을 함께 둔다.
  (`PokemonTrade.swift`·`CompanionStore.swift`, 2026-08-30.)

## 되돌릴 수 없는 것을 **성사 전에** 내보내는 부류

- **증상**: 교환 추억이 `performTrade` **앞에서** 나갔다. 상대는 아무것도 내주지 않고 남의 앨범만
  가져갈 수 있다 — 내 명부(`.roster`)는 수락 직후 건너가므로, 그 안의 개체 ID 를 그대로 베껴
  제안을 만들고 `.commit` 만 보내면 `performTrade` 가 거절한다. 그때 추억은 이미 나간 뒤다.
  신청자 쪽도 같았다: `.commit` 직전에 보내 놓고 상대가 `.decline` 로 답하면 끝이다.
- **부류**: **"곧 성사될 것" 을 성사로 취급하는 부류.** 전송·삭제·과금처럼 되돌릴 수 없는 동작을
  *결정 직전*에 놓으면, 그 결정이 거절로 끝나는 모든 분기가 곧바로 유출 경로가 된다. 그 코드에
  달린 주석이 "취소로 끝난 협상엔 안 나간다" 라고 **주장**하고 있어도 마찬가지다.
- **처방**: 되돌릴 수 없는 동작은 성사를 **관측한 뒤**에 놓는다. 수신자는 `performTrade` 성공 뒤
  (`.committed` 보다는 앞 — TCP 순서가 도착을 보장한다), 신청자는 `.committed` 를 받고 자기
  `performTrade` 가 성공한 뒤. 순서를 바꾸면 상대에게 프레임이 **늦게** 도착하므로, 받는 쪽에
  성사 뒤 도착 경로(`adoptTradedMemories`)를 함께 연다 — 검사는 기존 `adopt` 하나를 그대로 쓴다.
- **부수 제약**: 보낼 값이 삭제되기 전에 만들어 둬야 한다(`performTrade` 가 앨범을 지운다).
  "만드는 시점" 과 "보내는 시점" 을 분리하는 것으로 충분하다.
- **테스트가 못 걸른 이유 — `send()` 가 조용히 리턴한다**: `send` 는 연결이 없으면 아무것도 안
  하고 리턴한다. 소켓을 안 붙인 테스트에서는 무엇이 언제 나가든 단언이 하나도 안 깨지고,
  **라인 커버리지는 초록**으로 남는다. 전송 순서를 재려면 진짜 소켓이 필요하다(`TradeWireTap`).
  더 나쁜 함정: 탭의 콜백을 `.main` 큐나 `Task { @MainActor }` 에 걸면 `async` 테스트에서 영영
  안 돈다(본문이 `RunLoop.run(until:)` 로 메인을 잡고 있다). 탭이 비면 **"아무것도 안 나갔다" 를
  보는 단언이 공허하게 통과한다** — 전용 큐에 건다. (`PokemonTrade.swift`, 2026-08-30.)

## 화면에 안 나오는 필드를 **네트워크로만** 흘리는 부류

- **증상**: 교환이 관계 요약(`PokemonChatSession.summary`)을 함께 보냈는데, 그 값을 **읽는 곳이 앱
  어디에도 없었다.** UI 에도 안 뜨고 `PokemonChatRequest` 로도 안 실렸다. 유일한 소비자가 "다음
  교환으로 재전송" 이라, 실제 효과는 첫 주인의 통계가 낯선 사람들에게 영원히 전파되는 것뿐이었다.
- **부류**: 저장·전송 배관만 있고 **소비자가 없는 필드.** 기능처럼 보이지만 사용자에게 주는 값이
  0 이고, 남는 건 전파 경로뿐이다. 이 저장소의 "코드엔 있는데 화면엔 없다"(`memory-home-plan.md`)
  와 같은 부류인데, 네트워크가 붙으면 **무해한 미완성이 아니라 유출 통로**가 된다.
- **처방**: 새 필드를 경계 밖으로 내보내기 전에 `grep` 으로 **읽는 곳**을 센다. 0 이면 그 필드는
  기능이 아니다 — 화면에 붙이거나 지운다. 지웠다. 딸려 온 이득: 적용 가드의 `|| summary != nil`
  분기가 함께 사라져, 요약만 담은 페이로드가 "이전 트레이너와의 기억을 안고 왔다" 만 찍던 결함
  (`A || B` 게이트에서 **B 단독**을 안 밟은 부류)도 같이 닫혔다.
- **테스트가 못 걸른 이유**: 테스트가 `session.summary == "..."` 로 **저장된 값**을 단언했다.
  저장은 동작이 아니다 — 단언은 "사용자가 어디서 이걸 보는가" 를 가리켜야 한다.
  (`CompanionStore.swift`·`PokemonChat.swift`, 2026-08-30.)

## 형제 신뢰경계가 **서로 다른 정규화**를 갖는 부류

- **증상**: 같은 소켓의 두 경계가 본문을 다르게 접었다. 교환은 유니코드 **스칼라** 단위로 훑었는데
  ZWJ(U+200D)가 제어문자 범주(Cf)라 `👨‍👩‍👧` 가 낱개 셋으로 쪼개졌다 — 보이는 것도 망가지고
  글자 수가 부풀어(7자 → 11자) 정상 추억이 상한 밖으로 밀려 **통째로 버려졌다.** 보낸 쪽은 같은
  교환에서 앨범을 지우므로 그 줄은 **영구 소실**이다. 반대로 공백 런은 안 접혀서, 형제 경계가
  173자 → 4자로 접는 문자열이 교환에서는 173자 그대로 통과했다.
- **부류**: 같은 값을 보는 경계가 **각자 접는 부류.** 하나가 느슨하면 그쪽이 곧 공격 표면이 되고,
  하나가 빡빡하면 그쪽에서 정상 입력이 조용히 사라진다.
- **처방**: 정규화를 한 함수에 모은다(`BattleChatPolicy.normalizedBody(_:limit:)`). 상한만 부르는
  쪽이 정한다. **문자(grapheme) 단위로 돈다** — 스칼라로 훑으면 결합 문자가 쪼개진다. 제어문자는
  "스칼라가 **전부** 제어문자인 문자" 만 버려서 ZWJ 가 든 이모지를 살린다.
  (`BattleChat.swift`·`PokemonTrade.swift`, 2026-08-30.)

## 화면을 **팝오버로 옮기면**, 창을 띄우던 API 가 그 화면을 파괴하는 부류

- **증상**: 대화를 전용 `NSWindow` 에서 팝오버 오버레이로 옮기자, 대화 안의 "실행 파일 선택…"
  버튼이 자기 화면을 없앴다. `NSOpenPanel` 이 키 윈도우가 되는 순간 `.transient` 팝오버가 닫히고,
  `popoverDidClose` 가 `contentViewController` 를 nil 로 만들어 뷰가 `@State` 째로 사라진다.
  경로는 저장되는데 사용자는 닫힌 팝오버 앞에 남는다. 같은 부류로 `.sheet` 도 있었다 —
  저장소의 다른 `.sheet` 은 전부 진짜 창 안에 있어 팝오버 안에는 **선례가 없었다.**
- **왜 못 걸렀나**: `SettingsView.swift` 가 **바로 이 함정을 주석으로 이미 남겨 뒀는데** 부류 스윕을
  안 돌렸다. 더 나쁜 건, 그 버튼 위의 주석("설정 화면은 팝오버 안에 있고 대화는 별도 창이라")이
  이관으로 **거짓이 되면서** 읽는 사람에게 버그를 가렸다는 점이다.
- **부류**: 화면의 **호스트가 바뀌면 그 화면이 쓰던 API 의 전제도 바뀐다.** 팝오버 안에서는
  `NSOpenPanel`·`.sheet`·`NSAlert` 처럼 키 윈도우를 새로 만드는 것이 전부 자기 발표자를 죽인다.
- **처방**: 화면을 팝오버로 옮기기 전에 그 부류를 **먼저 grep** 한다. 대안은 팝오버 밖(설정 화면)에
  같은 기능이 있으면 거기로 보내고, 없으면 오버레이 안 자리 바꿈으로 그린다.
  **이관으로 거짓이 된 주석은 같은 커밋에서 고친다** — 안 고치면 다음 사람이 그 주석을 근거로 읽는다.
  (`PokemonChatView.swift`, 2026-08-30.)

## 팝오버 고정을 **원하는 이유가 둘 이상이면**, 각자 푸는 순간 서로를 푼다

- **증상**(주입으로 확인): 배틀은 `behavior = .applicationDefined` 로 팝오버를 붙들고 끝나면
  `.transient` 로 되돌린다. 대화 전송에 같은 형태를 하나 더 붙이자, 배틀 중에 대화가 **먼저** 끝나는
  순간 대화 쪽이 `.transient` 로 되돌리며 아직 진행 중인 배틀의 고정까지 풀었다.
- **부류**: 하나의 상태를 **여러 이유가 각자 세우고 각자 되돌리는 부류.** 세우는 쪽은 겹쳐도
  괜찮지만 되돌리는 쪽은 겹치면 안 된다.
- **처방**: 되돌림 판정을 순수 함수 한 곳에 모으고(`PopoverPinPolicy.behavior(...)`), 부르는 자리는
  **플래그만 넘기고 판정하지 않는다.** 그러면 저글링 버그가 테스트로 잡히는 게 아니라 애초에
  표현할 수 없다. 판정에는 "왜 붙드는가" 도 넣는다 — 대화 고정의 목적은 답이 오는 걸 **보게**
  하는 것이라, 사용자가 대화를 닫았으면 전송 중이어도 풀어야 한다(안 풀면 화면에 아무 설명 없이
  바깥 클릭이 먹통이 된다).
- **덧**: 이미 떠 있는 팝오버에 `behavior` 를 대입하는 것이 먹는지는 실측 못 했다(배틀 경로는 항상
  `show` **전에** 세운다). 그래서 `popoverShouldClose` 로 매 이벤트 재판정을 함께 뒀다 — 같은
  판정 함수를 읽으므로 둘이 갈라질 수 없다. (`PokeTokenBarApp.swift`, 2026-08-30.)

## 탭만 바꾸는 자리는 **덮인 오버레이를 그대로 둔다**

- **증상**: 대화 오버레이가 떠 있을 때 **거래 신청**이 오면 신청 화면 대신 대화가 계속 보였다.
  `PopoverView` 의 `onChange(of: trading.phase)` 가 `nav.tab = .battle` 만 대입했기 때문이다.
  배틀 신청은 AppDelegate 의 핀 경로가 `goToBattle()` 을 불러 우연히 덮이지 않았지만, 거래 신청은
  `.incoming` 에서 `wantsPinnedWindow == false` 라(`BattleNet.swift`) 그 경로를 아예 안 탄다.
- **왜 못 걸렀나**: 새 회귀 테스트가 `reset`·`goToBattle`·`goToGymBattle` 세 **헬퍼**만 밟았다.
  헬퍼를 안 거치고 `tab` 을 직접 대입하는 호출부 둘은 테스트 시야 밖이었다.
- **부류**: 같은 전환을 **헬퍼로도 하고 직접 대입으로도 하는 부류.** 헬퍼에 방어를 더해도 직접
  대입 경로는 안 받는다.
- **처방**: 탭 전환과 오버레이 접기는 한 함수 안에 함께 둔다. `nav.tab = ...` 직접 대입을 grep 해
  전부 헬퍼로 돌린다. 접는 목록 자체도 한 벌로 모은다(`closeOverlays()`) — 호출부마다 손으로
  베끼면 다음 오버레이에서 한 곳을 빠뜨리고, 그건 세 갈래 테스트로만 잡힌다.
  (`PopoverView.swift`, 2026-08-30.)

## "열 때 확인했다" 는 **떠 있는 동안**을 안 지킨다

- **증상**: 대화를 여는 자리가 소유 여부를 확인하지만, 대화가 떠 있는 동안 상대가 놓아주기·교환·
  졸업으로 사라지면 이름이 `?` 이고 스프라이트가 빈 화면에 전송 버튼만 살아 있었다. 보내면 죽은
  UUID 로 세션이 새로 생겨 다음 `prune` 까지 디스크에 남는다.
- **부류**: **진입 시점 검증**으로 **표시 구간 내내**를 보증하려는 부류. 화면이 오래 떠 있을수록
  간격이 벌어진다.
- **처방**: 소유 집합이 바뀔 때마다 다시 본다(`dropChatIfCompanionIsGone(ownedIDs:)`).
  **개수가 아니라 ID 집합을 본다** — 교환은 한 마리가 나가고 한 마리가 들어와 개수가 그대로다.
  (`PopoverView.swift`, 2026-08-30.)

## 개체별 화면이 **전역 카운터**를 읽으면, 남의 상태를 자기 것으로 그린다

- **증상**: `isSending` 이 스토어 전역 합이라, 피카츄에게 보낸 답을 기다리는 동안 파이리 대화를
  열면 파이리 기록에 **절대 오지 않을** 답의 "생각 중" 점 세 개가 떴다.
- **왜 이제 드러났나**: 전용 창일 때는 다른 개체로 옮기려면 창을 일부러 다시 열어야 했다.
  팝오버 오버레이로 옮기면서 두 클릭이 되어 상시로 밟게 됐다 — **결함은 그대로인데 노출 빈도만
  바뀌는 부류**다. 화면 구조를 바꿀 때 선재 결함의 빈도도 함께 본다.
- **처방**: 개체별로 센다(`[UUID: Int]`). 0 이 된 키는 **지운다** — 안 지우면 지나간 개체의 키가
  계속 쌓인다(같은 커밋에서 `drafts` 도 `deleteSession`·`startNewSession`·`prune` 셋 다에서
  정리하도록 고쳤다. 세션을 손대는 자리는 그 개체의 곁다리 상태도 함께 손댄다).
  (`PokemonChat.swift`, 2026-08-30.)

## `body` 안에서 파일시스템을 만지면 **키 입력마다** 돈다

- **증상**: 대화 입력칸을 스토어 바인딩으로 옮기자 키 입력마다 `body` 가 재평가됐고, 그 안에서
  `provider` 를 두 자리가 읽었다. `provider` 는 디렉터리 13곳에 `fileExists` + `isExecutableFile`
  을 던지므로 한 글자에 파일시스템 질의가 메인 스레드에서 두 벌씩 돌았다.
- **부류**: **읽을 때마다 계산하는 computed property 가 I/O 를 품은 부류.** 뷰에서 읽으면
  호출 횟수를 아무도 안 센다.
- **처방**: 해석 결과를 입력이 바뀔 때까지 캐시한다. **키는 해석에 쓰이는 입력 전부**여야 한다 —
  종류만 키로 쓰면 설정에서 경로를 고쳐도 옛 결과가 계속 나온다. 캐시의 **양쪽**(다시 안 보는 것,
  바뀌면 다시 보는 것)을 각각 테스트로 고정한다. 조회 클로저를 주입 가능하게 두면 호출 횟수를
  셀 수 있어 "캐시가 실제로 먹는가" 를 단언할 수 있다. (`PokemonChatProviderCache`, 2026-08-30.)

## 관문을 우회해도 **답이 우연히 같아** 가드가 안 깨지는 부류

- **증상**: 자동 선택(`PokemonChatProviderSelection.effectiveKind`)에 결함을 주입해 봤다 —
  후보를 `PokemonChatProviderSafety.verifiedKinds` 대신 `PokemonChatProviderKind.allCases` 에서
  뽑게 바꿨다. **격리 관문이 통째로 뚫렸는데 기존 가드 5개가 전부 초록이었다.**
- **원인**: 검증 종류가 열거형 앞자리에 있다(`codex, claude, opencode, custom`). 검증 CLI 가
  하나라도 설치된 상태에서는 `allCases.first` 와 `verifiedKinds.first` 가 **같은 답**을 낸다.
  테스트가 전부 "CLI 가 설치돼 있다" 는 정상 케이스로 짜여 있어 두 식을 구별하지 못했다.
- **부류**: **필터를 건너뛴 구현이 정상 입력에서는 같은 값을 내는 부류.** 안전 관문을 지나는지
  묻는 테스트가 실은 *결과가 우연히 겹치는 입력*만 밟고 있었다. 커버리지도 무력하다 — 그 줄은
  실행됐고 단언도 통과한다.
- **처방**: 관문을 시험할 땐 **관문이 없으면 답이 달라지는 입력**을 찾아 그걸로 단언한다.
  여기서는 "검증 CLI 는 하나도 없고 차단된 종류만 설치된" 상태가 유일한 구별 입력이었다
  (`testABlockedCLIIsNeverPickedEvenWhenItIsTheOnlyOneInstalled`). 필터가 목록의 **뒷부분만**
  걸러낸다면, 앞부분이 비어 있는 케이스가 반드시 테스트에 있어야 한다.
- **일반화**: 이 사실은 결함 주입으로만 드러났다. 새 가드는 통과를 보는 것으로 끝내지 말고
  **일부러 깨뜨려 빨개지는지** 확인한다 — 안 빨개지면 그 가드는 아무것도 안 지키고 있다.
  (`PokemonChat.swift`, 2026-08-30.)

## 결함 주입으로 가드를 검증하기 **전에** GREEN 을 커밋한다

- **증상**: 새 가드가 진짜 지키는지 보려고 프로덕션에 결함을 넣고 테스트를 돌린 뒤
  `git checkout <파일>` 로 되돌렸다. 그 파일의 구현이 아직 커밋 전이라 **구현까지 HEAD 로
  되감겼다.** 주입 증거는 남았지만 작업은 사라졌다.
- **처방**: 주입은 **GREEN 커밋 뒤**에 한다. 그러면 `git checkout` 이 되돌리는 지점이 곧 구현이다.
  (2026-08-30.)

## 여러 사유를 **한 갈래로 수렴하는 입력**으로 시험하면, 사유별 문구는 한 번도 안 밟힌다

- **증상**: `testEveryUnavailableGuidanceIsWrittenInAllThreeLanguages` 가 사유 3종(`opencode`·
  `custom`·미선택)을 전부 `effective: nil` 로 물었다. 그런데 그 상태에서는 어느 사유든 "설치된
  CLI 가 없다" 한 갈래로 수렴한다 — **차단 사유의 번역은 한 번도 실행되지 않은 채** 세 언어가
  서로 달라 통과했다. 게다가 그 통과가 사유 판정의 우선순위 역전(아래)까지 고정하고 있었다.
- **부류**: 위 "답이 우연히 같아 가드가 안 깨지는" 부류의 **테스트 입력판**. 구현이 아니라 *물음*이
  분기를 뭉갠다. 반복문 안에서 케이스만 늘리고 나머지 인자를 고정하면 이 모양이 되기 쉽다.
- **처방**: 케이스마다 **그 사유가 실제로 나오는 상태**를 함께 준다(`(stored, effective)` 쌍으로).
  단언이 "세 갈래가 나온다" 처럼 *모양*만 볼 때는, 그 모양이 서로 다른 코드 경로에서 나왔는지
  `--show-regions` 로 확인한다. (`PokemonChatProviderPathTests.swift`, 2026-08-30.)

## 사유 판정에서 **순서가 곧 우선순위**다 — 손쓸 수 없는 설명이 손쓸 수 있는 안내를 가린다

- **증상**: `unavailableMessage` 가 저장된 선택의 차단 사유를 먼저 보고 `effective == nil` 을 나중에
  봤다. CLI 를 하나도 안 깐 사용자가 "설정에서 경로를 넣으세요" 대신 "이 CLI 는 도구 격리가
  안 됩니다" 를 읽었다 — 버튼은 비활성인데 할 수 있는 일이 안 적혀 있다.
- **부류**: **여러 사유가 동시에 참인데 하나만 보여 주는 자리.** 먼저 쓴 가지가 이기므로 작성
  순서가 그대로 우선순위가 된다. 새 사유를 나중에 덧붙일 때 맨 아래에 두면 자동으로 최하위가 된다.
- **처방**: 이런 함수는 **사용자가 할 수 있는 일 순서**로 정렬한다. 또한 같은 판정이 "고른 것"과
  "실제로 나갈 곳"을 함께 볼 때는, 둘이 어긋나는 경우가 차단 말고 **또 있는지** 센다 — 여기서는
  "고른 CLI 를 지웠다" 가 빠져 있어 다른 벤더 CLI 로 조용히 나갔다.
  (`PokemonChatProviderSelection`, 2026-08-30.)

## 같은 값을 **두 저장소**에 두고 한 setter 로만 맞추는 부류

- **증상**: 지정 실행 경로가 `AppSettings.chatExecutablePaths`(딕셔너리 `pokemonChatExecutablePaths`)와
  `pokemonChatExecutablePath.<종류>`(스칼라 키) 두 곳에 있었다. `PokemonChatProviderCache` 는 앞쪽으로
  **캐시 키를 만들고** 해석기는 뒤쪽을 **다시 읽었다** — 키를 만든 값과 해석이 본 값이 다른 상태다.
  부류 스윕에서 `SettingsView` 의 "찾은 경로" 초록 체크도 뒤쪽을 읽고 있었다(사용자가 방금 지운
  경로를 계속 가리킬 수 있다).
- **왜 안 터졌나**: `setChatProviderExecutablePath` 가 **두 곳에 다 써서** 우연히 맞아 있었다.
  기본값 마이그레이션·설정 가져오기가 한쪽만 건드리는 순간 조용히 갈라진다.
- **처방**: 편의 오버로드가 스스로 `UserDefaults` 를 읽으면 그게 두 번째 저장소가 된다. 그 오버로드를
  **지워서** 지정 경로가 인자로만 들어오게 했다 — 두 벌이 다시 생기면 컴파일이 막힌다. 캐시 키는
  **해석기가 실제로 소비하는 값**으로만 만든다. (`PokemonChatProviderExecutableResolver`, 2026-08-30.)

## 바인딩의 **읽기와 쓰기가 다른 값**을 가리키면, 고를 수 없는 선택지가 생긴다

- **증상**: 제공자 피커가 `get` 은 자동 선택 결과, `set` 은 저장값에 걸려 있었다. "자동 선택" 은
  고른 직후에도 폴백 이름이 대신 보여 **한 번도 선택된 적이 없고**, 차단된 저장값(`opencode`)은
  목록 어디에도 안 뜨면서 배너만 그 이름을 말했다 — 화면이 가리키는 대상을 화면에서 찾을 수 없다.
- **부류**: `Binding(get:set:)` 으로 **다른 두 값**을 잇는 자리. `set(x)` 뒤 `get() != x` 면 그
  컨트롤은 사용자의 조작을 되돌려 주지 못한다.
- **처방**: 컨트롤은 **자기가 쓰는 값**을 읽는다(`$providerRaw`). 파생값을 함께 보여 주고 싶으면
  컨트롤이 아니라 **옆의 라벨**로 둔다 — 여기서는 전송 자리의 동의 줄이 이미 그 역할이었다.
  덧붙여 "막혔다" 색(주황)은 실제로 못 보낼 때만 쓴다. 폴백이 보내 주는 중에도 주황이면 같은
  화면이 "못 씁니다" 와 "Codex 로 나갑니다" 를 동시에 말한다. (`PokemonChatView.swift`, 2026-08-30.)

## `A && B` 게이트는 **B 가 늘 참인 상태로만** 시험하면 A 를 지워도 안 깨진다

- **증상**: 칩 제안 판정 `!timer.isRunning && activeAdventure == nil` 에서 앞 조건을 지우고
  **결함 주입**을 했는데 새 가드가 초록으로 통과했다. 준비한 상태 다섯 중 타이머가 도는 것은
  전부 `startFocusSession` 으로 만들었고, 그건 모험도 함께 내보낸다 — 뒤 조건이 앞 조건을 가려
  A 를 지운 채로도 결과가 같았다.
- **왜 안 터졌나**: 상태 조합을 "실제로 자주 보는 것" 으로만 만들면 두 조건이 **함께 참**인
  구간만 밟는다. 갈라지는 구간(타이머만 도는 **휴식** 단계, 모험만 남은 정산 대기)이 빠지면
  가드는 조건 하나를 통째로 잃어도 조용하다. 커버리지도 못 잡는다 — 그 줄은 실행되니까.
- **부류**: `A && B` / `A || B` 게이트의 회귀 테스트. **각 조건이 단독으로 판정을 뒤집는 상태**를
  하나씩 갖고 있어야 한다. 같은 가림을 실행기에서 이미 겪었다 —
  모험만 보던 시작 게이트가 휴식 단계를 놓쳐 `already in rest` 를 뒤늦게 붙였다.
- **처방**: 새 게이트를 넣을 때 조건 수만큼 **분리 상태**를 만든다. 그리고 결함 주입은 조건
  **하나씩** 지워 본다 — 전체를 한 번 지워 빨개지는 것만 보면 가려진 조건을 못 찾는다.
  (`PokemonChatToolbox.isReady`, 2026-08-31.)

## 가드가 **함수 안에 갇혀** 있으면 물어볼 방법이 없어, 판정이 두 벌이 된다

- **증상**: 칩 판정은 `evolutionPrompt != nil` 만 봤는데 `CompanionStore.acceptEvolution()` 은 가드가
  여덟 개였고, **틀리면 카드만 지우고 조용히 돌아갔다.** 카드가 뜬 뒤 조건이 무너지면(기술을 잊음·
  밤 한정 진화를 새벽에 승인·요구 파티원이 박스로 감) 앱이 권한 대로 누른 사용자가 진화를 잃는다.
- **왜 안 터졌나**: 실행기 쪽엔 이미 이 상태의 재현체가 있었다
  (`testEvolutionThatSilentlyFailsIsNotReportedAsAccepted`). 제안 쪽에서 **같은 상태를 재지 않아**
  두 판정이 갈라진 걸 아무도 못 봤다 — 조건표가 두 벌이면 갈라진 걸 알아챌 방법은 손으로 맞대 보는 것뿐이다.
- **부류**: `guard ... else { 부작용; return }` 로 끝나는 실행 함수. 그 조건은 **호출자가 미리
  물어볼 수 없는 값**이고, 그래서 화면·대화는 자기 조건표를 따로 쓴다. 실패가 조용할수록 더 나쁘다.
- **처방**: 가드를 **술어로 뽑아** 실행과 판정이 같은 계산을 보게 한다
  (`canAcceptEvolutionNow` → `resolvedEvolution()`, `canUseRareCandy` 가 이미 그 형태였다).
  새 액션 칩을 더할 때 스토어에 물어볼 술어가 없으면, 칩을 먼저 만들지 말고 술어를 먼저 만든다.
  (`CompanionStore.acceptEvolution`, 2026-08-31.)

## **두 팔이 같은 축**을 쓰는 대조군은 기능을 통째로 지워도 초록이다

- **증상**: 칩 줄 레이아웃 테스트 두 개가 액션 칩 `ForEach` 를 지워도 전부 통과했다. 하나는
  "액션 있음 vs 없음의 **높이가 같다**" 를 재고(칩이 아예 안 그려지면 당연히 같다), 대조군이라던
  다른 하나는 두 팔 모두 `actions: []` 로 두고 **질문 축**만 흔들었다. 기능의 유일한 뷰 테스트였다.
- **왜 안 터졌나**: 대조군을 "빈 것보다 큰가" 로 쓰면 뜻이 있어 보이지만, 흔든 축이 검증 대상과
  다르면 검증 대상이 사라져도 답이 안 변한다. 커버리지도 못 잡는다 — 다른 팔이 그 줄을 실행한다.
- **부류**: 불변식("A 를 더해도 B 가 안 변한다")을 재는 테스트. 반드시 **A 가 실제로 그려졌음**을
  같은 축에서 따로 단언해야 불변식이 뜻을 가진다.
- **처방**: 대조군은 **검증 대상 축만** 흔든다(`actions: [.startFocus], questions: []` vs 빈 줄).
  주입으로 확인한다 — `ForEach(actions)` 를 지우고 돌려 새 대조군만 빨개지는지 본다. 실제로
  그랬고, 기존 높이 동등 테스트는 그때도 초록이었다. (`PopoverLayoutTests`, 2026-08-31.)

## 사람에게 보여 주는 이름과 기계가 받는 인자가 **다른 어휘**면, 그 버튼은 영영 아무 일도 못 한다

- **증상**: 인자를 든 유일한 액션 칩이 입력칸에 사람 문장("… 하나 써 줘")을 채웠다. 파서는
  `ItemKind(rawValue:)` 로 `rareCandy` 만 받았고, 시스템 프롬프트는 rawValue 를 나열하지 않았다 —
  모델이 `bag.list` 를 먼저 부르지 않는 한 도달할 수 없는 마커였고(왕복은 3회뿐이다),
  사용자에겐 "칩을 눌렀는데 아무 일도 안 일어남" 으로 보인다.
- **왜 안 터졌나**: 파서 테스트가 rawValue 경로만 밟았고, 오히려 **현지화 이름이 떨어지는 것을
  단언**하고 있었다. 그 단언의 근거는 "모델이 되돌려 줄 수 있는 값으로 찍는다" 였는데, 칩이
  생기면서 모델이 아니라 **사용자**가 인자를 부르는 경로가 새로 생긴 걸 반영하지 못했다.
- **부류**: 표시 문자열과 인자 어휘가 갈라지는 자리. 칩·버튼이 "사람 문장" 을 만들어 기계 경로로
  보내는 모든 곳이 같다.
- **처방**: 닫힌 목록이면 **이름으로 되짚는다**(세 언어 표시 이름 + rawValue 대조). 추측이 아니라
  대조라 목록 밖 이름은 여전히 호출이 안 된다. 되짚기를 넣으면 **이름 충돌 가드**를 함께 넣는다 —
  아이템 사용은 소모라 엉뚱한 것을 쓰면 되돌릴 수 없다(`testNoTwoItemsAnswerToTheSameName`).
  (`PokemonChatToolParser`, 2026-08-31.)
- **되짚기를 넣고도 같은 증상이 남았다.** 문구가 **이름표의 두 번째 사본**이었다 — 한국어만
  붙여 써(`이상한사탕`) 파서가 받는 이름(`이상한 사탕`)과 갈라졌고, 한국어 칩은 여전히 아무
  일도 못 했다. 문서에도 띄어 쓴 채로 적혀 있어 부류가 닫힌 것처럼 보였다.
  **처방은 문구가 자기 `call` 에서 이름을 읽는 것**이다(`.startFocus` 가 분을 그렇게 읽는다) —
  사본이 없으면 갈라질 수 없다. 그리고 되짚기 표는 **실행기가 실제로 성공시킬 수 있는 종류**로
  좁힌다: 가구는 이름만 있고 성공 경로가 없어서, 표에 두면 승인 카드가 먼저 뜬 뒤에 실패한다.
  (`PokemonChatAction.phrase`·`usableFromChat`, 2026-08-31.)

## 인자를 든 케이스만 보는 불변식 가드는 **인자를 든 나머지**를 면제해 준다

- **증상**: "칩 문구는 자기 호출의 값을 그대로 말한다" 를 지키던 가드가 `guard case
  .pokedoroStart(let minutes) = action.call else { continue }` 로 시작했다. 인자를 든 다른 칩
  (`.itemUse`)은 규칙 밖이라, 한국어 문구가 아이템 이름을 틀리게 써도 파일 전체가 초록이었다.
  같은 날 짝 테스트도 입력을 **표에서** 뽑아(`L(lang).itemName(...)`) 표 → 표 항등식이 되었다 —
  이름이 어떻게 틀리든 실패할 수 없는 단언이었고, 이름은 "칩이 입력칸에 넣는 이름" 이라 적혀 있었다.
- **왜 안 터졌나**: `continue` 로 좁힌 가드는 **좁혔다는 사실이 안 보인다.** 통과 개수도 커버리지도
  줄지 않는다(다른 케이스가 그 줄을 실행한다). 테스트 이름이 실제 입력보다 넓은 약속을 하면
  리뷰도 못 잡는다.
- **부류**: `for ... { guard case X else { continue } }` 로 시작하는 불변식 테스트 전부. 그리고
  검증 대상이 만든 값이 아니라 **정답 표에서 입력을 뽑는** 테스트 전부.
- **처방**: 케이스를 `continue` 로 흘리지 않고 **인자 종류마다 갈래**를 둔다(`switch action.call`).
  입력은 검증 대상이 실제로 내놓는 값에서 뽑고, 표와 대조하는 단언은 따로 둔다. 주입으로 확인한다 —
  문구를 일부러 틀리면 빨개지는지 본다(실제로 그랬다). (`PokemonChatToolTests`, 2026-08-31.)

## `@Observable` 이 못 깨우는 술어 하나 때문에 **화면 전체를 초당 한 번** 다시 그리고 있었다

- **증상**: 대화 칩 줄이 `TimelineView(.periodic(by: 1))` 로 감싸여 팝오버가 열려 있는 내내 돌았다.
  타이머도 모험도 없는 대화에서도 초당 한 번씩 칩 목록과 `profile` 이 다시 만들어졌고, `profile`
  한 번이 `ownedMons`(박스 전체 배열 한 벌) + 진화 트리 조회다. 한 틱에 그게 6~9번이었다.
- **왜 안 터졌나**: 시계가 **필요한 이유**는 맞았다(`isAdventureInProgress` 가 `clock()` 을 읽어
  `@Observable` 이 못 깨운다). 근거가 참이라 게이트가 없다는 게 안 보였다. 선례(`FocusTimerView`)는
  같은 술어를 **조건 안에서만** 깨우는데, 주석이 그 선례를 인용하면서 조건은 안 가져왔다.
- **부류**: 상시 애니메이션·상시 타이머 전부. "왜 필요한가" 가 참인 것과 "언제 필요한가" 가 좁은 것은
  별개 질문이다.
- **처방**: 벽시계 술어의 **선행조건을 판정으로 만들어** 그때만 깨운다(`needsWallClockTicker`).
  판정은 술어를 아는 곳(실행기)에 두고 뷰는 묻기만 한다 — 뷰가 직접 판정하면 새 벽시계 술어가
  붙는 날 한쪽만 늘어난다. 주입으로 확인한다: 판정을 `true` 로 고정하면 가드가 빨개진다.
  (`PokemonChatView`·`PokemonChatToolbox`, 2026-08-31.)

## 누른 표시가 없는 칩은 **두 번 눌린다** — 이어붙이기가 요청을 두 벌로 만든다

- **증상**: 초안을 지우지 않으려고 칩을 `덮어쓰기` → `이어붙이기` 로 바꿨는데, 멱등이 아니었다.
  같은 액션 칩을 두 번 누르면 "25분 집중하자 25분 집중하자" 가 되고, 모델은 그걸 두 번의 요청이나
  50분으로 읽는다. 액션 칩은 줄 맨 앞이고 눌러도 아무 표시가 없어 두 번 눌리기 쉽다.
- **왜 안 터졌나**: 테스트가 "쓰던 문장이 남는가" 만 봤다. 새로 생긴 성질(이어붙이기)의 **반복
  적용**은 아무도 묻지 않았다 — 덮어쓰기 시절엔 멱등이 공짜였기 때문에 잃은 걸 못 알아챘다.
- **부류**: 덮어쓰기를 누적으로 바꾸는 모든 변경. 누적은 멱등을 공짜로 주지 않는다.
- **처방**: 누적 함수는 **같은 입력의 반복**을 단언한다(`f(f(x, c), c) == f(x, c)`). 되돌릴 곳은
  누적 쪽이다 — 덮어쓰기로 되돌리면 원래 고치려던 결함이 돌아온다. (`PokemonChatChipRow.composed`,
  2026-08-31.)
## LAN 광고 이름에 **고유 접미가 없으면**, 같은 이름의 두 기기가 서로를 자기로 지운다

- **증상**: Poké Home 의 VISIT 탭이 아무 집도 못 찾았다("주변 홈을 찾는 중이에요…" 고정).
  `MemoryHomeVisitCenter` 만 Bonjour 이름으로 닉네임 **원문**을 광고하고, 자기 필터도 원문으로 했다.
  닉네임이 같은 두 기기(기본값 `MemoryHome` 포함)가 만나면 mDNS 가 한쪽을 `MemoryHome (2)` 로
  개명하는데, 개명당한 쪽의 저장값은 여전히 `MemoryHome` 이라 **상대의 광고를 자기 것으로 오인해
  목록에서 지웠다**. 반대쪽은 개명된 이름이 보이지만 공백 때문에 `clean` 이 라벨을 버려 모든 집이
  같은 기본 라벨로 뭉개졌다.
- **부류**: `NWListener.Service(name:)` 에 **사용자가 고른 이름을 그대로** 넘기는 자리.
  `BattleNet`·`PokemonTrade`·`MultiplayerRoomCenter` 는 셋 다 `이름#고유값` 을 광고하고 그 고유
  이름으로 자기를 가른다(`PeerAdvertisementTests.testTheSameTrainerNameOnAnotherMachineIsStillAPeer`
  가 같은 규칙을 이미 지키고 있었다). 새로 생긴 네 번째 센터만 그 규칙 밖에 있었다.
- **왜 안 터졌나**: 방문 프로토콜 테스트는 `valid()` 순수 검증과 연결 수명만 봤다. 호스트 1개 +
  방문자 1개를 실제로 붙여 보는 종단 테스트가 0개라, 이름 충돌·자기 필터는 테스트가 밟는 경로
  **밖**이었다. 커버리지는 `valid()` 로 채워져 통과한다.
- **처방**: 광고 이름을 만드는 자리와 자기를 거르는 자리를 `nonisolated static` 순수 함수로 빼고
  (`serviceName(nickname:peerID:)` / `peer(fromService:excluding:endpoint:)`), 접미는
  `AppSettings.memoryHomeLANPeerID` — 설치마다 고정인 값 — 에서 굽는다. 표시 라벨은 접미만 떼고
  공백은 허용한다(`clean` 을 쓰면 개명된 이름이 통째로 버려진다).
  게이트는 **파일 어딘가의 `#\(` 로 세면 안 된다** — 결함이 있는 채로도 `speciesLabel` 의
  `"#\(speciesID)"` 때문에 통과했다. 광고 이름을 **넘기는 그 줄**이 `name: ...serviceName` 인지 본다
  (`test-gate.sh` ▶ Bonjour 광고 이름 스윕). (`MemoryHomeVisitCenter`, 2026-08-31.)

## `lastError` 를 **화면이 읽지 않으면**, 모든 실패가 원인 없는 무동작이 된다

- **증상**: 위 결함의 절반. `MemoryHomeVisitCenter` 는 로컬 네트워크 권한 거부(`NoAuth`)를 위한
  3개국어 안내 문구까지 만들어 두고도 그 값을 어느 화면도 읽지 않았다. 권한 거부·상대의 거절·잘못된
  페이로드가 전부 "주변 홈을 찾는 중이에요…" 한 줄로 뭉개져, 사용자에게는 원인 없는 무동작이었다.
- **부류**: `private(set) var lastError` 를 가진 센터 중 UI 에 그 값을 읽는 줄이 없는 것.
  `PlayerGymView`·`BattleView`·`GymLeagueView`·`PokemonTournamentView` 는 모두 갖고 있었다.
- **덧붙여**: `NWBrowser` 의 권한 차단은 `.failed` 가 아니라 **`.waiting` 으로 조용히 머문다**.
  `.failed` 만 처리하면 가장 흔한 실패가 한 번도 기록되지 않는다(`BattleNet.startBrowser` 는 둘 다
  처리한다). 재시작도 같이 붙인다 — `.failed` 뒤 그대로 두면 권한을 켜도 복구되지 않는다.
- **처방**: `test-gate.sh` ▶ 침묵하는 실패 스윕 — `Core` 의 `...Center` 중 `var lastError` 를
  선언한 타입은 `UI` 어딘가에서 그 값을 읽어야 한다. (`MemoryHomePresenter`, 2026-08-31.)

## 길이 상한을 **글자 수로 세면**, 한글 사용자에게만 결함이 남는다

- **증상**: 바로 위 결함(고유 접미)을 고친 커밋이 한글 닉네임에서 그대로 재발했다. 접미를 붙이긴
  하는데 닉네임을 40 **글자**로 잘랐고, Bonjour 인스턴스 이름 상한은 63 **UTF-8 바이트**다. 한글은
  글자당 3바이트라 21자면 이미 넘고, mDNSResponder 는 **꼬리부터** 자른다 → 방금 붙인 `#ABCDEF` 가
  제일 먼저 먹힌다 → 같은 닉네임 두 기기가 같은 이름을 광고 → 접미를 붙인 의미가 통째로 사라진다.
- **부류**: 외부 프로토콜의 **바이트** 상한을 `String.count`/`prefix(n)` 로 지키는 자리. 네 LAN
  센터 중 `PlayerGymRoomName.make` 만 바이트 예산 루프를 갖고 있었고, 나머지 셋(`BattleNet`·
  `PokemonTrade`·`MultiplayerRoomCenter`)과 Memory Home 은 예산을 아예 보지 않았다. **한 곳에만
  사는 규칙은 부류로 남는다** — 그 한 곳이 정답을 갖고 있어도 나머지는 모른다.
- **왜 안 터졌나**: 회귀 테스트(`testServiceNameIsBonjourSafe`)의 입력이 `"Memory Home\n"` 이었다.
  `clean` 이 공백 때문에 통째로 거부해서 10바이트 ASCII **기본값**(`MemoryHome`)만 쟀다 — 실제 광고
  이름은 한 번도 안 밟는 테스트였다. 통과하는 입력을 고르면 가드가 있는 척만 한다.
- **처방**: 예산을 `LANServiceName.make(base:suffix:)` 한 곳으로 모으고 네 센터가 전부 지나게 했다.
  `suffix` 는 절대 자르지 않는다(고유성이 거기에만 있다), 자르기는 `removeLast()` = **글자 단위**다
  (스칼라를 반 자르면 깨진 UTF-8 이 광고에 실린다). 게이트는 **식별자 이름을 보면 안 된다** —
  이전 판은 `name: ...serviceName` 인지만 봐서 `let serviceName = <맨 닉네임>` 이면 통과했다.
  지금은 "광고하는 파일이 공용 헬퍼를 지나는가" 를 본다(`test-gate.sh` ▶ Bonjour 광고 이름 스윕).
  (`LANServiceName`, 2026-09-01.)

## 오류를 **결과 콜백에서 지우면**, 사용자가 읽는 도중 사라진다

- **증상**: 방문 거절 문구("이 홈은 방문을 받지 않아요")가 몇 초 만에 사라졌다. `updateHomes` 가
  `if !homes.isEmpty { lastError = nil }` 로 지웠는데, mDNS 는 TTL 갱신·피어 변동마다 그 콜백을
  부른다. 반대 방향도 있었다: 주변에 홈이 없는(=흔한) 사용자는 `homes` 가 영영 비어 있어 Wi-Fi 가
  돌아와도 "권한을 허용해 주세요" 가 **영구히** 남았다 — 이미 켠 권한을 다시 켜라는 안내다.
- **부류**: 오류를 지우는 근거를 **상태 전이**가 아니라 **부수적 신호**(결과 도착·목록 비었음)에서
  찾는 자리. 지우는 조건과 세우는 조건이 다른 축이면 반드시 한쪽이 어긋난다.
- **처방**: 지우는 근거는 `.ready` 하나뿐 — 브라우저가 정상으로 돌아왔다는 그 전이. 목록 반영
  (`applyDiscovered`)은 `lastError` 를 **건드리지 않는다**. 상태 핸들러를 클로저에서
  `handleBrowserState(_:)` 로 꺼내 두 방향 모두 테스트했다(`NWBrowser.State` 는 테스트에서 만들 수
  있다 — `.waiting(.posix(.ENETDOWN))`). (`MemoryHomeVisitCenter`, 2026-09-01.)

## 실패한 LAN 객체는 **참조만 버리면 안 죽는다**

- **증상**: `.failed` 재시작이 `browser = nil` / `listener = nil` 로 참조만 버렸다. 실패한 객체는
  큐·포트·핸들러를 붙든 채 살아남아 슬립 복귀마다 하나씩 쌓이고, 죽은 브라우저가 계속 콜백을 쏜다.
  `guard browser == nil` 로도 회수할 수 없다 — 참조를 이미 버렸기 때문이다.
- **부류**: 이 규칙은 `BattleNet.startListener` 주석에 이미 적혀 있었다("참조만 버리면 실패한 객체가
  큐·포트를 붙든 채 남아 슬립 복귀마다 누적된다"). 그런데 **같은 파일의** `.failed` 두 분기가 둘 다
  그 규칙을 어겼고, Memory Home 이 그대로 따라 했다. 주석은 강제하지 않는다.
- **덧붙여**: 재시도에 상한이 없으면 영구 불가 상태(권한 차단)에서 5초마다 새 브라우저를 만들며
  하루 종일 돈다. 상한 + 지수 백오프를 두면 마지막 오류가 화면에 남아 원인이 보인다.
- **처방**: `test-gate.sh` ▶ 취소 없이 버려지는 LAN 객체 스윕 — `browser|listener = nil` 줄은
  같은 줄이나 바로 앞 줄에 `cancel()` 이 있어야 한다. (`BattleNet`·`MemoryHomeVisitCenter`,
  2026-09-01.)

## grep 게이트가 **이름**을 보면, 값이 무엇이든 통과한다

- **증상**: 위 결함들을 막으려고 넣은 게이트 세 개가 전부 우회 가능했다. ① Bonjour 이름 게이트는
  식별자가 `...serviceName` 인지만 봐서 그 변수에 맨 닉네임을 담으면 통과. ② `includePeerToPeer`
  게이트는 그 **단어**를 찾아서, 규칙을 설명하는 주석이 게이트를 만족시켰다(코드 줄을 지워도 통과).
  ③ 침묵하는 실패 게이트는 "UI 파일이 센터 이름을 언급 + 파일 어딘가에 `lastError` 라는 글자" 라,
  누가 `PopoverView` 에 **다른** 센터의 오류 줄을 붙이는 순간 Memory Home 오류 UI 가 0줄이어도 통과.
- **부류**: grep 게이트가 **표기**(식별자 이름·단어의 존재)를 보는 것과 **관계**(그 값이 어디서 왔나·
  그 변수가 무슨 타입인가)를 보는 것의 차이. 앞의 것은 규칙을 아는 사람만 통과시키고, 규칙을 모르는
  다음 사람은 이름만 맞춰서 결함을 그대로 넣는다.
- **처방**: 표기 대신 관계를 본다 — ① "광고하는 파일이 공용 헬퍼를 지나는가", ② `includePeerToPeer
  = true` **대입**, ③ 그 UI 파일에서 **그 센터 타입으로 선언된 식별자**를 뽑아 `<변수>.lastError`.
  그리고 게이트도 **결함을 주입해 실패하는지 확인한다** — 네 게이트 모두 그렇게 검증했고, ②는 그
  과정에서 주석 우회가 드러났다. 검증하지 않은 게이트는 게이트가 아니다.
- **함정**: `set -euo pipefail` 아래서 `{ grep A; grep B; } | sort` 는 A 가 빈손이면 B 를 영영 안
  돈다. 게이트를 넓힐 때 `|| true` 를 빠뜨리면 **조용히 좁아진다**(그 자리에서 `BattleCenter` 를
  오탐했다). (`scripts/test-gate.sh`, 2026-09-01.)

## 출력 후처리가 **형식 위반**을 안전 위반과 같이 처리하는 부류

- **증상**: 포켓몬 대화가 거의 매 턴 "그건 잘 모르겠어. 대신 …" 만 돌려줬다. 다섯 번 물으면 네 번이
  같은 문장이라, 사용자에겐 모델이 아무것도 모르는 것처럼 보였다.
- **직접원인**: `PokemonChatReplyGuard.sanitized` 가 문장 수(≤3)를 세어 넘으면 **답변을 통째로**
  캔 문구로 갈아치웠는데, 세그먼트 분할(`split(whereSeparator: ".!?。！？\n")`)이 끝에 붙은 이모지를
  한 문장으로 셌다 — `"…반가워! …가득 차 있어! ⚡"` 는 4세그먼트다. 실제 모델은 거의 매번 이모지를
  붙이므로 정상 답변 대부분이 버려졌다. (리포트 화면에서 **살아남은 유일한 답변**이 이모지까지 세어
  정확히 3이었던 게 증거다.)
- **부류**: 후처리가 **안전 위반**(역할 이탈·유출)과 **형식 위반**(너무 김·문장 수)을 같은 처분으로
  묶으면, 서식이 어긋났다는 이유로 사용자의 질문에 대한 답이 사라진다. 형식은 **접는 것**이고
  버리는 건 경계를 넘었을 때만이다. 같은 부류의 형제: 빈 본문. 마지막 왕복에서 모델이 마커만 적으면
  본문이 비는데, 그 빈 문장이 앞선 턴에 한 말을 덮어써서 "모델은 말했는데 화면엔 캔 문구" 가 됐다.
- **부류 스윕**: 문장·세그먼트를 세어 판정하는 자리는 코드베이스에 이 한 곳뿐이었다.
  `BattleChat.normalizedBody` 는 상한 초과를 `nil` 로 **거부**하지만 그건 신뢰경계(남의 기기가 보낸
  값)라 처분이 다른 게 맞다 — 같은 파일의 `displayName` 은 이미 "거부 대신 자른다" 로 갈라 두었다.
- **테스트 공백**: 가드 테스트는 **악성 입력**(코드펜스)만, 태그 테스트는 **깨끗한 3문장**만 넣었다.
  후자의 주석은 이 부류("정상 답변이 리다이렉트된다")를 이미 알고 있었으면서 태그 경로만 고쳤다 —
  실제 모델이 쓰는 **이모지 꼬리**를 아무 테스트도 밟지 않았다. 왕복 상한 테스트 둘은 본문이 있는
  응답만 반복해 빈 본문 경로가 `^0` 이었다.
- **처방**: ① 문장 수 판정 삭제(길이 상한이 같은 일을 한다), ② 길이 초과는 문장 경계에서 절단,
  ③ 빈 본문은 앞 턴의 말을 덮지 않음, ④ **침묵과 금지를 다른 문구로** 가른다 — "잘 모르겠어" 는
  질문을 못 알아들었다는 뜻이라, 모델이 침묵한 경우엔 거짓말이다, ⑤ 갈아치울 땐 `AppLog` 에 사유를
  남긴다(원인을 추측으로 찾은 게 이번 조사 시간의 대부분이었다).
  회귀: `testAWarmReplyWithATrailingEmojiIsNotThrownAway` ·
  `testAnOverlongReplyIsTrimmedAtASentenceBoundaryInsteadOfBeingReplaced` ·
  `testTheSteerLineNeitherClaimsIgnoranceNorRepeatsItself` ·
  `testTheModelsWordsSurviveALastRoundThatIsMarkerOnly` ·
  `testTotalSilenceGetsARetryInvitationNotAnIDontKnow`. (`PokemonChat.swift`, 2026-09-01.)

## 후처리의 **처분 등급**을 문자열 비교로 되묻는 부류 (`output == input` 은 등급이 아니다)

- **증상**: 바로 위 항목을 고친 그 PR 안에, 같은 부류의 형제 셋이 남아 있었다. ① 500자를 넘는
  정상 답변이 승인 카드를 잃고(사용자는 "같이 집중하자" 를 읽는데 카드가 안 뜬다), ② 가드가
  갈아치운 캔 문구가 **관계 기억**으로 앨범에 저장돼 이후 모든 요청에 `Relationship memory
  (conversation): 앗, 지금은 말이 잘 안 나와…` 로 되먹임되고, ③ 앞선 왕복의 문장에 마지막 왕복의
  승인 카드가 붙었다("가방 볼게!" 를 읽은 사용자에게 사탕을 쓸지 묻는다).
- **직접원인**: 호출부가 `safeReply == reply` 로 "가드가 손댔나" 를 되물었다. 그 등식은 **갈아치움**과
  **접힘**을 구분하지 못한다 — 앞 항목이 "형식 위반은 안전 위반이 아니다" 로 가드 안쪽을 갈라 놓고,
  호출부 두 곳은 옛 등식을 그대로 썼다. ③은 다른 뿌리다: 빈 본문이 앞 턴의 말을 못 덮게 고치면서
  `reply` 만 이월시키고 `call = parsed.call` 은 매 왕복 덮어써, 본문과 호출의 출처가 갈렸다.
- **부류**: 후처리가 **여러 처분**(그대로 · 접음 · 갈아치움)을 가지게 된 순간, 호출부가 그 등급을
  출력 비교로 복원하려 하면 반드시 하나가 뭉개진다. 등급은 **함수가 돌려줘야** 한다 —
  `sanitized` 가 `(text, verdict)` 를 반환하면 세 호출부가 같은 값을 보고, 새 처분을 더할 때
  컴파일러가 누락된 자리를 지목한다. 같은 부류: 파이프라인이 값을 이월시키면서 **어느 단계에서
  왔는지**를 안 들고 다니면, 이월된 값에 다른 단계의 부산물이 붙는다(③).
- **부류 스윕**: `X == input` 으로 변형 여부를 되묻는 자리는 코드베이스에 3곳 더 있다 —
  `BattleNet:1792` · `PokemonTrade:272` · `MultiplayerRoomCenter:1221` 의
  `normalizedBody(x), body == x`. **이건 다른 부류다**: 비교 대상이 남의 기기가 보낸 프레임이라
  "정규화가 필요했다 = 규약 위반 = 거부" 가 맞는 처분이다. 내 가드가 내 출력에 한 일을 되묻는 것과
  신뢰경계에서 입력을 검증하는 것을 섞지 않는다.
- **덧붙여 — 5층 울타리가 ASCII 뿐이었다**: `roleBreakNeedles` 가 전부 영어인데 시스템 프롬프트는
  `profile.language`(기본 한국어)로 답하라고 지시한다. 즉 실제로 나오는 역할 이탈("사실 나는 AI
  언어모델이야", "터미널에서 명령어를…")은 **한 번도 안 걸렸다**. 앞 PR 이 프롬프트의 주제 울타리와
  문장 수 게이트를 동시에 뺐으므로, 그 사이 이 목록이 유일한 층이었다.
- **테스트 공백**: 절단 테스트가 두 모양(구두점 91자마다 · 아예 없음)만 재서, **경계가 창 앞쪽에만
  있는** 세 번째 모양(`"좋아! " + 700자` → 3자)을 밟지 않았다. 승인 카드 테스트는 마지막 왕복의
  마커가 승인 불필요 도구뿐이라 ③ 조합을 만들지 않았다. 앨범 테스트는 갈아치움과 여섯 번째 턴을
  **함께** 밟지 않았다(도구 경로만 막고 아홉 줄 아래 형제 경로는 안 봤다).
- **처방**: ① `Verdict { kept, clipped, replaced }` 를 반환값에 싣고 세 호출부를 그 값으로 게이트,
  ② 문장 경계는 창의 **절반 뒤**일 때만 존중, ③ 본문의 왕복 번호를 들고 다니며 이월됐으면 승인
  카드를 버린다, ④ `roleBreakNeedles` 에 한국어·일본어 대응어 추가, ⑤ 로그에 **매치된 낱말**을
  싣는다(길이만 찍으면 다음 오탐도 추측으로 찾는다 — 앞 항목 처방 ⑤가 절반만 지켜졌었다),
  ⑥ 마커-only 이월도 로그를 남긴다(다른 가드 분기는 전부 남기는데 이 자리만 비어 있었다).
  회귀: `testAnOverlongReplyIsNotReducedToItsOpeningFragment` ·
  `testARoleBreakWrittenInTheReplyLanguageIsCaughtToo` ·
  `testAClippedReplyStillRaisesTheApprovalCardItCameWith` ·
  `testAnApprovalCardNeverAttachesToAnEarlierRoundsSentence` ·
  `testAGuardReplacementIsNeverKeptAsThePeriodicMemory`.
  다섯 개 전부 고치기 전 코드에서 실패하는 것을 확인했고, 새 분기는 `llvm-cov show --show-regions`
  에서 `^0` 이 없다. (`PokemonChat.swift`, 2026-09-01.)
## 코어가 국면을 **동기로 넘기면**, 그 턴의 재생은 화면에서 사라진다

- **증상**: 오늘의 던전에서 웨이브를 이기면 결정타·기절·로그가 **하나도 안 보이고** 곧장 보상
  목록이 떴다. 재생기(`BattleAnimator`)는 붙어 있었는데도 그랬다.
- **직접 원인**: `useMove` → `settle()` 이 같은 동기 블록에서 `stage = .picking` 을 세우고,
  화면은 `stage` 로 무엇을 그릴지 갈랐다. 전투 패널이 그 프레임에 사라지므로 `.onChange` 가
  재생기에 스트림을 넘길 기회가 없다 — 재생기는 **한 번도 돌지 않았다**.
- **테스트가 왜 못 걸렀나**: 코어 테스트는 `useMove` 뒤 `stage == .picking` 을 확인한다. 그게
  바로 결함을 만드는 동작이라, 코어를 옳게 잠글수록 화면의 어긋남은 보이지 않는다. 재생 순서는
  **뷰가 무엇을 그리는가**의 문제라 코어 단정으로는 닿지 않는다.
- **부류**: 값이 바뀐 **프레임**과 그 값을 보여 줄 **시간**이 다른 자리 전부. 배틀 화면은 같은
  문제를 `BattleAnimator.onCaughtUp` 으로 이미 풀어 뒀는데, 나중에 생긴 런 화면이 그 자리를
  지나지 않았다.
- **처방**: 화면 국면을 코어 국면에서 **분리**하고(`RogueRunPhase.of`), 재생이 스트림 끝에
  닿을 때까지 전투를 붙잡는다. 판정은 `isPlaying` 이 아니라 `playedCount < events.count` 다 —
  국면이 넘어간 그 프레임에는 재생기가 아직 새 이벤트를 못 받아 `isPlaying` 이 false 다.
  (`RogueRunView.swift`, 2026-08-31.)

## 이벤트를 **만들지 않는 행동**은 재생 대기만으로는 화면에 없다

- **증상**: 몬스터볼이 "기능이 없는 것" 처럼 보였다. 볼·성공률·던지기가 다 구현돼 있었는데도.
- **직접 원인**: 포획 성공은 `BattleEvent` 를 하나도 만들지 않는다(잡힌 상대는 `retireOpponent`
  로 조용히 빠진다). 그래서 위 처방(재생 끝까지 전투 유지)에도 걸리지 않고, 잡은 순간 보상
  화면으로 넘어간다 — 사용자가 본 것은 "볼을 눌렀더니 화면이 바뀌었다" 뿐이다.
- **부류**: 결과가 **상태로만** 남고 스트림에 흔적이 없는 행동. 재생기·로그를 근거로 "보여 준다"
  고 가정하는 화면 전부가 같은 함정을 밟는다.
- **처방**: 스트림에 못 실리는 결과는 **화면이 직접 한 줄로** 남기고(`BallThrowNotice`), 사용자가
  확인할 때까지 다음 국면으로 넘어가지 않는다. 와이어에 실리는 `BattleEvent` 에 런 전용 case 를
  더하지 않는다 — 멀티 대전의 계약이라 값이 커진다. (`RogueRunView.swift`, 2026-08-31.)

## 밸런스 손잡이를 **세이브 정규화에 쓰면**, 손잡이를 돌린 날 옛 기록이 바뀐다

- **증상**(잠재): `RunProgress.normalize` 가 "클리어한 적 있으면 최고 웨이브 = 최종 웨이브" 로
  보정했다. 판 길이를 12 → 30 으로 늘리는 순간, 12웨이브짜리 판을 클리어한 세이브가 업데이트
  당일에 **"30/30 완주"** 로 둔갑한다.
- **부류**: 밸런스 값(`RogueTuning`)처럼 **버전마다 달라지는 상수**를 저장값의 불변식에 쓰는 자리.
  같은 부류로 근처 트레이너 카드의 분모(업적 `achievementCeiling`)가 이미 있었다 — 그래서 런
  기록도 판 길이(`runFinal`)를 함께 광고한다.
- **처방**: 정규화는 **자르기만** 한다. 끌어올리지 않는다. 기록은 실제로 밟은 웨이브여야 한다.
  (`RunProgress.swift`, 2026-08-31.)

## 저장 형식이 **파생값을 안 실으면**, 되살린 상태는 화면만 맞고 계산은 틀리다

- **증상**(주입 검증으로 확인): 진행 중인 웨이브 런을 저장·복원하면 강화 표시줄은 그대로인데
  데미지에는 강화가 안 걸린다.
- **원인**: 지속 강화는 런이 들고, 개체(`BattleSide.runBoosts`)에는 `stampBoosts()` 가 **도장으로**
  옮긴다. 저장 형식은 런의 값 하나만 싣고 개체별 도장은 버리므로, 되살릴 때 다시 찍지 않으면
  개체는 강화 없이 싸운다. 화면은 런의 값을 읽어 그리므로 **눈으로는 절대 안 보인다**.
- **부류**: "한 곳에서 파생해 여러 곳에 복사해 두는 값" 을 저장·복원하는 자리 전부. 저장 형식이
  원본만 실으면 복원 코드가 파생 단계를 **다시 밟아야** 하는데, 그 단계는 대개 `private` 이라
  호출을 잊어도 컴파일이 통과한다.
- **처방**: 복원 경로도 파생 자리(`stampBoosts`)를 지난다. 테스트는 표시값이 아니라 **개체의
  값**을 확인한다(`party.map(\.runBoosts)`). (`RogueRunSave.swift`, 2026-08-31.)

## 콘텐츠를 갈아끼울 때 **적립 배선이 안 따라오면**, 업적 칸이 영영 안 찬다

- **증상**: 업적 선반의 `던전 클리어`·`보물 싹쓸이` 두 트랙 여덟 칸이 **도달 불가**였다. 총
  20,600⭐ 과 의상 3종이 영구 잠김이다. 화면에는 정상으로 보인다 — 0/1 로 그려질 뿐이다.
- **원인**: 이 두 트랙을 올리는 유일한 경로가 퍼즐 던전 정산(`settleDungeonClear`)인데, 던전 탭이
  웨이브 런(`RogueRunView`)으로 갈리면서 그 함수의 **화면 호출자가 사라졌다.** 새 정산 경로
  (`recordRunResult`)는 업적을 안 불렀다.
- **테스트가 왜 못 걸렀나**: `DungeonSettlementTests` 가 `settleDungeonClear` 를 **직접** 불러
  통과하고 있었다. 플레이어가 못 가는 경로를 재고 있었으므로 통과가 아무것도 보증하지 않았다.
  이것이 커버리지가 높을수록 오히려 안심되는 전형적인 false confidence 다.
- **부류**: 화면 하나를 다른 구현으로 교체하는 작업 전부. 교체된 화면이 **부수적으로** 하던 적립
  (업적·미션·통계·알림)은 새 화면에 자동으로 따라오지 않고, 옛 경로의 테스트는 그대로 통과한다.
- **처방**: 콘텐츠를 교체하면 옛 진입점의 **호출자 수를 센다**(`grep`). 화면 호출자가 0 이 된
  정산 함수는 그 자리에서 새 경로로 옮기거나 지운다. 적립 테스트는 코어 함수가 아니라 **화면이
  실제로 부르는 함수**를 통과시킨다. (`CompanionStore.recordRunResult`, 2026-08-31.)

## 새 대기 국면을 만들면, **그 국면을 안 보는 옛 입력 경로**가 대가를 건너뛴다

- **증상**: 2대2 를 넣으며 "쓰러진 칸을 채우기 전에는 행동을 받지 않는다" 는 대기 국면이 생겼다.
  그 상태에서 볼을 던지면 **볼만 사라지고 턴이 돌지 않았다** — 실패의 대가(상대가 한 번 움직이고
  잔뎀이 들어간다)가 통째로 없어져, 빈 칸을 방치한 채 볼을 남김없이 던지는 것이 최적이 된다.
- **원인**: 대기 국면 검사를 새 전투 코어(`WaveBattle.choose`/`sendOut`)에만 넣었다. 볼 던지기는
  런 쪽 함수(`RogueRun.canThrowBall`)가 스스로 조건을 들고 있어서 그 검사를 안 봤고, 던진 뒤
  실패 경로가 부르는 `spendTurnWithoutAttacking` 은 대기 중이라 **거부**되는데 볼 차감은 그 앞에
  있었다.
- **테스트가 왜 못 걸렀나**: 새 규칙의 테스트는 전투 코어만 겨눴다(타겟팅·턴 순서·보충). 포획
  테스트는 대기 국면이 없던 시절 그대로 — 만피 상대에게 던지는 경로라 빈 칸이 생기지 않는다.
  두 테스트 다 통과하는데 둘을 **겹친 상태**를 아무도 밟지 않았다.
- **부류**: "이 국면에서는 행동을 받지 않는다" 류 게이트를 새로 만드는 작업 전부. 게이트를 한
  타입 안에 넣으면 그 타입을 지나지 않는 입력(다른 계층이 자기 조건으로 판단하는 행동)은 조용히
  통과한다. 자원을 먼저 깎고 뒤에서 거부되는 순서면 **대가 없는 이득**이 된다.
- **처방**: 게이트를 만들면 그 자리에서 **입력 경로를 전수 센다**(기술·교체·보충·포획·항복 — 코어
  진입점 목록을 grep 으로 뽑는다). 각 경로가 게이트를 보는지 하나씩 확인하고, 자원을 깎는 함수는
  차감 **전에** 턴이 실제로 돌 수 있는지 검사한다. 회귀 테스트는 두 국면이 겹친 상태를 만든다
  (`testABallCannotBeThrownWhileASlotWaitsForAReplacement`, 2026-08-31.)

## 로컬에서 **한 번도 돌지 않은 테스트**는 전제가 깨진 채로 커밋된다

- **증상**: 2.22.0 태그를 밀자 CI 의 test-gate 가 `RogueRunSaveTests` 에서 멈췄다. 하나는
  `("battling") is not equal to ("picking")`, 하나는 `Fatal error: Index out of range` —
  보상 목록이 빈 판에서 `offers[0]` 을 집었다. 크래시라 뒤 스위트는 실행조차 못 했다.
- **직접 원인**: 두 테스트가 "`useMove` 한 번이면 이긴다" 를 전제했는데, 그 판의 상대는 기준
  HP 900 짜리라 한 턴에 안 죽는다. 같은 파일의 다른 테스트(왕복·상태이상)는 **이길 필요가
  없어서** 같은 헬퍼로도 통과한다 — 형제 테스트의 초록이 전제가 참이라는 증거처럼 읽혔다.
  같은 저장소의 `RogueRunTests` 는 이길 일이 있는 판에 `hp: 1` 상대를 쓴다(그 헬퍼를 안 봤다).
- **테스트가 왜 못 걸렀나**: 이 머신엔 Xcode 가 없어 `swift test` 가 `no such module 'XCTest'`
  로 죽는다. 대신 코어를 `swiftc` 로 묶은 단정 바이너리를 돌렸는데, 거기 옮긴 것은 `WaveBattle`
  단정뿐이었다. 세이브 테스트는 **작성만 되고 한 번도 실행되지 않은 채** 타입체크
  (`scripts/typecheck-tests.sh`)만 통과했다 — 타입체크는 전제가 참인지 묻지 않는다.
- **부류**: 로컬에서 실행할 수 없는 테스트 전부, 그리고 **단정하지 않은 전제**를 가진 테스트
  전부. 전제가 깨지면 테스트는 겨누던 규칙과 상관없는 이유로 실패하거나(운이 좋을 때),
  빈 배열을 집어 크래시한다(운이 나쁠 때 — 크래시는 그 뒤 스위트를 통째로 덮는다).
- **처방**: ① 승리·기절·보상처럼 **다음 국면을 전제하는 테스트는 그 국면을 먼저 단정**한다
  (`XCTAssertEqual(run.stage, .picking, "테스트 전제: ...")`). 전제 단정이 있으면 실패 메시지가
  전제를 가리킨다. ② 전제를 데미지 계산에 맡기지 않는다 — 한 방에 눕혀야 하면 `hp: 1` 상대처럼
  **전제가 참이 되도록 판을 만든다**(`makeWinnableRun`). ③ 로컬에서 못 도는 테스트를 새로
  썼으면, 같은 단정을 코어 단정 바이너리로 옮겨 한 번은 **실행**한다. 실행하지 않았으면
  "통과" 라고 말하지 않는다 — 타입체크 통과는 무검증과 같은 값이다. (`RogueRunSaveTests`,
  2026-09-01.)

## 세이브 축을 더하거나 필드를 지우면, **그 값을 흉내 내던 테스트 픽스처와 서명 어휘**가 함께 낡는다

- **증상**: 웨이브 런 PR 이 머지된 뒤 CI 가 14 건 실패했다. 갈래는 셋이다. ① `MoveSpec.target`
  (광역 범위 원문)을 더하자 "축이 다 찬 스펙" 을 뜻하던 픽스처 여섯이 **덜 찬 스펙**이 되어,
  "다시 안 받는다" 를 재던 대조군이 전부 뒤집혔다. ② 퍼즐 던전을 지우며 `CompanionState.dungeon`
  이 사라져 서명 세그먼트 `dun…` 이 없어졌는데 `integrityVersion` 을 안 올렸다 — 값이 든 기존
  세이브의 서명을 이 빌드가 재현하지 못해 **정상 세이브가 조작 판정**을 받는다. ③ 판 길이를
  12 → 30 으로 늘리자 구간 폭이 90 → 26 으로 좁아져, 보스 보너스(60)가 다음 구간 야생보다
  높아졌다 — 모든 웨이브를 한 줄로 세우던 단조 증가 단정이 깨졌다.
- **부류**: **데이터 축을 더하는 변경과 필드를 지우는 변경 전부.** 새 축은 "다 찼다" 를 흉내 내는
  픽스처를 전수로 낡게 하고(축이 늘 때마다 같은 일이 난다 — `statChanges` → `targetsUser` →
  `drain` → `healing` → `target` 으로 다섯 번째다), 지운 필드는 서명 어휘에서 세그먼트를 빼
  버전 상향을 요구한다. 밸런스 상수를 바꾸는 변경도 같다 — 상수에 매인 단정은 그 상수를 돌린
  날 깨진다.
- **처방**: ① 축을 더하면 `needsDetailRefresh` 같은 수렴 판정을 고치는 그 커밋에서
  `grep -rn '\.healing = ' Tests` 로 **형제 픽스처를 전수 갱신**한다. ② 서명 세그먼트를 지웠으면
  같은 커밋에서 `integrityVersion` 을 올린다(`SaveTransfer` 주석의 전례: 돌봄 삭제 7 → 8,
  던전 삭제 8 → 9). ③ 밸런스 상수에 매인 단정은 **규칙으로** 다시 쓴다 — "모든 웨이브가 단조"
  가 아니라 "야생끼리 단조 + 보스는 자기 구간 + 보너스".
- **절차 결함도 같이 남긴다**: 이 실패들은 PR CI 에 이미 떠 있었는데 **결과를 안 보고 머지**했다.
  로컬에서 `swift test` 를 못 돌리는 머신이면 PR CI 가 유일한 검증이다 — 머지 전에
  `gh run watch` 로 초록을 본다. (2026-09-01.)

## 기절 뒤 **강제 교체**를 일반 교체 행동으로 재사용하면 새 포켓몬의 턴을 빼앗는다

- **증상**: 포켓몬이 기절한 뒤 다음 포켓몬을 직접 골라도 기술 버튼이 잠긴 채 상대 행동만 기다렸다.
- **원인**: `switchTo` 하나로 자발적 교체와 기절 뒤 강제 출전을 모두 표현하면서, 둘 다
  `myAction`/`oppAction`에 저장했다. 자발적 교체는 턴 행동이 맞지만 강제 출전은 다음 행동을 고르기
  위한 상태 전환이다. 같은 케이스라는 이유로 같은 소비 규칙까지 적용했다.
- **테스트가 왜 못 걸렀나**: 기존 회귀 테스트는 자동 교체가 사라지고 사용자가 슬롯을 고를 수
  있는지만 확인했다. 교체 뒤 **같은 턴에 기술을 제출할 수 있는지**는 단언하지 않았다.
- **처방**: 기절한 활성 슬롯에서 들어온 `switchTo`는 즉시 양쪽 상태에 적용하고 출전 이벤트만
  기록한다. 행동 슬롯과 턴 번호는 그대로 두어 새 포켓몬의 기술 입력을 다시 받는다. 자발적 교체는
  기존처럼 턴을 소비한다. LAN·연습·토너먼트·공유 체육관과 시간초과 대타 경로를 모두 같은
  회귀 조건(교체 후 action=nil, move 가능)으로 검증한다. (`NetBattleState.replaceFainted`, 2026-09-01.)

## 클램프가 잘라낸 몫을 반환하지 않으면 호출부는 그게 사라진 줄도 모른다

- **증상**: 만렙(Lv.100) 파트너의 모험 경험치가 통째로 사라졌다. 해안 모험(2시간) 1회가 108,000,000
  XP 라 10회면 상한 990,000,000 에 닿는다 — **정상 플레이로 도달하는 지점**이고, 그 뒤로 모험은
  파트너에게 아무 의미가 없다. 이상한 사탕은 더 나빴다: 상점에서 5,000 별의조각에 파는 아이템이
  소모만 되고 아무 일도 일어나지 않았다(#82).
- **부류**: `min(cap, current + amount)` 는 **잘라낸 몫을 아무에게도 알리지 않는다.** 값을 넘긴
  호출부는 전액이 반영됐다고 믿고, 화면·대화·보상 객체가 전부 그 믿음 위에 세워진다. 클램프가
  "안전"해 보이는 게 함정이다 — 상한 위 저장을 막는 목적은 달성하면서, **초과분의 처분을 결정하지
  않은 채 조용히 버리는** 두 번째 동작이 딸려 온다. 상한을 두는 자리에서 물어야 하는 질문은 "얼마나
  잘라야 하나" 가 아니라 **"잘라낸 건 누구 것인가"** 다.
- **왜 테스트가 못 걸렀나**: #81 이 이 클램프에 붙인 테스트들은 전부 **저장값**만 봤다
  (`levelExperience == maxLevelExperience`). 클램프의 목적이 "상한 위 값을 저장하지 않는 것" 이었고
  테스트도 딱 그것만 검증했다 — 사라진 몫은 애초에 관찰 대상이 아니었다. 완전설명 불변식을 지키던
  `AdventureClaimTests` 의 두 테스트도 **만렙이 아니라서** 초과분이 항상 0 이었다(위 "부가 지급이
  실제로 일어나는 경로에서 검사해야" 와 같은 함정의 재발). 세 테스트 모두 결함 위에서 초록이었다.
- **처방 — 잘라낸 몫을 반환값으로 승격한다.** `gainExperience` 가 적립되지 못한 양을 반환하고,
  환산·지급·알림은 `CompanionStore.awardExperience` 한 곳에 모은다(`accrueTrainerPoints` 와 같은
  계약). **`@discardableResult` 를 붙이지 않는 것이 이 처방의 핵심이다** — 붙이면 새 호출부가 다시
  조용히 버릴 수 있고, 안 붙이면 그 자리가 컴파일러 경고가 되어 warning 0 게이트에 걸린다. 실제로
  구현 직후 기존 테스트 5곳이 경고로 떠서 전부 반환값을 검증하도록 강화됐다.
- **환율은 발명하지 말고 유도한다.** `AdventureRules.amounts` 가 이미 분당 120,000 XP 와 8 ⭐ 를
  주므로 존 배율이 약분돼 **모든 존·모든 길이에서 15,000 XP : 1 ⭐** 다. 그 절반(30,000)으로 환산해
  만렙 해안 1회를 7,200 → 10,800 으로 둔다(동등 환율은 정확히 2배가 되어 상한이 증산 장치가 된다).
  `testOverflowRateIsHalfTheRateAdventuresAlreadyPay` 가 그 유도 과정을 네 길이에서 다시 계산해,
  모험 계수를 재조정하면서 이 상수를 안 따라가면 걸리게 한다.
- **유도에 빠져 있던 두 번째 경로 — 사탕(리뷰에서 발견, 의도된 설계로 확정).** 위 유도는 모험만
  계산했는데, 환산은 `useRareCandy` 도 지난다. `RareCandy.dailyGrant = 1` · `RareCandy.xp =
  100,000,000` 이라 **만렙 파트너는 로그인만 해도 하루 3,333 ⭐** 를 번다. 이건 결함이 아니라 의도다 —
  만렙 이후 매일 들어오는 사탕이 아무 값도 못 하는 상태(#82 이전)를 되돌리는 게 환산의 목적이고,
  순환 루프도 없다(새 알 5,000 ⭐ > 하루 환급 3,333 ⭐ 라 사탕으로 알을 계속 뽑을 수 없다).
  **환율을 바꿀 때는 모험 경로만 보지 말고 이 일일 수입도 같이 본다** — 환율을 2배로 올리면
  만렙 계정의 기본 수입이 6,666 ⭐/일이 되어 알 가격을 넘긴다.
- **막는 것보다 환산이 안전했다.** 이슈는 "만렙이면 `canUseRareCandy` 에서 막자" 를 대안으로
  제시했는데, 사탕은 `usedAtStage` 도 미는 유일한 경로다 — 레벨 메타데이터가 없는 진화
  (`applyUsage` 의 `usedAtStage >= threshold` 분기)의 관문이 그것뿐이라, 막으면 그 개체의 진화
  경로가 영영 닫힌다. **"아무것도 안 하니 막자" 판단 전에 그 경로가 미는 축이 하나뿐인지 확인한다.**
- **첫 스윕이 놓친 자리 — 클램프만 보고 `if` 를 안 봤다(리뷰에서 발견).** 처분을 결정하지 않고
  값을 버리는 자리는 `min(...)` 만이 아니다. **호출 자체를 건너뛰는 `if` 도 같은 일을 한다** —
  `claimAdventure` 의 `if state.active != nil` 이 그것이었다. 모험 중에 알을 부화기에 넣으면
  파트너가 비는데(`beginIncubatingFocusEgg` 는 모험을 막지 않는다) 모험은 그대로 정산되므로,
  108,000,000 XP 가 통째로 사라지면서 `appliedExperience` 는 **전량 적립됐다고** 보고했다(대화
  도구가 그 값을 그대로 싣는다). 만렙 초과분을 고치면서 이 분기를 빠뜨린 이유는 스윕 대상을
  "클램프 표현식" 으로 좁혔기 때문이다 — **처분 결정을 건너뛰는 가드도 같은 부류로 센다.**
  처방은 `awardExperience` 를 무조건 지나게 하고(활성 개체가 없으면 전량을 초과분으로 처분),
  알림 문구("이미 다 자란 파트너")가 거짓이 되는 경우만 알림을 건너뛰는 것.
  회귀: `testAdventureWithoutAPartnerConvertsInsteadOfDroppingExperience`.
- **부류 스윕 — 같은 모양이 알 저장고에 있었다(리뷰에서 발견, 처분 확정).** 상한 999 를 쓰는 자리가
  5곳인데 넷은 `focusEggs` 만 클램프하고 `focusEggReadyDates` 는 **무조건** append 했다. 두 배열이
  어긋나면 `nextStoredEggHatchAt` 이 없는 알의 카운트다운을 그리고 `beginIncubatingFocusEgg` 의
  `removeFirst()` 짝이 밀린다 — 다음 기동의 `reconcileStoredEggDates()` 가 잘라 주므로 **세션 안에서만**
  틀리고, 그래서 재기동을 끼우는 테스트로는 안 잡혔다. 더 나쁜 건 `buyEgg` 로, `canBuyEgg` 에 상한
  검사가 없어 저장고가 꽉 차면 **별의조각만 차감되고 알은 0개** 늘었다(#82 는 지어낸 값이 사라졌지만
  여기선 실 재화다).
  처방은 **넣는 경로를 하나로 모으는 것** — `addStoredEggs(_:at:)` 가 클램프와 날짜 append 를 한 자리에서
  짝지어 하고, 실제로 들어간 개수를 돌려준다. `@discardableResult` 를 안 붙여 새 호출부가 잘린 몫을
  다시 버리면 `_ =` 로 눈에 띈다(`gainExperience` 와 같은 계약). `canBuyEgg` 에는 999 검사를 넣었다.
  회귀: `testBuyingAnEggWithFullStorageChargesNothing` · `testGymRewardAtFullEggStorageAddsNoHatchDate`
  (상한 검사 제거 + 날짜 무조건 append 주입으로 4개 단언이 빨개지는 것을 확인).
  **남은 판단** — `reward.bonusEggs` 는 여전히 *얻은* 값이라 저장고가 꽉 차면 대화·배너가 안 들어간
  알을 보고한다. 넘친 알의 처분(버림 · 조각 환산 · 정직 보고)은 미결이다.
- **범위 밖 결정도 테스트로 고정한다.** 트레이너 레벨(99) 초과 포인트는 환산하지 않는다 — 포인트가
  분 단위고 보상이 `500 × 레벨` 이라 경험치처럼 코드에서 유도되는 환율이 없고, 만렙 상태는 화면에
  이미 드러난다. `testTrainerPointsAtMaxLevelAreNotConverted` 가 그 결정을 붙잡는다. 이게 빨개지면
  회귀가 아니라 결정이 바뀐 것이다.
- 회귀: `testMaxLevelAdventureConvertsDiscardedExperienceIntoStardust` ·
  `testAdventureStraddlingTheCapSplitsBetweenExperienceAndStardust`(상한을 **걸치는** 정산 — 전부
  아니면 전무 구현을 거른다) · `testRareCandyAtMaxLevelPaysStardustInsteadOfNothing` ·
  `testOverflowRateIsHalfTheRateAdventuresAlreadyPay` · 대조군 3개(상한 아래 모험 · 상한 아래 사탕 ·
  트레이너). 환산을 죽이는 주입과 환율을 바꾸는 주입 두 가지로 각각 4개·6개가 빨개지는 것을 확인했고,
  새 분기는 `llvm-cov show --show-regions` 에서 `^0` 이 없다(유일한 `^0` 인 `awardExperience` 의 nil
  가드는 세 호출부가 이미 보장하는 도달 불가 방어라 사유를 주석으로 남겼다).
  (`CompanionModel.swift` · `CompanionStore.swift` · `AdventureModel.swift`, 2026-09-01.)

## 창 크기를 `contentRect` 로만 잡는 부류 (호스팅 컨트롤러가 그 값을 지운다)

- **증상.** 릴리스 노트 창이 본문을 서너 줄로 접은 채 떴다. 사용자 리포트로 발견했다.
- **직접원인.** `NSWindow(contentRect:)` 로 잡은 640×660 이 `contentViewController =
  NSHostingController(...)` 를 붙이는 순간 무효가 된다. AppKit 이 SwiftUI 호스팅 뷰의 fitting size 로
  창을 다시 재고, 그 값은 대개 `minSize` 까지 쪼그라든다(실측 480×400 = 선언한 minSize 그대로).
- **테스트·검증이 왜 못 걸렀나.** 실행 확인을 **"창이 떴는가"** 로만 했다. 버전 도장이 `present()`
  뒤에만 찍히는 걸 이용해 도장 변화로 창 생성을 확인했는데, 그 신호는 *존재*만 말하고 *치수*를
  말하지 않는다. 창이 뜨고 내용도 보이니 "동작한다" 로 읽혔다.
- **부류 스윕 — 같은 결함이 이미 배포돼 있었다.** `MemoryHomePresenter` 도 1040×720 을 선언하고
  `installContent(in:)` 로 호스팅 컨트롤러를 붙인다. 이 Mac 의 `NSWindow Frame MemoryHomeWindow`
  저장값이 `900 640` — 선언값이 아니라 minSize 다. 즉 Memory Home 은 줄곧 최소 크기로 열려 있었다.
  `FloatingPetPanel` 은 `contentView`(뷰) 를 넣고 프레임을 직접 잡아서 이 부류가 아니고,
  `NSPopover` 는 자체 `contentSize` 를 쓴다.
- **처방.** 크기는 컨트롤러를 붙인 **뒤에** `setContentSize(...)` 로 잡는다. `contentRect` 는 초기값일
  뿐이라 의도를 표현하지 못한다.
- **영구 캡처.** `WindowContentSizeGuardTests` — `NSWindow(contentRect:` 와
  `contentViewController = NSHostingController` 를 함께 쓰는 소스 파일은 `setContentSize(` 를 반드시
  호출해야 한다(주석 줄 제외 — 규칙을 설명하는 주석이 패턴을 담는다). 새 창을 세 번째로 추가할 때
  같은 함정을 다시 밟지 않게 한다. 측정 방법도 남긴다: `CGWindowListCopyWindowInfo` 로 실제 창
  치수를 읽거나, `defaults read <bundle-id> "NSWindow Frame <autosaveName>"` 를 본다.
- **곁가지.** 두 창 모두 `setFrameAutosaveName` 을 쓰지만 아무 데서도 `setFrameUsingName` 을 부르지
  않아 저장만 하고 복원하지 않는다. 릴리스 노트 창은 버전당 한 번뿐이라 이름을 지웠고, Memory Home 은
  기존 동작을 유지했다(저장값이 복원되지 않는 상태 그대로).
  (`ReleaseNotesPresenter.swift` · `MemoryHomePresenter.swift`, 2026-09-01.)

## 새 LAN 센터를 만들면서 `NSBonjourServices` 를 안 늘리면, 그 기능만 조용히 0건이 된다

- **증상.** 포켓몬 경매장에서 다른 트레이너의 출품이 하나도 안 보였다. 에러도 빈 상태 안내도 없이
  목록만 계속 비어 있었다. 사용자 리포트로 발견했다.
- **직접원인.** `PokemonAuctionCenter.serviceType` 은 `_kmonauct._tcp` 인데 `scripts/build-app.sh` 가
  굽는 Info.plist 의 `NSBonjourServices` 에는 앞선 네 개(`_ptbbattle`·`_kmonroom`·`_kmontrade`·
  `_kmonhome`)만 있었다. macOS 는 목록에 없는 서비스 타입의 브라우징·광고를 막는데, **거부가
  아니라 무결과**다 — 콜백이 빈 집합으로 정상 호출되므로 코드 어디에도 실패 신호가 남지 않는다.
- **테스트·검증이 왜 못 걸렀나.** 경매의 단위 테스트는 전부 프로세스 안의 상태 기계(제안 수락·거절·
  중복 결제 차단)를 봤다. 그 경로는 plist 를 한 번도 지나지 않으므로 통과해도 "탐색이 된다"는 말을
  전혀 하지 않는다. plist 는 소스가 아니라 **빌드 스크립트 안의 히어독**이라, 새 서비스 타입을
  선언해도 아무것도 깨지지 않는다.
- **부류 스윕.** 코드에 선언된 `serviceType` 은 다섯 개(배틀·방·교환·메모리홈·경매)이고 그중
  경매만 빠져 있었다. 나머지 넷은 모두 선언돼 있다.
- **영구 캡처.** `BonjourServiceDeclarationTests` — `Sources/` 를 훑어 `serviceType` 줄의
  `_*._tcp` 문자열을 모으고, 각각이 `build-app.sh` 의 `<string>…</string>` 로 있는지 대조한다.
  여섯 번째 LAN 센터를 만들 때 같은 함정을 다시 밟지 않게 한다.
- **곁가지.** 이 부류는 "기능은 다 만들었는데 그 기능만 아무 일도 안 일어난다"로 나타나므로
  디버깅이 오래 걸린다. LAN 기능을 추가할 때는 코드보다 **plist 를 먼저** 고치는 편이 낫다.
  (`PokemonAuction.swift` · `scripts/build-app.sh`, 2026-09-02.)

## `CompanionState` 에 필드를 더하고 **손글씨 디코더에 줄을 안 넣으면**, 저장은 되는데 로드에서 사라진다

- **증상.** 즐겨찾기를 켜고 앱을 껐다 켜면 풀려 있었다. CI 가 잡았다(`testFavoritePersistsAcrossRestart`).
- **직접원인.** `CompanionState` 는 **디코더만 손으로 쓰고 인코더는 합성**이다
  (`init(from:)` 이 `c.lenient(..., forKey: .필드)` 로 한 줄씩 읽는다 — 필드 하나가 깨져도 상태
  전체를 날리지 않으려는 부분 복원 설계). 새 필드 `favoriteMonIDs` 를 선언만 하면 합성 인코더가
  파일에 **쓰기는 쓰고**, 손글씨 디코더는 그 키를 **읽지 않아** 매 로드마다 기본값(빈 집합)이 된다.
- **테스트·검증이 왜 못 걸렀나.** 컴파일이 통과한다(기본값이 있으니 `init(from:)` 이 불완전해도
  에러가 아니다). 인코딩 왕복 테스트도 통과한다 — 기본값끼리 비교하면 같다. 즉 **비어 있을 때만
  맞는 검사**뿐이라, 값이 든 상태로 재시작하는 경로를 밟는 테스트가 없으면 드러나지 않는다.
- **부류 스윕.** 손글씨 디코더를 가진 타입은 `CompanionState` 하나다(나머지는 합성 Codable).
  같은 커밋에서 `testEveryCompanionStateFieldIsClassifiedForTransfer` 도 함께 빨개졌다 —
  그 가드는 "이 필드가 이전에서 무엇인가"를 묻지 "읽히기는 하는가"를 묻지 않는다. 둘은 다른 축이다.
- **영구 캡처.** `testEveryCompanionStateFieldIsReadByTheHandWrittenDecoder` — `Mirror` 로 뽑은
  저장 프로퍼티 이름이 전부 `CompanionModel.swift` 에 `forKey: .이름` 으로 등장하는지 대조한다
  (`forKey:` 는 그 파일에서 디코더만 쓴다). 새 필드를 더하는 다음 사람이 같은 함정을 밟지 않는다.
  (`CompanionModel.swift`, 2026-09-02.)

## 이미 있는 **커밋 프로토콜을 재사용하지 않고 새로 짜면**, 거기 있던 안전장치가 통째로 빠진다

- **증상.** 경매 교환이 실패하면 신청자의 포켓몬이 사라지고 게시자의 포켓몬은 남았다 — 없어진 개체를
  되돌릴 경로가 없다. 게시자가 두 제안을 연달아 수락하면 같은 개체가 두 트레이너에게 갔다.
  `main` 버그 감사(2026-09-02)로 발견했다.
- **직접원인.** 신청자가 수락 프레임을 받는 **즉시** 자기 개체를 먼저 넘기고, 게시자는 그 뒤에야
  자기 쪽을 처리했다. 게시자 쪽이 실패하면 `.failed` 만 보내고 되돌리지 않는다. `PokemonTrade` 는
  같은 문제를 두 단계 커밋(`.commit` → 넘김 → `.committed` → 넘김)과 국면 가드로 이미 풀어 뒀는데,
  경매는 그 프로토콜을 쓰지 않고 새로 짰다. 수락 중복 가드·추억 전달(`incomingMemories`)·연결 정리도
  같은 이유로 함께 빠졌다.
- **테스트·검증이 왜 못 걸렀나.** 경매 테스트는 제안 목록의 **상태 전이만** 봤다. 개체가 실제로 누구
  손에 있는지(`ownedMons`)를 보는 단언이 하나도 없어, 신청자가 개체를 먼저 넘기든 나중에 넘기든
  모든 단언이 똑같이 통과했다. 교환(`PokemonTrade`)에는 그 단언이 있었지만 **다른 타입**이라
  경매에는 아무것도 강제하지 않았다.
- **부류 스윕.** `performTrade` 를 부르는 자리는 교환과 경매 둘뿐이고, 경매만 이 순서였다.
  판정 조건이 두 벌로 갈리는 것을 막으려고 `CompanionStore.canPerformTrade` 를 정본으로 두고
  `performTrade` 가 그것을 쓴다 — 두 단계 커밋은 개체가 움직이기 전에 같은 판정을 미리 물어야 한다.
- **영구 캡처.** `AuctionCommitTests`(swift-testing, `scripts/test-local.sh` 로 로컬 실행) — 커밋
  순서·이중 수락·연결당 제안 하나·광고값 대조·추억 전달을 **소유권 기준으로** 본다. 순서를 옛날로
  되돌리는 결함을 일부러 주입해 실제로 빨개지는 것을 확인했다.
- **곁가지.** 같은 종류의 두 번째 기능을 만들 때는 프로토콜을 새로 짜지 말고 첫 번째 것을 부른다.
  프로토콜의 안전장치는 대개 주석이 아니라 **가드 한 줄**로 들어 있어서, 새로 짜는 사람은 그것이
  거기 있었다는 사실 자체를 모른다. (`PokemonAuction.swift`, 2026-09-02.)

## 저장 실패를 `try?` 로 덮으면, 사라진 진행에 **아무 단서도 남지 않는다**

- **증상.** 잠재 결함으로 발견했다(2026-09-02 감사). `CompanionStore.save()` 는 encode 와 write 를
  둘 다 `try?` 로 덮고 로그도 남기지 않았다. 거의 모든 상태 변경 뒤에 불리는 유일한 영속화
  경로라, 디스크가 차거나 권한이 막히면 사용자는 앱을 계속 쓰다가 **다음 기동에서** 진행이
  통째로 사라진 것을 본다. 그 시점에는 원인을 가릴 단서가 하나도 없다.
- **직접원인.** 실패를 값으로도 로그로도 남기지 않는 형태. 같은 파일의 `loadRogueRun()` 은 실패를
  적는데 짝인 `persistRogueRun()` 만 적지 않는 **형제 비대칭**도 함께 있었다.
- **테스트·검증이 왜 못 걸렀나.** 테스트는 전부 쓸 수 있는 임시 디렉터리를 쓴다. 쓰기가 실패하는
  경우를 **한 번도 만들지 않으므로** 그 분기는 실행되지 않고, 커버리지도 `save()` 를 초록으로
  칠한다(성공 경로가 그 줄을 지난다).
- **부류 스윕.** 사용자 데이터를 적는 경로 셋이 같은 모양이었다 — 세이브(`CompanionStore.save`),
  추억 앨범, 대화 기록. 캐시(스프라이트·PokéAPI 인덱스)는 대상이 아니다: 다시 받으면 그만이라
  실패를 알릴 것이 없다. 판단 기준은 "실패했을 때 **다시 만들 수 없는 값**인가" 다.
- **영구 캡처.** `SaveFailureTests` — 세이브 파일 자리에 디렉터리를 앉혀 쓰기를 실제로 실패시키고,
  화면이 읽는 `saveFailed` 가 서는지 본다(성공 경로에서는 서지 않는지도 함께 본다. 그러지 않으면
  경고가 상시 표시가 돼 아무 의미가 없다). 홈 헤더가 그 값을 읽어 경고를 띄운다.
- **곁가지.** 실패 로그는 **전이할 때만** 적는다. 상태가 바뀔 때마다 불리는 경로라 매번 적으면
  실패가 이어지는 동안 로그가 밀려 원인 줄이 먼저 밀려난다.
  (`CompanionStore.swift` · `PokemonChat.swift` · `CompanionView.swift`, 2026-09-02.)

## `await` 를 지나 깨어난 작업이 **방이 아직 그 방인지** 안 보면, 닫은 방이 LAN 에 남는다

- **증상.** 잠재 결함으로 발견했다(2026-09-02 감사). 방을 만드는 동안 나가기를 누르면
  `leaveRoom()` 이 listener 를 끄고 국면을 `.idle` 로 되돌리는데, 그 뒤에 깨어난 개설 작업이
  새 listener 를 세워 다시 광고한다. 사용자는 닫았다고 믿는 방이 LAN 에 남고, 그 다음부터는
  개설·참가가 전부 `guard phase == .idle` 에서 **조용히** 거절된다.
- **직접원인.** 네 진입점(솔로 퀴즈·솔로 포켓슬론·방 개설·참가)이 `phase` 를 먼저 바꾸고
  `Task { await … }` 안에서 마무리하는데, 깨어난 뒤 국면을 다시 보지 않았다. 나가기 버튼은
  `.creating` 중에도 눌리고, 체육관 타이머(`PlayerGymCoordinator`)는 조작 없이도 `leaveRoom()` 을
  부른다.
- **테스트·검증이 왜 못 걸렀나.** 테스트는 각 진입점을 **끝까지** 돌린다. 중간에 나가는 순서를
  한 번도 만들지 않으므로 그 인터리빙은 존재하지 않는 것과 같다. 단일 스레드(MainActor)라
  자료 경합은 없고, 결함은 순서 문제라 어떤 경합 검사기에도 안 걸린다.
- **부류 스윕.** 같은 모양이 방 센터에 일곱 자리 있었다(위 넷 + 퀴즈 준비·토너먼트 팀 제출·
  체육관 도전/판 시작). 국면 비교가 아니라 **수명 번호**(`sessionEpoch`, `leaveRoom()` 이 올린다)로
  본다 — 나갔다가 곧바로 다시 개설하면 국면이 같은 값으로 돌아와 옛 작업이 새 작업을 덮어쓴다.
- **영구 캡처.** `RoomSessionEpochTests` — 개설 중에 나가고, 뒤늦게 깨어난 작업이 화면에
  오류·국면을 쓰지 않는지 본다. 나가지 않은 경우에는 실패가 **그대로 보고되는지**도 함께 본다
  (가드가 정상 경로까지 막으면 개설이 영영 안 끝난다). 가드를 지운 상태로 실제로 빨개지는 것을
  확인했다.
- **곁가지.** 진입점을 새로 만들 때 `await` 앞뒤로 국면을 바꾼다면 수명 번호를 함께 잡는다.
  (`MultiplayerRoomCenter.swift`, 2026-09-02.)

## 형제 타입 하나만 디코딩 클램프를 가지면, 나머지는 **같은 프레임으로 들어와** 죽는다

- **증상.** 잠재 결함으로 발견했다(2026-09-02 감사). 호스트가 보낸 경기 상태(`PokeathlonRace`)에
  `teamSpeciesIDs` 보다 짧은 `stamina` 가 실려 오면, 게스트 화면이 팀 인덱스로 그 배열을 읽는
  순간 인덱스 범위 밖 접근으로 죽는다(`PokeathlonView` 의 스태미나 막대). 음수 `activeTeamIndex`
  는 `activeSpeciesID` 의 첨자로 그대로 들어간다.
- **직접원인.** 같은 방에서 오가는 값인데 `PokeathlonPool`·`PokeathlonBet` 만 디코딩 경계 클램프를
  갖고 있었다. 베팅 원장은 오버플로 사고를 겪어 클램프가 붙었고, **그때 형제 타입을 함께 보지
  않았다.**
- **테스트·검증이 왜 못 걸렀나.** 경기 테스트는 전부 `PokeathlonRace(racers:)` 로 값을 **코드에서**
  만든다. 그 생성자는 항상 정합한 값을 만들므로 와이어에서 오는 조합(길이 불일치·음수)이
  존재하지 않는다. JSON 을 통과시키는 테스트가 하나도 없었다.
- **부류 스윕.** 방에서 오가는 Codable 중 클램프가 있는 것은 `PokeathlonPool`·`PokeathlonBet`
  (이번에 `PokeathlonRacer`·`PokeathlonRace` 추가), 없는 것은 `BattleSnapshot` 이다 —
  **미완 스윕**: 스냅샷의 수치가 첨자로 쓰이는 자리가 있는지 아직 확인하지 않았다. 종 번호
  자르기는 `PokemonAssets.clampedID` 를 정본으로 쓴다.
- **영구 캡처.** `PokeathlonDecodingTests` — 길이 불일치·음수 인덱스·범위 밖 값·트랙에 없는
  우승자를 **JSON 으로** 넣어 자르는지 보고, 정상 경기는 왕복해도 그대로인지 함께 본다.
- **곁가지.** 신뢰경계 클램프를 하나 붙일 때는 "같은 프레임에 실려 오는 형제 타입"을 함께 본다.
  공격자는 클램프가 붙은 필드를 피해 옆 필드를 보낸다. (`MultiplayerBattle.swift`, 2026-09-02.)
