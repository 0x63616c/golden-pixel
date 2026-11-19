/// Immediate-mode UI on the art grid: the renderer records hit regions as it draws, and
/// gestures resolve against the regions of the last frame.

public enum Tab: Int, Sendable, CaseIterable { case balls, upgrades, skills, more }

public enum Action: Equatable, Sendable {
    case start
    case tab(Tab)
    case toggleCollapse
    case buyBall(BallKind)
    case upgrade(BallKind, Stat)
    case specialize(BallKind, Int)
    case skill(String)
    case closeSkills
    case prestige
    case setting(Int)
    case board
    case panel
    case none
}

public struct Hit: Sendable {
    public var rect: Rect
    public var action: Action
    /// Shown on long-press only.
    public var info: [String]
}

public struct Tooltip: Sendable {
    public var lines: [String]
    public var at: Point
}

public struct UIState: Sendable {
    public var started = false
    public var tab: Tab = .balls
    public var collapsed = false
    public var scroll = 0
    public var maxScroll = 0
    public var skillsOpen = false
    public var skillPan = Point(0, 0)
    public var tooltip: Tooltip?
    public var confirmPrestigeUntil = -1.0
    public var pressed: Action = .none
    public var pressedUntil = 0.0
    public var hits: [Hit] = []
    public var layout = Layout.make(width: Tuning.canvasWidth, height: Tuning.canvasHeight, collapsed: false)
    /// Board zoom and pan. The UI itself never zooms.
    public var camera = Camera(boardW: Tuning.boardCells * Tuning.cellPixels, boardH: Tuning.boardCells * Tuning.cellPixels,
                               viewW: Tuning.boardCells * Tuning.cellPixels, viewH: Tuning.boardCells * Tuning.cellPixels)
    var lastDragCell = -1
    /// What a one-finger drag on the board does, decided where it starts.
    var dragMode: DragMode = .none
    var lastTap: (at: Point, time: Double)?
    public init() {}
}

/// Where the board and the panel go for a canvas size. Landscape puts the panel on the
/// right; a tall canvas puts it underneath. The board is always the hero.
public struct Layout: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var board: Rect
    public var panel: Rect
    public var landscape: Bool

    public static let railWidth = 17

    public static func make(width w: Int, height h: Int, collapsed: Bool) -> Layout {
        let side = Tuning.boardCells * Tuning.cellPixels
        if w >= h {
            let panelW = collapsed ? railWidth : max(railWidth, w - max(h, side + 3))
            let free = w - panelW
            let board = Rect((free - side) / 2, (h - side) / 2, side, side)
            return Layout(width: w, height: h, board: board, panel: Rect(w - panelW, 0, panelW, h), landscape: true)
        } else {
            let panelH = collapsed ? railWidth : max(railWidth, h - max(w, side + 3))
            let free = h - panelH
            let board = Rect((w - side) / 2, (free - side) / 2, side, side)
            return Layout(width: w, height: h, board: board, panel: Rect(0, h - panelH, w, panelH), landscape: false)
        }
    }
}

enum DragMode: Sendable { case none, chip, pan, scroll, skills }

public enum Gesture: Equatable, Sendable {
    case tap(Point, time: Double = 0)
    case longPress(Point)
    case drag(from: Point, to: Point)
    case release(Point)
    /// Two fingers: zoom by `factor` about `center`, and pan by the centre's movement.
    case pinch(center: Point, factor: Double, dx: Int, dy: Int)
    case pinchEnded
}

/// Turns raw touches (in canvas pixels) into taps, long-presses, drags and pinches. A second
/// finger always wins: it cancels the first finger's tap or drag and starts a pinch, and
/// nothing more is reported until every finger is up.
public struct PointerTracker: Sendable {
    public static let dragThreshold = 3
    public static let longPressTime = 0.42
    var start: Point?
    var last = Point(0, 0)
    var startTime = 0.0
    var dragging = false
    var longFired = false
    var touches: [Int: Point] = [:]
    var order: [Int] = []
    var pinching = false
    var swallow = false
    var pinchDist = 0.0
    var pinchMid = Point(0, 0)

