import Foundation

/// 앱 전체 UI 문자열. 뷰는 `companion.l.<key>` 로 접근한다.
///
/// **한국어 하나만 둔다**(2026-09-07 결정). 예전엔 `ko` 로 세 언어를 한자리에서
/// 골랐지만, 다국어를 걷어내면서 화면 문자열은 한국어 리터럴로 내려앉았다. 포켓몬·기술 이름은
/// 여전히 PokéAPI 다국어 데이터에서 오고, 그쪽에서 한국어를 고르는 규칙은 `PokemonNaming` 이다.
struct L {

    // MARK: 첫 화면

    /// 스타터를 고르기 전 화면의 첫 줄. **무슨 앱인지 먼저 말한다** — 예전엔 트레이너 이름
    /// 입력칸부터 나와서, 처음 연 사람은 이게 집중 타이머인지 포켓몬 게임인지 왜 이름을 묻는지
    /// 알 수 없었다.
    var onboardingHeadline: String {
        "집중하면 포켓몬이 자라요"
    }

    /// 그 다음 줄 — 지금 할 일 하나를 말한다. 화면에 남겨 둔 것도 그 하나뿐이다.
    var onboardingSubhead: String {
        "이름을 정하고 함께 시작할 타입을 고르세요."
    }

    /// 경험치 단위. 보상 미리보기 줄이 `EXP` 를 그대로 박아 두어 줄 하나에 영어와 한국어가
    /// 섞여 있었다.
    var experienceUnit: String { "경험치" }

    /// 한 화면씩 넘기는 셰브론의 이름. 진화 라인과 도감 카드가 함께 쓴다.
    var previousPage: String { "이전" }
    var nextPage: String { "다음" }

    /// 확인까지 누른 구매가 거절됐을 때. 잔액 부족 안내와 **다른 말**이어야 한다 — 눌러서 거절된
    /// 것과 애초에 못 누르는 것은 사용자가 할 일이 다르다.
    var purchaseFailed: String {
        "구매하지 못했어요. 잔액을 확인하고 다시 시도해 주세요."
    }

    /// 트레이너 바의 `NEXT 320p` 가 무슨 단위인지 푼다.
    func trainerNextLevelHint(_ points: Int) -> String {
        "다음 트레이너 레벨까지 \(points) 포인트"
    }

    /// 트레이너 바 오른쪽 숫자가 무엇인지 푼다 — 재화 이름은 앱 전체와 같은 것을 쓴다.
    var starPieceBalanceHint: String {
        "보유 별의조각"
    }

    // MARK: 탭
    var home: String { "홈" }
    /// 최상위 탭 라벨. **하위 세그먼트(도감 | 업적)의 상위어여야 한다** — "도감" 이던 때는 도감 탭
    /// 안에 다시 "도감" 세그먼트가 보였다. 도감 쪽은 `dexTitle` 을 쓴다.
    /// 이름을 늘려도 상단 피커 폭은 그대로다 — 다섯 라벨 합계 330pt 로 콘텐츠 폭 332pt 안에
    /// 들어간다(한국어 전용 전환 전 계측값이며, en·ja 라벨을 걷어냈으므로 여유는 그때보다 늘었다).
    /// 넘기면 macOS 가 라벨을 압축한다 — **더 늘리지 않는다**.
    var collection: String { "컬렉션" }
    var battle: String { "배틀" }

    // MARK: 배틀
    var battleMyPokemon: String { "내 포켓몬" }
    /// 알을 품는 중이어도 박스에 개체가 있으면 배틀할 수 있다 — 이 문구는 **한 마리도 없을 때**만 뜬다.
    var battleNeedHatch: String {
        "배틀에 내보낼 포켓몬이 없어요 — 알을 먼저 부화시키세요."
    }
    var battleStatsFailed: String { "스탯을 불러오지 못했어요 — 네트워크 확인 후 다시 시도하세요." }
    var battleDraw: String { "무승부!" }
    var battleSpectatorFinished: String { "관전한 배틀이 끝났어요." }
    var battleSuperEffective: String { "효과가 굉장했다!" }
    var battleNotVeryEffective: String { "효과가 별로인 듯하다…" }
    var battleCritical: String { "급소에 맞았다!" }
    /// 재생 속도 설정 — 끄기는 저전력·접근성 때문에 반드시 고를 수 있어야 한다.
    var battleReplaySpeedLabel: String { "배틀 연출" }
    func battleReplaySpeedName(_ speed: ReplaySpeed) -> String {
        switch speed {
        case .normal: return "보통"
        case .fast:   return "빠름"
        case .off:    return "끄기"
        }
    }
    func battleLv(_ n: Int) -> String { "Lv.\(n)" }
    func battleTrainerLabel(_ trainer: String) -> String {
        "\(trainer)의 포켓몬"
    }

    // MARK: 배틀 (네트워크 대전)
    var battleNearby: String { "근처의 트레이너" }
    var battleNoPeers: String {
        "같은 네트워크에서 대전 상대를 찾는 중… 친구도 앱을 켜야 보여요."
    }
    var battleChallengeButton: String { "대결 신청" }
    /// 구버전 상대는 랭크를 광고하지 않는다. 최하위 티어와 구별돼야 하므로 빈칸이 아니라 문구다.
    var battleRankUnknown: String { "랭크 정보 없음" }
    var battleWaitingAccept: String { "수락 대기 중…" }
    var battleCancel: String { "취소" }
    var battleIncomingTitle: String { "배틀 신청이 왔습니다!" }
    var battleAccept: String { "수락" }
    var battleDecline: String { "거절" }
    var battleRulesMismatch: String {
        "상대와 앱 버전이 달라 대전할 수 없어요 — 양쪽 다 업데이트해 주세요."
    }
    var battleDeclined: String { "상대가 거절했어요." }
    var battleConnectionLost: String { "연결이 끊어졌어요." }
    var battleChallengeTimedOut: String { "신청 시간이 초과됐어요." }
    func battleChallengeTimeRemaining(_ seconds: Int) -> String {
        "수락까지 \(seconds)초"
    }
    func menuBarBattleChallengeSent(_ peer: String) -> String { "\(peer) 응답 대기" }
    func menuBarBattleChallengeReceived(_ peer: String) -> String { "\(peer) 수락 대기" }
    func menuBarBattling(_ peer: String, isMyTurn: Bool) -> String {
        let koTurn = isMyTurn ? "내 턴" : "상대 턴"
        return "\(peer)와 대결 중 · \(koTurn)"
    }
    /// 랭크전 판돈을 못 낼 때 — 세 경로(수신 수락·수락 응답·개시 에스크로)가 같은 문구를 쓴다.
    var battleStakeShort: String {
        "랭크전 판돈이 부족해요."
    }
    func battleNeedsPokemon(_ count: Int) -> String {
        "\(count) vs \(count) 대결에는 포켓몬이 \(count)마리 필요해요."
    }
    var battleYourTurn: String { "기술 또는 교체를 선택하세요" }
    var battleWaitingOpponent: String { "상대가 행동을 고르는 중…" }
    var battleForfeit: String { "기권" }
    var battleChatTitle: String { "채팅" }
    var battleChatPlaceholder: String { "메시지 입력" }
    var battleChatSend: String { "전송" }
    var battleChatUnavailable: String {
        "상대 앱 버전에서는 채팅을 지원하지 않습니다."
    }
    func battleChatNewMessages(_ count: Int) -> String {
        "새 메시지 \(count)개"
    }
    var battleSwitch: String { "교체" }
    var battleMissed: String { "빗나갔다!" }
    var battleNoEffect: String { "효과가 없었다…" }
    /// 방어에 막힌 순간의 팝 — 이름이 없다(누가 막았는지는 같은 순간의 로그 줄이 말한다).
    var battleGuardBlockedPopup: String { "막혔다!" }
    var battleOppForfeited: String { "상대가 기권했어요 — 승리!" }
    var battleYouForfeited: String { "기권했어요." }
    var battleWon: String { "이겼다! 🏆" }
    var battleLost: String { "졌다…" }
    var battleClose: String { "확인" }
    var battleManualHint: String {
        "자동 탐색이 안 되면(사내망 등) 주소로 직접 연결하세요."
    }
    /// 방 배틀 화면에는 주소 입력칸이 없다 — `battleManualHint` 를 쓰면 여기서 할 수 없는
    /// 일을 시키게 되므로, 주소 연결이 있는 화면을 가리킨다.
    var roomBattleDiscoveryBlocked: String {
        "자동 탐색이 안 되면(사내망 등) 1:1 배틀 화면에서 주소로 연결하세요."
    }
    var battleMyAddress: String { "내 주소" }
    var battleManualPlaceholder: String { "상대 주소 (예: 10.1.2.3:50628)" }
    var battleBadAddress: String { "주소 형식이 잘못됐어요 — IP:포트" }
    var battleKindBrawl: String { "맞짱" }
    var battleAutoAccept: String { "신청 자동 수락" }
    var battleDiscoveryBlocked: String {
        "자동 탐색이 막혀 있어요 — 시스템 설정 > 개인정보 보호 > 로컬 네트워크에서 허용하거나, 아래 주소로 직접 연결하세요."
    }
    func battleTurnLabel(_ n: Int) -> String { "턴 \(n)" }
    func battleIncomingFrom(_ trainer: String) -> String {
        "\(trainer)님이 대결을 신청했어요!"
    }
    var battleChallengeNotifTitle: String { "배틀 신청이 왔습니다!" }
    func battleChallengeNotifBody(_ trainer: String, pokemon: String, level: Int) -> String {
        "\(trainer) — \(pokemon) Lv.\(level) · 메뉴바에서 수락하세요"
    }
    func battleUsedMoveNamed(_ attacker: String, move: String, damage: Int) -> String {
        "\(attacker)의 \(move)! \(damage) 데미지"
    }
    func battleUsedMoveMissed(_ attacker: String, move: String) -> String {
        "\(attacker)의 \(move)!"
    }
    /// 기술과 무관하게 깎였을 때 — 상태이상 잔뎀(Phase 2)이 이 문구로 온다.
    func battleTookDamage(_ name: String, damage: Int) -> String {
        "\(name)은(는) \(damage) 데미지"
    }
    func battleFainted(_ name: String) -> String {
        "\(name)은(는) 쓰러졌다!"
    }

    // MARK: 배틀 (상태이상)

    func battleStatusInflicted(_ name: String, status: Status) -> String {
        switch status {
        case .burn:      return "\(name)은(는) 화상을 입었다!"
        case .poison:    return "\(name)은(는) 독에 걸렸다!"
        case .toxic:     return "\(name)은(는) 맹독에 걸렸다!"
        case .paralysis: return "\(name)은(는) 마비되어 기술이 나오기 어려워졌다!"
        case .sleep:     return "\(name)은(는) 잠들어 버렸다!"
        case .freeze:    return "\(name)은(는) 얼어붙었다!"
        case .confusion: return "\(name)은(는) 혼란에 빠졌다!"
        case .flinch:    return "\(name)은(는) 풀죽었다!"
        }
    }

    func battleStatusCured(_ name: String, status: Status) -> String {
        switch status {
        case .burn:            return "\(name)의 화상이 나았다!"
        case .poison, .toxic:  return "\(name)의 독이 나았다!"
        case .paralysis:       return "\(name)의 마비가 풀렸다!"
        case .sleep:           return "\(name)은(는) 잠에서 깨어났다!"
        case .freeze:          return "\(name)의 얼음이 녹았다!"
        case .confusion:       return "\(name)의 혼란이 풀렸다!"
        // 풀죽음은 주 상태가 아니라 `.cureStatus` 가 나올 일이 없다. 그래도 빈 문자열은 안 둔다 —
        // 빈 줄이 로그로 나가는 걸 막으려고 이 switch 를 다 채운다(위 주석).
        case .flinch:          return "\(name)의 풀죽음이 풀렸다!"
        }
    }

    /// 그 상태 때문에 이번 턴을 못 썼다. 화상·독은 행동을 막지 않아 마지막 분기가 나올 일은 없지만,
    /// 비워 두면 나중에 상태를 더할 때 조용히 빈 줄이 로그로 나간다.
    func battleCantMove(_ name: String, status: Status) -> String {
        switch status {
        case .paralysis: return "\(name)은(는) 몸이 저려서 움직일 수 없다!"
        case .sleep:     return "\(name)은(는) 쿨쿨 잠들어 있다."
        case .freeze:    return "\(name)은(는) 얼어붙어서 움직일 수 없다!"
        case .confusion: return "\(name)은(는) 혼란에 빠져 자신을 공격했다!"
        case .flinch:    return "\(name)은(는) 풀죽어서 움직일 수 없다!"
        case .burn, .poison, .toxic:
            return "\(name)은(는) 움직일 수 없다!"
        }
    }

