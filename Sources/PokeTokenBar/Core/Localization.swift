import Foundation

/// 앱 전체 UI 문자열 — 언어별. 단일 소스(AppLanguage)에서 파생한다.
/// 뷰는 `companion.l.<key>` 로 접근하며, language 변경 시 @Observable 로 자동 재렌더된다.
/// 포켓몬 이름은 PokéAPI 다국어 데이터(EvoLine.localizedName)에서 별도로 온다.
struct L {
    let lang: AppLanguage
    init(_ lang: AppLanguage) { self.lang = lang }

    /// 세 언어를 한자리에서 고른다. 뷰에서도 직접 쓴다. 일회성 문구까지 이름 붙인 프로퍼티로
    /// 올리면 이 파일이 뒤덮이고, 그걸 피하려다 두 갈래 삼항이 115곳 쌓여 일본어 사용자에게
    /// 영어가 나갔다. 인자 세 개가 필수라 한 칸을 비우면 컴파일이 막는다. 두 화면이 같은 문구를
    /// 쓰면 그때 프로퍼티로 승격한다. 가드는 `LanguageSplitGuardTests`.
    func t(_ ko: String, _ en: String, _ ja: String) -> String {
        switch lang {
        case .ko: return ko
        case .en: return en
        case .ja: return ja
        }
    }

    // MARK: 탭
    var home: String { t("홈", "Home", "ホーム") }
    /// 최상위 탭 라벨. **하위 세그먼트(도감 | 업적)의 상위어여야 한다** — "도감" 이던 때는 도감 탭
    /// 안에 다시 "도감" 세그먼트가 보였다. 도감 쪽은 `dexTitle` 을 쓴다.
    /// 이름을 늘려도 상단 피커 폭은 그대로다 — 계측 ko 330pt · en 445pt(변화 없음) · ja 445pt
    /// (옛 "ポケモン図鑑" 455pt 보다 10pt 좁다). en·ja 는 다섯 라벨이 이미 콘텐츠 폭 332pt 를 넘어
    /// macOS 가 압축하는 기존 상태다 — **더 늘리지 않는다**.
    var collection: String { t("컬렉션", "Collection", "コレクション") }
    var battle: String { t("배틀", "Battle", "バトル") }

    // MARK: 배틀
    var battleMyPokemon: String { t("내 포켓몬", "My Pokémon", "自分のポケモン") }
    var battleNeedHatch: String { t("알은 배틀할 수 없어요 — 먼저 부화시키세요.", "Eggs can't battle — hatch first.", "タマゴはバトルできません — まず孵化させましょう。") }
    var battleStatsFailed: String { t("스탯을 불러오지 못했어요 — 네트워크 확인 후 다시 시도하세요.", "Couldn't load stats — check your network and retry.", "ステータスを取得できません — 通信を確認して再試行してください。") }
    var battleDraw: String { t("무승부!", "It's a draw!", "引き分け！") }
    var battleSpectatorFinished: String { t("관전한 배틀이 끝났어요.", "The battle you watched is over.", "観戦したバトルが終わりました。") }
    var battleSuperEffective: String { t("효과가 굉장했다!", "It's super effective!", "こうかはばつぐんだ！") }
    var battleNotVeryEffective: String { t("효과가 별로인 듯하다…", "It's not very effective…", "こうかはいまひとつのようだ…") }
    var battleCritical: String { t("급소에 맞았다!", "A critical hit!", "きゅうしょにあたった！") }
    /// 재생 속도 설정 — 끄기는 저전력·접근성 때문에 반드시 고를 수 있어야 한다.
    var battleReplaySpeedLabel: String { t("배틀 연출", "Battle playback", "バトル演出") }
    func battleReplaySpeedName(_ speed: ReplaySpeed) -> String {
        switch speed {
        case .normal: return t("보통", "Normal", "ふつう")
        case .fast:   return t("빠름", "Fast", "はやい")
        case .off:    return t("끄기", "Off", "オフ")
        }
    }
    func battleLv(_ n: Int) -> String { "Lv.\(n)" }
    func battleTrainerLabel(_ trainer: String) -> String {
        t("\(trainer)의 포켓몬", "\(trainer)'s Pokémon", "\(trainer)のポケモン")
    }

    // MARK: 배틀 (네트워크 대전)
    var battleNearby: String { t("근처의 트레이너", "Nearby trainers", "近くのトレーナー") }
    var battleNoPeers: String {
        t("같은 네트워크에서 대전 상대를 찾는 중… 친구도 앱을 켜야 보여요.",
          "Searching this network for opponents… your friend needs the app running too.",
          "同じネットワークで対戦相手を探しています… 相手もアプリを起動している必要があります。")
    }
    var battleChallengeButton: String { t("대결 신청", "Challenge", "対戦を申し込む") }
    /// 구버전 상대는 랭크를 광고하지 않는다. 최하위 티어와 구별돼야 하므로 빈칸이 아니라 문구다.
    var battleRankUnknown: String { t("랭크 정보 없음", "Rank unavailable", "ランク情報なし") }
    var battleWaitingAccept: String { t("수락 대기 중…", "Waiting for accept…", "承諾を待っています…") }
    var battleCancel: String { t("취소", "Cancel", "キャンセル") }
    var battleIncomingTitle: String { t("배틀 신청이 왔습니다!", "Incoming battle challenge!", "バトルの申し込みが来ました！") }
    var battleAccept: String { t("수락", "Accept", "承諾") }
    var battleDecline: String { t("거절", "Decline", "拒否") }
    var battleRulesMismatch: String {
        t("상대와 앱 버전이 달라 대전할 수 없어요 — 양쪽 다 업데이트해 주세요.",
          "Versions don't match — both sides need to update before battling.",
          "アプリのバージョンが違うため対戦できません — 両方とも更新してください。")
    }
    var battleDeclined: String { t("상대가 거절했어요.", "They declined.", "相手に断られました。") }
    var battleConnectionLost: String { t("연결이 끊어졌어요.", "Connection lost.", "接続が切れました。") }
    var battleChallengeTimedOut: String { t("신청 시간이 초과됐어요.", "The challenge timed out.", "対戦の申請時間が切れました。") }
    func battleChallengeTimeRemaining(_ seconds: Int) -> String {
        t("수락까지 \(seconds)초", "\(seconds)s to accept", "承諾まで \(seconds)秒")
    }
    func menuBarBattleChallengeSent(_ peer: String) -> String { t("\(peer) 응답 대기", "Waiting for \(peer)", "\(peer)の応答待ち") }
    func menuBarBattleChallengeReceived(_ peer: String) -> String { t("\(peer) 수락 대기", "Accept \(peer)'s challenge", "\(peer)の承諾待ち") }
    func menuBarBattling(_ peer: String, isMyTurn: Bool) -> String {
        let koTurn = isMyTurn ? "내 턴" : "상대 턴"
        let enTurn = isMyTurn ? "Your turn" : "Opponent's turn"
        let jaTurn = isMyTurn ? "自分のターン" : "相手のターン"
        return t("\(peer)와 대결 중 · \(koTurn)", "Battling \(peer) · \(enTurn)", "\(peer)と対戦中 · \(jaTurn)")
    }
    /// 랭크전 판돈을 못 낼 때 — 세 경로(수신 수락·수락 응답·개시 에스크로)가 같은 문구를 쓴다.
    var battleStakeShort: String {
        t("랭크전 판돈이 부족해요.", "Not enough Star Pieces for the ranked stake.",
          "ランク戦の賭け星のかけらが足りません。")
    }
    func battleNeedsPokemon(_ count: Int) -> String {
        t("\(count) vs \(count) 대결에는 포켓몬이 \(count)마리 필요해요.",
          "You need \(count) Pokémon for a \(count) vs \(count) battle.",
          "\(count)対\(count)の対戦にはポケモンが\(count)匹必要です。")
    }
    var battleYourTurn: String { t("기술 또는 교체를 선택하세요", "Choose a move or switch", "わざか交代を選んでください") }
    var battleWaitingOpponent: String { t("상대가 행동을 고르는 중…", "Opponent is choosing…", "相手が行動を選んでいます…") }
    var battleForfeit: String { t("기권", "Forfeit", "降参") }
    var battleChatTitle: String { t("채팅", "Chat", "チャット") }
    var battleChatPlaceholder: String { t("메시지 입력", "Type a message", "メッセージを入力") }
    var battleChatSend: String { t("전송", "Send", "送信") }
    var battleChatUnavailable: String {
        t("상대 앱 버전에서는 채팅을 지원하지 않습니다.", "Chat is unavailable with this app version.", "相手のアプリのバージョンではチャットを利用できません。")
    }
    func battleChatNewMessages(_ count: Int) -> String {
        t("새 메시지 \(count)개", "\(count) new messages", "新着メッセージ \(count)件")
    }
    var battleSwitch: String { t("교체", "Switch", "こうたい") }
    var battleMissed: String { t("빗나갔다!", "It missed!", "はずれた！") }
    var battleNoEffect: String { t("효과가 없었다…", "It had no effect…", "こうかがないようだ…") }
    var battleOppForfeited: String { t("상대가 기권했어요 — 승리!", "Opponent forfeited — you win!", "相手が降参しました — 勝ち！") }
    var battleYouForfeited: String { t("기권했어요.", "You forfeited.", "降参しました。") }
    var battleWon: String { t("이겼다! 🏆", "You won! 🏆", "勝った！ 🏆") }
    var battleLost: String { t("졌다…", "You lost…", "負けた…") }
    var battleClose: String { t("확인", "Done", "閉じる") }
    var battleManualHint: String {
        t("자동 탐색이 안 되면(사내망 등) 주소로 직접 연결하세요.",
          "If auto-discovery is blocked (office Wi-Fi etc.), connect by address.",
          "自動検出できない場合（社内ネットワーク等）はアドレスで直接接続。")
    }
    var battleMyAddress: String { t("내 주소", "My address", "自分のアドレス") }
    var battleManualPlaceholder: String { t("상대 주소 (예: 10.1.2.3:50628)", "Opponent address (e.g. 10.1.2.3:50628)", "相手のアドレス（例: 10.1.2.3:50628）") }
    var battleBadAddress: String { t("주소 형식이 잘못됐어요 — IP:포트", "Bad address — use IP:port", "アドレス形式が不正です — IP:ポート") }
    var battleKindBrawl: String { t("맞짱", "Brawl", "タイマン") }
    var battleAutoAccept: String { t("신청 자동 수락", "Auto-accept challenges", "自動で承諾") }
    var battleDiscoveryBlocked: String {
        t("자동 탐색이 막혀 있어요 — 시스템 설정 > 개인정보 보호 > 로컬 네트워크에서 허용하거나, 아래 주소로 직접 연결하세요.",
          "Auto-discovery is blocked — allow it in System Settings > Privacy > Local Network, or connect by address below.",
          "自動検出がブロックされています — システム設定 > プライバシー > ローカルネットワークで許可するか、下のアドレスで直接接続してください。")
    }
    func battleTurnLabel(_ n: Int) -> String { t("턴 \(n)", "Turn \(n)", "ターン \(n)") }
    func battleIncomingFrom(_ trainer: String) -> String {
        t("\(trainer)님이 대결을 신청했어요!", "\(trainer) challenged you!", "\(trainer)さんが対戦を申し込みました！")
    }
    var battleChallengeNotifTitle: String { t("배틀 신청이 왔습니다!", "Battle challenge!", "バトルの申し込み！") }
    func battleChallengeNotifBody(_ trainer: String, pokemon: String, level: Int) -> String {
        t("\(trainer) — \(pokemon) Lv.\(level) · 메뉴바에서 수락하세요",
          "\(trainer) — \(pokemon) Lv.\(level) · accept from the menu bar",
          "\(trainer) — \(pokemon) Lv.\(level) · メニューバーから承諾")
    }
    func battleUsedMoveNamed(_ attacker: String, move: String, damage: Int) -> String {
        t("\(attacker)의 \(move)! \(damage) 데미지",
          "\(attacker) used \(move)! \(damage) damage",
          "\(attacker)の\(move)！ \(damage)ダメージ")
    }
    func battleUsedMoveMissed(_ attacker: String, move: String) -> String {
        t("\(attacker)의 \(move)!", "\(attacker) used \(move)!", "\(attacker)の\(move)！")
    }
    /// 기술과 무관하게 깎였을 때 — 상태이상 잔뎀(Phase 2)이 이 문구로 온다.
    func battleTookDamage(_ name: String, damage: Int) -> String {
        t("\(name)은(는) \(damage) 데미지", "\(name) took \(damage) damage", "\(name)は \(damage)ダメージ")
    }
    func battleFainted(_ name: String) -> String {
        t("\(name)은(는) 쓰러졌다!", "\(name) fainted!", "\(name)はたおれた！")
    }

