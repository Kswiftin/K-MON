import XCTest
@testable import PokeTokenBar

/// 첫 실행 화면은 **고를 것 하나**만 남긴다.
///
/// 예전엔 스타터를 고르기 전에도 트레이너 바(`Lv.1 · NEXT 320p · ⭐ 0`) · 집중 타이머 · 탭바 ·
/// 상점 · 가방이 다 떠 있었다. 그중 타이머는 "완료 시 파트너 보상" 이라고 말하는데 **파트너가
/// 아직 없다** — 앱이 첫 화면에서 없는 것의 보상을 약속한 셈이고, 탭들은 눌러도 빈 화면이다.
///
/// 왜 안 걸렸나: 화면 조각들은 각자 자기 상태만 본다. 타이머는 타이머 상태가 맞으면 옳고,
/// 탭바는 고른 탭을 칠하면 옳다. "아직 게임이 시작되지 않았다" 는 그중 누구의 상태도 아니라
/// 아무도 안 봤다 — 그래서 판정을 조각 밖에 하나로 둔다.
final class FirstRunChromeTests: XCTestCase {

    func testTheGameChromeIsHiddenUntilAStarterIsChosen() {
        XCTAssertFalse(PopoverChrome.showsGameChrome(needsStarterSelection: true),
                       "고를 것 하나만 남긴다 — 없는 파트너의 보상을 약속하지 않는다")
    }

    func testTheGameChromeComesBackOnceTheStarterExists() {
        XCTAssertTrue(PopoverChrome.showsGameChrome(needsStarterSelection: false))
    }

    // MARK: 첫 화면이 무슨 앱인지 말한다

    /// 처음 열면 이름 입력칸부터 나왔다. 이 앱이 집중 타이머인지 포켓몬 게임인지, 왜 이름을
    /// 묻는지 어디에도 없었다 — 세 언어 모두에서 한 줄로 말한다.
    func testTheStarterScreenSaysWhatTheAppIs() {
        for language in AppLanguage.allCases {
            let l = L(language)
            XCTAssertFalse(l.onboardingHeadline.isEmpty, "\(language)")
            XCTAssertFalse(l.onboardingSubhead.isEmpty, "\(language)")
        }
    }

    // MARK: 보상 줄의 단위

    /// 보상 미리보기가 `EXP` 를 하드코딩해 한국어 · 일본어 사용자도 영어를 봤다. 형제 문구
    /// (`focusHint` · `adventureText`)는 전부 세 언어를 타는데 이 줄만 빠져 있었다.
    func testTheRewardPreviewSpeaksTheChosenLanguage() {
        XCTAssertEqual(L(.ko).experienceUnit, "경험치")
        XCTAssertEqual(L(.ja).experienceUnit, "経験値")
        XCTAssertEqual(L(.en).experienceUnit, "EXP")
    }
}