    /// 기술이 아닌 데미지 — 원인을 말하지 않으면 로그가 "무엇에 맞았는지" 를 잃는다.
    func battleStatusDamage(_ name: String, damage: Int, cause: DamageCause) -> String {
        switch cause {
        case .burn:      return "\(name)은(는) 화상 데미지! \(damage)"
        case .poison:    return "\(name)은(는) 독 데미지! \(damage)"
        case .toxic:     return "\(name)은(는) 맹독 데미지! \(damage)"
        case .confusion: return "\(name)은(는) 혼란으로 \(damage) 데미지"
        case .weather:   return "\(name)은(는) 날씨 데미지! \(damage)"
        case .move:      return battleTookDamage(name, damage: damage)
        case .recoil:    return t("\(name)은(는) 반동으로 \(damage) 데미지",
                                  "\(name) was hurt by recoil! \(damage)",
                                  "\(name)は 反動で \(damage)ダメージ")
        case .trap:      return t("\(name)은(는) 조이기 데미지! \(damage)",
                                  "\(name) is hurt by the bind! \(damage)",
                                  "\(name)は しめつけの ダメージ！ \(damage)")
        case .curse:     return t("\(name)은(는) 저주 데미지! \(damage)",
                                  "\(name) is afflicted by the curse! \(damage)",
                                  "\(name)は のろいの ダメージ！ \(damage)")
        case .leechSeed: return t("\(name)은(는) 씨뿌리기에 체력을 빨렸다! \(damage)",
                                  "\(name)'s health is sapped by Leech Seed! \(damage)",
                                  "\(name)は やどりぎに たいりょくを すいとられた！ \(damage)")
        case .nightmare: return t("\(name)은(는) 악몽에 시달렸다! \(damage)",
                                  "\(name) is locked in a nightmare! \(damage)",
                                  "\(name)は あくむに くるしんでいる！ \(damage)")
        case .hazard:    return t("\(name)은(는) 발밑에 깔린 것을 밟았다! \(damage)",
                                  "\(name) was hurt by what was laid on the ground! \(damage)",
                                  "\(name)は あしもとの しかけで ダメージ！ \(damage)")
        }
    }

    /// 개체에 붙은 상태가 붙었다 / 풀렸다. 진영 상태와 달리 이름이 들어간다 — 누구에게 붙은
    /// 조이기인지가 문구의 절반이고, 필드에 개체가 넷인 모드(방·웨이브)에선 그것 없이는 안 읽힌다.
    func battleVolatileStarted(_ name: String, _ volatileStatus: BattleVolatile) -> String {
        switch volatileStatus {
        case .aquaRing:         return t("\(name)은(는) 물의베일을 둘렀다!",
                                         "\(name) surrounded itself with a veil of water!",
                                         "\(name)は みずの ベールを まとった！")
        case .ingrain:          return t("\(name)은(는) 뿌리를 내렸다!", "\(name) planted its roots!",
                                         "\(name)は ねを はった！")
        case .leechSeed:        return t("\(name)에게 씨가 박혔다!", "\(name) was seeded!",
                                         "\(name)に やどりぎが うえつけられた！")
        case .nightmare:        return t("\(name)은(는) 악몽을 꾸기 시작했다!",
                                         "\(name) began having a nightmare!",
                                         "\(name)は あくむを みはじめた！")
        case .curse:            return t("\(name)은(는) 저주에 걸렸다!", "\(name) was cursed!",
                                         "\(name)は のろわれた！")
        case .partiallyTrapped: return t("\(name)은(는) 조여졌다!", "\(name) was squeezed!",
                                         "\(name)は しめつけられた！")
        case .focusEnergy:      return t("\(name)은(는) 기합이 충전됐다!", "\(name) is getting pumped!",
                                         "\(name)は きあいを ためている！")
        case .laserFocus:       return t("\(name)은(는) 집중하기 시작했다!",
                                         "\(name) began concentrating intensely!",
                                         "\(name)は しゅうちゅうし はじめた！")
        case .minimize:         return t("\(name)은(는) 작아졌다!", "\(name) minimized!",
                                         "\(name)は ちいさくなった！")
        case .defenseCurl:      return t("\(name)은(는) 몸을 웅크렸다!", "\(name) curled up!",
                                         "\(name)は まるくなった！")
        case .charge:           return t("\(name)은(는) 전기를 모았다!", "\(name) began charging power!",
                                         "\(name)は でんきを ためた！")
        case .endure:           return t("\(name)은(는) 공격에 대비했다!", "\(name) braced itself!",
                                         "\(name)は こうげきに そなえた！")
        case .destinyBond:      return t("\(name)은(는) 상대를 길동무로 정했다!",
                                         "\(name) is trying to take its foe down with it!",
                                         "\(name)は あいてを みちづれに しようとしている！")
        case .grudge:           return t("\(name)은(는) 원한을 품었다!",
                                         "\(name) wants its foe to bear a grudge!",
                                         "\(name)は うらみを こめている！")
        case .substitute:       return t("\(name)은(는) 대타를 내세웠다!",
                                         "\(name) put up a substitute!",
                                         "\(name)は みがわりを だした！")
        }
    }

    /// 붙어 있던 상태가 **일한** 줄 — 버텼다 / 길동무로 데려갔다 / PP 를 앗았다.
    ///
    /// 셋 말고는 이 줄이 나가지 않는다(붙는 순간이나 턴 끝에만 일한다). 그래도 나머지를 한 자리에
    /// 모아 **붙는 줄**로 되돌려 두는 이유는, 나중에 일하는 상태가 하나 늘었을 때 로그가 조용히
    /// 비는 것보다 상태 이름이라도 나오는 편이 낫기 때문이다(컴파일러가 분류를 강제한다).
    func battleVolatileTriggered(_ name: String, _ volatileStatus: BattleVolatile) -> String {
        switch volatileStatus {
        case .endure:      return t("\(name)은(는) 공격을 버텼다!", "\(name) endured the hit!",
                                    "\(name)は こうげきを もちこたえた！")
        case .destinyBond: return t("\(name)은(는) 상대를 길동무로 데려갔다!",
                                    "\(name) took its attacker down with it!",
                                    "\(name)は あいてを みちづれに した！")
        case .grudge:      return t("\(name)의 원한이 상대 기술의 PP 를 앗았다!",
                                    "\(name)'s grudge drained the PP of the move that felled it!",
                                    "\(name)の うらみが わざの PPを うばった！")
        case .substitute:  return t("\(name) 대신 대타가 맞았다!",
                                    "The substitute took the hit for \(name)!",
                                    "\(name)の みがわりが ダメージを うけた！")
        case .aquaRing, .ingrain, .leechSeed, .nightmare, .curse, .partiallyTrapped,
             .focusEnergy, .laserFocus, .minimize, .defenseCurl, .charge:
            return battleVolatileStarted(name, volatileStatus)
        }
    }

    /// 지니고 있던 물건이 일한 줄 — **무엇으로** 버텼는지가 문구의 절반이다(인내와 구별된다).
    /// 지금 이 줄을 내는 것은 기합의띠뿐이고, 나머지 둘은 자기 줄이 이미 있다(회복·반동 데미지).
    func battleHeldItemTriggered(_ name: String, item: ItemKind) -> String {
        let itemName = self.itemName(item)
        return t("\(name)은(는) \(itemName)으로 버텼다!",
                 "\(name) hung on with its \(itemName)!",
                 "\(name)は \(itemName)で もちこたえた！")
    }

    func battleVolatileEnded(_ name: String, _ volatileStatus: BattleVolatile) -> String {
        switch volatileStatus {
        case .aquaRing:         return t("\(name)의 물의베일이 사라졌다", "\(name)'s veil of water faded",
                                         "\(name)の みずの ベールが きえた")
        case .ingrain:          return t("\(name)의 뿌리가 사라졌다", "\(name)'s roots withered",
                                         "\(name)の ねが きえた")
        case .leechSeed:        return t("\(name)의 씨가 사라졌다", "\(name)'s Leech Seed withered",
                                         "\(name)の やどりぎが きえた")
        case .nightmare:        return t("\(name)은(는) 악몽에서 깨어났다", "\(name) woke from its nightmare",
                                         "\(name)は あくむから めざめた")
        case .curse:            return t("\(name)의 저주가 풀렸다", "\(name)'s curse lifted",
                                         "\(name)の のろいが とけた")
        case .partiallyTrapped: return t("\(name)은(는) 조이기에서 벗어났다", "\(name) was freed from the bind",
                                         "\(name)は しめつけから ぬけだした")
        case .focusEnergy:      return t("\(name)의 기합이 풀렸다", "\(name) is no longer pumped",
                                         "\(name)の きあいが とけた")
        case .laserFocus:       return t("\(name)의 집중이 풀렸다", "\(name) is no longer concentrating",
                                         "\(name)の しゅうちゅうが とけた")
        case .minimize:         return t("\(name)은(는) 원래 크기로 돌아왔다", "\(name) is no longer minimized",
                                         "\(name)は もとの おおきさに もどった")
        case .defenseCurl:      return t("\(name)은(는) 몸을 풀었다", "\(name) uncurled",
                                         "\(name)は まるまりを といた")
        case .charge:           return t("\(name)의 전기가 흩어졌다", "\(name)'s charge faded",
                                         "\(name)の でんきが きえた")
        case .endure:           return t("\(name)의 대비가 풀렸다", "\(name) is no longer braced",
                                         "\(name)の そなえが とけた")
        case .destinyBond:      return t("\(name)의 길동무가 풀렸다", "\(name)'s Destiny Bond faded",
                                         "\(name)の みちづれが とけた")
        case .grudge:           return t("\(name)의 원한이 풀렸다", "\(name)'s grudge faded",
                                         "\(name)の うらみが とけた")
        case .substitute:       return t("\(name)의 대타가 부서졌다", "\(name)'s substitute broke",
                                         "\(name)の みがわりが こわれた")
        }
    }

    /// 회복 — 드레인기(흡수·기가드레인)가 쓴다. **원인으로 문구를 가르지 않는다.** 플레이어가
    /// 알아야 하는 건 "누가 얼마나 회복했나"뿐이고, 무엇으로 회복했는지는 앞 줄의 기술명이 이미 말한다.
    func battleHealed(_ name: String, amount: Int) -> String {
        "\(name)은(는) \(amount) 회복했다"
    }

    /// 날씨가 시작·종료됐다. 어느 쪽의 줄도 아니다 — 판 전체에 걸린 상태라 이름이 들어가지 않는다.
    func battleWeatherStarted(_ weather: BattleWeather) -> String {
        switch weather {
        case .sun:       return "햇살이 강해졌다!"
        case .rain:      return "비가 내리기 시작했다!"
        case .sandstorm: return "모래바람이 불기 시작했다!"
        case .snow:      return "눈이 내리기 시작했다!"
        }
    }

    func battleWeatherEnded(_ weather: BattleWeather) -> String {
        switch weather {
        case .sun:       return "햇살이 원래대로 돌아왔다"
        case .rain:      return "비가 그쳤다"
        case .sandstorm: return "모래바람이 가라앉았다"
        case .snow:      return "눈이 그쳤다"
        }
    }

    /// 필드가 깔렸다 / 걷혔다. 날씨와 같은 자리의 줄이다.
    func battleTerrainStarted(_ terrain: BattleTerrain) -> String {
        switch terrain {
        case .electric: return "발밑에 전기가 흐르기 시작했다!"
        case .grassy:   return "발밑에 풀이 무성해졌다!"
        case .misty:    return "발밑에 안개가 자욱해졌다!"
        case .psychic:  return "발밑이 이상해졌다!"
        }
    }

    func battleTerrainEnded(_ terrain: BattleTerrain) -> String {
        switch terrain {
        case .electric: return "발밑의 전기가 사라졌다"
        case .grassy:   return "발밑의 풀이 사라졌다"
        case .misty:    return "발밑의 안개가 걷혔다"
        case .psychic:  return "발밑이 원래대로 돌아왔다"
        }
    }