    // MARK: 배틀 (상태이상)

    func battleStatusInflicted(_ name: String, status: Status) -> String {
        switch status {
        case .burn:      return t("\(name)은(는) 화상을 입었다!", "\(name) was burned!", "\(name)は やけどを おった！")
        case .poison:    return t("\(name)은(는) 독에 걸렸다!", "\(name) was poisoned!", "\(name)は どくを あびた！")
        case .toxic:     return t("\(name)은(는) 맹독에 걸렸다!", "\(name) was badly poisoned!", "\(name)は もうどく状態になった！")
        case .paralysis: return t("\(name)은(는) 마비되어 기술이 나오기 어려워졌다!",
                                  "\(name) is paralyzed! It may be unable to move!",
                                  "\(name)は しびれて 技が でにくくなった！")
        case .sleep:     return t("\(name)은(는) 잠들어 버렸다!", "\(name) fell asleep!", "\(name)は 眠ってしまった！")
        case .freeze:    return t("\(name)은(는) 얼어붙었다!", "\(name) was frozen solid!", "\(name)は こおりついた！")
        case .confusion: return t("\(name)은(는) 혼란에 빠졌다!", "\(name) became confused!", "\(name)は 混乱した！")
        case .flinch:    return t("\(name)은(는) 풀죽었다!", "\(name) flinched!", "\(name)は ひるんだ！")
        }
    }

    func battleStatusCured(_ name: String, status: Status) -> String {
        switch status {
        case .burn:            return t("\(name)의 화상이 나았다!", "\(name)'s burn was healed!", "\(name)の やけどが 治った！")
        case .poison, .toxic:  return t("\(name)의 독이 나았다!", "\(name) was cured of its poison!", "\(name)の どくが 治った！")
        case .paralysis:       return t("\(name)의 마비가 풀렸다!", "\(name) was cured of paralysis!", "\(name)の まひが 治った！")
        case .sleep:           return t("\(name)은(는) 잠에서 깨어났다!", "\(name) woke up!", "\(name)は 目を覚ました！")
        case .freeze:          return t("\(name)의 얼음이 녹았다!", "\(name) thawed out!", "\(name)の こおりが とけた！")
        case .confusion:       return t("\(name)의 혼란이 풀렸다!", "\(name) snapped out of its confusion!", "\(name)の 混乱が とけた！")
        case .flinch:          return ""
        }
    }

    /// 그 상태 때문에 이번 턴을 못 썼다. 화상·독은 행동을 막지 않아 마지막 분기가 나올 일은 없지만,
    /// 비워 두면 나중에 상태를 더할 때 조용히 빈 줄이 로그로 나간다.
    func battleCantMove(_ name: String, status: Status) -> String {
        switch status {
        case .paralysis: return t("\(name)은(는) 몸이 저려서 움직일 수 없다!",
                                  "\(name) is paralyzed! It can't move!",
                                  "\(name)は からだが しびれて 動けない！")
        case .sleep:     return t("\(name)은(는) 쿨쿨 잠들어 있다.", "\(name) is fast asleep.", "\(name)は ぐうぐう 眠っている。")
        case .freeze:    return t("\(name)은(는) 얼어붙어서 움직일 수 없다!",
                                  "\(name) is frozen solid!", "\(name)は こおって 動けない！")
        case .confusion: return t("\(name)은(는) 혼란에 빠져 자신을 공격했다!",
                                  "\(name) hurt itself in its confusion!",
                                  "\(name)は わけも わからず 自分を 攻撃した！")
        case .flinch:    return t("\(name)은(는) 풀죽어서 움직일 수 없다!", "\(name) flinched and can't move!", "\(name)は ひるんで 動けない！")
        case .burn, .poison, .toxic:
            return t("\(name)은(는) 움직일 수 없다!", "\(name) can't move!", "\(name)は 動けない！")
        }
    }

    /// 기술이 아닌 데미지 — 원인을 말하지 않으면 로그가 "무엇에 맞았는지" 를 잃는다.
    func battleStatusDamage(_ name: String, damage: Int, cause: DamageCause) -> String {
        switch cause {
        case .burn:      return t("\(name)은(는) 화상 데미지! \(damage)",
                                  "\(name) was hurt by its burn! \(damage)",
                                  "\(name)は やけどの ダメージ！ \(damage)")
        case .poison:    return t("\(name)은(는) 독 데미지! \(damage)",
                                  "\(name) was hurt by poison! \(damage)",
                                  "\(name)は どくの ダメージ！ \(damage)")
        case .toxic:     return t("\(name)은(는) 맹독 데미지! \(damage)",
                                  "\(name) was hurt by the bad poison! \(damage)",
                                  "\(name)は もうどくの ダメージ！ \(damage)")
        case .confusion: return t("\(name)은(는) 혼란으로 \(damage) 데미지",
                                  "\(name) hurt itself in confusion! \(damage)",
                                  "\(name)は 混乱で \(damage)ダメージ")
        case .move:      return battleTookDamage(name, damage: damage)
        case .recoil:    return t("\(name)은(는) 반동으로 \(damage) 데미지", "\(name) was hurt by recoil! \(damage)", "\(name)は 反動で\(damage)ダメージ")
        }
    }

    // MARK: 배틀 (랭크)

    /// 두 단계 이상은 본가처럼 "크게" 가 붙는다 — 한 단계와 두 단계가 화면에서 같으면 랭크가
    /// 얼마나 올랐는지 로그로 알 방법이 없다(배지는 현재 값만 보여 준다).
    func battleStatRose(_ name: String, stat: BattleStat, by amount: Int) -> String {
        let much = amount >= 2
        let subject = Self.koreanSubject(stat.name(.ko))
        return t("\(name)의 \(subject) \(much ? "크게 " : "")올라갔다!",
                 "\(name)'s \(stat.name(.en)) rose\(much ? " sharply" : "")!",
                 "\(name)の \(stat.name(.ja))が \(much ? "ぐーんと " : "")あがった！")
    }

    func battleStatFell(_ name: String, stat: BattleStat, by amount: Int) -> String {
        let much = amount >= 2
        let subject = Self.koreanSubject(stat.name(.ko))
        return t("\(name)의 \(subject) \(much ? "크게 " : "")떨어졌다!",
                 "\(name)'s \(stat.name(.en)) fell\(much ? " harshly" : "")!",
                 "\(name)の \(stat.name(.ja))が \(much ? "がくっと " : "")さがった！")
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
    var todayTokens: String { t("오늘 함께한 시간", "Time together today", "今日一緒にいた時間") }
    var totalPlaytime: String { t("누적", "Total", "累計") }
    /// 초 → "N시간 M분" / "M분" / "M초"(짧을 때). 대시보드가 사용량 숫자 대신 이 시간을 보여준다.
    func duration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = (s % 3600) / 60
        if h > 0 { return t("\(h)시간 \(m)분", "\(h)h \(m)m", "\(h)時間\(m)分") }
        if m > 0 { return t("\(m)분", "\(m)m", "\(m)分") }
        return t("\(s)초", "\(s)s", "\(s)秒")
    }
    var thisWeek: String { t("이번 주", "This week", "今週") }
    var thisMonth: String { t("이번 달", "This month", "今月") }

    // MARK: 한도 섹션
    var limitsOfficial: String { t("한도 (공식)", "Limits (official)", "上限（公式）") }
    var fiveHourSession: String { t("5시간 세션", "5-hour session", "5時間セッション") }
    var weekly: String { t("주간", "Weekly", "週間") }
    var weeklyOpus: String { t("주간 Opus", "Weekly Opus", "週間 Opus") }
    var weeklySonnet: String { t("주간 Sonnet", "Weekly Sonnet", "週間 Sonnet") }
    var claudeCurrentBlock: String { t("Claude 현재 5h 블록", "Claude current 5h block", "Claude 現在の5hブロック") }
    var reset: String { t("리셋", "Reset", "リセット") }
    var limitReached: String { t("한도 도달", "Limit reached", "上限到達") }
    var personalSpendLimit: String { t("개인 사용 한도", "Personal spend limit", "個人利用上限") }
    var staleLimits: String { t("갱신 지연", "Stale", "更新遅延") }
    var refresh: String { t("갱신", "Refresh", "更新") }
    var limitsTapToLoad: String { t("공식 한도 불러오기", "Load official limits", "公式上限を読み込む") }

