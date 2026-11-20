/// Immediate-mode UI on the art grid: the renderer records hit regions as it draws, and
/// gestures resolve against the regions of the last frame.

/// Which full screen is showing. The game only runs on `.game`.
public enum Screen: Sendable, Equatable { case menu, howTo, settings, game }

public enum Action: Equatable, Sendable {
    // Menu
    case play
    case howTo
    case settings
    case backToMenu
    case setting(Int)
    case resetProgress
    // Game
    case openMenu
    case openSkills
    case closeSkills
    case selectSkill(String)
    case buySkill(String)
    /// Tap a ball row: its info sheet. Drag from it: aim and buy.
    case ballRow(BallKind)
    case buyBall(BallKind)
    case closeSheet
    /// Backgrounds: where drags pan and pinches zoom.
    case board
    case tree
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
    /// Game time it disappears.
    public var until: Double
}

/// A slingshot aim in progress: dragged from `from` to `to`; the ball flies the other way.
public struct Aim: Sendable, Equatable {
    public var kind: BallKind
    public var from: Point
    public var to: Point
    /// Launch direction (opposite the drag), or nil while the pull is too short to count.
    public var direction: (x: Double, y: Double)? {
        let dx = Double(from.x - to.x), dy = Double(from.y - to.y)
        let len = (dx * dx + dy * dy).squareRoot()
        return len < Double(Aim.minPull) ? nil : (dx / len, dy / len)
    }
    public static let minPull = 10
    public static func == (a: Aim, b: Aim) -> Bool { a.kind == b.kind && a.from == b.from && a.to == b.to }
}

public struct UIState: Sendable {
    public var screen: Screen = .menu
    /// Shorthand for "on the game screen" (tests and scenes).
    public var started: Bool {
        get { screen == .game }
        set { screen = newValue ? .game : .menu }
    }
    public var skillsOpen = false
    /// The tree node whose card is showing.
    public var selectedSkill: String?
    /// The ball type whose info sheet is open.
    public var sheet: BallKind?
    public var aim: Aim?
    public var tooltip: Tooltip?
    /// Reset needs a second tap before this time.
    public var confirmResetUntil = -1.0
    public var pressed: Action = .none
    public var pressedUntil = 0.0
    public var hits: [Hit] = []
    public var layout = Layout.make(width: Tuning.canvasWidth, height: Tuning.canvasHeight)
    /// Board zoom and pan. The UI itself never zooms.
    public var camera: Camera
    /// Skill-tree zoom and pan: the tree is a "board" of `SkillTree.size` art pixels.
    public var treeCamera: Camera
    /// What a one-finger drag does, decided where it starts.
    var dragMode: DragMode = .none
    var lastTap: (at: Point, time: Double)?

    public init() {
        let L = layout
        camera = Camera(boardW: 330, boardH: 330, viewW: L.board.w, viewH: L.board.h)
        treeCamera = Camera(boardW: SkillTree.size.w, boardH: SkillTree.size.h, viewW: L.width, viewH: L.height, levels: Camera.treeLevels)
        // Open on the top of the tree: the ball branches.
        treeCamera.look(at: Double(SkillTree.size.w) / 2, 0)
    }
}

/// Where the skill-tree nodes sit, in tree art pixels at zoom 1.
public enum SkillTree {
    static let minX = SkillNode.all.map(\.x).min()!, maxX = SkillNode.all.map(\.x).max()!
    static let minY = SkillNode.all.map(\.y).min()!, maxY = SkillNode.all.map(\.y).max()!
    /// The tree's extent plus a margin of two units on every side (and room for the card).
    /// 32 px of extra room at the top (under the header) and 80 at the bottom (under the card).
    public static let size = (w: (maxX - minX + 4) * SkillNode.unit, h: (maxY - minY + 4) * SkillNode.unit + 112)
    public static func position(_ s: SkillNode) -> (x: Double, y: Double) {
        (Double((s.x - minX + 2) * SkillNode.unit), Double((s.y - minY + 2) * SkillNode.unit + 32))
    }
}

/// Where the board and the panel go for a canvas size. Landscape puts the panel on the
/// right; a tall canvas puts it underneath. The board view fills the rest.
public struct Layout: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var board: Rect
    public var panel: Rect
    public var landscape: Bool

    public static let panelWidth = 150
    public static let panelHeight = 200

    public static func make(width w: Int, height h: Int) -> Layout {
        if w >= h {
            let pw = min(panelWidth, w / 2)
            return Layout(width: w, height: h, board: Rect(0, 0, w - pw, h), panel: Rect(w - pw, 0, pw, h), landscape: true)
        } else {
            let ph = min(panelHeight, h / 2)
            return Layout(width: w, height: h, board: Rect(0, 0, w, h - ph), panel: Rect(0, h - ph, w, ph), landscape: false)
        }
    }

    /// True when the point lies inside the screen's rounded outline (corner radius
    /// `Tuning.cornerRadius`), i.e. not in a cut-off corner.
    public func onScreen(_ x: Int, _ y: Int) -> Bool {
        let r = Tuning.cornerRadius
        guard x >= 0, y >= 0, x <= width, y <= height else { return false }
        let cx = x < r ? r : (x > width - r ? width - r : x)
        let cy = y < r ? r : (y > height - r ? height - r : y)
        let dx = x - cx, dy = y - cy
        return dx * dx + dy * dy <= r * r
    }

    /// True when the whole rectangle is clear of the rounded corners.
    public func safe(_ rc: Rect) -> Bool {
        onScreen(rc.x, rc.y) && onScreen(rc.maxX, rc.y) && onScreen(rc.x, rc.maxY) && onScreen(rc.maxX, rc.maxY)
    }
}