    /// 진영 상태가 깔렸다 / 걷혔다.
    ///
    /// 어느 편인지는 문구에 넣지 않는다 — 바로 앞 줄이 누가 그 기술을 썼는지 이미 말한다.
    /// 양쪽이 같은 장막을 폈을 때만 걷히는 줄이 모호해지는데, 남은 턴은 화면의 배지가 들고 있다.
    func battleSideConditionStarted(_ condition: BattleSideCondition) -> String {
        switch condition {
        case .reflect:     return t("리플렉터가 펼쳐졌다!", "Reflect raised the team's Defense!",
                                    "リフレクターが はられた！")
        case .lightScreen: return t("빛의장막이 펼쳐졌다!", "Light Screen raised the team's Sp. Def!",
                                    "ひかりのかべが はられた！")
        case .auroraVeil:  return t("오로라베일이 펼쳐졌다!", "Aurora Veil shielded the team!",
                                    "オーロラベールが はられた！")
        case .safeguard:   return t("신비의부적이 편을 감쌌다!", "The team is cloaked in a mystical veil!",
                                    "しんぴのまもりに つつまれた！")
        case .mist:        return t("하얀안개가 편을 감쌌다!", "The team became shrouded in mist!",
                                    "しろいきりに つつまれた！")
        case .luckyChant:  return t("행운의부적이 편을 감쌌다!", "The team is protected from critical hits!",
                                    "こううんの まもりに つつまれた！")
        case .tailwind:    return t("순풍이 불기 시작했다!", "The tailwind blew from behind the team!",
                                    "おいかぜが 吹き始めた！")
        case .wideGuard:   return t("와이드가드로 편을 지켰다!", "Wide Guard protected the team!",
                                    "ワイドガードで まもりを かためた！")
        case .quickGuard:  return t("퀵가드로 편을 지켰다!", "Quick Guard protected the team!",
                                    "ファストガードで まもりを かためた！")
        case .matBlock:    return t("니가하지마로 편을 지켰다!", "Mat Block shielded the team!",
                                    "たたみがえしで まもりを かためた！")
        case .craftyShield: return t("트릭가드로 편을 지켰다!", "Crafty Shield shielded the team!",
                                     "トリックガードで まもりを かためた！")
        // 입장 데미지는 **상대 편에** 깔린다 — 그래서 문구가 "상대" 를 말한다(나머지는 앞 줄이
        // 누가 썼는지 말하므로 편을 안 밝힌다). 몇 층인지는 문구에 넣지 않는다: 같은 줄이 다시
        // 나가는 것이 곧 한 층 더 쌓였다는 뜻이고, 넣으면 세 언어를 층 수만큼 적어야 한다.
        case .spikes:      return t("상대 발밑에 압정이 흩뿌려졌다!",
                                    "Spikes were scattered around the opposing team!",
                                    "相手の 足下に まきびしを ばらまいた！")
        case .toxicSpikes: return t("상대 발밑에 독압정이 흩뿌려졌다!",
                                    "Poison spikes were scattered around the opposing team!",
                                    "相手の 足下に どくびしを ばらまいた！")
        case .stealthRock: return t("상대 주위에 스텔스록이 떠올랐다!",
                                    "Pointed stones float in the air around the opposing team!",
                                    "相手の まわりに とがった いわが ただよいはじめた！")
        case .stickyWeb:   return t("상대 발밑에 끈적끈적네트가 깔렸다!",
                                    "A sticky web spreads out beneath the opposing team!",
                                    "相手の 足下に ねばねばネットが 広がった！")
        }
    }

    /// 테라스탈 버튼. 남은 횟수가 없으면 버튼 자체가 사라지므로 "쓸 수 없음" 문구는 없다.
    var battleTerastallize: String { "테라스탈" }

    func battleTerastallized(_ name: String, type: PokemonType) -> String {
        return "\(name)가 \(type.name) 테라스탈했다!"
    }

    /// 방어를 친 줄과 그것이 막은 줄. 이름이 들어가므로 `KeyPath` 팝으로 담을 수 없다 —
    /// 막힌 순간의 팝은 이름 없는 `battleGuardBlockedPopup` 이 맡는다.
    func battleGuardUp(_ name: String) -> String {
        "\(name)는 몸을 지켰다!"
    }

    func battleGuardBlocked(_ name: String) -> String {
        "\(name)는 공격을 막아냈다!"
    }

    func battleSideConditionEnded(_ condition: BattleSideCondition) -> String {
        switch condition {
        case .reflect:     return t("리플렉터가 사라졌다", "Reflect wore off", "リフレクターが きえた")
        case .lightScreen: return t("빛의장막이 사라졌다", "Light Screen wore off", "ひかりのかべが きえた")
        case .auroraVeil:  return t("오로라베일이 사라졌다", "Aurora Veil wore off", "オーロラベールが きえた")
        case .safeguard:   return t("신비의부적이 사라졌다", "The mystical veil wore off",
                                    "しんぴのまもりが きえた")
        case .mist:        return t("하얀안개가 걷혔다", "The mist wore off", "しろいきりが きえた")
        case .luckyChant:  return t("행운의부적이 사라졌다", "The lucky chant wore off",
                                    "こううんの まもりが きえた")
        case .tailwind:    return t("순풍이 멎었다", "The tailwind petered out",
                                    "おいかぜが やんだ")
        // 편 방어기는 한 턴짜리라 걷히는 줄이 매 턴 나간다 — 그래서 문구를 짧게 둔다.
        case .wideGuard:   return t("와이드가드가 풀렸다", "Wide Guard wore off", "ワイドガードが きえた")
        case .quickGuard:  return t("퀵가드가 풀렸다", "Quick Guard wore off", "ファストガードが きえた")
        case .matBlock:    return t("니가하지마가 풀렸다", "Mat Block wore off", "たたみがえしが きえた")
        case .craftyShield: return t("트릭가드가 풀렸다", "Crafty Shield wore off", "トリックガードが きえた")
        // 입장 데미지는 턴으로 걷히지 않아 이 줄이 지금은 나가지 않는다. 그래도 문구를 두는
        // 이유는 제거 수단(코트체인지·고속스핀)이 붙는 자리가 이미 정해져 있기 때문이다 —
        // 그때 걷히는 줄이 없으면 사라진 것이 로그로 설명되지 않는다.
        case .spikes:      return t("발밑의 압정이 사라졌다", "The spikes disappeared",
                                    "あしもとの まきびしが きえた")
        case .toxicSpikes: return t("발밑의 독압정이 사라졌다", "The poison spikes disappeared",
                                    "あしもとの どくびしが きえた")
        case .stealthRock: return t("떠 있던 스텔스록이 사라졌다", "The pointed stones disappeared",
                                    "ただよっていた とがった いわが きえた")
        case .stickyWeb:   return t("발밑의 끈적끈적네트가 사라졌다", "The sticky web disappeared",
                                    "あしもとの ねばねばネットが きえた")
        }
    }

    /// 다단 히트 — 몇 번 맞았는지 안 쓰면 플레이어에겐 "위력이 이상하게 센 기술"로만 보인다.
    /// 급소·상성 문구와 같은 자리(공격 줄의 노트)에 붙는다.
    func battleMultiHit(_ hits: Int) -> String {
        "\(hits)번 맞았다!"
    }

    // MARK: 배틀 (랭크)

    /// 두 단계 이상은 본가처럼 "크게" 가 붙는다 — 한 단계와 두 단계가 화면에서 같으면 랭크가
    /// 얼마나 올랐는지 로그로 알 방법이 없다(배지는 현재 값만 보여 준다).
    func battleStatRose(_ name: String, stat: BattleStat, by amount: Int) -> String {
        let much = amount >= 2
        let subject = Self.koreanSubject(stat.name)
        return "\(name)의 \(subject) \(much ? "크게 " : "")올라갔다!"
    }

    func battleStatFell(_ name: String, stat: BattleStat, by amount: Int) -> String {
        let much = amount >= 2
        let subject = Self.koreanSubject(stat.name)
        return "\(name)의 \(subject) \(much ? "크게 " : "")떨어졌다!"
    }

    /// 한글 주격 조사를 붙인 낱말 — 받침이 있으면 "이", 없으면 "가". 스탯 이름이 7개로 고정이라
    /// "이(가)" 로 도망칠 이유가 없다. 판정은 종성 인덱스다 — (스칼라 − 0xAC00) % 28 == 0 이면 받침이 없다.
    static func koreanSubject(_ word: String) -> String {
        guard let scalar = word.unicodeScalars.last?.value, (0xAC00...0xD7A3).contains(scalar) else {
            return word + "가"
        }
        return word + ((scalar - 0xAC00) % 28 == 0 ? "가" : "이")
    }