    public init() {}

    public mutating func began(_ p: Point, id: Int = 0, at t: Double) -> [Gesture] {
        touches[id] = p; order.append(id)
        if touches.count == 1 && !swallow {
            start = p; last = p; startTime = t; dragging = false; longFired = false
            return []
        }
        guard touches.count >= 2, !pinching else { return [] }
        var out: [Gesture] = []
        if start != nil, dragging || longFired { out.append(.release(last)) }
        start = nil
        pinching = true; swallow = true
        (pinchDist, pinchMid) = pinchState()
        return out
    }

    func pinchState() -> (Double, Point) {
        let a = touches[order[0]]!, b = touches[order[1]]!
        let dx = Double(a.x - b.x), dy = Double(a.y - b.y)
        return (max(1, (dx * dx + dy * dy).squareRoot()), Point((a.x + b.x) / 2, (a.y + b.y) / 2))
    }

    public mutating func moved(_ p: Point, id: Int = 0, at t: Double) -> [Gesture] {
        guard touches[id] != nil else { return [] }
        touches[id] = p
        if pinching {
            guard touches.count >= 2 else { return [] }
            let (d, m) = pinchState()
            defer { pinchDist = d; pinchMid = m }
            return [.pinch(center: m, factor: d / pinchDist, dx: m.x - pinchMid.x, dy: m.y - pinchMid.y)]
        }
        guard let s = start else { return [] }
        if !dragging, abs(p.x - s.x) + abs(p.y - s.y) > PointerTracker.dragThreshold, !longFired { dragging = true }
        defer { last = p }
        return dragging ? [.drag(from: last, to: p)] : []
    }

    public mutating func ended(_ p: Point, id: Int = 0, at t: Double) -> [Gesture] {
        guard touches[id] != nil else { return [] }
        touches[id] = nil; order.removeAll { $0 == id }
        if pinching {
            if touches.count < 2 { pinching = false; return [.pinchEnded] }
            (pinchDist, pinchMid) = pinchState()
            return []
        }
        if touches.isEmpty { defer { swallow = false } ; if swallow { start = nil; return [] } }
        guard start != nil else { return [] }
        defer { start = nil }
        if longFired || dragging { return [.release(p)] }
        return [.tap(p, time: t)]
    }

    public mutating func tick(at t: Double) -> [Gesture] {
        guard !pinching, let s = start, !dragging, !longFired, t - startTime >= PointerTracker.longPressTime else { return [] }
        longFired = true
        return [.longPress(s)]
    }
}

extension Game {
    public func handle(_ g: Gesture) {
        switch g {
        case .tap(let p, let time):
            ui.tooltip = nil
            if !ui.started { ui.started = true; events.append(.tap); return }
            guard let h = hit(at: p) else { return }
            // Double-tap on open space (not a block, which a tap always hits) toggles zoom.
            if h.action == .board, !breakableShown(p) {
                if let last = ui.lastTap, time - last.time < Game.doubleTapTime,
                   abs(last.at.x - p.x) + abs(last.at.y - p.y) <= 8 {
                    let v = viewPoint(p)
                    ui.camera.toggle(at: v.x, v.y)
                    ui.lastTap = nil
                    return
                }
                ui.lastTap = (p, time)
            } else {
                ui.lastTap = nil
            }
            perform(h.action, at: p)
        case .longPress(let p):
            guard ui.started, let h = hit(at: p) else { return }
            if !h.info.isEmpty { ui.tooltip = Tooltip(lines: h.info, at: p) }
            else if h.action == .board, let i = boardCell(p), board.revealed[i], board.kind[i] == .block {
                ui.tooltip = Tooltip(lines: ["HP \(compact(board.hp[i].rounded(.up)))"], at: p)
            }
        case .drag(let from, let to):
            guard ui.started else { return }
            if ui.dragMode == .none {
                // Decide once, where the finger went down: a swipe that starts on a visible
                // block chips blocks; one that starts on open space or fog pans the camera.
                if ui.skillsOpen { ui.dragMode = .skills }
                else if ui.layout.panel.contains(from) { ui.dragMode = .scroll }
                else if ui.layout.board.contains(from) { ui.dragMode = breakableShown(from) ? .chip : .pan }
                else { ui.dragMode = .scroll }
            }
            switch ui.dragMode {
            case .skills:
                ui.skillPan = Point(ui.skillPan.x + to.x - from.x, ui.skillPan.y + to.y - from.y)
                ui.skillPan.x = max(-120, min(120, ui.skillPan.x)); ui.skillPan.y = max(-90, min(90, ui.skillPan.y))
            case .scroll:
                ui.scroll = max(0, min(ui.maxScroll, ui.scroll + from.y - to.y))
            case .pan:
                ui.camera.pan(Double(to.x - from.x), Double(to.y - from.y))
            case .chip:
                if let i = boardCell(to), i != ui.lastDragCell {
                    ui.lastDragCell = i
                    tap(cellX: i % board.size, cellY: i / board.size)
                }
            case .none: break
            }
        case .release:
            ui.tooltip = nil
            ui.lastDragCell = -1
            ui.dragMode = .none
        case .pinch(let center, let factor, let dx, let dy):
            guard ui.started, !ui.skillsOpen else { return }
            ui.tooltip = nil
            let v = viewPoint(center)
            ui.camera.pinch(factor: factor, at: v.x, v.y)
            ui.camera.pan(Double(dx), Double(dy))
        case .pinchEnded:
            ui.camera.settle()
            ui.dragMode = .none
        }
    }

