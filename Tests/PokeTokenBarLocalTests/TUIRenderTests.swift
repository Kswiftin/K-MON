import Testing
@testable import PokeTokenBar

// 진행 막대·시계는 TUI 가 상태를 보여주는 유일한 수단이다. AppKit 뷰와 달리 문자열이라
// 전부 순수 함수로 검증할 수 있다 — 터미널을 띄우지 않고 잡을 수 있는 결함을 여기서 잡는다.
@Suite("TUIRenderTests")
struct TUIRenderTests {

    // MARK: 진행 막대

    @Test func testEmptyBarIsAllHollow() {
        #expect(TUIRender.bar(progress: 0, width: 5) == "░░░░░")
    }

    @Test func testFullBarIsAllSolid() {
        #expect(TUIRender.bar(progress: 1, width: 5) == "█████")
    }

    @Test func testHalfBarSplitsEvenly() {
        #expect(TUIRender.bar(progress: 0.5, width: 10) == "█████░░░░░")
    }

    /// 진행도는 계산 결과라 범위를 벗어난 값이 들어올 수 있다(시계 되감김·0 길이 모험).
    /// 클램프가 없으면 문자열 반복 횟수가 음수가 되어 **크래시**한다.
    @Test func testProgressIsClampedOnBothEnds() {
        #expect(TUIRender.bar(progress: -3, width: 4) == "░░░░")
        #expect(TUIRender.bar(progress: 9, width: 4) == "████")
    }

    /// 아주 좁은 터미널에서 폭이 0 이하로 계산될 수 있다. 빈 문자열이어야 하고 크래시하면 안 된다.
    @Test func testNonPositiveWidthYieldsEmptyBar() {
        #expect(TUIRender.bar(progress: 0.5, width: 0) == "")
        #expect(TUIRender.bar(progress: 0.5, width: -2) == "")
    }

    /// 막대 길이는 진행도와 무관하게 **항상 요청한 폭**이다. 어긋나면 줄마다 테두리가 흔들린다.
    @Test func testBarLengthIsStableAcrossProgress() {
        for step in 0...20 {
            #expect(TUIRender.bar(progress: Double(step) / 20, width: 13).count == 13)
        }
    }

    // MARK: 남은 시간

    @Test func testDurationUnderAnHourUsesMinutesAndSeconds() {
        #expect(TUIRender.duration(0) == "00:00")
        #expect(TUIRender.duration(61) == "01:01")
        #expect(TUIRender.duration(59 * 60 + 59) == "59:59")
    }

    /// 90분 모험은 한 시간을 넘는다. 시 자리가 없으면 "30:00" 이 되어 남은 시간이 한 시간 줄어 보인다.
    @Test func testDurationOverAnHourGainsAnHourField() {
        #expect(TUIRender.duration(3600) == "1:00:00")
        #expect(TUIRender.duration(90 * 60) == "1:30:00")
    }

    /// 끝난 모험을 늦게 열면 남은 시간이 음수로 온다. 음수 시계를 그리면 정산 가능한 상태가
    /// 아직 진행 중인 것처럼 보인다.
    @Test func testNegativeDurationFloorsAtZero() {
        #expect(TUIRender.duration(-42) == "00:00")
    }

    // MARK: 화면 구성

    /// 모든 줄은 터미널 폭을 넘지 않아야 한다. 넘치면 터미널이 접어 다음 줄을 밀어내고
    /// 화면 전체가 위로 흘러간다(전체 다시 그리기 방식이라 복구되지 않는다).
    @Test func testHomeLinesNeverExceedTerminalWidth() {
        let model = TUIHomeModel.sample
        for width in [24, 40, 80, 120] {
            for line in TUIRender.home(model, width: width) {
                #expect(TUIText.displayWidth(line) <= width, "폭 \(width) 에서 넘침: \(line)")
            }
        }
    }

    /// 파트너가 없는 상태(알 부화 중)도 홈이 그려져야 한다 — 초기 사용자가 처음 보는 화면이다.
    @Test func testHomeRendersWithoutPartner() {
        var model = TUIHomeModel.sample
        model.partnerName = nil
        #expect(!(TUIRender.home(model, width: 60).isEmpty))
    }

    /// 목록은 높이만큼만 돌려준다. 넘겨 주면 화면 밖으로 나가 스크롤이 터진다.
    @Test func testListNeverReturnsMoreLinesThanHeight() {
        let rows = (0..<50).map { "행 \($0)" }
        let lines = TUIRender.list(rows: rows, selection: 30, height: 7, width: 40)
        #expect(lines.count == 7)
    }

    /// 선택 행은 항상 보이는 창 안에 있어야 한다 — 커서가 창 밖으로 나가면 조작이 눈먼다.
    @Test func testListWindowFollowsSelection() {
        let rows = (0..<50).map { "행 \($0)" }
        for selection in [0, 12, 30, 49] {
            let lines = TUIRender.list(rows: rows, selection: selection, height: 7, width: 40)
            #expect(lines.contains { $0.contains("행 \(selection)") }, "선택 \(selection) 이 창 밖으로 나갔다")
        }
    }

    /// 커서 표식과 행의 활성 표식은 **반드시 달라야** 한다. 같으면 같은 열에 두 뜻이 겹쳐
    /// `▸ ▸ 고디탱` 처럼 찍히고, 어느 쪽이 커서인지 화면만 보고는 알 수 없다.
    @Test func testCursorAndActiveMarksAreDistinct() {
        #expect(TUIRender.cursorMark != TUIRender.activeMark)
    }

    /// 커서 표식은 선택된 줄에만 붙는다.
    @Test func testOnlyTheSelectedRowCarriesTheCursorMark() {
        let lines = TUIRender.list(rows: ["가", "나", "다"], selection: 1, height: 3, width: 20)
        #expect(lines.filter { $0.hasPrefix(TUIRender.cursorMark) }.count == 1)
        #expect(lines[1].hasPrefix(TUIRender.cursorMark))
    }

    @Test func testListHandlesEmptyRows() {
        #expect(TUIRender.list(rows: [], selection: 0, height: 3, width: 20).count == 3)
    }
}