enum DragMode: Sendable, Equatable { case none, pan, tree, aim, ignore }

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
            guard let h = hit(at: p) else { return }
            // Double-tap on the board toggles the zoom; a single tap says what's there.
            if h.action == .board {
                if let last = ui.lastTap, time - last.time < Game.doubleTapTime,
                   abs(last.at.x - p.x) + abs(last.at.y - p.y) <= 10 {
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
            guard let h = hit(at: p) else { return }
            if !h.info.isEmpty { ui.tooltip = Tooltip(lines: h.info, at: p, until: self.time + 3) }
            else if h.action == .board { showCellInfo(p) }
        case .drag(let from, let to):
            if ui.dragMode == .none {
                // Decided once, where the finger went down.
                let h = hit(at: from)?.action ?? .none
                switch h {
                case .board: ui.dragMode = .pan
                case .tree, .selectSkill: ui.dragMode = .tree
                case .ballRow(let k) where mods.unlocked.contains(k) && ui.screen == .game && !ui.skillsOpen && ui.sheet == nil:
                    ui.dragMode = .aim
                    ui.aim = Aim(kind: k, from: from, to: from)
                case .buyBall(let k) where mods.unlocked.contains(k):
                    // Drag the sheet's BUY button to aim as well.
                    ui.dragMode = .aim
                    ui.sheet = nil
                    ui.aim = Aim(kind: k, from: from, to: from)
                default: ui.dragMode = .ignore
                }
                ui.tooltip = nil
            }
            switch ui.dragMode {
            case .pan: ui.camera.pan(Double(to.x - from.x), Double(to.y - from.y))
            case .tree: ui.treeCamera.pan(Double(to.x - from.x), Double(to.y - from.y))
            case .aim: ui.aim?.to = to
            case .none, .ignore: break
            }
        case .release:
            if ui.dragMode == .aim, let a = ui.aim, let d = a.direction {
                buyBall(a.kind, direction: d)
            }
            ui.aim = nil
            ui.dragMode = .none
        case .pinch(let center, let factor, let dx, let dy):
            ui.tooltip = nil
            if ui.skillsOpen {
                ui.treeCamera.pinch(factor: factor, at: Double(center.x) + 0.5, Double(center.y) + 0.5)
                ui.treeCamera.pan(Double(dx), Double(dy))
            } else if ui.screen == .game, ui.sheet == nil {
                let v = viewPoint(center)
                ui.camera.pinch(factor: factor, at: v.x, v.y)
                ui.camera.pan(Double(dx), Double(dy))
            }
        case .pinchEnded:
            ui.camera.settle()
            ui.treeCamera.settle()
            ui.aim = nil
            ui.dragMode = .none
        }
    }

    static let doubleTapTime = 0.32

    /// Canvas point → view-local point in the board's camera view.
    func viewPoint(_ p: Point) -> (x: Double, y: Double) {
        (Double(p.x - ui.layout.board.x) + 0.5, Double(p.y - ui.layout.board.y) + 0.5)
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

    func showCellInfo(_ p: Point) {
        guard let i = boardCell(p), let lines = describe(cellX: i % board.size, cellY: i / board.size) else { return }
        ui.tooltip = Tooltip(lines: lines, at: p, until: time + 2)
    }

    public func perform(_ a: Action, at p: Point = Point(0, 0)) {
        ui.pressed = a
        ui.pressedUntil = time + 0.12
        switch a {
        case .play:
            ui.screen = .game
            events.append(.tap)
        case .howTo: ui.screen = .howTo; events.append(.tap)
        case .settings: ui.screen = .settings; ui.confirmResetUntil = -1; events.append(.tap)
        case .backToMenu: ui.screen = .menu; events.append(.tap)
        case .setting(let i):
            switch i {
            case 0: progress.settings.sound.toggle()
            case 1: progress.settings.haptics.toggle()
            default: progress.settings.glow.toggle()
            }
            events.append(.tap)
        case .resetProgress:
            if time < ui.confirmResetUntil {
                resetProgress()
                ui.confirmResetUntil = -1
                ui.screen = .menu
            } else {
                ui.confirmResetUntil = time + 3
                events.append(.denied)
            }
        case .openMenu:
            ui.screen = .menu
            ui.sheet = nil; ui.skillsOpen = false
            events.append(.tap)
        case .openSkills:
            ui.skillsOpen = true
            ui.sheet = nil
            events.append(.tap)
        case .closeSkills:
            ui.skillsOpen = false
            events.append(.tap)
        case .selectSkill(let id):
            ui.selectedSkill = id
            events.append(.tap)
        case .buySkill(let id): buySkill(id)
        case .ballRow(let k):
            ui.sheet = k
            events.append(.tap)
        case .buyBall(let k):
            if mods.unlocked.contains(k) { buyBall(k) }
            else { ui.sheet = nil; ui.skillsOpen = true; ui.selectedSkill = "u-\(k.rawValue)"; events.append(.tap) }
        case .closeSheet:
            ui.sheet = nil
            events.append(.tap)
        case .board: showCellInfo(p)
        case .tree, .panel, .none: break
        }
    }

    public func isPressed(_ a: Action) -> Bool { ui.pressed == a && time < ui.pressedUntil }
}