    static let doubleTapTime = 0.32

    /// Canvas point → view-local point in the board's camera view.
    func viewPoint(_ p: Point) -> (x: Double, y: Double) {
        (Double(p.x - ui.layout.board.x) + 0.5, Double(p.y - ui.layout.board.y) + 0.5)
    }

    /// True when the point is over a revealed block or the revealed gold.
    func breakableShown(_ p: Point) -> Bool {
        guard let i = boardCell(p) else { return false }
        return board.revealed[i] && (board.kind[i] == .block || board.kind[i] == .gold)
    }

    func hit(at p: Point) -> Hit? { ui.hits.last { $0.rect.contains(p) } }

    func boardCell(_ p: Point) -> Int? {
        let r = ui.layout.board
        guard r.contains(p) else { return nil }
        let v = viewPoint(p)
        let b = ui.camera.toBoard(v.x, v.y)
        guard b.x >= 0, b.y >= 0 else { return nil }
        let x = Int(b.x) / Tuning.cellPixels, y = Int(b.y) / Tuning.cellPixels
        return board.inside(x, y) ? board.index(x, y) : nil
    }

    public func perform(_ a: Action, at p: Point = Point(0, 0)) {
        ui.pressed = a
        ui.pressedUntil = time + 0.12
        switch a {
        case .start: ui.started = true
        case .tab(let t):
            if t == .skills { ui.skillsOpen = true } else { ui.tab = t; ui.scroll = 0 }
            events.append(.tap)
        case .toggleCollapse:
            ui.collapsed.toggle()
            events.append(.tap)
        case .buyBall(let k): buyBall(k)
        case .upgrade(let k, let s): upgrade(k, s)
        case .specialize(let k, let i): specialize(k, i)
        case .skill(let id): buySkill(id)
        case .closeSkills: ui.skillsOpen = false; events.append(.tap)
        case .prestige:
            if time < ui.confirmPrestigeUntil { prestige(); ui.confirmPrestigeUntil = -1 }
            else if prestigeStars > 0 { ui.confirmPrestigeUntil = time + 3; events.append(.tap) }
            else { events.append(.denied) }
        case .setting(let i):
            switch i {
            case 0: progress.settings.sound.toggle()
            case 1: progress.settings.haptics.toggle()
            default: progress.settings.glow.toggle()
            }
            events.append(.tap)
        case .board:
            if let i = boardCell(p) { tap(cellX: i % board.size, cellY: i / board.size) }
        case .panel, .none: break
        }
    }

    public func isPressed(_ a: Action) -> Bool { ui.pressed == a && time < ui.pressedUntil }
}
