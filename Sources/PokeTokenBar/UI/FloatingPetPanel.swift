import AppKit
import SwiftUI

@MainActor
@Observable
final class FloatingPetMotionState {
    var facingLeft = false
}

/// 데스크톱 위에 떠 있는 컴패니언 포켓몬 오버레이(옵트인, 설정 → 플로팅 펫).
/// - 드래그: 커스텀 `mouseDragged` (클릭과 충돌하지 않음).
/// - 클릭 → 팝오버, 우클릭 → 메뉴, 호버 → 함께한 시간 콜아웃.
/// - 에너지: 숨김·슬립 시 호스팅 트리 해제.
@MainActor
final class FloatingPetController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let companion: CompanionStore
    private let defaults: UserDefaults
    private var panel: NSPanel?
    private var hoverPanel: NSPanel?
    private var displayAwake = true
    private var builtAnimated: Bool?
    private var powerObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var movementTimer: Timer?
    private var lastMovementTick: TimeInterval?
    private var direction = CGVector(dx: 1, dy: 0)
    private var directionDeadline: TimeInterval = 0
    private var lastPositionSave: TimeInterval = 0
    private var isAutomaticMove = false
    private var isUserDragging = false
    private let motion = FloatingPetMotionState()

    private static let originXKey = "floatingPetOriginX"
    private static let originYKey = "floatingPetOriginY"

    /// Squared movement (pt²) below which a mouse-up counts as a click, not a drag.
    static let clickThresholdSquared: CGFloat = 16  // ~4pt
    static let minimumTravelDuration: TimeInterval = 3
    static let maximumTravelDuration: TimeInterval = 8

    private var onOpenPopover: (() -> Void)?
    private var onHide: (() -> Void)?

    init(settings: AppSettings, companion: CompanionStore, defaults: UserDefaults = .standard,
         onOpenPopover: (() -> Void)? = nil, onHide: (() -> Void)? = nil) {
        self.settings = settings
        self.companion = companion
        self.defaults = defaults
        self.onOpenPopover = onOpenPopover
        self.onHide = onHide
        super.init()
        observeSettings()
        observePowerState()
        observeScreens()
        sync()
    }

    static func isClick(from start: NSPoint, to end: NSPoint,
                        thresholdSquared: CGFloat = clickThresholdSquared) -> Bool {
        let dx = end.x - start.x, dy = end.y - start.y
        return dx * dx + dy * dy < thresholdSquared
    }

    func setDisplayAwake(_ awake: Bool) {
        displayAwake = awake
        sync()
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.floatingPetEnabled
            _ = settings.floatingPetSize
            _ = settings.floatingPetRoamingEnabled
            _ = settings.floatingPetMovementSpeed
            _ = settings.floatingPetSpeciesID
            _ = settings.doNotDisturb
            _ = companion.activeSecondsToday
            _ = companion.language
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.sync()
                self.observeSettings()
            }
        }
    }

    private func observePowerState() {
        powerObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
    }

    private func observeScreens() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screenConfigurationDidChange() }
        }
    }

    static func shouldAnimate(lowPower: Bool) -> Bool { !lowPower }

    static func panelSize(petSize: CGFloat) -> NSSize { NSSize(width: petSize, height: petSize) }

    static func panelOrigin(petOrigin: NSPoint, petSize: CGFloat, panelSize: NSSize) -> NSPoint {
        let xInset = max(0, (panelSize.width - petSize) / 2)
        return NSPoint(x: petOrigin.x - xInset, y: petOrigin.y)
    }

    static func petOrigin(panelOrigin: NSPoint, petSize: CGFloat, panelSize: NSSize) -> NSPoint {
        let xInset = max(0, (panelSize.width - petSize) / 2)
        return NSPoint(x: panelOrigin.x + xInset, y: panelOrigin.y)
    }

    private func sync() {
        guard settings.floatingPetEnabled, !settings.doNotDisturb, displayAwake else {
            stopMovement()
            hide()
            return
        }
        show()
        if settings.floatingPetRoamingEnabled { startMovement() } else { stopMovement() }
    }

    private func show() {
        let p = panel ?? makePanel()
        panel = p
        let wantAnimated = Self.shouldAnimate(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        if p.contentView == nil || builtAnimated != wantAnimated {
            let hosting = PetHostingView(rootView: AnyView(
                FloatingPetView(animated: wantAnimated, motion: motion)
                    .environment(settings).environment(companion)))
            hosting.onOpenPopover = onOpenPopover
            hosting.onHide = onHide
            hosting.onPet = { [weak self] in _ = self?.companion.petCompanion() }
            hosting.languageProvider = { [weak self] in self?.companion.language ?? .systemDefault }
            hosting.onHoverChange = { [weak self] hovering in
                if hovering { self?.showHoverCallout() } else { self?.hideHoverCallout() }
            }
            hosting.onDragChange = { [weak self] dragging in
                self?.isUserDragging = dragging
                if !dragging { self?.persistCurrentOrigin() }
            }
            p.contentView = hosting
            builtAnimated = wantAnimated
        }
        if let hosting = p.contentView as? PetHostingView {
            hosting.toolTip = currentHoverText()
        }
        let petSize = CGFloat(settings.floatingPetSize)
        var frame = NSRect(origin: p.frame.origin, size: Self.panelSize(petSize: petSize))
        if !p.isVisible || !Self.isCovered(frame, by: NSScreen.screens.map(\.visibleFrame)) {
            frame = targetFrame(petSize: petSize)
        }
        p.setFrame(frame, display: true)
        p.orderFrontRegardless()
        if hoverPanel?.isVisible == true { showHoverCallout() }
    }

    private func hide() {
        persistCurrentOrigin()
        hideHoverCallout()
        guard let p = panel else { return }
        p.orderOut(nil)
        p.contentView = nil
        builtAnimated = nil
    }

    private func startMovement() {
        guard movementTimer == nil else { return }
        chooseDirection(now: ProcessInfo.processInfo.systemUptime)
        lastMovementTick = nil
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceMovement() }
        }
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        movementTimer = timer
    }

    private func stopMovement() {
        movementTimer?.invalidate()
        movementTimer = nil
        lastMovementTick = nil
        persistCurrentOrigin()
    }

    private func chooseDirection(now: TimeInterval) {
        let angle = Double.random(in: 0..<(Double.pi * 2))
        direction = CGVector(dx: cos(angle), dy: sin(angle))
        directionDeadline = now + Double.random(
            in: Self.minimumTravelDuration...Self.maximumTravelDuration)
        motion.facingLeft = direction.dx < 0
    }

    private func advanceMovement() {
        guard settings.floatingPetRoamingEnabled, !isUserDragging,
              let panel, panel.isVisible else { return }
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastMovementTick = now }
        guard let previous = lastMovementTick else { return }
        let delta = min(0.1, max(0, now - previous))
        if now >= directionDeadline { chooseDirection(now: now) }

        let speed = CGFloat(settings.floatingPetMovementSpeed)
        let velocity = CGVector(dx: direction.dx * speed, dy: direction.dy * speed)
        let result = Self.resolvedMotion(
            origin: panel.frame.origin,
            petSize: CGFloat(settings.floatingPetSize),
            velocity: velocity,
            delta: delta,
            screens: NSScreen.screens.map(\.visibleFrame))
        if speed > 0 {
            direction = CGVector(dx: result.velocity.dx / speed, dy: result.velocity.dy / speed)
            if abs(direction.dx) > 0.05 { motion.facingLeft = direction.dx < 0 }
        }
        isAutomaticMove = true
        panel.setFrameOrigin(result.origin)
        isAutomaticMove = false
        if now - lastPositionSave >= 2 {
            persistCurrentOrigin()
            lastPositionSave = now
        }
    }

    private func currentHoverText() -> String {
        "\(L(companion.language).todayTokens) \(L(companion.language).duration(companion.activeSecondsToday))"
    }

    private func showHoverCallout() {
        guard let pet = panel, pet.isVisible else { return }
        let text = currentHoverText()
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.backgroundColor = .clear
        label.drawsBackground = false
        label.sizeToFit()

        let pad: CGFloat = 8
        let size = NSSize(width: label.bounds.width + pad * 2,
                          height: label.bounds.height + pad * 2)
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        label.frame.origin = NSPoint(x: pad, y: pad)
        container.addSubview(label)

        let hp = hoverPanel ?? makeHoverPanel()
        hoverPanel = hp
        hp.contentView = container
        hp.setContentSize(size)
        let petFrame = pet.frame
        hp.setFrameOrigin(NSPoint(x: petFrame.midX - size.width / 2, y: petFrame.maxY + 6))
        hp.orderFrontRegardless()
    }

    private func hideHoverCallout() {
        hoverPanel?.orderOut(nil)
        hoverPanel?.contentView = nil
    }

    private func makeHoverPanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true
        p.animationBehavior = .none
        return p
    }

    private func targetFrame(petSize: CGFloat) -> NSRect {
        let size = Self.panelSize(petSize: petSize)
        let petOrigin: NSPoint
        if let x = defaults.object(forKey: Self.originXKey) as? Double,
           let y = defaults.object(forKey: Self.originYKey) as? Double {
            petOrigin = NSPoint(x: x, y: y)
        } else {
            petOrigin = Self.defaultPetOrigin(petSize: petSize)
        }
        var frame = NSRect(origin: Self.panelOrigin(petOrigin: petOrigin, petSize: petSize, panelSize: size),
                           size: size)
        if !Self.isCovered(frame, by: NSScreen.screens.map(\.visibleFrame)) {
            let fallbackPet = Self.defaultPetOrigin(petSize: petSize)
            frame.origin = Self.panelOrigin(petOrigin: fallbackPet, petSize: petSize, panelSize: size)
        }
        return frame
    }

    /// 사각형 전체가 여러 모니터의 visibleFrame 합집합 안에 있는지 판정한다.
    /// 맞닿은 두 모니터의 경계에 걸친 펫도 허용하되, 바깥쪽과 모니터 사이 빈 공간은 막는다.
    static func isCovered(_ rect: NSRect, by screens: [NSRect]) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        let clipped = screens.map { $0.intersection(rect) }
            .filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
        guard !clipped.isEmpty else { return false }

        var xs = [rect.minX, rect.maxX]
        for frame in clipped { xs.append(frame.minX); xs.append(frame.maxX) }
        xs = Array(Set(xs)).sorted()
        let epsilon: CGFloat = 0.01
        for index in 0..<(xs.count - 1) where xs[index + 1] - xs[index] > epsilon {
            let midX = (xs[index] + xs[index + 1]) / 2
            let intervals = clipped.filter { $0.minX <= midX && midX <= $0.maxX }
                .map { (max(rect.minY, $0.minY), min(rect.maxY, $0.maxY)) }
                .sorted { $0.0 < $1.0 }
            guard var coveredY = intervals.first?.0, coveredY <= rect.minY + epsilon else { return false }
            for interval in intervals {
                if interval.0 > coveredY + epsilon { return false }
                coveredY = max(coveredY, interval.1)
                if coveredY >= rect.maxY - epsilon { break }
            }
            if coveredY < rect.maxY - epsilon { return false }
        }
        return true
    }

    static func resolvedMotion(origin: NSPoint, petSize: CGFloat, velocity: CGVector,
                               delta: TimeInterval, screens: [NSRect])
        -> (origin: NSPoint, velocity: CGVector) {
        let dx = velocity.dx * CGFloat(delta)
        let dy = velocity.dy * CGFloat(delta)
        let candidate = NSPoint(x: origin.x + dx, y: origin.y + dy)
        let rect = { (point: NSPoint) in
            NSRect(origin: point, size: NSSize(width: petSize, height: petSize))
        }
        if isCovered(rect(candidate), by: screens) { return (candidate, velocity) }

        let xOnly = NSPoint(x: origin.x + dx, y: origin.y)
        let yOnly = NSPoint(x: origin.x, y: origin.y + dy)
        let canMoveX = isCovered(rect(xOnly), by: screens)
        let canMoveY = isCovered(rect(yOnly), by: screens)
        switch (canMoveX, canMoveY) {
        case (true, false):
            return (xOnly, CGVector(dx: velocity.dx, dy: -velocity.dy))
        case (false, true):
            return (yOnly, CGVector(dx: -velocity.dx, dy: velocity.dy))
        case (true, true):
            // 오목한 모니터 배치의 코너에서는 각 축 이동은 가능해도 대각선 후보만 빈 공간일 수 있다.
            if abs(dx) >= abs(dy) {
                return (xOnly, CGVector(dx: velocity.dx, dy: -velocity.dy))
            }
            return (yOnly, CGVector(dx: -velocity.dx, dy: velocity.dy))
        case (false, false):
            return (origin, CGVector(dx: -velocity.dx, dy: -velocity.dy))
        }
    }

    private func screenConfigurationDidChange() {
        guard let panel else { return }
        let screens = NSScreen.screens.map(\.visibleFrame)
        guard !Self.isCovered(panel.frame, by: screens) else { return }
        panel.setFrame(targetFrame(petSize: CGFloat(settings.floatingPetSize)), display: true)
        chooseDirection(now: ProcessInfo.processInfo.systemUptime)
    }

    private static func defaultPetOrigin(petSize: CGFloat) -> NSPoint {
        guard let visible = NSScreen.main?.visibleFrame else { return NSPoint(x: 120, y: 120) }
        return NSPoint(x: visible.maxX - petSize - 24, y: visible.minY + 24)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        p.allowsToolTipsWhenApplicationIsInactive = true
        p.animationBehavior = .none
        p.delegate = self
        return p
    }

    func windowDidMove(_ notification: Notification) {
        guard let p = panel, p.isVisible else { return }
        if isAutomaticMove {
            if hoverPanel?.isVisible == true { showHoverCallout() }
            return
        }
        persistCurrentOrigin()
        if hoverPanel?.isVisible == true { showHoverCallout() }
    }

    private func persistCurrentOrigin() {
        guard let p = panel, p.isVisible else { return }
        let petSize = CGFloat(settings.floatingPetSize)
        let size = Self.panelSize(petSize: petSize)
        let pet = Self.petOrigin(panelOrigin: p.frame.origin, petSize: petSize, panelSize: size)
        defaults.set(Double(pet.x), forKey: Self.originXKey)
        defaults.set(Double(pet.y), forKey: Self.originYKey)
    }
}

