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
    enum PortalAxis { case horizontal, vertical }
    struct PortalRoute {
        let axis: PortalAxis
        let target: CGFloat
        let crossingSign: CGFloat
        let completionCoordinate: CGFloat
    }

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
    private var pendingPortal: PortalRoute?
    private var lastPositionSave: TimeInterval = 0
    private var isAutomaticMove = false
    private var isUserDragging = false
    private var lastMouseChaseEnabled = false
    private let motion = FloatingPetMotionState()

    private static let originXKey = "floatingPetOriginX"
    private static let originYKey = "floatingPetOriginY"

    /// Squared movement (pt²) below which a mouse-up counts as a click, not a drag.
    static let clickThresholdSquared: CGFloat = 16  // ~4pt
    static let minimumTravelDuration: TimeInterval = 3
    static let maximumTravelDuration: TimeInterval = 8

    private var onOpenPopover: (() -> Void)?
    private var onChat: (() -> Void)?
    private var onHide: (() -> Void)?

    init(settings: AppSettings, companion: CompanionStore, defaults: UserDefaults = .standard,
         onOpenPopover: (() -> Void)? = nil, onChat: (() -> Void)? = nil, onHide: (() -> Void)? = nil) {
        self.settings = settings
        self.companion = companion
        self.defaults = defaults
        self.onOpenPopover = onOpenPopover
        self.onChat = onChat
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
            _ = settings.floatingPetMouseChaseEnabled
            _ = settings.floatingPetMovementSpeed
            _ = settings.floatingPetSpeciesID
            _ = settings.doNotDisturb
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
        if lastMouseChaseEnabled != settings.floatingPetMouseChaseEnabled {
            pendingPortal = nil
            lastMouseChaseEnabled = settings.floatingPetMouseChaseEnabled
        }
        guard settings.floatingPetEnabled, !settings.doNotDisturb, displayAwake else {
            stopMovement()
            hide()
            return
        }
        show()
        if settings.floatingPetRoamingEnabled || settings.floatingPetMouseChaseEnabled {
            startMovement()
        } else {
            stopMovement()
        }
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
            hosting.onChat = onChat
            hosting.onHide = onHide
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
        let desiredSize = Self.panelSize(petSize: petSize)
        let sizeChanged = p.frame.size != desiredSize
        var frame = NSRect(origin: p.frame.origin, size: desiredSize)
        if !p.isVisible {
            frame = targetFrame(petSize: petSize)
        } else if sizeChanged, pendingPortal == nil,
                  !Self.isCovered(frame, by: NSScreen.screens.map(\.visibleFrame)) {
            // 이미 보이는 패널의 일반 상태 갱신은 현재 위치를 보존한다. 통과 중 저장 좌표로
            // 되감기는 일을 막고, 실제 크기 변경으로 밖에 밀린 경우에만 복구한다.
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
        pendingPortal = nil
        persistCurrentOrigin()
    }

    private func chooseDirection(now: TimeInterval) {
        pendingPortal = nil
        let angle = Double.random(in: 0..<(Double.pi * 2))
        direction = CGVector(dx: cos(angle), dy: sin(angle))
        directionDeadline = now + Double.random(
            in: Self.minimumTravelDuration...Self.maximumTravelDuration)
        motion.facingLeft = direction.dx < 0
    }

    private func advanceMovement() {
        guard (settings.floatingPetRoamingEnabled || settings.floatingPetMouseChaseEnabled), !isUserDragging,
              let panel, panel.isVisible else { return }
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastMovementTick = now }
        guard let previous = lastMovementTick else { return }
        let delta = min(0.1, max(0, now - previous))
        let speed = CGFloat(settings.floatingPetMovementSpeed)
        if let route = pendingPortal {
            advanceTowardPortal(route, speed: speed, delta: delta, now: now)
            return
        }
        if settings.floatingPetMouseChaseEnabled {
            advanceMouseChase(panel: panel, speed: speed, delta: delta, now: now)
            return
        }
        if now >= directionDeadline { chooseDirection(now: now) }

        let velocity = CGVector(dx: direction.dx * speed, dy: direction.dy * speed)
        let screens = NSScreen.screens.map(\.visibleFrame)
        // 충돌한 뒤가 아니라 경계에 닿기 직전에 통과 모드를 선점한다. 통로 안으로 대각선 진입한 뒤
        // 세로 성분이 통로를 벗어나면 두 화면에 걸친 채 source 판정이 사라지는 간헐 교착을 막는다.
        if let route = Self.portalRoute(origin: panel.frame.origin,
                                        petSize: CGFloat(settings.floatingPetSize),
                                        velocity: velocity, screens: screens) {
            pendingPortal = route
            advanceTowardPortal(route, speed: speed, delta: delta, now: now)
            return
        }
        let result = Self.resolvedMotion(
            origin: panel.frame.origin,
            petSize: CGFloat(settings.floatingPetSize),
            velocity: velocity,
            delta: delta,
            screens: screens)
        if result.collided,
           let route = Self.portalRoute(origin: panel.frame.origin,
                                        petSize: CGFloat(settings.floatingPetSize),
                                        velocity: velocity, screens: screens) {
            pendingPortal = route
        }
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

    private func advanceMouseChase(panel: NSPanel, speed: CGFloat,
                                   delta: TimeInterval, now: TimeInterval) {
        let petSize = CGFloat(settings.floatingPetSize)
        let mouse = NSEvent.mouseLocation
        let velocity = Self.mouseChaseVelocity(
            petOrigin: panel.frame.origin, petSize: petSize,
            mouse: mouse, speed: speed)
        guard velocity.dx != 0 || velocity.dy != 0 else { return }
        if abs(velocity.dx) > 0.05 { motion.facingLeft = velocity.dx < 0 }
        let screens = NSScreen.screens.map(\.visibleFrame)
        if let route = Self.portalRoute(origin: panel.frame.origin, petSize: petSize,
                                        velocity: velocity, screens: screens, destination: mouse) {
            pendingPortal = route
            advanceTowardPortal(route, speed: speed, delta: delta, now: now)
            return
        }
        let result = Self.resolvedMotion(origin: panel.frame.origin, petSize: petSize,
                                         velocity: velocity, delta: delta, screens: screens)
        setAutomaticOrigin(result.origin)
        if now - lastPositionSave >= 2 {
            persistCurrentOrigin()
            lastPositionSave = now
        }
    }

    /// 커서까지의 직선 방향을 매 틱 다시 계산한다. 포인터를 가리지 않도록 펫 반지름 안에서는 정지한다.
    static func mouseChaseVelocity(petOrigin: NSPoint, petSize: CGFloat, mouse: NSPoint,
                                   speed: CGFloat) -> CGVector {
        let center = NSPoint(x: petOrigin.x + petSize / 2, y: petOrigin.y + petSize / 2)
        let dx = mouse.x - center.x
        let dy = mouse.y - center.y
        let distance = hypot(dx, dy)
        let stopDistance = max(24, petSize * 0.75)
        guard distance > stopDistance, speed > 0 else { return .zero }
        return CGVector(dx: dx / distance * speed, dy: dy / distance * speed)
    }

    private func advanceTowardPortal(_ route: PortalRoute, speed: CGFloat,
                                     delta: TimeInterval, now: TimeInterval) {
        guard let panel else { return }
        var origin = panel.frame.origin
        let step = speed * CGFloat(delta)
        let current = route.axis == .horizontal ? origin.y : origin.x
        let difference = route.target - current
        if abs(difference) <= step {
            if route.axis == .horizontal { origin.y = route.target }
            else { origin.x = route.target }
            // 서로 다른 backing scale의 화면 사이에 NSPanel을 걸쳐 두면 AppKit 좌표 보정과
            // 이동 타이머가 충돌해 경계에서 앞뒤로 떨린다. 유효 통로의 반대편으로 원자적으로 인계한다.
            setAutomaticOrigin(Self.portalDestinationOrigin(from: origin, route: route))
            direction = route.axis == .horizontal
                ? CGVector(dx: route.crossingSign, dy: 0)
                : CGVector(dx: 0, dy: route.crossingSign)
            motion.facingLeft = direction.dx < 0
            pendingPortal = nil
            directionDeadline = now + Self.minimumTravelDuration
            persistCurrentOrigin()
            return
        }
        let sign: CGFloat = difference < 0 ? -1 : 1
        let velocity = route.axis == .horizontal
            ? CGVector(dx: 0, dy: sign * speed)
            : CGVector(dx: sign * speed, dy: 0)
        let result = Self.resolvedMotion(
            origin: origin, petSize: CGFloat(settings.floatingPetSize),
            velocity: velocity, delta: delta, screens: NSScreen.screens.map(\.visibleFrame))
        setAutomaticOrigin(result.origin)
    }

    static func portalDestinationOrigin(from origin: NSPoint, route: PortalRoute) -> NSPoint {
        var next = origin
        switch route.axis {
        case .horizontal:
            next.y = route.target
            next.x = route.completionCoordinate
        case .vertical:
            next.x = route.target
            next.y = route.completionCoordinate
        }
        return next
    }

    private func setAutomaticOrigin(_ origin: NSPoint) {
        guard let panel else { return }
        isAutomaticMove = true
        panel.setFrameOrigin(origin)
        isAutomaticMove = false
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
        -> (origin: NSPoint, velocity: CGVector, collided: Bool) {
        let dx = velocity.dx * CGFloat(delta)
        let dy = velocity.dy * CGFloat(delta)
        let candidate = NSPoint(x: origin.x + dx, y: origin.y + dy)
        let rect = { (point: NSPoint) in
            NSRect(origin: point, size: NSSize(width: petSize, height: petSize))
        }
        if isCovered(rect(candidate), by: screens) { return (candidate, velocity, false) }

        let xOnly = NSPoint(x: origin.x + dx, y: origin.y)
        let yOnly = NSPoint(x: origin.x, y: origin.y + dy)
        let canMoveX = isCovered(rect(xOnly), by: screens)
        let canMoveY = isCovered(rect(yOnly), by: screens)
        switch (canMoveX, canMoveY) {
        case (true, false):
            return (xOnly, CGVector(dx: velocity.dx, dy: -velocity.dy), true)
        case (false, true):
            return (yOnly, CGVector(dx: -velocity.dx, dy: velocity.dy), true)
        case (true, true):
            // 오목한 모니터 배치의 코너에서는 각 축 이동은 가능해도 대각선 후보만 빈 공간일 수 있다.
            if abs(dx) >= abs(dy) {
                return (xOnly, CGVector(dx: velocity.dx, dy: -velocity.dy), true)
            }
            return (yOnly, CGVector(dx: -velocity.dx, dy: velocity.dy), true)
        case (false, false):
            return (origin, CGVector(dx: -velocity.dx, dy: -velocity.dy), true)
        }
    }

    /// 현재 화면의 막힌 경계 너머에 실제 이웃 모니터가 있으면, 펫 전체가 통과 가능한
    /// 가장 가까운 연결 구간을 찾는다. 모니터 외곽에는 route가 없으므로 기존 반사 동작을 유지한다.
    static func portalRoute(origin: NSPoint, petSize: CGFloat, velocity: CGVector,
                            screens: [NSRect], destination: NSPoint? = nil) -> PortalRoute? {
        let pet = NSRect(origin: origin, size: NSSize(width: petSize, height: petSize))
        let epsilon: CGFloat = 2
        let sources = screens.filter { source in
            let containsY = source.minY <= pet.minY + epsilon && source.maxY >= pet.maxY - epsilon
            let containsX = source.minX <= pet.minX + epsilon && source.maxX >= pet.maxX - epsilon
            let horizontalTrailingEdgeInside = containsY && (
                (velocity.dx > 0 && source.minX <= pet.minX + epsilon && pet.minX < source.maxX) ||
                (velocity.dx < 0 && source.maxX >= pet.maxX - epsilon && pet.maxX > source.minX))
            let verticalTrailingEdgeInside = containsX && (
                (velocity.dy > 0 && source.minY <= pet.minY + epsilon && pet.minY < source.maxY) ||
                (velocity.dy < 0 && source.maxY >= pet.maxY - epsilon && pet.maxY > source.minY))
            return horizontalTrailingEdgeInside || verticalTrailingEdgeInside
        }
        var routes: [PortalRoute] = []
        for source in sources {
            if velocity.dx > 0, pet.maxX >= source.maxX - abs(velocity.dx) * 0.1 - epsilon {
                for neighbor in screens where abs(neighbor.minX - source.maxX) <= epsilon {
                    let preferred = preferredPortalCoordinate(
                        origin: origin, petSize: petSize, seam: source.maxX,
                        destination: destination, axis: .horizontal)
                    if let target = portalTarget(current: preferred,
                                                 lower: max(source.minY, neighbor.minY),
                                                 upper: min(source.maxY, neighbor.maxY) - petSize) {
                        routes.append(PortalRoute(axis: .horizontal, target: target, crossingSign: 1,
                                                  completionCoordinate: neighbor.minX))
                    }
                }
            } else if velocity.dx < 0, pet.minX <= source.minX + abs(velocity.dx) * 0.1 + epsilon {
                for neighbor in screens where abs(neighbor.maxX - source.minX) <= epsilon {
                    let preferred = preferredPortalCoordinate(
                        origin: origin, petSize: petSize, seam: source.minX,
                        destination: destination, axis: .horizontal)
                    if let target = portalTarget(current: preferred,
                                                 lower: max(source.minY, neighbor.minY),
                                                 upper: min(source.maxY, neighbor.maxY) - petSize) {
                        routes.append(PortalRoute(axis: .horizontal, target: target, crossingSign: -1,
                                                  completionCoordinate: neighbor.maxX - petSize))
                    }
                }
            }
            if velocity.dy > 0, pet.maxY >= source.maxY - abs(velocity.dy) * 0.1 - epsilon {
                for neighbor in screens where abs(neighbor.minY - source.maxY) <= epsilon {
                    let preferred = preferredPortalCoordinate(
                        origin: origin, petSize: petSize, seam: source.maxY,
                        destination: destination, axis: .vertical)
                    if let target = portalTarget(current: preferred,
                                                 lower: max(source.minX, neighbor.minX),
                                                 upper: min(source.maxX, neighbor.maxX) - petSize) {
                        routes.append(PortalRoute(axis: .vertical, target: target, crossingSign: 1,
                                                  completionCoordinate: neighbor.minY))
                    }
                }
            } else if velocity.dy < 0, pet.minY <= source.minY + abs(velocity.dy) * 0.1 + epsilon {
                for neighbor in screens where abs(neighbor.maxY - source.minY) <= epsilon {
                    let preferred = preferredPortalCoordinate(
                        origin: origin, petSize: petSize, seam: source.minY,
                        destination: destination, axis: .vertical)
                    if let target = portalTarget(current: preferred,
                                                 lower: max(source.minX, neighbor.minX),
                                                 upper: min(source.maxX, neighbor.maxX) - petSize) {
                        routes.append(PortalRoute(axis: .vertical, target: target, crossingSign: -1,
                                                  completionCoordinate: neighbor.maxY - petSize))
                    }
                }
            }
        }
        return routes.min { abs($0.target - ($0.axis == .horizontal ? origin.y : origin.x)) <
                            abs($1.target - ($1.axis == .horizontal ? origin.y : origin.x)) }
    }

    private static func portalTarget(current: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat? {
        guard lower <= upper else { return nil }
        return min(max(current, lower), upper)
    }

    /// 직선이 화면 경계와 만나는 좌표를 통로 목표로 사용한다. 통로 범위를 벗어나면 이후 clamp되어
    /// 가장 가까운 끝점을 지나므로, 단순히 현재 높이를 유지하는 것보다 커서까지의 경로가 짧다.
    private static func preferredPortalCoordinate(origin: NSPoint, petSize: CGFloat, seam: CGFloat,
                                                   destination: NSPoint?, axis: PortalAxis) -> CGFloat {
        guard let destination else { return axis == .horizontal ? origin.y : origin.x }
        let center = NSPoint(x: origin.x + petSize / 2, y: origin.y + petSize / 2)
        switch axis {
        case .horizontal:
            let denominator = destination.x - center.x
            guard abs(denominator) > 0.001 else { return origin.y }
            let t = min(1, max(0, (seam - center.x) / denominator))
            return center.y + (destination.y - center.y) * t - petSize / 2
        case .vertical:
            let denominator = destination.y - center.y
            guard abs(denominator) > 0.001 else { return origin.x }
            let t = min(1, max(0, (seam - center.y) / denominator))
            return center.x + (destination.x - center.x) * t - petSize / 2
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
    var onChat: (() -> Void)?
    var onHide: (() -> Void)?
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
        let chat = menu.addItem(withTitle: l.t("대화하기", "Chat", "話す"),
                                action: #selector(handleChat(_:)), keyEquivalent: "")
        chat.target = self
        chat.isEnabled = true
        let hide = menu.addItem(withTitle: l.floatingPetMenuHide,
                                action: #selector(handleHide(_:)), keyEquivalent: "")
        hide.target = self
        hide.isEnabled = true
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc func handleOpen(_ sender: Any?) { onOpenPopover?() }
    @objc func handleChat(_ sender: Any?) { onChat?() }
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