    // MARK: 헤더 (오늘/주/월)
    var todayTokens: String { "오늘 함께한 시간" }
    var totalPlaytime: String { "누적" }
    /// 초 → "N시간 M분" / "M분" / "M초"(짧을 때). 대시보드가 사용량 숫자 대신 이 시간을 보여준다.
    func duration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = (s % 3600) / 60
        if h > 0 { return "\(h)시간 \(m)분" }
        if m > 0 { return "\(m)분" }
        return "\(s)초"
    }
    var thisWeek: String { "이번 주" }
    var thisMonth: String { "이번 달" }

    // MARK: 한도 섹션
    var limitsOfficial: String { "한도 (공식)" }
    var fiveHourSession: String { "5시간 세션" }
    var weekly: String { "주간" }
    var weeklyOpus: String { "주간 Opus" }
    var weeklySonnet: String { "주간 Sonnet" }
    var claudeCurrentBlock: String { "Claude 현재 5h 블록" }
    var reset: String { "리셋" }
    var limitReached: String { "한도 도달" }
    var personalSpendLimit: String { "개인 사용 한도" }
    var staleLimits: String { "갱신 지연" }
    var refresh: String { "갱신" }
    var limitsTapToLoad: String { "공식 한도 불러오기" }

    func plan(_ p: String) -> String { "플랜 \(p)" }
    func forecastReach(_ time: String) -> String {
        "현재 속도면 \(time) 한도 도달"
    }
    var forecastNoReach: String {
        "현재 속도로는 리셋 전 한도 도달 없음"
    }

    /// Claude oauth/usage 신형 limits[] 엔트리 이름 — kind + 모델 스코프 기반.
    func claudeLimitEntry(kind: String?, model: String?) -> String {
        switch kind {
        case "session": return fiveHourSession
        case "weekly_all": return weekly
        case "weekly_scoped":
            // 모델명이 없으면 레거시 "주간" 행과 이름이 겹치므로 scoped 임을 구분 표기
            guard let model else { return "주간 (모델별)" }
            return "주간 \(model)"
        default:
            let base = kind ?? "limit"
            let name = model.map { " \($0)" } ?? ""
            return base.replacingOccurrences(of: "_", with: " ") + name
        }
    }

    /// Codex 한도 윈도우 이름 (windowDurationMins 기반). 알림·팝오버 공통.
    func codexWindow(_ mins: Int?) -> String {
        switch mins {
        case 300: return fiveHourSession
        case 10_080: return weekly
        case let m? where m >= 60 && m % 60 == 0:
            let h = m / 60
            return "\(h)시간"
        case let m?: return "\(m)분"
        case nil: return "한도"
        }
    }

    // MARK: 푸터
    var refreshNow: String { "지금 새로고침" }
    var updated: String { "갱신" }
    var settings: String { "설정" }
    var back: String { "뒤로" }
    var generalSectionTitle: String { "일반" }
    var menuBarSectionTitle: String { "메뉴바에 표시" }
    var advancedSectionTitle: String { "고급" }
    var advancedDisclosureLabel: String { "고급 설정 · 진단" }
    var aboutSupportSectionTitle: String { "정보 & 지원" }
    var quit: String { "종료" }

    // MARK: 설정
    var refreshInterval: String { "새로고침 간격" }
    var menuBarItems: String { "메뉴바 표시 항목 (복수 선택)" }
    var todayTokensShort: String { "오늘 함께한 시간" }
    var todayCost: String { "오늘 비용 ($)" }
    var limitPercent: String { "한도 %" }
    var limitDisplayModeLabel: String { "한도 표시 방식" }
    var limitDisplayUsed: String { "사용량" }
    var limitDisplayRemaining: String { "남은 양" }
    /// 팝오버 한도 행의 remaining 모드 표시 — %에 자기설명 접미사를 붙인다.
    func percentRemaining(_ percent: String) -> String {
        "\(percent) 남음"
    }
    var allOffHint: String { "전부 끄면 캐릭터만 표시됩니다" }
    // MARK: 플로팅 펫
    var floatingPetSectionTitle: String { "플로팅 펫" }
    var floatingPetEnableLabel: String { "플로팅 펫 표시" }
    var floatingPetHint: String {
        "포켓몬이 화면 위에 떠 있어요 — 드래그로 위치를 옮길 수 있어요"
    }
    var floatingPetSizeLabel: String { "크기" }
    var floatingPetArtworkTitle: String { "그림" }
    /// 라벨에 맞바꿈을 넣는다 — "선명하게" 만 있으면 왜 기본이 아닌지 알 수 없다.
    func floatingPetArtworkLabel(_ artwork: FloatingPetArtwork) -> String {
        switch artwork {
        case .animated: return "움직이게"
        case .sharp:    return "선명하게"
        }
    }
    /// 고른 쪽이 무엇을 포기하는지 밝힌다. 특히 "선명하게" 를 골라도 **돌아다니기는 그대로**라는
    /// 걸 말해야 한다 — 안 그러면 펫이 아예 멈추는 줄 알고 안 고른다.
    func floatingPetArtworkHint(_ artwork: FloatingPetArtwork) -> String {
        switch artwork {
        case .animated:
            return "5세대 도트 그림이라 크게 띄우면 흐려져요."
        case .sharp:
            return "4배 선명한 정지 그림이에요. 돌아다니기는 그대로예요."
        }
    }
    var floatingPetRoamingLabel: String { "화면 돌아다니기" }
    var floatingPetMouseChaseLabel: String { "마우스 따라가기" }
    var floatingPetSpeedLabel: String { "이동 속도" }
    var floatingPetSpeciesLabel: String { "표시할 포켓몬" }
    var floatingPetSpeciesFollowsPartner: String {
        "지금 키우는 파트너"
    }
    var imageAntialiasingLabel: String { "이미지 부드럽게 표시" }
    /// 지금은 한도 알림만 말풍선으로 뜨지만, 알림 종류가 늘어도 이 라벨은 그대로 쓴다.
    var floatingPetBubbleAlertsLabel: String {
        "말풍선으로 알림 받기"
    }
    var floatingPetMenuOpen: String { "열기" }
    var floatingPetMenuHide: String {
        "플로팅 펫 끄기"
    }
    func floatingPetHoverTokensOnly(_ tokens: String) -> String {
        "오늘 \(tokens)"
    }
    func floatingPetHoverWithLimit(_ tokens: String, _ percent: String) -> String {
        "오늘 \(tokens) (한도 \(percent))"
    }

    var disableKeychain: String { "Keychain 접근 끄기" }
    var disableKeychainHint: String { "켜면 Keychain 접근 허용 팝업이 더 안 뜹니다 — 공식 한도(%)만 숨겨지고 토큰·비용은 그대로" }
    var refreshLimitToken: String { "한도 토큰 캐시 갱신" }
    var onlyOnPress: String { "누를 때만 Keychain 을 읽어요 — 자동 폴링은 안 읽어 팝업이 안 떠요. 토큰 만료 후 이 버튼으로 한도 갱신" }
    var launchAtLogin: String { "로그인 시 자동 시작" }
    var bundledOnly: String { ".app 번들로 설치된 경우에만 사용 가능 (scripts/build-app.sh)" }
    var notificationsSection: String { "알림" }
    var limitNotificationsLabel: String { "한도 알림" }
    var companionNotificationsLabel: String { "Companion 이벤트 (부화·진화·졸업)" }
    var statusChecksLabel: String { "프로바이더 상태 확인" }
    var statusChecksHint: String { "Claude·OpenAI 장애를 팝오버에 표시 (알림 아님)" }
    var warning: String { "경고" }
    var critical: String { "임박" }
    var aggregationNote: String { "토큰 집계 기준: totalTokens (input + output + cache, 로컬 날짜)" }
    var close: String { "닫기" }

    // MARK: 세이브 이전 (설정 → 백업 & 이전)
    var transferSectionTitle: String { "백업 & 이전" }
    var exportSaveLabel: String { "세이브 내보내기" }
    var exportSaveHint: String {
        "도감·누적 별의조각·가방·현재 포켓몬을 파일 하나로 저장해요"
    }
    var exportSaveButton: String { "내보내기…" }
    var importSaveLabel: String { "세이브 불러오기" }
    var importSaveHint: String {
        "다른 Mac에서 내보낸 파일을 골라 이 Mac으로 이어서 키워요"
    }
    var importSaveButton: String { "불러오기…" }
    var importConfirmTitle: String {
        "이 Mac의 진행을 대체할까요?"
    }
    /// 무엇이 사라지는지 수치로 적는다 — 일반적인 "정말 진행할까요?" 보다 판단에 실제로 쓸모 있다.
    /// 내보낸 시각·출처 기기를 함께 보여주는 이유: 도감 수가 같으면 3주 전 세이브도 문구가 똑같아,
    /// 오래된 파일을 되돌리는 상황을 사용자가 알아챌 단서가 없다.
    func importConfirmBody(incomingDex: Int, incomingTokens: String,
                           exportedAt: String, sourceDevice: String,
                           currentDex: Int, currentTokens: String) -> String {
        """
          불러올 세이브: 도감 \(incomingDex)마리 · 누적 \(incomingTokens)
          내보낸 시각: \(exportedAt) · \(sourceDevice)
          현재 이 Mac: 도감 \(currentDex)마리 · 누적 \(currentTokens)

          이 Mac의 현재 진행은 대체됩니다. 직전 상태는 상태 폴더에 백업으로 남습니다(최근 5개).
          """
    }
    var importConfirmReplace: String { "대체" }
    func importSaveDone(dex: Int, tokens: String) -> String {
        "불러왔어요 — 도감 \(dex)마리 · 누적 \(tokens)"
    }
    var importErrorNotSaveFile: String {
        "PokeTokenBar 세이브 파일이 아니에요."
    }
    var importErrorNewerSchema: String {
        "더 새로운 버전에서 만든 세이브예요 — 앱을 업데이트한 뒤 다시 시도해 주세요."
    }
    /// 불러오기 실패 사유 → 사용자 문구. 뷰가 아니라 여기 두는 이유는 이 매핑이 테스트 가능해야 하기
    /// 때문이다 — 매핑이 어긋나면 `SaveTransferError` 는 LocalizedError 가 아니라서 "The operation
    /// couldn't be completed…" 같은 원문이 그대로 노출된다(조용한 품질 저하).
    func importErrorMessage(_ error: Error) -> String {
        switch error {
        case SaveTransferError.notASaveFile:  return importErrorNotSaveFile
        case SaveTransferError.newerSchema:   return importErrorNewerSchema
        case SaveTransferError.fileTooLarge:  return importErrorTooLarge
        case SaveTransferError.backupFailed:  return importErrorBackupFailed
        default: return error.localizedDescription
        }
    }
    var importErrorTooLarge: String {
        "세이브 파일이라기엔 너무 커요 — 다른 파일을 고른 것 같아요."
    }
    /// 백업을 못 남기면 불러오기를 중단한다 — 되돌릴 수단 없이 진행을 대체하지 않기 위해서다.
    var importErrorBackupFailed: String {
        "현재 상태를 백업하지 못해 불러오기를 중단했어요 — 진행은 그대로예요. 디스크 여유 공간을 확인해 주세요."
    }

    // MARK: 문제점 알리기 (설정 → 메일 리포트)
    var reportProblem: String { "문제점 알리기" }
    var showLogFile: String { "로그 파일 보기" }
    var reportAttachHint: String {
        "메일에 로그 파일을 첨부해 주시면 원인 파악에 큰 도움이 돼요."
    }
    func reportMailFallback(_ address: String) -> String {
        "메일 앱을 열 수 없어요. \(address) 로 직접 보내주세요."
    }
    func reportMailSubject(_ version: String) -> String {
        "[PokeTokenBar] 문제 리포트 (v\(version))"
    }
    func reportMailBody(version: String, os: String) -> String {
        """
        문제 내용:
        (겪으신 문제를 적어주세요 — 언제, 어떤 화면에서, 어떻게 되었는지)


        ---
        앱 버전: v\(version)
        macOS: \(os)
        로그 파일(첨부 권장): ~/Library/Logs/PokeTokenBar.log
        """
    }

    /// 새로고침 간격 라벨 (초 단위 값 → 표시). 0 = 수동.
    func intervalLabel(_ seconds: TimeInterval) -> String {
        if seconds == 0 { return "수동" }
        let m = Int(seconds / 60)
        return "\(m)분"
    }

    // MARK: 컴패니언
    var finalForm: String { "최종 진화체" }
    func stage(_ i: Int, _ k: Int) -> String { "진화 단계 \(i) / \(k)" }
    var unknownNextEvolution: String { "알 수 없는 다음 진화" }

    // MARK: 기술 목록 (홈 · "기술 보기")
    // 행 라벨과 툴팁이 같은 키를 쓴다 — 예전엔 행만 한국어 리터럴이라 en/ja 에서 둘이 어긋났다(#10).
    var movesTitle: String { "기술 보기" }
    var movesLoading: String { "기술 불러오는 중" }
    var movesEmpty: String { "확인할 수 있는 기술이 없습니다." }
    var moveCategoryStatus: String { "변화" }
    var moveCategoryPhysical: String { "물리" }
    var moveCategorySpecial: String { "특수" }
    func moveCategory(_ damageClass: MoveDamageClass) -> String {
        switch damageClass {
        case .physical: return moveCategoryPhysical
        case .special: return moveCategorySpecial
        case .status: return moveCategoryStatus
        }
    }
    var movePowerLabel: String { "위력" }
    var moveAccuracyLabel: String { "명중" }
    var moveAlwaysHits: String { "필중" }
    /// 행 라벨은 폭이 좁아 축약형을 쓴다(툴팁은 위 전체 라벨).
    func movePowerShort(_ power: Int) -> String { "위력 \(power)" }
    func moveAccuracyShort(_ accuracy: Int) -> String { "명중 \(accuracy)" }
    func movePP(_ pp: Int) -> String { "PP \(pp)" }

    var moveHoverHint: String {
        "기술에 마우스를 올리면 설명이 나와요."
    }

    /// 기술 한 줄 요약 — 설명이 없을 때 쓰는 폴백이자 툴팁 상세줄. 두 자리가 같은 어휘를 쓰도록 한 곳에 둔다.
    func moveDetailLine(_ move: MoveSpec) -> String {
        let power = move.damageClass == .status ? "—" : "\(move.power)"
        let accuracy = move.accuracy.map(String.init) ?? moveAlwaysHits
        return "\(move.type.name) · \(moveCategory(move.damageClass)) · "
            + "\(movePowerLabel) \(power) · \(moveAccuracyLabel) \(accuracy) · \(movePP(move.pp))"
    }

    /// 호버 슬롯 문구 — 올린 기술이 없으면 안내, 설명이 있으면 설명, 없거나 비어 있으면 스탯 요약.
    /// 슬롯이 빈 채로 남으면 "고장 난 것"처럼 보이므로 어느 분기에서도 빈 문자열을 내지 않는다.
    func moveHoverText(_ move: MoveSpec?) -> String {
        guard let move else { return moveHoverHint }
        if let description = move.flavorText, !description.isEmpty { return description }
        return moveDetailLine(move)
    }

    // MARK: 집중 타이머 · 모험 재화 줄
    /// 알·조각·주간 모험 진행도 한 줄. 예전엔 "주간" 만 한국어로 박혀 있었다(#10 부류 스윕).
    func focusStash(eggs: Int, fragments: Int, weekly: Int) -> String {
        let progress = "주간 \(weekly)/10"
        return "🥚 ×\(eggs) · 🧩 \(fragments)/10 · \(progress)"
    }
    /// 보관 알 자동 부화 줄의 제목과, 예정 시각을 지난 뒤의 대기 문구(#86).
    var eggAutoHatchLabel: String { "🥚 자동 부화까지" }
    var eggHatchingSoon: String { "곧 부화" }
    func battleFixedStake(_ amount: String) -> String {
        "고정 판돈 ⭐ \(amount)"
    }

    // MARK: 메뉴바 상태 (#20 — MenuBarStatus.fullDescription)
    var menuBarResting: String { "휴식 중" }
    var menuBarAdventuring: String { "모험 중" }
    var menuBarAdventureClaimable: String { "보상 받기" }

    // MARK: 스타터 선택 (맨 처음 1회)
    var trainerNamePrompt: String { "트레이너 이름" }
    var trainerNamePlaceholder: String { "이름을 입력하세요" }
    var starterNeedName: String { "먼저 트레이너 이름을 입력하세요." }
    var starterPrompt: String { "함께할 첫 파트너를 골라요" }
    var starterHint: String {
        "고른 포켓몬이 바로 함께합니다. 이후엔 알에서 다양한 포켓몬이 태어나요."
    }
    var starterLoading: String { "후보를 부르는 중…" }
    var eggIncubating: String { "🥚 부화 준비 중" }
    /// 게임 재화 표시 단위 — 사용량 트래커의 실제 AI 토큰 숫자와 시각적으로 구분하는 ✨ 접두.
    func stardust(_ amount: String) -> String { "✨\(amount)" }
    /// 시간당 생산량(방치형 핵심 신호) — "앱을 켜 두면 자란다"를 수치로.
    func perHour(_ amount: String) -> String { "시간당 ✨\(amount)" }
    func eggToHatch(_ amount: String) -> String { "부화까지 ✨\(amount)" }
    func toNextEvolution(_ amount: String) -> String { "다음 진화까지 ✨\(amount)" }
    func toGraduation(_ amount: String) -> String { "졸업까지 ✨\(amount)" }
    func graduated(_ name: String) -> String {
        "\(name) 졸업 → 도감에 보존. 새 알이 도착했어요!"
    }
    var dexEmptyTitle: String { "아직 잡은 포켓몬이 없어요!" }
    var dexEmptyHint: String { "앱을 켜 두고 첫 포켓몬을 부화시켜 보세요." }

    // MARK: 도감 요약 헤더
    var dexTitle: String { "도감" }
    func dexTotal(_ n: Int) -> String { "총 \(n)마리" }
    /// 포획 로그 = 개체 단위 기록(같은 라인 중복이 정상). 도감 = 종 단위 집계.
    var catchLogTitle: String { "포획 로그" }
    /// 도감 총계는 개체가 아니라 종 수 — 로그의 dexTotal("총 N마리")과 단위가 다르다.
    /// 도감 총계 — `raising` 은 아직 졸업하지 않은(키우는 중인) 종 수다. 총계는 그 종까지 세고
    /// 목표 줄은 졸업분만 센다 — 갈라지는 몫을 밝혀야 두 숫자가 서로를 설명한다.
    func dexSpeciesTotal(_ n: Int, raising: Int) -> String {
        guard raising > 0 else { return "\(n)종" }
        return "\(n)종 (\(raising) 육성중)"
    }
    /// 페이저 접근성 문구 — 도감과 소유 포켓몬이 함께 쓴다(둘 다 페이지식 고정 격자).
    func dexPageLabel(_ page: Int, _ total: Int) -> String {
        "\(total)페이지 중 \(page)페이지"
    }
    /// 능력치 표의 HP 칸. 나머지 다섯은 `BattleStat.name` 이 든다(랭크가 붙는 스탯이라 그쪽에 있다).
    /// HP 만 여기 있는 게 어색해 보여도, 이름을 두 벌로 만들면 배틀 로그와 표가 다른 말을 쓴다.
    var statHP: String { "HP" }
    /// 능력치가 **이 개체의 레벨·성격 기준**임을 밝힌다. 종족값으로 오해하면 성격을 바꿔도
    /// 안 변한다고 생각한다.
    func statsAtLevel(_ level: Int) -> String {
        "Lv.\(level) 기준 능력치"
    }
    /// 갈라지는 진화 — 갈래가 몇 개인지부터 알려야 나머지가 막힌 게 아니란 걸 안다.
    func evolutionBranchCount(_ count: Int) -> String {
        "진화 갈래 \(count)가지"
    }
    /// 갈래 한 줄 — "물의돌 → 강챙이". 무엇을 하면 무엇이 되는지가 한눈에 붙어 있어야 한다.
    func evolutionBranchRow(condition: String, target: String) -> String {
        "\(condition) → \(target)"
    }
    /// 조건을 못 밝히는 갈래(장소·파티처럼 앱에 축이 없는 것). 이름만 적고 조건 자리는 비운다 —
    /// 거짓 조건을 지어내면 그걸 채우려다 시간을 버린다.
    var evolutionBranchUnknownCondition: String { "조건 불명" }
    /// 기술 조건 진화(원시의힘·흉내내기 …) — 레벨 조건이 없어서, 안 알려주면 아무리 키워도
    /// 왜 진화가 안 오는지 알 길이 없다.
    func evolutionNeedsMove(_ move: String, into target: String) -> String {
        "\(target)(으)로 진화하려면 ‘\(move)’이(가) 필요해요"
    }
    /// 기술 습득 카드의 표식 — 이 기술을 넣으면 진화가 열린다는 사실은 카드를 볼 때 알아야 한다.
    /// 거절하면 다음 기회가 하트비늘뿐이라, 고른 뒤에 알려주면 늦다.
    func evolutionMoveUnlocks(_ target: String) -> String {
        "배우면 \(target)(으)로 진화할 수 있어요"
    }
    var dexPagePrev: String { "이전 페이지" }
    var dexPageNext: String { "다음 페이지" }
    /// 페이지 표시를 누르면 바로 건너뛴다 — 전체를 펼치면 28페이지라 화살표만으로는 멀다.
    var dexPageJumpHint: String {
        "눌러서 다른 페이지로 바로 이동"
    }
    var dexRaising: String { "키우는 중" }
    var rarityCommon: String { "일반" }
    var rarityUncommon: String { "고급" }
    var rarityRare: String { "희귀" }
    var rarityLegendary: String { "전설" }
    var dexFilterHint: String { "탭하면 이 희귀도만 보기 · 다시 탭하면 전체" }
    /// 도감 칸의 ✨ 를 읽어주는 명사 — 이모지는 스크린리더가 일관되게 읽지 못한다.
    var dexShinyLabel: String { "이로치" }
    /// 이로치만 보기 필터의 캡슐 라벨. `dexShinyLabel` 과 나눠 둔다 — 저쪽은 칸 하나를 읽어주는
    /// 명사고 이쪽은 필터 이름이라, 한쪽 문구를 다듬으면 다른 쪽이 어색해진다.
    var dexShinyFilter: String { "이로치" }
    var dexShinyFilterHint: String {
        "탭하면 이로치만 보기 · 다시 탭하면 전체 (희귀도 필터와 함께 걸립니다)"
    }
    /// 잡은 것만 보기 — 끄면 아직 안 잡은 종이 실루엣으로 함께 나온다.
    var dexCaughtOnly: String { "잡은 것만" }
    var dexCaughtOnlyHint: String {
        "끄면 아직 안 잡은 종도 실루엣으로 보입니다"
    }
    /// 희귀도·이로치는 잡아야 생기는 값이라, 그 필터를 켜면 미포획 칸이 함께 빠진다는 안내.
    var dexCaughtOnlyLocked: String {
        "희귀도·이로치는 잡은 종에만 있는 정보라 미포획은 빠집니다"
    }
    /// 미포획 칸을 읽어주는 문구 — 화면에는 `???` 만 보이지만 스크린리더는 물음표를 못 읽는다.
    var dexNotCaught: String { "아직 안 잡음" }
    var dexTypeFilter: String { "타입" }
    var dexTypeFilterAll: String { "모든 타입" }
    /// 타입은 미포획 종도 아는 유일한 축이라 실루엣에도 걸린다 — 다른 필터와 다른 점이라 밝힌다.
    var dexTypeFilterHint: String {
        "아직 안 잡은 종에도 걸립니다"
    }
    var dexTypeFilterUnavailable: String {
        "타입 정보를 아직 못 받았어요 (인터넷 연결 후 다시 열어 주세요)"
    }
    func rarityLabel(_ r: Rarity) -> String {
        switch r {
        case .common:    return rarityCommon
        case .uncommon:  return rarityUncommon
        case .rare:      return rarityRare
        case .legendary: return rarityLegendary
        }
    }

    // 상태 한 줄
    var statusEgg: String { "곧 깨어나요." }
    var statusIdle: String { "오늘은 조용히 자리를 지켜요." }
    var statusWorking: String { "오늘의 작업 흔적이 쌓이고 있어요." }
    var statusFocus: String { "지금은 집중 모드예요." }
    func statusEvolved(_ name: String) -> String { "\(name)(으)로 진화했어요!" }
    var statusGrew: String { "성장했어요!" }

    // MARK: companion 이벤트 시스템 알림
    var notifHatchTitle: String { "🥚 부화!" }
    func notifHatchBody(_ name: String) -> String { "알에서 \(name)이(가) 나왔어요!" }
    var notifShinyHatchTitle: String { "✨ 이로치 포켓몬!" }
    func notifShinyHatchBody(_ name: String) -> String { "이로치 \(name)이(가) 태어났어요! (1/64)" }
    var eggImminent: String { "곧 부화해요!" }
    /// 첫 실행(아직 적립 0) 안내 — "왜 아무 일도 안 일어나지"를 방지.
    var eggFirstRunHint: String {
        "앱을 켜 두면 별의조각이 쌓여 자라요. 잠시 뒤 알이 부화해요." }
    var notifEvolveTitle: String { "✨ 진화!" }
    func notifEvolveBody(_ name: String) -> String { "\(name)(으)로 진화했어요!" }
    // 메타몽 위장 리빌 — 진화 못 하는 메타몽이 첫 진화 순간 정체를 드러낸다.
    var notifDittoRevealTitle: String { "🎭 어라? 메타몽!" }
    func notifDittoRevealBody(_ disguise: String) -> String { "\(disguise)인 줄 알았는데 — 사실은 메타몽이었어요!" }
    var notifShinyDittoRevealTitle: String { "🎭✨ 어라? 이로치 메타몽!" }
    func notifShinyDittoRevealBody(_ disguise: String) -> String { "\(disguise)인 줄 알았는데 — 이로치 메타몽이었어요! (1/64)" }
    var notifTrainerLevelUpTitle: String { "👑 트레이너 레벨업!" }
    func notifTrainerLevelUpBody(_ level: Int, _ stardust: Int) -> String {
        let amount = GameNumberFormatter.compact(stardust)
        return "Lv.\(level) 달성 — 별의조각 \(amount) 받았어요!"
    }
    var notifMaxLevelOverflowTitle: String { "💫 경험치가 별의조각으로!" }
    /// 만렙 파트너가 더 받을 수 없는 경험치를 되돌려 받았다는 알림(#82). 예전엔 그냥 사라졌다.
    func notifMaxLevelOverflowBody(_ stardust: Int) -> String {
        let amount = GameNumberFormatter.compact(stardust)
        return "이미 다 자란 파트너의 경험치를 별의조각 \(amount) 로 바꿨어요!"
    }
    /// 정산 배너 첫 줄 — 이번 정산이 지갑에 더한 별의조각 **전부**(`AdventureReward.totalStardust`).
    /// 알림은 번들앱·방해금지·토글 3중 게이트라 끈 사용자에겐 안 나간다. 이 줄이 그 사용자가 지급을
    /// 보는 유일한 자리다(#192).
    func claimSettled(_ stardust: Int) -> String {
        let amount = GameNumberFormatter.compact(stardust)
        return "모험 정산 · 별의조각 \(amount)"
    }
    /// 정산 배너 둘째 줄 — 위 금액 **중** 만렙에 걸린 경험치를 되돌린 몫. 환산이 없으면 그리지 않는다.
    /// "그중" 이 핵심이다. 따로 더 받은 것처럼 읽히면 배너 합이 지갑과 안 맞아 보인다.
    ///
    /// 조사는 숫자 뒤에 바로 붙이지 않는다 — `compact` 는 10,000 미만을 그대로 숫자로 내보내서
    /// (흔한 구간이다) "3600 는" 처럼 받침을 잘못 고른 문장이 나간다. 단위 명사 "개" 를 끼우면
    /// 어떤 값이 와도 조사가 고정된다.
    func claimOverflowConverted(_ stardust: Int) -> String {
        let amount = GameNumberFormatter.compact(stardust)
        return "그중 \(amount)개는 다 자란 파트너의 남은 경험치를 바꾼 몫이에요"
    }
    /// 정산 **밖** 지급 배너(#200). `claimSettled` 와 같은 형태다 — 사건 이름 · 금액.
    ///
    /// 사건 이름을 빼면 안 된다. 금액만 띄우면 "왜 늘었는지" 는 여전히 화면에 없고, 그게 이
    /// 배너를 만든 이유 자체다. 조립을 뷰가 아니라 여기 두는 것도 `ClaimBannerLine` 과 같은
    /// 이유다 — 뷰 안 `switch` 로만 있으면 한 경로가 빠져도 테스트가 전부 초록이다.
    func payoutSettled(_ payout: StardustPayout) -> String {
        let amount = GameNumberFormatter.compact(payout.stardust)
        let event: String
        switch payout.source {
        case .evolve:     event = "진화 보상"
        case .race:       event = "포켓슬론 완주"
        case .battle:     event = "배틀 승리"
        case .dungeon:    event = "웨이브 런 클리어"
        case .graduation: event = "졸업 보상"
        }
        return "\(event) · 별의조각 \(amount)"
    }
    /// 상단 트레이너 바 라벨. `Lv.N` 만 쓰면 포켓몬 레벨(파트너·로스터·배틀에서 이미 쓰는 표기)로
    /// 잘못 읽힌다 — 이 단어가 계정 단위 값임을 알려주는 유일한 장치다.
    var trainerLevelLabel: String { "트레이너" }
    var notifMissionDoneTitle: String { "🎯 미션 완료!" }
    func notifMissionDoneBody(_ name: String, _ stardust: Int) -> String {
        let amount = GameNumberFormatter.compact(stardust)
        return "\(name) — 별의조각 \(amount) 받았어요!"
    }
    /// 목표 이름 — 미션과 시즌 챌린지가 **같은 문구를 공유**한다. 두 곳에 두면 한쪽만 고쳐진다.
    ///
    /// id 가 아니라 **이벤트로 스위치**한다: 이벤트를 더하면 컴파일러가 막으니 빈 문자열 폴백이
    /// 필요 없다(`achievementName` 과 같은 이유). "오늘"·"이번 주" 는 넣지 않는다 — 카드의 주기
    /// 배지가 이미 말하고, 360pt 팝오버에서 두 번 쓰면 이름이 잘린다. 목표 수치가 들어가 알림에서도
    /// 구분된다(집중 60분 vs 300분).
    func goalName(_ event: MissionEvent, _ target: Int) -> String {
        switch event {
        case .adventures:
            return "모험 정산 \(target)회"
        case .focusMinutes:
            return "집중 \(target)분"
        case .graduations:
            return "졸업 \(target)회"
        }
    }

    /// 영어 복수형 — 세 이벤트가 공유한다. 한 케이스만 처리하면 목표값을 1 로 조절하는 순간
    /// 나머지에서 "Claim 1 adventures" 가 나온다.
    private func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    func missionName(_ mission: Mission) -> String { goalName(mission.event, mission.target) }
    var missionsTitle: String { "미션" }

    /// 시즌 카드 제목과 남은 일수. 완료 알림 본문은 미션 것을 재사용한다(같은 문장을 두 번 번역하지
    /// 않는다). 남은 일수는 한 줄 헤더에 들어가므로 가장 짧은 말을 쓴다.
    var seasonTitle: String { "시즌 챌린지" }
    func seasonDaysLeft(_ days: Int) -> String {
        "\(days)일 남음"
    }
    var notifSeasonDoneTitle: String { "🗓️ 시즌 챌린지 달성!" }

    var notifDexGoalTitle: String { "📘 도감 목표 달성!" }
    func notifDexGoalBody(_ name: String) -> String {
        "\(name) — 보상이 도착했어요!"
    }
    /// 이름 없는 목표는 **빈 문자열**을 돌려준다 — 카탈로그에 목표를 더하고 문구를 빼먹으면
    /// `DexGoalTests` 가 그 자리에서 실패한다. id 를 폴백으로 쓰면 그 가드가 무력해진다.
    /// 목표값이 이름에 들어가 알림에서도 어느 칸인지 구분된다(종 10 vs 종 25).
    func dexGoalName(_ goal: DexGoal) -> String {
        switch goal.kind {
        case .species: return "도감 \(goal.target)종"
        case .types:   return "타입 \(goal.target)종류"
        case .shiny:   return "이로치 \(goal.target)마리"
        }
    }
    /// 도감 헤더 목표 줄의 축 라벨 — 한 줄에 셋이 들어가므로 가장 짧은 말을 쓴다.
    func dexGoalShortLabel(_ kind: DexGoalKind) -> String {
        switch kind {
        case .species: return "종"
        case .types:   return "타입"
        case .shiny:   return dexShinyLabel   // 같은 한 단어를 두 번 번역하지 않는다
        }
    }
    /// 주간 배지는 위쪽 한도 섹션의 `weekly` 를 그대로 쓴다 — 같은 한 단어를 두 번 번역하지 않는다.
    var missionDaily: String { "일간" }

    /// 컬렉션 탭 세그먼트 라벨 겸 선반 제목. 체육관 "배지" 와 다른 말을 쓴다 — 한 앱에 배지가
    /// 두 종류면 어느 쪽 진행인지 안 읽힌다.
    var achievementsTitle: String { "업적" }
    /// 단계 표시(`●●○○`)의 스크린리더 대체 문구 — 점 문자를 그대로 읽히면 "검은 원 흰 원" 이 된다.
    func achievementTierLabel(_ reached: Int, _ total: Int) -> String {
        "\(total)단계 중 \(reached)단계"
    }
    /// 카드 진행도 줄의 스크린리더 대체 문구. `Lv.12 · 🏅8/16` 을 그대로 읽히면 뜻이 안 통한다.
    /// 광고에 없는 칸은 문구에서도 빠진다.
    func peerProgressLabel(_ level: Int?, _ tiers: Int?, _ total: Int) -> String {
        var parts: [String] = []
        if let level {
            parts.append("트레이너 Lv.\(level)")
        }
        if let tiers {
            parts.append("업적 \(tiers)/\(total)")
        }
        return parts.joined(separator: ", ")
    }

    var notifAchievementTitle: String { "🏅 업적 달성!" }
    func notifAchievementBody(_ name: String, _ tier: Int, _ stardust: Int) -> String {
        let amount = GameNumberFormatter.compact(stardust)
        return "\(name) \(tier)단계 — 별의조각 \(amount) 받았어요!"
    }
    /// 업적 트랙 이름. 미션·도감 목표와 달리 **id 문자열이 아니라 열거형으로 스위치**한다 —
    /// 트랙을 더하면 컴파일이 막으니 빈 문자열 폴백이 필요 없다.
    func achievementName(_ track: AchievementTrack) -> String {
        switch track {
        case .focus:  return "집중 시간"
        case .evolve: return "진화"
        case .battle: return "배틀 승리"
        case .race:   return "레이스 완주"
        case .dungeon: return "던전 클리어"
        case .dungeonSweep: return "위험한 길 완주"
        }
    }

    var notifGraduateTitle: String { "🎓 졸업!" }
    func notifGraduateBody(_ name: String) -> String { "\(name) — 도감에 보존! 새 알이 도착했어요." }

    // MARK: Claude 한도 토큰 갱신 오류 (친절 안내)
    func limitRefreshHTTPError(_ status: Int) -> String {
        if status == 401 || status == 403 {
            return "Claude 자격증명이 만료됐거나 권한이 없어요 (\(status)). Claude Code 로그인을 확인하세요. Codex만 쓴다면 무시해도 됩니다 — Codex 한도는 따로 표시돼요."
        }
        return "Claude 한도 조회 실패 (\(status))."
    }
    var limitRefreshNoCredential: String {
        "Claude 자격증명을 찾지 못했어요. Claude Code 에 로그인하면 한도가 표시됩니다. Codex만 쓴다면 무시해도 돼요."
    }
    var limitRefreshReauthNeeded: String {
        "Claude 자격증명에 계정 로그인 정보가 없어요. Claude Code 에서 `/login` 으로 다시 로그인하면 한도가 표시됩니다."
    }
    var limitRefreshGeneric: String {
        "Claude 한도 조회에 실패했어요. 잠시 후 다시 시도하세요."
    }
    var limitRefreshRateLimited: String {
        "Claude 한도 조회가 일시 제한됐어요 (429). 잠시 쉬었다가 자동으로 재시도합니다."
    }

    // MARK: Claude 세션 만료(401) 안내
    var claudeAuthExpiredTitle: String {
        "Claude 세션 만료 — 한도가 갱신 안 돼요"
    }
    var claudeAuthExpiredHint: String {
        "표시된 값은 만료 전 기준이에요. 다시 시도하거나, Claude Code 를 한 번 실행하면 자동 갱신됩니다."
    }
    var retry: String { "다시 시도" }

    // MARK: 업데이트 알림
    func updateAvailable(_ version: String, current: String) -> String {
        "🆕 v\(version) 사용 가능 (현재 \(current))"
    }
    var updateButton: String { "업데이트" }
    var updateLater: String { "나중에" }
    var updating: String { "업데이트 중…" }
    var updateSectionTitle: String { "업데이트" }
    var githubAccountLabel: String { "GitHub 계정" }
    var githubLogin: String { "로그인" }
    var githubLogout: String { "로그아웃" }
    var githubConnected: String { "연결됨" }
    var githubLoginHint: String {
        "비공개 릴리스에서 업데이트를 받으려면 로그인해 주세요."
    }
    func githubDeviceCode(_ code: String) -> String {
        "코드 \(code)"
    }
    var githubDeviceCodeHint: String {
        "코드를 복사했어요. 열린 GitHub 창에서 승인해 주세요."
    }
    var updateNotificationsLabel: String { "업데이트 알림" }
    var automaticUpdateDownloadsLabel: String {
        "업데이트 자동 다운로드"
    }
    var checkForUpdatesLabel: String { "업데이트 확인" }
    var releaseNotesOnUpdateLabel: String {
        "업데이트 후 새로워진 점 보기"
    }
    var releaseNotesWindowTitle: String { "새로워진 점" }
    func releaseNotesUpdatedTo(_ version: String) -> String {
        "v\(version) 으로 업데이트됐어요"
    }
    var releaseNotesUnavailable: String {
        "릴리스 노트를 불러오지 못했어요 — GitHub 로그인과 네트워크를 확인해 주세요."
    }
    var releaseNotesOpenPage: String {
        "릴리스 페이지 열기"
    }
    var checkNowButton: String { "지금 확인" }
    func updateFound(_ version: String) -> String { "새 버전 v\(version) 있어요" }
    func upToDate(_ version: String) -> String { "최신 버전이에요 (v\(version))" }
    func updateCheckError(_ error: UpdateChecker.CheckError) -> String {
        switch error {
        case .authenticationRequired:
            "GitHub 로그인이 필요해요."
        case .network:
            "업데이트 확인에 실패했어요. 네트워크를 확인해 주세요."
        case .keychain:
            "로그인 정보를 Keychain에 갱신하지 못했어요. 앱을 다시 로그인해 주세요."
        case .repositoryAccess:
            "이 계정은 Kswiftin/K-MON 릴리스에 접근할 수 없어요."
        }
    }

    // MARK: 알림
    var notifCritical: String { "한도 임박" }
    var notifWarning: String { "한도 경고" }
    func notifBody(_ name: String, _ percent: String) -> String {
        "\(name) 한도 \(percent) 사용"
    }
    var claudeFiveHour: String { "Claude 5시간 세션" }
    var claudeWeekly: String { "Claude 주간" }
    var codexPersonalLimit: String { "Codex 개인 한도" }

    // MARK: 가방 / 아이템
    var bag: String { "가방" }
    var bagEmptyTitle: String { "아직 가방이 비어있어요!" }
    var useItem: String { "사용하기" }
    var use: String { "사용" }
    var cancel: String { "취소" }
    func useOnCurrent(_ name: String) -> String {
        "\(name)에게 사용할까요?"
    }
    var useAfterHatch: String { "부화 후 사용할 수 있어요" }
    var useNeedsPokemon: String { "사용할 포켓몬이 없어요" }

    // 즐겨찾기 — 표시가 아니라 자물쇠다. 켜져 있으면 그 개체를 잃는 동작이 막힌다.
    var favorite: String { "즐겨찾기" }
    var unfavorite: String { "즐겨찾기 해제" }
    var favoritesOnly: String { "즐겨찾기만 보기" }
    var favoriteLockedHint: String {
        "즐겨찾기한 포켓몬은 놓아주거나 경매에 내놓을 수 없어요. 별을 끄면 풀립니다."
    }

    // 가방 버리기 — 환불이 없고 되돌릴 수 없어, 확인 문구에 그 사실을 함께 적는다.
    var discard: String { "버리기" }
    func discardConfirm(_ name: String) -> String {
        "\(name) 버릴까요? 되돌릴 수 없고 별의조각도 돌려받지 못해요."
    }
    var discardOne: String { "1개만" }
    func discardAll(_ count: Int) -> String { "전부 ×\(count)" }

    /// 팀 선택 영역 제목 — 이게 "내가 가진 것 중에서 고르는 자리" 임을 말해 준다.
    var teamPickerTitle: String { "내 포켓몬에서 고르기" }

    /// 팀 선택 타입 필터의 '거르지 않음' 항목.
    var teamFilterAllTypes: String { "전체 타입" }

    // MARK: 체육관
    var gymLeagueTitle: String { "체육관" }

    // MARK: 퍼즐 던전 (#79)
    var dungeonTitle: String { "오늘의 던전" }
    /// 오늘의 던전 클리어 알 보상 — 하루 첫 클리어에서만 뜬다(`recordRunResult`).
    var waveRunDailyEggEarned: String { "오늘의 클리어 알 보상을 받았습니다!" }
    var gymBadgeEarned: String { "배지 획득" }
    func gymNeedsMorePokemon(_ count: Int) -> String {
        "체육관은 \(count)마리로 도전해요 — 포켓몬이 부족합니다."
    }
    func gymNeedsHigherLevel(_ level: Int) -> String {
        "도전 팀 전원이 Lv.\(level) 이상이어야 합니다."
    }
    var gymLevelGateTitle: String { "레벨 부족" }

    // MARK: 공유 체육관(쟁탈전) — 카탈로그 체육관과 이름이 겹치지 않게 "쟁탈전"으로 구분한다.

    var playerGymTitle: String { "체육관 쟁탈전" }
    var playerGymSubtitle: String {
        "이긴 사람이 관장 · 관장은 방어팀 4마리를 세운다"
    }
    var gymDeployedBadge: String { "체육관 방어 중" }
    var playerGymOpen: String { "체육관 열기" }
    var playerGymSearching: String { "체육관 검색 중…" }
    var playerGymDiscoveryOff: String {
        "근거리 탐색이 꺼져 있습니다."
    }
    var playerGymDiscoveryOffHint: String {
        "설정에서 LAN 배틀 신청 받기를 켜면 체육관을 찾을 수 있습니다."
    }
    var playerGymAlreadyOpen: String {
        "이미 열린 체육관이 있습니다. 그곳에 도전하세요."
    }
    var playerGymChallenge: String { "도전" }
    var playerGymSpectate: String { "관전" }
    var playerGymResign: String { "관장 그만두기" }
    var playerGymDefenseTeam: String { "방어팀" }
    var playerGymUsesAI: String { "AI 에게 맡기기" }
    var playerGymAIHint: String {
        "앱이 켜져 있는 동안에만 방어합니다."
    }
    /// 방 참가가 프로토콜 차이로 거절될 때. **구버전 상대의 화면에 그대로 뜨는 문구**라
    /// "안 맞는다" 로 끝내지 않고 무엇을 해야 하는지까지 적는다.
    var gymVersionMismatch: String {
        "앱 버전이 달라 참가할 수 없습니다. 최신 버전으로 업데이트해 주세요."
    }
    // MARK: LAN 협동 레이드 (#80)

    var raidTitle: String { "협동 레이드" }
    var raidTodaysBoss: String { "오늘의 보스" }
    var raidBossLoadFailed: String {
        "오늘의 보스를 불러오지 못했습니다. 잠시 뒤 다시 시도해 주세요."
    }
    /// 게스트가 오늘의 보스와 다른 편성을 받았을 때. **정직한 버전 차이로도 뜬다** — 상대가
    /// 자정을 갓 넘겼거나 시간대가 다르면 날짜 키가 갈린다. 그래서 "조작"이라고 쓰지 않는다.
    var raidBossMismatch: String {
        "이 방의 보스가 오늘의 보스와 다릅니다. 날짜가 갈렸거나 앱 버전이 다를 수 있어요."
    }
    func raidRoomOpenedTitle(tier: Int) -> String {
        "⚔️ \(tier)★ 레이드가 열렸어요"
    }
    func raidRoomOpenedBody(trainer: String) -> String {
        "\(trainer) 님이 같은 네트워크에서 모집 중입니다."
    }
    func raidTierLabel(_ tier: Int, runners: Int) -> String {
        "\(tier)★ · \(runners)인 권장"
    }
    var raidPickMon: String { "들고 갈 포켓몬" }
    /// 안 고른 사용자에게 **실제로 나가는 개체를 이름으로** 말한다 — 피커가 선택 사항이라 티어
    /// 버튼이 잠기지 않고, 그러면 아무것도 안 고른 채 방이 열린다. 무엇이 나갔는지는 그때 알면 늦다.
    ///
    /// "동행" 으로 못 박으면 안 된다. 동행이 알이거나 체육관을 지키는 중이면 `battleFacadeMon` 은
    /// 박스 개체를 돌려주는데, 하필 그 두 경우가 이 피커를 만든 이유다.
    ///
    /// **다른 대전에도 적용된다는 사실을 반드시 말한다.** 여기서 고르는 값은 레이드 전용이 아니라
    /// 대표 포켓몬이다 — 레이드 화면에서 누른 것이 체육관·토너먼트의 출전까지 바꾸는데 화면이
    /// 입을 다물면, 다음에 진 대전의 원인을 찾을 단서가 없다.
    func raidPickMonHint(_ runner: String) -> String {
        "고르지 않으면 나가는 개체는 \(runner)입니다. 고르면 대표 포켓몬이 바뀌어 다른 대전에도 나갑니다."
    }
    var raidTurnsLeft: String { "남은 턴" }
    var raidContribution: String { "기여도" }
    var raidRewardBase: String { "기본" }
    var raidRewardSurvivors: String { "생존" }
    var raidAlreadyPaidToday: String {
        "이번 오전/오후 레이드 보상은 이미 받았습니다 — 계속 참가할 수는 있어요."
    }
    /// 티어 카드의 완료 배지 — `raidRewardClaimedToday(tier:)` 를 그대로 보여준다.
    var raidRewardClaimedBadge: String { "완료" }
    var raidRewardOpenBadge: String { "미완료" }
    var raidTurnCapReached: String {
        "턴이 다 됐습니다 — 보스가 버텼어요."
    }
    /// 턴이 남았는데 진 판 — 진 이유가 화력이 아니라 생존이다. 두 패배를 같은 문구로 덮으면
    /// 사용자가 "더 빨리 때리자"로 배우는데 필요한 건 티어를 낮추거나 사람을 모으는 것이다.
    var raidPartyWiped: String {
        "파티가 전멸했습니다 — 티어를 낮추거나 사람을 모아 보세요."
    }
    /// 5★ 는 부화 창 안에서만 열린다.
    var raidHatchClosed: String {
        "지금은 5★ 부화 시간이 아닙니다. 다음 부화 시각을 기다려 주세요."
    }
    var raidHostLeft: String {
        "방장이 나가 레이드가 끝났습니다. 다시 열어 주세요."
    }
    var raidCaughtTitle: String { "🎉 보스를 잡았다" }
    /// **어디로 갔는지 말한다.** 동행이 비어 있으면 잡은 보스가 바로 동행이 되는데(`catchRaidBoss`),
    /// 그때도 "박스" 라고 말하면 사용자는 빈 박스를 열고 보상이 사라졌다고 판단한다.
    func raidCaughtBody(_ name: String, toBox: Bool) -> String {
        toBox ? "\(name)이(가) 박스에 들어왔어요."
              : "\(name)이(가) 새 동행이 됐어요."
    }
    /// 결과창 — 내가 뽑혔을 때. 잡힌 개체가 어디로 갔는지 말해 준다(박스를 안 열면 안 보인다).
    func raidCaughtByMe(_ name: String, toBox: Bool) -> String {
        toBox ? "추첨에 뽑혀 \(name)을(를) 데려왔다 — 박스에 있어요."
              : "추첨에 뽑혀 \(name)을(를) 데려왔다 — 새 동행이 됐어요."
    }
    /// 결과창 — 남이 뽑혔을 때. 아무 말도 안 하면 "나만 못 받았다" 로 읽힌다.
    func raidCaughtByOther(trainer: String, name: String) -> String {
        "\(trainer) 님이 추첨에 뽑혀 \(name)을(를) 데려갔어요."
    }
    /// 오늘의 한 마리를 이미 데려온 판. **불러오기 실패와 갈라 둔다** — 그 문구는 "오늘 다시 도전할
    /// 수 있어요" 로 끝나는데, 이 판에서는 그게 거짓이다.
    /// 정산표 — 혼자 돈 판. **말 안 하면 `+0 ✨` 세 줄이 계산 오류로 읽힌다**(하루 한 번 게이트를
    /// 말해 주는 것과 같은 이유). 지급이 0 이 아니라 그쪽 문구는 안 뜨는 자리다.
    var raidSoloSettlement: String {
        "혼자 돈 판은 기본급만 나가요 — 기여·남은 턴·생존 보너스는 2명 이상부터예요."
    }
    var raidCatchAlreadyToday: String {
        "오늘은 이미 보스를 데려왔어요 — 포획은 하루 한 마리예요."
    }
    var raidCatchFailed: String {
        "보스 정보를 불러오지 못해 데려오지 못했어요 — 오늘 다시 도전할 수 있어요."
    }
    var raidNextHatch: String { "다음 5★ 부화" }
    func raidHatchSoonTitle(minutes: Int) -> String {
        "⏰ \(minutes)분 뒤 5★ 레이드"
    }
    var raidHatchSoonBody: String {
        "같은 네트워크의 트레이너와 모일 시간이에요."
    }
    var raidNotificationsLabel: String {
        "레이드 알림"
    }
    var raidNotificationsHint: String {
        "5★ 부화 15분 전과 근처에서 레이드 방이 열릴 때 알려요."
    }

    var playerGymUpdateRequired: String {
        "앱을 업데이트해 주세요 — 더 새로운 체육관이 열려 있어 도전도 개설도 할 수 없습니다."
    }
    /// 이미 관장인 사람에게는 "개설도 못 한다" 가 틀린 말이다 — 체육관은 돌고 있다. 대신 지금
    /// 무엇이 막혔고(새 버전 도전자) 무엇이 곧 일어나는지(재시작 시 자리 양보)를 말한다.
    var playerGymUpdateRequiredAsLeader: String {
        "앱이 오래됐습니다. 새 버전 트레이너는 도전할 수 없고, 앱을 다시 켜면 관장 자리를 넘기게 됩니다 — 업데이트해 주세요."
    }
    var playerGymPeerNeedsUpdate: String {
        "상대 트레이너의 앱이 오래됐습니다 — 업데이트해야 도전할 수 있습니다."
    }
    var playerGymLeaveAndRetry: String {
        "나가서 다시 시도"
    }
    var playerGymTakeOverFromAI: String { "직접 싸우기" }
    var playerGymHandBackToAI: String { "다시 AI 에게" }
    var playerGymTakeOverNextTurn: String {
        "다음 턴부터 내가 고릅니다. 이번 턴 행동은 AI 가 이미 냈습니다."
    }
    var playerGymBusyElsewhere: String {
        "체육관 관장인 동안은 참가할 수 없습니다."
    }
    var playerGymLeaderLeft: String {
        "관장이 이탈했습니다 — 체육관을 이어받으시겠습니까?"
    }
    var playerGymTakeOver: String { "이어받기" }
    var playerGymNotReady: String { "준비 중" }
    func playerGymSetupCountdown(_ text: String) -> String {
        "\(text) 안에 방어팀 4마리를 세우지 않으면 관장 자격을 잃습니다."
    }
    func playerGymCooldownRemaining(_ text: String) -> String {
        "다시 도전하기까지 \(text)"
    }
    func playerGymLeaderLabel(_ name: String) -> String {
        "관장 \(name)"
    }
    /// "현우 - 25분째 유지중" — 목록에서 접속 없이 보이는 한 줄.
    func playerGymTenure(_ name: String, _ duration: String) -> String {
        "\(name) — \(duration)째 유지중"
    }
    /// 재임 기간 표기. 한 시간이 안 되면 분만, 넘으면 시간까지 — 초 단위는 이 화면에서 의미가 없다.
    func playerGymDuration(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)분" }
        let hours = minutes / 60
        let rest = minutes % 60
        guard rest > 0 else { return "\(hours)시간" }
        return "\(hours)시간 \(rest)분"
    }
    var playerGymRejectedBusy: String {
        "관장이 다른 도전을 받는 중입니다."
    }
    var playerGymRejectedNotReady: String {
        "관장이 아직 방어팀을 세우지 않았습니다."
    }
    func playerGymDefenseReward(_ amount: Int) -> String {
        let value = GameNumberFormatter.compact(amount)
        return "방어 성공! ⭐ \(value)"
    }
    var playerGymDefenseCapped: String {
        "오늘 방어 보상을 모두 받았습니다."
    }
    func playerGymDefenseLedger(_ earned: Int, _ cap: Int) -> String {
        "오늘 방어 보상 \(GameNumberFormatter.compact(earned)) / \(GameNumberFormatter.compact(cap))"
    }
    func playerGymStreak(_ count: Int) -> String {
        "\(count)연속 방어 중"
    }
    var playerGymDefenseLogTitle: String {
        "도전 기록"
    }
    var playerGymDefenseLogEmpty: String {
        "아직 아무도 도전하지 않았습니다."
    }
    var playerGymDefended: String { "방어" }
    var playerGymYielded: String { "자리 내줌" }
    /// "25분 전" — 기록 한 줄의 시각 표기.
    func playerGymTimeAgo(_ duration: String) -> String {
        "\(duration) 전"
    }
    var playerGymBecameLeader: String { "체육관 관장이 되었습니다!" }
    var playerGymLostLeadership: String { "관장 자리를 내주었습니다." }
    func gymBadgeCount(_ earned: Int, _ total: Int) -> String {
        "배지 \(earned) / \(total)"
    }
    func gymLeaderLevel(_ level: Int) -> String {
        "관장 Lv.\(level)"
    }
    var gymChallenge: String { "도전" }
    var gymRematch: String { "재도전" }
    var gymCleared: String { "클리어" }

    /// 최종형인데 아직 졸업 못 하는 개체의 파트너 카드 한 줄 — 남은 관문이 레벨뿐임을 알린다.
    /// "Lv.N 에 진화" 가 사라진 그 자리에 들어간다.
    func graduatesAtLevel(_ level: Int) -> String {
        "Lv.\(level)에 졸업"
    }

    /// 돌·교환 진화 종의 파트너 카드 한 줄 — 레벨 진화의 "Lv.N 에 진화" 자리에 대신 들어간다.
    /// 상점에서 사서 가방에서 쓴다는 것까지는 담지 않는다(caption 한 줄) — 이름만 알면 상점에서 찾는다.
    func evolutionNeedsItem(_ item: String) -> String {
        "\(item) 필요"
    }

    /// 아이템 표시명 — species 처럼 공식 현지명.
    func itemName(_ kind: ItemKind) -> String {
        switch kind {
        case .rareCandy: return t("이상한 사탕", "Rare Candy", "ふしぎなアメ")
        case .mint:      return t("민트", "Mint", "ミント")
        case .teraShard: return t("테라피스", "Tera Shard", "テラピース")
        case .lifeOrb: return t("생명의구슬", "Life Orb", "いのちのたま")
        case .focusSash: return t("기합의띠", "Focus Sash", "きあいのタスキ")
        case .leftovers: return t("먹다남은음식", "Leftovers", "たべのこし")
        case .shinyCharm: return t("이로치 부적", "Shiny Charm", "ひかるおまもり")
        case .linkingCord: return t("연결의끈", "Linking Cord", "つながりのヒモ")
        case .fireStone: return t("불꽃의돌", "Fire Stone", "ほのおのいし")
        case .waterStone: return t("물의돌", "Water Stone", "みずのいし")
        case .thunderStone: return t("천둥의돌", "Thunder Stone", "かみなりのいし")
        case .leafStone: return t("리프의돌", "Leaf Stone", "リーフのいし")
        case .iceStone: return t("얼음의돌", "Ice Stone", "こおりのいし")
        case .moonStone: return t("달의돌", "Moon Stone", "つきのいし")
        case .sunStone: return t("태양의돌", "Sun Stone", "たいようのいし")
        case .shinyStone: return t("빛의돌", "Shiny Stone", "ひかりのいし")
        case .duskStone: return t("어둠의돌", "Dusk Stone", "やみのいし")
        case .dawnStone: return t("각성의돌", "Dawn Stone", "めざめいし")
        // 지닌물건 진화 아이템(#89) — 본가 공식 현지명 그대로.
        case .kingsRock: return "왕의징표석"
        case .metalCoat: return "금속코트"
        case .dragonScale: return "용의비늘"
        case .upgrade: return "업그레이드"
        case .dubiousDisc: return "괴상한패치"
        case .deepSeaTooth: return "심해의이빨"
        case .deepSeaScale: return "심해의비늘"
        case .protector: return "프로텍터"
        case .electirizer: return "에레키부스터"
        case .magmarizer: return "마그마부스터"
        case .reaperCloth: return "영계의천"
        case .razorClaw: return "예리한손톱"
        case .razorFang: return "예리한이빨"
        case .prismScale: return "아름다운비늘"
        case .ovalStone: return "둥근돌"
        case .heartScale: return "하트비늘"
        case .roomBed: return "별빛 침대"
        case .roomTable: return "추억 테이블"
        case .roomLamp: return "달빛 램프"
        case .lovelyVanity: return "러블리 화장대"
        case .lovelySofa: return "러블리 소파"
        case .lovelyHeartLamp: return "하트 램프"
        // 6~9세대 진화 아이템 — PokéAPI `itemnames` 의 공식 현지명 그대로.
        case .sachet: return "향기주머니"
        case .whippedDream: return "휘핑팝"
        case .tartApple: return "새콤한사과"
        case .sweetApple: return "달콤한사과"
        case .syrupyApple: return "꿀맛사과"
        case .crackedPot: return "깨진포트"
        case .chippedPot: return "이빠진포트"
        case .unremarkableTeacup: return "범작찻잔"
        case .masterpieceTeacup: return "걸작찻잔"
        case .scrollOfDarkness: return "악의 족자"
        case .scrollOfWaters: return "물의 족자"
        case .blackAugurite: return "검은휘석"
        case .peatBlock: return "피트블록"
        case .auspiciousArmor: return "축복받은갑옷"
        case .maliciousArmor: return "저주받은갑옷"
        case .metalAlloy: return "복합금속"
        case .retroArcade: return "레트로 오락기"
        case .retroRadio: return "레트로 라디오"
        case .retroTV: return "레트로 TV"
        case .naturePlant: return "숲 화분"
        case .natureBench: return "나무 벤치"
        case .natureLantern: return "이끼 랜턴"
        }
    }
    func outfitSlotName(_ slot: OutfitSlot) -> String {
        switch slot {
        case .hat: return "모자"
        case .hair: return "머리"
        case .top: return "상의"
        case .bottom: return "하의"
        case .accessory: return "소품"
        }
    }
    func outfitItemName(_ item: OutfitItem) -> String {
        switch item {
        case .capRed: return "빨간 캡"
        case .strawHat: return "밀짚모자"
        case .hairBob: return "단발"
        case .hairPony: return "포니테일"
        case .jacketBlue: return "파란 재킷"
        case .teeWhite: return "흰 티셔츠"
        case .shortsKhaki: return "반바지"
        case .backpack: return "백팩"
        case .hairMessy: return "흐트러진 머리"
        case .cloakWorn: return "낡은 망토"
        case .bootsLong: return "탐험 부츠"
        case .helmetExplorer: return "탐험가 헬멧"
        }
    }
    var outfitTitle: String { t("꾸미기", "Wardrobe", "きせかえ") }
    var outfitWardrobe: String { t("꾸미기", "Wardrobe", "きせかえ") }
    var outfitTakeOff: String { t("벗기", "Take off", "はずす") }
    var outfitLocked: String { t("업적으로 해금", "Unlock via achievements", "実績で解放") }
    /// 아이템 설명 — 가방과 상점이 읽는다. **`default:` 를 두지 않는다**: 진화가 아닌 새 아이템이
    /// 진화 갈래로 흘러가면 설명이 빈 문자열이 된다(`ItemKind.bagUse` 가 있는 이유).
    func itemDescription(_ kind: ItemKind) -> String {
        switch kind.bagUse {
        case .candy:
            let xp = GameNumberFormatter.compact(RareCandy.xp)   // 상수에서 파생(하드코딩 드리프트 방지)
            return "현재 포켓몬의 경험치를 \(xp) 올려줘요."
        case .mint:
            return t("현재 포켓몬의 성격을 랜덤으로 바꿔줘요.",
                     "Randomly changes your Pokémon's nature.",
                     "ポケモンのせいかくをランダムに変えます。")
        case .heartScale:
            return t("지금까지 배울 수 있었던 기술 하나를 다시 떠올려요. 기술이 4개면 하나를 잊어요.",
                     "Recalls one move it could have learned by now. With four moves, one is forgotten.",
                     "これまでに覚えられた技をひとつ思い出します。技が4つなら1つ忘れます。")
        case .teraShard:
            return t("테라스탈했을 때 되는 타입을 랜덤으로 바꿔줘요. 대전에서만 쓰이는 타입이에요.",
                     "Randomly changes the type it becomes when it Terastallizes. It only matters in battle.",
                     "テラスタルしたときのタイプをランダムに変えます。対戦でのみ意味があります。")
        case .heldItem:
            // 문구가 아이템마다 갈린다 — 셋을 한 줄로 뭉개면 무엇을 사는지 화면에서 알 수 없다.
            // 수치는 상수에서 파생하지 않는다(분모를 문장에 녹여야 자연스럽고, 어긋나면
            // `HeldItemTests` 가 아니라 사람이 읽는다) — 상수를 바꾸면 이 세 줄도 함께 본다.
            switch kind.heldBattleEffect {
            case .lifeOrb:
                return t("대전에서 기술 데미지가 1.3배가 돼요. 대신 턴이 끝날 때 최대 HP의 1/10을 잃어요.",
                         "In battle, move damage becomes 1.3×. In exchange it loses 1/10 of its max HP each turn.",
                         "対戦で技のダメージが1.3倍になります。代わりに毎ターン最大HPの1/10を失います。")
            case .focusSash:
                return t("체력이 가득할 때 쓰러질 한 방을 HP 1로 버텨요. 대전 한 번에 한 번만이에요.",
                         "At full HP it survives a knockout hit with 1 HP left. Once per battle.",
                         "HPが満タンのとき、倒れる一撃をHP1で耐えます。対戦で一度だけです。")
            case .leftovers:
                return t("대전에서 턴이 끝날 때마다 최대 HP의 1/16을 회복해요.",
                         "In battle it restores 1/16 of its max HP at the end of each turn.",
                         "対戦で毎ターンの終わりに最大HPの1/16を回復します。")
            case nil:
                // 지닌물건 갈래인데 효과가 없는 조합 — `bagUse` 가 둘을 함께 정하므로 도달 불가다.
                return ""
            }
        case .passive:
            return t("보유하면 이로치 포켓몬이 태어날 확률이 올라가요.",
                     "While owned, raises the chance of hatching a shiny.",
                     "持っていると色違いが生まれる確率が上がります。")
        case .furniture:
            return t("미니룸에 배치하는 가구예요. 성장이나 보상에는 영향을 주지 않아요.",
                     "Furniture for your mini room. It never affects growth or rewards.",
                     "ミニルームに置く家具です。成長や報酬には影響しません。")
        case .evolutionItem:
            // 진화 아이템 설명은 규칙에서 갈린다 — 케이스를 40개 나열하면 새 아이템을 넣을 때 빠뜨린다.
            switch kind.evolutionRule {
            case .plainTrade:
                return "통신교환으로 진화하는 포켓몬을 진화시켜요."
            case .useItem:
                return "이 돌에 반응하는 포켓몬을 진화시켜요."
            case .heldItem:
                return "이 도구를 지녀야 진화하는 포켓몬을 진화시켜요."
            case nil:
                // 진화 갈래인데 규칙이 없는 조합 — `bagUse` 가 둘을 함께 정하므로 도달 불가다.
                return ""
            }
        }
    }
    /// 가방 사용 컨트롤의 효과 힌트 — 민트("성격 랜덤 변경", 사탕의 "+XP" 자리).
    var mintEffectHint: String { t("성격 랜덤 변경", "Random nature", "せいかくランダム変更") }
    /// 지닌물건 3종의 효과 힌트 — 가방 사용 컨트롤의 "+XP" 자리다. 아이템마다 갈린다(무엇이
    /// 붙는지가 이 물건의 전부라, 셋을 "지니게 하기" 한 줄로 뭉개면 고를 근거가 사라진다).
    func heldItemEffectHint(_ kind: ItemKind) -> String {
        switch kind.heldBattleEffect {
        case .lifeOrb:   return t("데미지 ×1.3 / 자해", "1.3× damage / recoil", "ダメージ1.3倍 / 反動")
        case .focusSash: return t("만피에서 한 방 버티기", "Survive one hit at full HP", "満タンで一撃耐える")
        case .leftovers: return t("턴 끝 HP 회복", "Heals each turn", "ターン終わりに回復")
        case nil:        return ""   // `bagUse` 가 둘을 함께 정하므로 도달 불가다
        }
    }
    /// 이미 지니고 있는 물건을 또 지니게 할 수는 없다 — 가방이 비활성 사유로 쓴다. "포켓몬이
    /// 필요해요" 로 뭉개면 재고도 동행도 있는데 거절당한 사용자가 이유를 알 수 없다.
    var heldItemAlreadyHeld: String { t("이미 지니고 있어요", "Already held", "すでに持っています") }
    /// 테라피스(#3) — 성격과 달리 대전 성능을 바꾸므로 문구도 "테라 타입" 을 밝힌다.
    var teraShardEffectHint: String { t("테라 타입 랜덤 변경", "Random Tera type", "テラスタイプランダム変更") }
    /// 바뀐 타입을 알리는 줄 — 어떤 타입이 됐는지가 이 아이템의 결과 전부다.
    func teraShardUsed(_ type: PokemonType) -> String {
        let name = type.name(lang)
        return t("테라 타입이 \(name)(으)로 바뀌었어요!",
                 "Its Tera type changed to \(name)!",
                 "テラスタイプが\(name)に変わりました！")
    }

    // MARK: 하트비늘 (기술 다시 배우기 — #97)
    var heartScaleEffectHint: String { "기술 다시 배우기" }
    var relearnHeader: String { "기술을 다시 떠올릴까요?" }
    var relearnPickTitle: String { "떠올릴 기술을 고르세요." }
    var relearnLoading: String { "떠올릴 수 있는 기술을 찾고 있어요…" }
    var relearnEmpty: String { "지금 떠올릴 수 있는 기술이 없어요." }
    var relearnClose: String { "닫기" }

    // MARK: 상점 (재화 = 별의조각)
    var shop: String { "상점" }
    var spendableTokens: String { "보유 별의조각" }
    var shopHint: String { "모험에서 얻은 별의조각으로 아이템을 살 수 있어요." }
    var buy: String { "구매" }
    func buyConfirm(_ name: String) -> String { "\(name) 구매할까요?" }
    /// 여러 개를 한 번에 살 때의 확인 문구 — 수량과 합계를 함께 보여 준다. 1개면 기존 문구 그대로.
    func buyConfirm(_ name: String, quantity: Int, total: String) -> String {
        guard quantity > 1 else { return buyConfirm(name) }
        return "\(name) \(quantity)개를 ⭐\(total)에 구매할까요?"
    }
    var buyMax: String { "최대" }
    var notEnoughTokens: String { "별의조각이 부족해요" }
    func ownedCount(_ n: Int) -> String { "보유 ×\(n)" }
    var shopPriceLabel: String { "가격" }
    var ownedAlready: String { "보유 중" }
    var shinyCharmEffectHint: String { "이로치 확률 ↑ · 적용 중" }
    // 알 (리롤) — tier = 보증 등급 하한(nil = 보증 없는 기본 알).
    // 이름은 `rarityLabel(r) + " 알"` 식 조합으로 만들지 않는다 — 등급마다 자연스러운 표기가
    // 달라서, 조합으로 만들면 어느 등급에선가 어색해진다. 등급별로 이름을 그대로 적는다.
    func eggName(_ tier: Rarity?) -> String {
        switch tier {
        case nil, .common?: return "알"
        case .uncommon?:  return "고급 알"
        case .rare?:      return "희귀 알"
        case .legendary?: return "전설 알"   // 미판매(FreshEgg.shopTiers)
        }
    }
    func eggDescription(_ tier: Rarity?) -> String {
        guard let tier, tier != .common else {
            return "소유 포켓몬은 그대로 두고 알을 1개 받아요."
        }
        let r = rarityLabel(tier)
        return "지금 포켓몬을 놓아주고 \(r) 이상이 확정으로 나오는 알을 받아요."
    }
    /// 인큐베이션 중 표시하는 보증 배지 — 어떤 알을 품고 있는지 한 줄로.
    func eggGuaranteeHint(_ tier: Rarity) -> String {
        let r = rarityLabel(tier)
        return "\(r) 이상 확정"
    }
    func eggConfirm(_ monName: String, _ eggName: String) -> String {
        "\(monName)을(를) 놓아주고 \(eggName)(으)로 바꿀까요?"
    }
    var freshEggShinyWarning: String { "⚠️ 이로치 포켓몬이에요! 정말 놓아줄까요?" }
    var freshEggDiscardShiny: String { "이로치 놓아주기" }

    // MARK: 사탕 획득 알림 (일일 보상)
    func notifCandyTitle(item: String, count: Int) -> String {
        "🍬 \(item) \(count)개를 받았어요!"
    }
    var notifDailyCandyBody: String {
        "오늘의 첫 만남 보상이에요 — 포켓몬에게 써서 진화시켜 보세요!"
    }
}