final class PetHostingView: NSHostingView<AnyView> {
    var onOpenPopover: (() -> Void)?
    var onHide: (() -> Void)?
    var onPet: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    var onDragChange: ((Bool) -> Void)?
    var languageProvider: () -> AppLanguage = { .systemDefault }

    private var mouseDownScreen: NSPoint?
    private var originAtDown: NSPoint?
    private var didDrag = false

    override var mouseDownCanMoveWindow: Bool { false }

    static func isClick(from start: NSPoint, to end: NSPoint,
                        thresholdSquared: CGFloat = FloatingPetController.clickThresholdSquared) -> Bool {
        FloatingPetController.isClick(from: start, to: end, thresholdSquared: thresholdSquared)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            showContextMenu(event)
            return
        }
        mouseDownScreen = NSEvent.mouseLocation
        originAtDown = window?.frame.origin
        didDrag = false
        onDragChange?(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let start = mouseDownScreen, let origin = originAtDown else { return }
        let now = NSEvent.mouseLocation
        if !Self.isClick(from: start, to: now) { didDrag = true }
        window.setFrameOrigin(NSPoint(x: origin.x + (now.x - start.x),
                                      y: origin.y + (now.y - start.y)))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            onDragChange?(false)
            mouseDownScreen = nil
            originAtDown = nil
            didDrag = false
        }
        guard !didDrag, let start = mouseDownScreen else { return }
        if Self.isClick(from: start, to: NSEvent.mouseLocation) {
            onOpenPopover?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        showContextMenu(event)
    }