    func plan(_ p: String) -> String { t("플랜 \(p)", "Plan \(p)", "プラン \(p)") }
    func forecastReach(_ time: String) -> String {
        t("현재 속도면 \(time) 한도 도달", "At current rate, limit hit at \(time)", "現在のペースで \(time) に上限到達")
    }
    var forecastNoReach: String {
        t("현재 속도로는 리셋 전 한도 도달 없음", "Won't hit limit before reset at current rate", "現在のペースではリセット前に上限到達なし")
    }

    /// Claude oauth/usage 신형 limits[] 엔트리 이름 — kind + 모델 스코프 기반.
    func claudeLimitEntry(kind: String?, model: String?) -> String {
        switch kind {
        case "session": return fiveHourSession
        case "weekly_all": return weekly
        case "weekly_scoped":
            // 모델명이 없으면 레거시 "주간" 행과 이름이 겹치므로 scoped 임을 구분 표기
            guard let model else { return t("주간 (모델별)", "Weekly (scoped)", "週間（モデル別）") }
            return t("주간 \(model)", "Weekly \(model)", "週間 \(model)")
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
            return t("\(h)시간", "\(h)h", "\(h)時間")
        case let m?: return t("\(m)분", "\(m)m", "\(m)分")
        case nil: return t("한도", "Limit", "上限")
        }
    }

    // MARK: 푸터
    var refreshNow: String { t("지금 새로고침", "Refresh now", "今すぐ更新") }
    var updated: String { t("갱신", "Updated", "更新") }
    var settings: String { t("설정", "Settings", "設定") }
    var back: String { t("뒤로", "Back", "戻る") }
    var generalSectionTitle: String { t("일반", "General", "一般") }
    var menuBarSectionTitle: String { t("메뉴바에 표시", "Show in menu bar", "メニューバーに表示") }
    var advancedSectionTitle: String { t("고급", "Advanced", "詳細") }
    var advancedDisclosureLabel: String { t("고급 설정 · 진단", "Advanced · diagnostics", "詳細設定・診断") }
    var aboutSupportSectionTitle: String { t("정보 & 지원", "About & Support", "情報とサポート") }
    var quit: String { t("종료", "Quit", "終了") }

    // MARK: 설정
    var refreshInterval: String { t("새로고침 간격", "Refresh interval", "更新間隔") }
    var language: String { t("언어", "Language", "言語") }
    var menuBarItems: String { t("메뉴바 표시 항목 (복수 선택)", "Menu bar items (multi-select)", "メニューバー表示項目（複数選択）") }
    var todayTokensShort: String { t("오늘 함께한 시간", "Time together today", "今日一緒にいた時間") }
    var todayCost: String { t("오늘 비용 ($)", "Today's cost ($)", "本日のコスト ($)") }
    var limitPercent: String { t("한도 %", "Limit %", "上限 %") }
    var limitDisplayModeLabel: String { t("한도 표시 방식", "Limit display", "上限の表示") }
    var limitDisplayUsed: String { t("사용량", "Used", "使用量") }
    var limitDisplayRemaining: String { t("남은 양", "Remaining", "残量") }
    /// 팝오버 한도 행의 remaining 모드 표시 — %에 자기설명 접미사를 붙인다.
    func percentRemaining(_ percent: String) -> String {
        t("\(percent) 남음", "\(percent) left", "残り\(percent)")
    }
    var allOffHint: String { t("전부 끄면 캐릭터만 표시됩니다", "All off shows only the character", "すべてオフにするとキャラクターのみ表示") }
    // MARK: 플로팅 펫
    var floatingPetSectionTitle: String { t("플로팅 펫", "Floating Pet", "フローティングペット") }
    var floatingPetEnableLabel: String { t("플로팅 펫 표시", "Show floating pet", "フローティングペットを表示") }
    var floatingPetHint: String {
        t("포켓몬이 화면 위에 떠 있어요 — 드래그로 위치를 옮길 수 있어요",
          "Your Pokémon floats over the screen — drag to reposition",
          "ポケモンが画面の上に浮かびます — ドラッグで移動できます")
    }
    var floatingPetSizeLabel: String { t("크기", "Size", "サイズ") }
    var floatingPetRoamingLabel: String { t("화면 돌아다니기", "Roam across screens", "画面を歩き回る") }
    var floatingPetMouseChaseLabel: String { t("마우스 따라가기", "Follow the pointer", "マウスを追いかける") }
    var floatingPetSpeedLabel: String { t("이동 속도", "Movement speed", "移動速度") }
    var floatingPetSpeciesLabel: String { t("표시할 포켓몬", "Pokémon shown", "表示するポケモン") }
    var floatingPetSpeciesFollowsPartner: String {
        t("지금 키우는 파트너", "Current partner", "育成中のパートナー")
    }
    var imageAntialiasingLabel: String { t("이미지 부드럽게 표시", "Smooth image edges", "画像の輪郭を滑らかにする") }
    /// 지금은 한도 알림만 말풍선으로 뜨지만, 알림 종류가 늘어도 이 라벨은 그대로 쓴다.
    var floatingPetBubbleAlertsLabel: String {
        t("말풍선으로 알림 받기", "Show notifications as bubbles", "通知を吹き出しで表示")
    }
    var floatingPetMenuOpen: String { t("열기", "Open", "開く") }
    var floatingPetMenuHide: String {
        t("플로팅 펫 끄기", "Turn off floating pet", "フローティングペットをオフ")
    }
    func floatingPetHoverTokensOnly(_ tokens: String) -> String {
        t("오늘 \(tokens)", "Today: \(tokens)", "今日: \(tokens)")
    }
    func floatingPetHoverWithLimit(_ tokens: String, _ percent: String) -> String {
        t("오늘 \(tokens) (한도 \(percent))",
          "Today: \(tokens) (limit \(percent))",
          "今日: \(tokens)（上限 \(percent)）")
    }

    var disableKeychain: String { t("Keychain 접근 끄기", "Disable Keychain access", "Keychainアクセスを無効化") }
    var disableKeychainHint: String { t("켜면 Keychain 접근 허용 팝업이 더 안 뜹니다 — 공식 한도(%)만 숨겨지고 토큰·비용은 그대로", "When on, no more Keychain permission pop-ups — only official limits (%) are hidden; tokens/cost stay", "オンにするとKeychain許可のポップアップが出なくなります — 公式上限(%)のみ非表示、トークン・費用はそのまま") }
    var refreshLimitToken: String { t("한도 토큰 캐시 갱신", "Refresh limit token cache", "上限トークンキャッシュを更新") }
    var onlyOnPress: String { t("누를 때만 Keychain 을 읽어요 — 자동 폴링은 안 읽어 팝업이 안 떠요. 토큰 만료 후 이 버튼으로 한도 갱신", "Reads Keychain only when pressed — auto-polling never does, so no pop-ups. Refresh limits here after the token expires", "押した時のみKeychainを読みます — 自動更新では読まずポップアップも出ません。トークン期限切れ後はこのボタンで上限を更新") }
    var launchAtLogin: String { t("로그인 시 자동 시작", "Launch at login", "ログイン時に自動起動") }
    var bundledOnly: String { t(".app 번들로 설치된 경우에만 사용 가능 (scripts/build-app.sh)", "Available only when installed as an .app bundle (scripts/build-app.sh)", ".appバンドルでインストールした場合のみ利用可能 (scripts/build-app.sh)") }
    var notificationsSection: String { t("알림", "Notifications", "通知") }
    var limitNotificationsLabel: String { t("한도 알림", "Limit alerts", "上限通知") }
    var companionNotificationsLabel: String { t("Companion 이벤트 (부화·진화·졸업)", "Companion events (hatch / evolve / graduate)", "コンパニオンイベント（孵化・進化・卒業）") }
    var statusChecksLabel: String { t("프로바이더 상태 확인", "Provider status checks", "プロバイダー状態チェック") }
    var statusChecksHint: String { t("Claude·OpenAI 장애를 팝오버에 표시 (알림 아님)", "Show Claude / OpenAI incidents in the popover (not a notification)", "Claude・OpenAIの障害をポップオーバーに表示（通知ではない）") }
    var warning: String { t("경고", "Warning", "警告") }
    var critical: String { t("임박", "Critical", "切迫") }
    var aggregationNote: String { t("토큰 집계 기준: totalTokens (input + output + cache, 로컬 날짜)", "Token basis: totalTokens (input + output + cache, local date)", "集計基準: totalTokens (input + output + cache, ローカル日付)") }
    var close: String { t("닫기", "Close", "閉じる") }

