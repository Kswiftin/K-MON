---
summary: "결함 대응 프로토콜로 축적된 구체 규칙 — 한 번 겪은 부류의 실수를 다시 겪지 않기 위한 원장."
read_when:
  - 결함·회귀·공백을 고치는 중 (프로토콜 4단계의 '부류 스윕'·'영구 캡처' 근거)
  - 동시성/await·옵셔널 판정·캐시 무효화·외부 로그 포맷을 건드릴 때
  - 메뉴바·플로팅 펫 등 상시 표시 애니메이션의 성능을 손볼 때
  - 세이브 이전/병합·외부 파일 입력 경로를 만들 때
  - 외부 API(PokéAPI 등) DTO 에서 조건 필드를 새로 읽기 시작할 때
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
  `contains` 한 줄" 은 곱·합으로 결합되는 축에서는 검증이 아니다.
- **처방**: 결합값에 직접 상한을 건다(`power * (maxHits ?? 1) <= 250`), 상한 숫자는 **도감 최대치**를
  근거로 적는다(도감 다단기 총합 최대 100, 흡수 최대 75 = 드레인키스). 가드는 축 하나만 극단으로
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
  가드는 "확률이 접혔다" 가 아니라 **행동 기회가 남는다**를 단언한다
  (`BattlePhase5Tests.testAHundredPercentFlinchMoveCannotLockTheOpponentOutOfTheBattle`).
  (`MoveSpec.flinchPercent`, 2026-08-25.)

## 값 하나를 두 게이트가 각자 판정하면 "같은 기준" 이라는 주석만 남는다

- 도감 위력이 0 인 공격기(일렉트릭볼·지구던지기·자이로볼 …)를 `VariableDamage` 로 살렸는데,
  자동 무브셋(`pickFour`)은 `power > 0` 으로 갈라 그 부류를 **공격기 칸에도 변화기 칸에도** 못
  넣었다. 사용자 습득 경로(`canonicalLevelUpMoves`·하트비늘)는 `isUsable` 을 봐서 통과시켰다 —
  "같은 기준을 쓴다" 는 주석이 두 함수에 붙어 있는데 실제로는 기술 한 부류를 두고 갈라져 있었다.
  기전을 만든 커밋이 소비자 하나만 고친 부류다(`VariableDamage` 는 살렸고 `pickFour` 는 안 봤다).
- **부류**: 한 판정을 두 곳이 **각자 표현**하면(한쪽은 `power > 0`, 한쪽은 `damageClass`) 주석이
  동기화를 대신하지 못한다. 새 기전이 어떤 값의 의미를 바꿨으면(위력 0 = 변화기 → 공격기일 수도)
  **그 값을 읽는 전 지점을 grep** 한다. `power > 0` 은 "공격기냐" 와 같은 뜻이 아니다.
- **처방**: 판정을 함수 하나로 올리고(`VariableDamage.dealsDamage` 가 `isUsable` 을 **재사용**한다)
  갈라질 자리를 없앤다. 가드는 새 부류 **단독** 풀을 쓴다 — 위력 있는 공격기를 같이 넣으면 옛
  분할에서도 초록이라 아무것도 지키지 않는다
  (`BattleStageTests.testPickFourSelectsVariablePowerAttacks`).
  (`PokeAPIClient.pickFour`, 2026-08-25.)

## 축을 새로 만들면 그 축이 **정의**인 항목을 먼저 확인한다

- 반동 축(`drain` 음수)을 만들고 도감 기술은 `meta.drain` 으로 다 채웠는데, 반동이 정의인 유일한
  합성 기술 발버둥은 `drain` 이 `nil` 로 남았다. `moveDetail` 이 채워 줄 수 없는 스펙이라
  (`id` 가 음수 → `needsDetailRefresh` 가 조기반환) 수렴 경로가 아예 없다. 결과는 대가 없는
  위력 50 무상성기 — PP 가 마른 쪽이 오히려 유리해진다.
- **부류**: 새 축은 **외부에서 오는 값**만 챙기고 앱이 직접 합성하는 값(`struggle`·`fallbackSet`)을
  빠뜨린다. 기존 테스트는 축을 직접 박은 스펙으로 통과하므로 그 구멍이 초록으로 덮인다.
- **처방**: 축을 더하면 그 축을 쓰는 합성 스펙을 grep 하고(`MoveSpec.struggle`·`fallbackSet`),
  가드는 합성 스펙을 **그대로** 엔진에 넣어 값을 단언한다
  (`BattlePhase5Tests.testStruggleCostsTheUserAQuarterOfTheDamageDealt`).
  (`MoveSpec.struggle`, 2026-08-25.)