    private func showContextMenu(_ event: NSEvent) {
        onHoverChange?(false)
        NSApp.activate(ignoringOtherApps: true)
        let l = L(languageProvider())
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false
        let open = menu.addItem(withTitle: l.floatingPetMenuOpen,
                                action: #selector(handleOpen(_:)), keyEquivalent: "")
        open.target = self
        open.isEnabled = true
        let pet = menu.addItem(withTitle: languageProvider() == .ko ? "쓰다듬기" : "Pet",
                               action: #selector(handlePet(_:)), keyEquivalent: "")
        pet.target = self
        pet.isEnabled = true
        let hide = menu.addItem(withTitle: l.floatingPetMenuHide,
                                action: #selector(handleHide(_:)), keyEquivalent: "")
        hide.target = self
        hide.isEnabled = true
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc func handleOpen(_ sender: Any?) { onOpenPopover?() }
    @objc func handlePet(_ sender: Any?) { onPet?() }
    @objc func handleHide(_ sender: Any?) { onHide?() }
}

struct FloatingPetView: View {
    // 플로팅 펫도 쇼다운 GIF가 가진 원본 프레임 속도를 그대로 사용한다.
    static let frameFloor: TimeInterval = 0
    var animated: Bool = true
    var motion: FloatingPetMotionState
    @Environment(AppSettings.self) private var settings
    @Environment(CompanionStore.self) private var companion

    var body: some View {
        let size = CGFloat(settings.floatingPetSize)
        VStack(spacing: 8) {
            let subject = companion.floatingPetSubject(pinnedSpeciesID: settings.floatingPetSpeciesID)
            SpriteView(speciesID: subject.speciesID, size: size, animated: animated,
                       shiny: subject.isShiny, minFrameDelay: Self.frameFloor)
                .frame(width: size, height: size)
                .scaleEffect(x: motion.facingLeft ? -1 : 1, y: 1)
                .zIndex(0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .environment(\.spriteAntialiasing, settings.imageAntialiasing)
    }
}