    // MARK: 세이브 이전 (설정 → 백업 & 이전)
    var transferSectionTitle: String { t("백업 & 이전", "Backup & Transfer", "バックアップと移行") }
    var exportSaveLabel: String { t("세이브 내보내기", "Export save", "セーブを書き出す") }
    var exportSaveHint: String {
        t("도감·누적 별의모래·가방·현재 포켓몬을 파일 하나로 저장해요",
          "Saves your Pokédex, lifetime Stardust, Bag, and current Pokémon as one file",
          "図鑑・累計トークン・バッグ・現在のポケモンを1つのファイルに保存します")
    }
    var exportSaveButton: String { t("내보내기…", "Export…", "書き出す…") }
    var importSaveLabel: String { t("세이브 불러오기", "Import save", "セーブを読み込む") }
    var importSaveHint: String {
        t("다른 Mac에서 내보낸 파일을 골라 이 Mac으로 이어서 키워요",
          "Pick a file exported from another Mac and continue here",
          "他のMacから書き出したファイルを選んでこのMacで続けます")
    }
    var importSaveButton: String { t("불러오기…", "Import…", "読み込む…") }
    var importConfirmTitle: String {
        t("이 Mac의 진행을 대체할까요?", "Replace this Mac's progress?", "このMacの進行を置き換えますか？")
    }
    /// 무엇이 사라지는지 수치로 적는다 — 일반적인 "정말 진행할까요?" 보다 판단에 실제로 쓸모 있다.
    /// 내보낸 시각·출처 기기를 함께 보여주는 이유: 도감 수가 같으면 3주 전 세이브도 문구가 똑같아,
    /// 오래된 파일을 되돌리는 상황을 사용자가 알아챌 단서가 없다.
    func importConfirmBody(incomingDex: Int, incomingTokens: String,
                           exportedAt: String, sourceDevice: String,
                           currentDex: Int, currentTokens: String) -> String {
        t("""
          불러올 세이브: 도감 \(incomingDex)마리 · 누적 \(incomingTokens)
          내보낸 시각: \(exportedAt) · \(sourceDevice)
          현재 이 Mac: 도감 \(currentDex)마리 · 누적 \(currentTokens)

          이 Mac의 현재 진행은 대체됩니다. 직전 상태는 상태 폴더에 백업으로 남습니다(최근 5개).
          """,
          """
          Incoming save: \(incomingDex) in Pokédex · \(incomingTokens) lifetime
          Exported: \(exportedAt) · \(sourceDevice)
          This Mac now: \(currentDex) in Pokédex · \(currentTokens) lifetime

          This Mac's current progress is replaced. The previous state is kept as a backup in the state folder (last 5).
          """,
          """
          読み込むセーブ: 図鑑 \(incomingDex)匹 · 累計 \(incomingTokens)
          書き出し日時: \(exportedAt) · \(sourceDevice)
          現在のこのMac: 図鑑 \(currentDex)匹 · 累計 \(currentTokens)

          このMacの現在の進行は置き換えられます。直前の状態は状態フォルダにバックアップとして残ります（最新5件）。
          """)
    }
    var importConfirmReplace: String { t("대체", "Replace", "置き換える") }
    func importSaveDone(dex: Int, tokens: String) -> String {
        t("불러왔어요 — 도감 \(dex)마리 · 누적 \(tokens)",
          "Imported — \(dex) in Pokédex · \(tokens) lifetime",
          "読み込みました — 図鑑 \(dex)匹 · 累計 \(tokens)")
    }
    var importErrorNotSaveFile: String {
        t("PokeTokenBar 세이브 파일이 아니에요.",
          "That isn't a PokeTokenBar save file.",
          "PokeTokenBar のセーブファイルではありません。")
    }
    var importErrorNewerSchema: String {
        t("더 새로운 버전에서 만든 세이브예요 — 앱을 업데이트한 뒤 다시 시도해 주세요.",
          "This save was made by a newer version — update the app and try again.",
          "より新しいバージョンで作成されたセーブです — アプリを更新してから再試行してください。")
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
        t("세이브 파일이라기엔 너무 커요 — 다른 파일을 고른 것 같아요.",
          "That file is too large to be a save — it looks like the wrong file.",
          "セーブファイルにしては大きすぎます — 別のファイルを選んだようです。")
    }
    /// 백업을 못 남기면 불러오기를 중단한다 — 되돌릴 수단 없이 진행을 대체하지 않기 위해서다.
    var importErrorBackupFailed: String {
        t("현재 상태를 백업하지 못해 불러오기를 중단했어요 — 진행은 그대로예요. 디스크 여유 공간을 확인해 주세요.",
          "Import stopped because the current state couldn't be backed up — your progress is untouched. Check free disk space.",
          "現在の状態をバックアップできなかったため読み込みを中止しました — 進行はそのままです。ディスクの空き容量を確認してください。")
    }

    // MARK: 문제점 알리기 (설정 → 메일 리포트)
    var reportProblem: String { t("문제점 알리기", "Report a problem", "問題を報告") }
    var showLogFile: String { t("로그 파일 보기", "Show log file", "ログファイルを表示") }
    var reportAttachHint: String {
        t("메일에 로그 파일을 첨부해 주시면 원인 파악에 큰 도움이 돼요.",
          "Attaching the log file to the email helps a lot with diagnosis.",
          "メールにログファイルを添付していただくと原因の特定に役立ちます。")
    }
    func reportMailFallback(_ address: String) -> String {
        t("메일 앱을 열 수 없어요. \(address) 로 직접 보내주세요.",
          "Couldn't open a mail app. Please email \(address) directly.",
          "メールアプリを開けません。\(address) 宛に直接お送りください。")
    }
    func reportMailSubject(_ version: String) -> String {
        t("[PokeTokenBar] 문제 리포트 (v\(version))",
          "[PokeTokenBar] Problem report (v\(version))",
          "[PokeTokenBar] 問題レポート (v\(version))")
    }
    func reportMailBody(version: String, os: String) -> String {
        t("""
        문제 내용:
        (겪으신 문제를 적어주세요 — 언제, 어떤 화면에서, 어떻게 되었는지)


        ---
        앱 버전: v\(version)
        macOS: \(os)
        로그 파일(첨부 권장): ~/Library/Logs/PokeTokenBar.log
        """,
        """
        What happened:
        (Describe the problem — when, on which screen, and what you saw)


        ---
        App version: v\(version)
        macOS: \(os)
        Log file (please attach): ~/Library/Logs/PokeTokenBar.log
        """,
        """
        問題の内容:
        （いつ・どの画面で・どうなったかをご記入ください）


        ---
        アプリのバージョン: v\(version)
        macOS: \(os)
        ログファイル（添付推奨）: ~/Library/Logs/PokeTokenBar.log
        """)
    }

    /// 새로고침 간격 라벨 (초 단위 값 → 표시). 0 = 수동.
    func intervalLabel(_ seconds: TimeInterval) -> String {
        if seconds == 0 { return t("수동", "Manual", "手動") }
        let m = Int(seconds / 60)
        return t("\(m)분", "\(m) min", "\(m)分")
    }

    // MARK: 컴패니언
    var finalForm: String { t("최종 진화체", "Final form", "最終進化") }
    func stage(_ i: Int, _ k: Int) -> String { t("진화 단계 \(i) / \(k)", "Stage \(i) / \(k)", "進化段階 \(i) / \(k)") }
    var unknownNextEvolution: String { t("알 수 없는 다음 진화", "Unknown next evolution", "次の進化先は不明") }

    // MARK: 기술 목록 (홈 · "기술 보기")
    // 행 라벨과 툴팁이 같은 키를 쓴다 — 예전엔 행만 한국어 리터럴이라 en/ja 에서 둘이 어긋났다(#10).
    var movesTitle: String { t("기술 보기", "Moves", "わざを見る") }
    var movesLoading: String { t("기술 불러오는 중", "Loading moves", "わざを読み込み中") }
    var movesEmpty: String { t("확인할 수 있는 기술이 없습니다.", "No moves available.", "確認できるわざがありません。") }
    var moveCategoryStatus: String { t("변화", "Status", "へんか") }
    var moveCategoryPhysical: String { t("물리", "Physical", "ぶつり") }
    var moveCategorySpecial: String { t("특수", "Special", "とくしゅ") }
    func moveCategory(_ damageClass: MoveDamageClass) -> String {
        switch damageClass {
        case .physical: return moveCategoryPhysical
        case .special: return moveCategorySpecial
        case .status: return moveCategoryStatus
        }
    }
    var movePowerLabel: String { t("위력", "Power", "威力") }
    var moveAccuracyLabel: String { t("명중", "Accuracy", "命中") }
    var moveAlwaysHits: String { t("필중", "Always hits", "必中") }
    /// 행 라벨은 폭이 좁아 축약형을 쓴다(툴팁은 위 전체 라벨).
    func movePowerShort(_ power: Int) -> String { t("위력 \(power)", "Pow \(power)", "威力 \(power)") }
    func moveAccuracyShort(_ accuracy: Int) -> String { t("명중 \(accuracy)", "Acc \(accuracy)", "命中 \(accuracy)") }
    func movePP(_ pp: Int) -> String { "PP \(pp)" }

    var moveHoverHint: String {
        t("기술에 마우스를 올리면 설명이 나와요.",
          "Hover a move to see what it does.",
          "わざにカーソルを合わせると説明が出ます。")
    }

    /// 기술 한 줄 요약 — 설명이 없을 때 쓰는 폴백이자 툴팁 상세줄. 두 자리가 같은 어휘를 쓰도록 한 곳에 둔다.
    func moveDetailLine(_ move: MoveSpec) -> String {
        let power = move.damageClass == .status ? "—" : "\(move.power)"
        let accuracy = move.accuracy.map(String.init) ?? moveAlwaysHits
        return "\(move.type.name(lang)) · \(moveCategory(move.damageClass)) · "
            + "\(movePowerLabel) \(power) · \(moveAccuracyLabel) \(accuracy) · \(movePP(move.pp))"
    }

    /// 호버 슬롯 문구 — 올린 기술이 없으면 안내, 설명이 있으면 설명, 없거나 비어 있으면 스탯 요약.
    /// 슬롯이 빈 채로 남으면 "고장 난 것"처럼 보이므로 어느 분기에서도 빈 문자열을 내지 않는다.
    func moveHoverText(_ move: MoveSpec?) -> String {
        guard let move else { return moveHoverHint }
        if let description = move.description(lang), !description.isEmpty { return description }
        return moveDetailLine(move)
    }

    // MARK: 집중 타이머 · 모험 재화 줄
    /// 알·조각·주간 모험 진행도 한 줄. 예전엔 "주간" 만 한국어로 박혀 있었다(#10 부류 스윕).
    func focusStash(eggs: Int, fragments: Int, weekly: Int) -> String {
        let progress = t("주간 \(weekly)/10", "Weekly \(weekly)/10", "週間 \(weekly)/10")
        return "🥚 ×\(eggs) · 🧩 \(fragments)/10 · \(progress)"
    }
    /// 보관 알 자동 부화 줄의 제목과, 예정 시각을 지난 뒤의 대기 문구(#86).
    var eggAutoHatchLabel: String { t("🥚 자동 부화까지", "🥚 Auto hatch", "🥚 自動ふ化まで") }
    var eggHatchingSoon: String { t("곧 부화", "Hatching soon", "まもなくふ化") }
    func battleFixedStake(_ amount: String) -> String {
        t("고정 판돈 ⭐ \(amount)", "Fixed stake ⭐ \(amount)", "固定かけ金 ⭐ \(amount)")
    }

    // MARK: 메뉴바 상태 (#20 — MenuBarStatus.fullDescription)
    var menuBarResting: String { t("휴식 중", "RESTING", "休憩中") }
    var menuBarAdventuring: String { t("모험 중", "ADVENTURING", "冒険中") }
    var menuBarAdventureClaimable: String { t("보상 받기", "CLAIM REWARD", "報酬あり") }

    // MARK: 스타터 선택 (맨 처음 1회)
    var trainerNamePrompt: String { t("트레이너 이름", "Trainer name", "トレーナー名") }
    var trainerNamePlaceholder: String { t("이름을 입력하세요", "Enter your name", "名前を入力") }
    var starterNeedName: String { t("먼저 트레이너 이름을 입력하세요.", "Enter your trainer name first.", "先にトレーナー名を入力してください。") }
    var starterPrompt: String { t("함께할 첫 파트너를 골라요", "Choose your first partner", "最初のパートナーを選ぼう") }
    var starterHint: String {
        t("고른 포켓몬이 바로 함께합니다. 이후엔 알에서 다양한 포켓몬이 태어나요.",
          "Your pick joins you right away. After that, eggs hatch a variety of Pokémon.",
          "選んだポケモンがすぐに仲間になります。以降はタマゴから色々なポケモンが生まれます。")
    }
    var starterLoading: String { t("후보를 부르는 중…", "Summoning candidates…", "候補を呼び出し中…") }
    var eggIncubating: String { t("🥚 부화 준비 중", "🥚 Incubating", "🥚 孵化の準備中") }
    /// 게임 재화 표시 단위 — 사용량 트래커의 실제 AI 토큰 숫자와 시각적으로 구분하는 ✨ 접두.
    func stardust(_ amount: String) -> String { "✨\(amount)" }
    /// 시간당 생산량(방치형 핵심 신호) — "앱을 켜 두면 자란다"를 수치로.
    func perHour(_ amount: String) -> String { t("시간당 ✨\(amount)", "✨\(amount)/hr", "毎時 ✨\(amount)") }
    func eggToHatch(_ amount: String) -> String { t("부화까지 ✨\(amount)", "✨\(amount) to hatch", "孵化まで ✨\(amount)") }
    func toNextEvolution(_ amount: String) -> String { t("다음 진화까지 ✨\(amount)", "✨\(amount) to next evolution", "次の進化まで ✨\(amount)") }
    func toGraduation(_ amount: String) -> String { t("졸업까지 ✨\(amount)", "✨\(amount) to graduation", "卒業まで ✨\(amount)") }
    func graduated(_ name: String) -> String {
        t("\(name) 졸업 → 도감에 보존. 새 알이 도착했어요!",
          "\(name) graduated → saved to the dex. A new egg has arrived!",
          "\(name) 卒業 → 図鑑に保存。新しいタマゴが届きました！")
    }
    var dexEmptyTitle: String { t("아직 잡은 포켓몬이 없어요!", "No Pokémon caught yet!", "まだ捕まえたポケモンがいません！") }
    var dexEmptyHint: String { t("앱을 켜 두고 첫 포켓몬을 부화시켜 보세요.", "Keep the app running to hatch your first Pokémon.", "アプリを起動したままにして最初のポケモンを孵化させましょう。") }

    // MARK: 도감 요약 헤더
    var dexTitle: String { t("도감", "Pokédex", "図鑑") }
    func dexTotal(_ n: Int) -> String { t("총 \(n)마리", "\(n) total", "全\(n)匹") }
    /// 포획 로그 = 개체 단위 기록(같은 라인 중복이 정상). 도감 = 종 단위 집계.
    var catchLogTitle: String { t("포획 로그", "Catch log", "捕獲ログ") }
    /// 도감 총계는 개체가 아니라 종 수 — 로그의 dexTotal("총 N마리")과 단위가 다르다.
    /// 도감 총계 — `raising` 은 아직 졸업하지 않은(키우는 중인) 종 수다. 총계는 그 종까지 세고
    /// 목표 줄은 졸업분만 센다 — 갈라지는 몫을 밝혀야 두 숫자가 서로를 설명한다.
    func dexSpeciesTotal(_ n: Int, raising: Int) -> String {
        guard raising > 0 else { return t("\(n)종", "\(n) species", "\(n)種") }
        return t("\(n)종 (\(raising) 육성중)", "\(n) species (\(raising) raising)", "\(n)種 (\(raising)育成中)")
    }
    /// 페이저 접근성 문구 — 도감과 소유 포켓몬이 함께 쓴다(둘 다 페이지식 고정 격자).
    func dexPageLabel(_ page: Int, _ total: Int) -> String {
        t("\(total)페이지 중 \(page)페이지", "Page \(page) of \(total)", "\(total)ページ中 \(page)ページ")
    }
    var dexPagePrev: String { t("이전 페이지", "Previous page", "前のページ") }
    var dexPageNext: String { t("다음 페이지", "Next page", "次のページ") }
    var dexRaising: String { t("키우는 중", "Raising", "育成中") }
    var rarityCommon: String { t("일반", "Common", "ノーマル") }
    var rarityUncommon: String { t("고급", "Uncommon", "アンコモン") }
    var rarityRare: String { t("희귀", "Rare", "レア") }
    var rarityLegendary: String { t("전설", "Legendary", "伝説") }
    var dexFilterHint: String { t("탭하면 이 희귀도만 보기 · 다시 탭하면 전체", "Tap to show only this rarity · tap again to clear", "タップでこの希少度のみ表示・再タップで全体") }
    /// 도감 칸의 ✨ 를 읽어주는 명사 — 이모지는 스크린리더가 일관되게 읽지 못한다.
    var dexShinyLabel: String { t("이로치", "Shiny", "色違い") }
    func rarityLabel(_ r: Rarity) -> String {
        switch r {
        case .common:    return rarityCommon
        case .uncommon:  return rarityUncommon
        case .rare:      return rarityRare
        case .legendary: return rarityLegendary
        }
    }

    // 상태 한 줄
    var statusEgg: String { t("곧 깨어나요.", "Hatching soon.", "もうすぐ孵化します。") }
    var statusIdle: String { t("오늘은 조용히 자리를 지켜요.", "Keeping quiet today.", "今日は静かにしています。") }
    var statusWorking: String { t("오늘의 작업 흔적이 쌓이고 있어요.", "Today's work is piling up.", "本日の作業が積み重なっています。") }
    var statusFocus: String { t("지금은 집중 모드예요.", "In focus mode now.", "今は集中モードです。") }
    var statusTired: String { t("에너지가 부족해요. 잠깐 쉬어도 괜찮아요.", "Low on energy. A short rest would help.", "エネルギーが少ないです。少し休みましょう。") }
    var statusSleep: String { t("지금은 자고 있어요.", "Sleeping now.", "今は眠っています。") }
    func statusEvolved(_ name: String) -> String { t("\(name)(으)로 진화했어요!", "Evolved into \(name)!", "\(name) に進化しました！") }
    var statusGrew: String { t("성장했어요!", "It grew!", "成長しました！") }

    // MARK: companion 이벤트 시스템 알림
    var notifHatchTitle: String { t("🥚 부화!", "🥚 Hatched!", "🥚 孵化！") }
    func notifHatchBody(_ name: String) -> String { t("알에서 \(name)이(가) 나왔어요!", "\(name) hatched from the egg!", "タマゴから \(name) が生まれました！") }
    var notifShinyHatchTitle: String { t("✨ 이로치 포켓몬!", "✨ Shiny Pokémon!", "✨ 色違いポケモン！") }
    func notifShinyHatchBody(_ name: String) -> String { t("이로치 \(name)이(가) 태어났어요! (1/64)", "A shiny \(name) hatched! (1 in 64)", "色違いの \(name) が生まれました！(1/64)") }
    var eggImminent: String { t("곧 부화해요!", "About to hatch!", "もうすぐ孵化！") }
    /// 첫 실행(아직 적립 0) 안내 — "왜 아무 일도 안 일어나지"를 방지.
    var eggFirstRunHint: String {
        t("앱을 켜 두면 별의모래가 쌓여 자라요. 잠시 뒤 알이 부화해요.",
          "Grows on Stardust that piles up while the app is running. Your egg hatches soon.",
          "アプリを起動している間にほしのすなが貯まって育ちます。まもなくタマゴが孵化します。") }
    var notifEvolveTitle: String { t("✨ 진화!", "✨ Evolved!", "✨ 進化！") }
    func notifEvolveBody(_ name: String) -> String { t("\(name)(으)로 진화했어요!", "Evolved into \(name)!", "\(name) に進化しました！") }
    // 메타몽 위장 리빌 — 진화 못 하는 메타몽이 첫 진화 순간 정체를 드러낸다.
    var notifDittoRevealTitle: String { t("🎭 어라? 메타몽!", "🎭 Huh? It's Ditto!", "🎭 あれ？メタモン！") }
    func notifDittoRevealBody(_ disguise: String) -> String { t("\(disguise)인 줄 알았는데 — 사실은 메타몽이었어요!", "You thought it was \(disguise) — it was Ditto all along!", "\(disguise) だと思ってた… 実はメタモンでした！") }
    var notifShinyDittoRevealTitle: String { t("🎭✨ 어라? 이로치 메타몽!", "🎭✨ Huh? A shiny Ditto!", "🎭✨ あれ？色違いメタモン！") }
    func notifShinyDittoRevealBody(_ disguise: String) -> String { t("\(disguise)인 줄 알았는데 — 이로치 메타몽이었어요! (1/64)", "You thought it was \(disguise) — it was a shiny Ditto! (1 in 64)", "\(disguise) だと思ってた… 色違いのメタモンでした！(1/64)") }
    var notifTrainerLevelUpTitle: String { t("👑 트레이너 레벨업!", "👑 Trainer level up!", "👑 トレーナーレベルアップ！") }
    func notifTrainerLevelUpBody(_ level: Int, _ stardust: Int) -> String {
        let amount = GameNumberFormatter.compact(stardust)
        return t("Lv.\(level) 달성 — 별의조각 \(amount) 받았어요!",
                 "Reached Lv.\(level) — you earned \(amount) Star Pieces!",
                 "Lv.\(level) 到達 — ほしのかけら \(amount) を獲得！")
    }
    /// 상단 트레이너 바 라벨. `Lv.N` 만 쓰면 포켓몬 레벨(파트너·로스터·배틀에서 이미 쓰는 표기)로
    /// 잘못 읽힌다 — 이 단어가 계정 단위 값임을 알려주는 유일한 장치다.
    var trainerLevelLabel: String { t("트레이너", "Trainer", "トレーナー") }
    var notifMissionDoneTitle: String { t("🎯 미션 완료!", "🎯 Mission complete!", "🎯 ミッション達成！") }
    func notifMissionDoneBody(_ name: String, _ stardust: Int) -> String {
        let amount = GameNumberFormatter.compact(stardust)
        return t("\(name) — 별의조각 \(amount) 받았어요!",
                 "\(name) — you earned \(amount) Star Pieces!",
                 "\(name) — ほしのかけら \(amount) を獲得！")
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
            return t("모험 정산 \(target)회", "Claim \(plural(target, "adventure"))", "冒険を\(target)回精算")
        case .focusMinutes:
            return t("집중 \(target)분", "Focus \(plural(target, "minute"))", "\(target)分集中")
        case .graduations:
            return t("졸업 \(target)회", "Graduate \(plural(target, "partner"))", "\(target)体を卒業")
        }
    }

    /// 영어 복수형 — 세 이벤트가 공유한다. 한 케이스만 처리하면 목표값을 1 로 조절하는 순간
    /// 나머지에서 "Claim 1 adventures" 가 나온다.
    private func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    func missionName(_ mission: Mission) -> String { goalName(mission.event, mission.target) }
    var missionsTitle: String { t("미션", "Missions", "ミッション") }

    /// 시즌 카드 제목과 남은 일수. 완료 알림 본문은 미션 것을 재사용한다(같은 문장을 두 번 번역하지
    /// 않는다). 남은 일수는 한 줄 헤더에 들어가므로 가장 짧은 말을 쓴다.
    var seasonTitle: String { t("시즌 챌린지", "Season challenges", "シーズンチャレンジ") }
    func seasonDaysLeft(_ days: Int) -> String {
        t("\(days)일 남음", "\(days)d left", "残り\(days)日")
    }
    var notifSeasonDoneTitle: String { t("🗓️ 시즌 챌린지 달성!", "🗓️ Season challenge cleared!", "🗓️ シーズンチャレンジ達成！") }

    var notifDexGoalTitle: String { t("📘 도감 목표 달성!", "📘 Pokédex goal cleared!", "📘 図鑑目標を達成！") }
    func notifDexGoalBody(_ name: String) -> String {
        t("\(name) — 보상이 도착했어요!", "\(name) — your reward has arrived!", "\(name) — 報酬が届きました！")
    }
    /// 이름 없는 목표는 **빈 문자열**을 돌려준다 — 카탈로그에 목표를 더하고 문구를 빼먹으면
    /// `DexGoalTests` 가 그 자리에서 실패한다. id 를 폴백으로 쓰면 그 가드가 무력해진다.
    /// 목표값이 이름에 들어가 알림에서도 어느 칸인지 구분된다(종 10 vs 종 25).
    func dexGoalName(_ goal: DexGoal) -> String {
        switch goal.kind {
        case .species: return t("도감 \(goal.target)종", "\(goal.target) species in the Pokédex", "図鑑\(goal.target)種")
        case .types:   return t("타입 \(goal.target)종류", "\(goal.target) types covered", "タイプ\(goal.target)種類")
        case .shiny:   return t("이로치 \(goal.target)마리", "\(goal.target) shiny graduates", "色違い\(goal.target)体")
        }
    }
    /// 도감 헤더 목표 줄의 축 라벨 — 한 줄에 셋이 들어가므로 가장 짧은 말을 쓴다.
    func dexGoalShortLabel(_ kind: DexGoalKind) -> String {
        switch kind {
        case .species: return t("종", "Species", "種")
        case .types:   return t("타입", "Types", "タイプ")
        case .shiny:   return dexShinyLabel   // 같은 한 단어를 두 번 번역하지 않는다
        }
    }
    /// 주간 배지는 위쪽 한도 섹션의 `weekly` 를 그대로 쓴다 — 같은 한 단어를 두 번 번역하지 않는다.
    var missionDaily: String { t("일간", "Daily", "デイリー") }

    /// 컬렉션 탭 세그먼트 라벨 겸 선반 제목. 체육관 "배지" 와 다른 말을 쓴다 — 한 앱에 배지가
    /// 두 종류면 어느 쪽 진행인지 안 읽힌다.
    var achievementsTitle: String { t("업적", "Achievements", "実績") }
    /// 단계 표시(`●●○○`)의 스크린리더 대체 문구 — 점 문자를 그대로 읽히면 "검은 원 흰 원" 이 된다.
    func achievementTierLabel(_ reached: Int, _ total: Int) -> String {
        t("\(total)단계 중 \(reached)단계", "tier \(reached) of \(total)", "\(total)段階中\(reached)段階")
    }
    /// 카드 진행도 줄의 스크린리더 대체 문구. `Lv.12 · 🏅8/16` 을 그대로 읽히면 뜻이 안 통한다.
    /// 광고에 없는 칸은 문구에서도 빠진다.
    func peerProgressLabel(_ level: Int?, _ tiers: Int?, _ total: Int) -> String {
        var parts: [String] = []
        if let level {
            parts.append(t("트레이너 Lv.\(level)", "Trainer Lv.\(level)", "トレーナー Lv.\(level)"))
        }
        if let tiers {
            parts.append(t("업적 \(tiers)/\(total)", "\(tiers) of \(total) achievements", "実績 \(tiers)/\(total)"))
        }
        return parts.joined(separator: ", ")
    }

    var notifAchievementTitle: String { t("🏅 업적 달성!", "🏅 Achievement unlocked!", "🏅 実績を達成！") }
    func notifAchievementBody(_ name: String, _ tier: Int, _ stardust: Int) -> String {
        let amount = GameNumberFormatter.compact(stardust)
        return t("\(name) \(tier)단계 — 별의조각 \(amount) 받았어요!",
                 "\(name) tier \(tier) — you earned \(amount) Star Pieces!",
                 "\(name) ティア\(tier) — ほしのかけら \(amount) を獲得！")
    }
    /// 업적 트랙 이름. 미션·도감 목표와 달리 **id 문자열이 아니라 열거형으로 스위치**한다 —
    /// 트랙을 더하면 컴파일이 막으니 빈 문자열 폴백이 필요 없다.
    func achievementName(_ track: AchievementTrack) -> String {
        switch track {
        case .focus:  return t("집중 시간", "Focus time", "集中時間")
        case .evolve: return t("진화", "Evolutions", "進化")
        case .battle: return t("배틀 승리", "Battle wins", "バトル勝利")
        case .race:   return t("레이스 완주", "Races finished", "レース完走")
        }
    }

    var notifGraduateTitle: String { t("🎓 졸업!", "🎓 Graduated!", "🎓 卒業！") }
    func notifGraduateBody(_ name: String) -> String { t("\(name) — 도감에 보존! 새 알이 도착했어요.", "\(name) — saved to your Pokédex! A new egg has arrived.", "\(name) — 図鑑に保存！新しいタマゴが届きました。") }

    // MARK: Claude 한도 토큰 갱신 오류 (친절 안내)
    func limitRefreshHTTPError(_ status: Int) -> String {
        if status == 401 || status == 403 {
            return t(
                "Claude 자격증명이 만료됐거나 권한이 없어요 (\(status)). Claude Code 로그인을 확인하세요. Codex만 쓴다면 무시해도 됩니다 — Codex 한도는 따로 표시돼요.",
                "Claude credential is expired or unauthorized (\(status)). Check that you're signed in to Claude Code. If you only use Codex you can ignore this — Codex limits show separately.",
                "Claude の認証情報が期限切れか権限がありません (\(status))。Claude Code にサインインしているか確認してください。Codex のみ使用する場合は無視できます — Codex の上限は別に表示されます。")
        }
        return t("Claude 한도 조회 실패 (\(status)).", "Failed to fetch Claude limits (\(status)).", "Claude の上限取得に失敗しました (\(status))。")
    }
    var limitRefreshNoCredential: String {
        t("Claude 자격증명을 찾지 못했어요. Claude Code 에 로그인하면 한도가 표시됩니다. Codex만 쓴다면 무시해도 돼요.",
          "No Claude credential found. Sign in to Claude Code to see limits. If you only use Codex you can ignore this.",
          "Claude の認証情報が見つかりません。Claude Code にサインインすると上限が表示されます。Codex のみなら無視して構いません。")
    }
    var limitRefreshReauthNeeded: String {
        t("Claude 자격증명에 계정 로그인 정보가 없어요. Claude Code 에서 `/login` 으로 다시 로그인하면 한도가 표시됩니다.",
          "Your Claude credential has no account sign-in. Run `/login` in Claude Code to sign in again and limits will appear.",
          "Claude の認証情報にアカウントのサインインが含まれていません。Claude Code で `/login` を実行して再度サインインすると上限が表示されます。")
    }
    var limitRefreshGeneric: String {
        t("Claude 한도 조회에 실패했어요. 잠시 후 다시 시도하세요.",
          "Couldn't fetch Claude limits. Please try again shortly.",
          "Claude の上限取得に失敗しました。しばらくして再試行してください。")
    }
    var limitRefreshRateLimited: String {
        t("Claude 한도 조회가 일시 제한됐어요 (429). 잠시 쉬었다가 자동으로 재시도합니다.",
          "Claude limit checks are temporarily rate-limited (429). Backing off and retrying automatically.",
          "Claude の上限取得が一時的に制限されています (429)。少し待って自動的に再試行します。")
    }

    // MARK: Claude 세션 만료(401) 안내
    var claudeAuthExpiredTitle: String {
        t("Claude 세션 만료 — 한도가 갱신 안 돼요",
          "Claude session expired — limits can't refresh",
          "Claude セッション期限切れ — 上限を更新できません")
    }
    var claudeAuthExpiredHint: String {
        t("표시된 값은 만료 전 기준이에요. 다시 시도하거나, Claude Code 를 한 번 실행하면 자동 갱신됩니다.",
          "Values shown are from before expiry. Retry, or run Claude Code once to refresh automatically.",
          "表示値は期限切れ前のものです。再試行するか、Claude Code を一度実行すると自動更新されます。")
    }
    var retry: String { t("다시 시도", "Retry", "再試行") }

    // MARK: 업데이트 알림
    func updateAvailable(_ version: String, current: String) -> String {
        t("🆕 v\(version) 사용 가능 (현재 \(current))",
          "🆕 v\(version) available (you have \(current))",
          "🆕 v\(version) が利用可能（現在 \(current)）")
    }
    var updateButton: String { t("업데이트", "Update", "更新") }
    var updateLater: String { t("나중에", "Later", "後で") }
    var updating: String { t("업데이트 중…", "Updating…", "更新中…") }
    var updateSectionTitle: String { t("업데이트", "Updates", "アップデート") }
    var githubAccountLabel: String { t("GitHub 계정", "GitHub account", "GitHubアカウント") }
    var githubLogin: String { t("로그인", "Sign in", "ログイン") }
    var githubLogout: String { t("로그아웃", "Sign out", "ログアウト") }
    var githubConnected: String { t("연결됨", "Connected", "接続済み") }
    var githubLoginHint: String {
        t("비공개 릴리스에서 업데이트를 받으려면 로그인해 주세요.",
          "Sign in to download updates from the private release.",
          "非公開リリースから更新するにはログインしてください。")
    }
    func githubDeviceCode(_ code: String) -> String {
        t("코드 \(code)", "Code \(code)", "コード \(code)")
    }
    var githubDeviceCodeHint: String {
        t("코드를 복사했어요. 열린 GitHub 창에서 승인해 주세요.",
          "The code was copied. Approve it in the GitHub window.",
          "コードをコピーしました。GitHubの画面で承認してください。")
    }
    var updateNotificationsLabel: String { t("업데이트 알림", "Update notifications", "アップデート通知") }
    var automaticUpdateDownloadsLabel: String {
        t("업데이트 자동 다운로드", "Download updates automatically", "アップデートを自動ダウンロード")
    }
    var checkForUpdatesLabel: String { t("업데이트 확인", "Check for updates", "アップデートを確認") }
    var checkNowButton: String { t("지금 확인", "Check now", "今すぐ確認") }
    func updateFound(_ version: String) -> String { t("새 버전 v\(version) 있어요", "Version \(version) is available", "バージョン \(version) が利用可能です") }
    func upToDate(_ version: String) -> String { t("최신 버전이에요 (v\(version))", "You're on the latest (v\(version))", "最新です (v\(version))") }
    func updateCheckError(_ error: UpdateChecker.CheckError) -> String {
        switch error {
        case .authenticationRequired:
            t("GitHub 로그인이 필요해요.", "GitHub sign-in is required.", "GitHubへのログインが必要です。")
        case .network:
            t("업데이트 확인에 실패했어요. 네트워크를 확인해 주세요.",
              "Couldn't check for updates. Check your network.",
              "更新を確認できませんでした。ネットワークを確認してください。")
        case .keychain:
            t("로그인 정보를 Keychain에 갱신하지 못했어요. 앱을 다시 로그인해 주세요.",
              "Couldn't refresh the sign-in information in Keychain. Sign in again.",
              "Keychainのログイン情報を更新できませんでした。もう一度ログインしてください。")
        case .repositoryAccess:
            t("이 계정은 Kswiftin/K-MON 릴리스에 접근할 수 없어요.",
              "This account cannot access the Kswiftin/K-MON release.",
              "このアカウントはKswiftin/K-MONのリリースにアクセスできません。")
        }
    }

    // MARK: 알림
    var notifCritical: String { t("한도 임박", "Limit imminent", "上限切迫") }
    var notifWarning: String { t("한도 경고", "Limit warning", "上限警告") }
    func notifBody(_ name: String, _ percent: String) -> String {
        t("\(name) 한도 \(percent) 사용", "\(name) at \(percent)", "\(name) 上限 \(percent) 使用")
    }
    var claudeFiveHour: String { t("Claude 5시간 세션", "Claude 5-hour session", "Claude 5時間セッション") }
    var claudeWeekly: String { t("Claude 주간", "Claude weekly", "Claude 週間") }
    var codexPersonalLimit: String { t("Codex 개인 한도", "Codex personal limit", "Codex 個人上限") }

    // MARK: 가방 / 아이템
    var bag: String { t("가방", "Bag", "バッグ") }
    var bagEmptyTitle: String { t("아직 가방이 비어있어요!", "Your bag is empty!", "バッグはまだ空っぽです！") }
    var useItem: String { t("사용하기", "Use", "つかう") }
    var use: String { t("사용", "Use", "つかう") }
    var cancel: String { t("취소", "Cancel", "キャンセル") }
    func useOnCurrent(_ name: String) -> String {
        t("\(name)에게 사용할까요?", "Use on \(name)?", "\(name) に使いますか？")
    }
    var useAfterHatch: String { t("부화 후 사용할 수 있어요", "Usable after hatching", "孵化後に使えます") }
    var useNeedsPokemon: String { t("사용할 포켓몬이 없어요", "No Pokémon to use it on", "使えるポケモンがいません") }

    /// 팀 선택 영역 제목 — 이게 "내가 가진 것 중에서 고르는 자리" 임을 말해 준다.
    var teamPickerTitle: String { t("내 포켓몬에서 고르기", "Pick from your Pokémon", "手持ちから選ぶ") }

    /// 팀 선택 타입 필터의 '거르지 않음' 항목.
    var teamFilterAllTypes: String { t("전체 타입", "All types", "全タイプ") }

    // MARK: 체육관
    var gymLeagueTitle: String { t("체육관", "Gyms", "ジム") }

    // MARK: 퍼즐 던전 (#79)
    var dungeonTitle: String { t("오늘의 던전", "Today's Dungeon", "きょうのダンジョン") }
    var dungeonEnter: String { t("들어가기", "Enter", "はいる") }
    var dungeonRetry: String { t("다시 도전", "Try again", "もういちど") }
    var dungeonLeave: String { t("나가기", "Leave", "でる") }
    var dungeonFailed: String {
        t("쓰러졌다… 밟은 방은 기억에 남았어요.",
          "You collapsed… the rooms you walked stay remembered.",
          "たおれた… 歩いたへやは記憶に残りました。")
    }
    var dungeonClearedTitle: String { t("던전 클리어!", "Dungeon cleared!", "ダンジョンクリア！") }
    var dungeonAlreadyCleared: String {
        t("오늘 보상은 이미 받았어요 — 지금부터는 연습이에요.",
          "Today's reward is already paid — this is practice now.",
          "きょうの報酬は受け取りました — ここからは練習です。")
    }
    func dungeonRewardBody(_ amount: Int) -> String {
        t("별의조각 \(GameNumberFormatter.compact(amount))개를 받았어요.",
          "You received \(GameNumberFormatter.compact(amount)) Star Pieces.",
          "ほしのかけらを\(GameNumberFormatter.compact(amount))こ受け取りました。")
    }
    func dungeonRewardPreview(_ amount: Int) -> String {
        t("첫 클리어 보상 ⭐\(GameNumberFormatter.compact(amount))",
          "First clear pays ⭐\(GameNumberFormatter.compact(amount))",
          "初クリア報酬 ⭐\(GameNumberFormatter.compact(amount))")
    }
    func dungeonRoomCounter(_ visited: Int, _ total: Int) -> String {
        t("방 \(visited)/\(total)", "Room \(visited)/\(total)", "へや \(visited)/\(total)")
    }
    func dungeonHitPoints(_ hp: Int, _ budget: Int) -> String { "HP \(hp)/\(budget)" }
    /// 오늘의 상성 축과 예산을 한 줄로 — 왜 내 예산이 105 인지 화면에서 읽혀야 한다.
    func dungeonBudgetLine(_ type: PokemonType, _ budget: Int) -> String {
        t("\(type.name(lang))에 강한 파트너면 유리 · 예산 \(budget)",
          "A partner strong against \(type.name(lang)) helps · budget \(budget)",
          "\(type.name(lang))に強いパートナーが有利 · 予算\(budget)")
    }
    /// 먹는샘물 체크박스 — 재고가 없으면 개수 0 으로 그려 왜 못 쓰는지 보이게 한다.
    func dungeonDrinkFreshWater(_ count: Int) -> String {
        t("먹는샘물 마시고 시작 (+3, 보유 \(count))",
          "Drink Fresh Water first (+3, \(count) left)",
          "おいしいみずを飲んで開始（+3・残り\(count)）")
    }
    var freshWaterEffectHint: String {
        t("던전 입장 시 +3", "+3 on dungeon entry", "ダンジョン入場時 +3")
    }
    var dungeonExitUnknown: String { t("미탐사", "Unexplored", "未探索") }
    func dungeonRoomName(_ kind: RoomKind) -> String {
        switch kind {
        case .empty: return t("빈 방", "Empty room", "空きへや")
        case .encounter: return t("교전", "Encounter", "せんとう")
        case .spring: return t("회복의 샘", "Healing spring", "かいふくのいずみ")
        case .boss: return t("가장 깊은 방", "Deepest room", "いちばん深いへや")
        }
    }
    func dungeonExitCost(_ cost: Int) -> String {
        t("통로 \(cost)", "corridor \(cost)", "通路 \(cost)")
    }
    var dungeonSpringSpent: String { t("(사용됨)", "(spent)", "（使用済み）") }
    /// 로그 한 줄 — 코어는 값(`DungeonEvent`)만 남기고 문구는 여기서 만든다.
    func dungeonEventLine(_ event: DungeonEvent) -> String {
        switch event {
        case .entered(_, let kind): return dungeonRoomName(kind)
        case .damaged(let amount): return t("−\(amount) HP", "−\(amount) HP", "−\(amount) HP")
        case .healed(let amount): return t("+\(amount) HP", "+\(amount) HP", "+\(amount) HP")
        case .springAlreadyUsed: return t("샘이 말랐다", "The spring is dry", "いずみは枯れている")
        case .bossFelled: return t("가장 깊은 방을 넘었다!", "You cleared the deepest room!", "いちばん深いへやを越えた！")
        case .collapsed: return t("쓰러졌다", "You collapsed", "たおれた")
        }
    }
    var gymBadgeEarned: String { t("배지 획득", "Badge earned", "バッジ獲得") }
    func gymNeedsMorePokemon(_ count: Int) -> String {
        t("체육관은 \(count)마리로 도전해요 — 포켓몬이 부족합니다.",
          "Gyms take a team of \(count) — not enough Pokémon.",
          "ジムは\(count)体で挑みます — ポケモンが足りません。")
    }
    func gymBadgeCount(_ earned: Int, _ total: Int) -> String {
        t("배지 \(earned) / \(total)", "\(earned) / \(total) badges", "バッジ \(earned) / \(total)")
    }
    func gymLeaderLevel(_ level: Int) -> String {
        t("관장 Lv.\(level)", "Leader Lv.\(level)", "ジムリーダー Lv.\(level)")
    }
    var gymChallenge: String { t("도전", "Challenge", "挑戦") }

    /// 최종형인데 아직 졸업 못 하는 개체의 파트너 카드 한 줄 — 남은 관문이 레벨뿐임을 알린다.
    /// "Lv.N 에 진화" 가 사라진 그 자리에 들어간다.
    func graduatesAtLevel(_ level: Int) -> String {
        t("Lv.\(level)에 졸업", "Graduates at Lv.\(level)", "Lv.\(level)で卒業")
    }

    /// 돌·교환 진화 종의 파트너 카드 한 줄 — 레벨 진화의 "Lv.N 에 진화" 자리에 대신 들어간다.
    /// 상점에서 사서 가방에서 쓴다는 것까지는 담지 않는다(caption 한 줄) — 이름만 알면 상점에서 찾는다.
    func evolutionNeedsItem(_ item: String) -> String {
        t("\(item) 필요", "Needs \(item)", "\(item)が必要")
    }

    /// 아이템 표시명 — species 처럼 공식 현지명.
    func itemName(_ kind: ItemKind) -> String {
        switch kind {
        case .rareCandy: return t("이상한 사탕", "Rare Candy", "ふしぎなアメ")
        case .mint:      return t("민트", "Mint", "ミント")
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
        case .kingsRock: return t("왕의징표석", "King's Rock", "おうじゃのしるし")
        case .metalCoat: return t("금속코트", "Metal Coat", "メタルコート")
        case .dragonScale: return t("용의비늘", "Dragon Scale", "りゅうのウロコ")
        case .upgrade: return t("업그레이드", "Up-Grade", "アップグレード")
        case .dubiousDisc: return t("괴상한패치", "Dubious Disc", "あやしいパッチ")
        case .deepSeaTooth: return t("심해의이빨", "Deep Sea Tooth", "しんかいのキバ")
        case .deepSeaScale: return t("심해의비늘", "Deep Sea Scale", "しんかいのウロコ")
        case .protector: return t("프로텍터", "Protector", "プロテクター")
        case .electirizer: return t("에레키부스터", "Electirizer", "エレキブースター")
        case .magmarizer: return t("마그마부스터", "Magmarizer", "マグマブースター")
        case .reaperCloth: return t("영계의천", "Reaper Cloth", "れいかいのぬの")
        case .razorClaw: return t("예리한손톱", "Razor Claw", "するどいツメ")
        case .razorFang: return t("예리한이빨", "Razor Fang", "するどいキバ")
        case .prismScale: return t("아름다운비늘", "Prism Scale", "きれいなウロコ")
        case .freshWater: return t("먹는샘물", "Fresh Water", "おいしいみず")
        case .ovalStone: return t("둥근돌", "Oval Stone", "まるいいし")
        case .heartScale: return t("하트비늘", "Heart Scale", "ハートのウロコ")
        }
    }
    func itemDescription(_ kind: ItemKind) -> String {
        switch kind {
        case .rareCandy:
            let xp = GameNumberFormatter.compact(RareCandy.xp)   // 상수에서 파생(하드코딩 드리프트 방지)
            return t("현재 포켓몬의 경험치를 \(xp) 올려줘요.",
                     "Raises your Pokémon's EXP by \(xp).",
                     "ポケモンの経験値を\(xp)上げます。")
        case .mint:
            return t("현재 포켓몬의 성격을 랜덤으로 바꿔줘요.",
                     "Randomly changes your Pokémon's nature.",
                     "ポケモンのせいかくをランダムに変えます。")
        // 하트비늘(#97) — 아래 `default:` 는 진화 아이템 전용이라 여기에 명시하지 않으면
        // `evolutionRule == nil` 로 흘러가 설명이 빈 문자열이 된다.
        case .heartScale:
            return t("지금까지 배울 수 있었던 기술 하나를 다시 떠올려요. 기술이 4개면 하나를 잊어요.",
                     "Recalls one move it could have learned by now. With four moves, one is forgotten.",
                     "これまでに覚えられた技をひとつ思い出します。技が4つなら1つ忘れます。")
        case .shinyCharm:
            return t("보유하면 이로치 포켓몬이 태어날 확률이 올라가요.",
                     "While owned, raises the chance of hatching a shiny.",
                     "持っていると色違いが生まれる確率が上がります。")
        case .freshWater:
            return t("던전에 들어갈 때 한 병 마셔 체력 예산을 3 올려줘요.",
                     "Drink one on entering the dungeon to raise the hit-point budget by 3.",
                     "ダンジョンに入るとき1本飲んで体力予算を3上げます。")
        default:
            // 진화 아이템 설명은 규칙에서 갈린다 — 케이스를 27개 나열하면 새 아이템을 넣을 때 빠뜨린다.
            switch kind.evolutionRule {
            case .plainTrade:
                return t("통신교환으로 진화하는 포켓몬을 진화시켜요.", "Evolves a Pokémon that normally evolves by trade.", "通信交換で進化するポケモンを進化させます。")
            case .useItem:
                return t("이 돌에 반응하는 포켓몬을 진화시켜요.", "Evolves a Pokémon that reacts to this stone.", "この石に反応するポケモンを進化させます。")
            case .heldItem:
                return t("이 도구를 지녀야 진화하는 포켓몬을 진화시켜요.",
                         "Evolves a Pokémon that needs to hold this item.",
                         "この道具を持たせると進化するポケモンを進化させます。")
            case nil:
                return ""   // 진화 아이템이 아닌데 설명이 없는 경우(도달 불가 — 위 케이스가 다 덮는다)
            }
        }
    }
    /// 가방 사용 컨트롤의 효과 힌트 — 민트("성격 랜덤 변경", 사탕의 "+XP" 자리).
    var mintEffectHint: String { t("성격 랜덤 변경", "Random nature", "せいかくランダム変更") }

    // MARK: 하트비늘 (기술 다시 배우기 — #97)
    var heartScaleEffectHint: String { t("기술 다시 배우기", "Relearn a move", "技を思い出す") }
    var relearnHeader: String { t("기술을 다시 떠올릴까요?", "Relearn a move?", "技を思い出しますか？") }
    var relearnPickTitle: String { t("떠올릴 기술을 고르세요.", "Choose a move to relearn.", "思い出す技を選んでください。") }
    var relearnLoading: String { t("떠올릴 수 있는 기술을 찾고 있어요…", "Looking for moves to relearn…", "思い出せる技を探しています…") }
    var relearnEmpty: String { t("지금 떠올릴 수 있는 기술이 없어요.", "There are no moves to relearn right now.", "いま思い出せる技はありません。") }
    var relearnClose: String { t("닫기", "Close", "閉じる") }

    // MARK: 상점 (재화 = 별의모래)
    var shop: String { t("상점", "Shop", "ショップ") }
    var spendableTokens: String { t("보유 별의조각", "Star Pieces", "ほしのかけら") }
    var shopHint: String { t("모험에서 얻은 별의조각으로 아이템을 살 수 있어요.", "Buy items with Star Pieces earned from adventures.", "冒険で手に入れたほしのかけらで購入できます。") }
    var buy: String { t("구매", "Buy", "購入") }
    func buyConfirm(_ name: String) -> String { t("\(name) 구매할까요?", "Buy \(name)?", "\(name) を購入しますか？") }
    var notEnoughTokens: String { t("별의조각이 부족해요", "Not enough Star Pieces", "ほしのかけらが足りません") }
    func ownedCount(_ n: Int) -> String { t("보유 ×\(n)", "Owned ×\(n)", "所持 ×\(n)") }
    var shopPriceLabel: String { t("가격", "Price", "価格") }
    var ownedAlready: String { t("보유 중", "Owned", "所持済み") }
    var shinyCharmEffectHint: String { t("이로치 확률 ↑ · 적용 중", "Shiny rate ↑ · active", "色違い率↑ · 適用中") }
    // 알 (리롤) — tier = 보증 등급 하한(nil = 보증 없는 기본 알).
    // 이름은 `rarityLabel(r) + " 알"` 식 조합으로 만들지 않는다: 한국어·영어는 맞아떨어져도 일본어에서
    // 조사가 어긋난다(レアのタマゴ vs 자연스러운 レアなタマゴ). 세 언어를 명시 트리플로 적는다.
    func eggName(_ tier: Rarity?) -> String {
        switch tier {
        case nil, .common?: return t("알", "Egg", "タマゴ")
        case .uncommon?:  return t("고급 알", "Uncommon Egg", "アンコモンのタマゴ")
        case .rare?:      return t("희귀 알", "Rare Egg", "レアのタマゴ")
        case .legendary?: return t("전설 알", "Legendary Egg", "でんせつのタマゴ")   // 미판매(FreshEgg.shopTiers)
        }
    }
    func eggDescription(_ tier: Rarity?) -> String {
        guard let tier, tier != .common else {
            return t("소유 포켓몬은 그대로 두고 알을 1개 받아요.",
                     "Receive one Egg without releasing any Pokémon.",
                     "ポケモンを手放さず、タマゴを1個受け取ります。")
        }
        let r = rarityLabel(tier)
        return t("지금 포켓몬을 놓아주고 \(r) 이상이 확정으로 나오는 알을 받아요.",
                 "Send off your current Pokémon for an egg guaranteed to hatch \(r) or better.",
                 "いまのポケモンを手放して \(r) 以上が確定で孵るタマゴをもらいます。")
    }
    /// 인큐베이션 중 표시하는 보증 배지 — 어떤 알을 품고 있는지 한 줄로.
    func eggGuaranteeHint(_ tier: Rarity) -> String {
        let r = rarityLabel(tier)
        return t("\(r) 이상 확정", "\(r) or better", "\(r) 以上確定")
    }
    func eggConfirm(_ monName: String, _ eggName: String) -> String {
        t("\(monName)을(를) 놓아주고 \(eggName)(으)로 바꿀까요?",
          "Send off \(monName) for the \(eggName)?",
          "\(monName) を手放して \(eggName) にしますか？")
    }
    var freshEggShinyWarning: String { t("⚠️ 이로치 포켓몬이에요! 정말 놓아줄까요?", "⚠️ This one is shiny! Really send it off?", "⚠️ 色違いです！本当に手放しますか？") }
    var freshEggDiscardShiny: String { t("이로치 놓아주기", "Send shiny off", "手放す") }

    // MARK: 사탕 획득 알림 (일일 보상)
    func notifCandyTitle(item: String, count: Int) -> String {
        t("🍬 \(item) \(count)개를 받았어요!",
          "🍬 You got \(count)× \(item)!",
          "🍬 \(item)を\(count)個もらいました！")
    }
    var notifDailyCandyBody: String {
        t("오늘의 첫 만남 보상이에요 — 포켓몬에게 써서 진화시켜 보세요!",
          "Your daily check-in treat — use it to evolve your Pokémon!",
          "本日のごほうびです — ポケモンに使って進化させよう！")
    }
}
