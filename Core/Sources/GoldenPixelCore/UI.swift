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
    /// The in-game pause card (the panel's MENU button): RESUME, RESTART LEVEL, MAIN MENU.
    case pause
    case resume
    /// Asks before restarting: a confirm card with RESTART and CANCEL.
    case restartLevel
    case confirmRestart
    case cancelRestart
    // Game
    case openMenu
    case openSkills
    case closeSkills
    case selectSkill(String)
    case buySkill(String)
    /// Tap a ball row: select that type (tap the selected one again, or hold, for its info
    /// sheet). Press an open spot on the board and drag out to launch one of the selected type.
    case ballRow(BallKind)
    case buyBall(BallKind)
    case closeSheet
    /// Backgrounds: where drags pan and pinches zoom. On `.board`, a short hold on an open cell
    /// places a ball and a drag from it aims; a quick drag anywhere pans.
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
    /// The ball type a tap on the board buys.
    public var selected: BallKind = .basic
    /// A ball being placed: held on an open cell at `from`, aimed toward `to` (canvas).
    public var launch: LaunchDrag?
    /// A finger that went down on an open cell: a short hold turns it into a placement, a
    /// quick drag pans instead.
    var pressOnOpen: Point?
    /// The in-game pause card, and its restart confirmation.
    public var paused = false
    public var confirmingRestart = false
    public var tooltip: Tooltip?
    /// Reset needs a second tap before this time.
    public var confirmResetUntil = -1.0
    public var pressed: Action = .none
    public var pressedUntil = 0.0
    public var hits: [Hit] = []
    public var layout = Layout.make(width: Tuning.canvasWidth, height: Tuning.canvasHeight)
    /// A card whose content is taller than the screen scrolls: how far down it is (art
    /// pixels), how far it can go, and the part of the screen where a drag scrolls it. The
    /// renderer sets the last two every frame.
    public var scroll = 0
    public internal(set) var scrollMax = 0
    public internal(set) var scrollArea: Rect?
    /// Board zoom and pan. The UI itself never zooms.
    public var camera: Camera
    /// Skill-tree zoom and pan: the tree is a "board" of `SkillTree.size` art pixels.
    public var treeCamera: Camera
    /// What a one-finger drag does, decided where it starts.
    var dragMode: DragMode = .none

    public init() {
        let L = layout
        camera = Camera(boardW: 330, boardH: 330, viewW: L.board.w, viewH: L.board.h, overscroll: 1)
        // Some overscroll, so a small early tree can sit in the middle of the screen.
        treeCamera = Camera(boardW: SkillTree.size.w, boardH: SkillTree.size.h, viewW: L.width, viewH: L.height, levels: Camera.treeLevels, overscroll: 0.5)
        // Open on what a new game can see: the root and the basic ball above it. Opening the
        // tree re-centres on whatever is showing by then (`SkillTree.focus`).
        let f = SkillTree.focus(ranks: SkillNode.startingRanks)
        treeCamera.look(at: f.x, f.y)
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
        let p = point(s)
        return (Double(p.x), Double(p.y))
    }
    /// A node's centre in whole tree art pixels (a multiple of 8, so it stays on the grid at
    /// zoom 0.5 too).
    public static func point(_ s: SkillNode) -> Point {
        Point((s.x - minX + 2) * SkillNode.unit, (s.y - minY + 2) * SkillNode.unit + 32)
    }

    /// The one node that needs nothing: every other node hangs off it.
    public static let root = "core"

    /// The link from prerequisite `from` to the node that needs it, as the corners of an
    /// orthogonal path in tree art pixels (first point on `from`'s centre, last on `to`'s):
    /// straight when they share a row or column, otherwise out to halfway between their rows,
    /// across, and on in. Siblings share the halfway bar, so a fork reads as one bracket.
    public static func route(from: SkillNode, to: SkillNode) -> [Point] {
        let a = point(from), b = point(to)
        if a.x == b.x || a.y == b.y { return [a, b] }
        let mid = (a.y + b.y) / 2
        return [a, Point(a.x, mid), Point(b.x, mid), b]
    }

    /// Where the tree camera should look: the selected node if it is showing, otherwise the
    /// middle of everything that is showing (owned and buyable-next nodes), nudged down a little
    /// so it centres in the space between the header and the card.
    public static func focus(ranks: [String: Int], selected: String? = nil) -> (x: Double, y: Double) {
        if let id = selected, let s = SkillNode.byID[id], Skills.visible(id, ranks: ranks) {
            let p = point(s)
            return (Double(p.x), Double(p.y + 16))
        }
        let pts = SkillNode.all.filter { Skills.visible($0.id, ranks: ranks) }.map(point)
        guard let x0 = pts.map(\.x).min(), let x1 = pts.map(\.x).max(),
              let y0 = pts.map(\.y).min(), let y1 = pts.map(\.y).max() else { return position(SkillNode.byID[root]!) }
        return (Double(x0 + x1) / 2, Double(y0 + y1) / 2 + 16)
    }
}

/// Where the board and the panel go for a canvas size. Landscape puts the panel on the
/// right; a tall canvas puts it underneath. The board view fills the rest, edge to edge.
///
/// The system covers part of some screens (the Dynamic Island's side, the home indicator):
/// `safeArea` is what it leaves clear. The board and the panel's background run under the
/// insets; everything you read or press stays inside the safe area and out of the rounded
/// corners (`safe`).
public struct Layout: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var board: Rect
    public var panel: Rect
    public var landscape: Bool
    /// The canvas minus the system's insets.
    public var safeArea: Rect
    /// The screen's corner radius in art pixels (0 on a square screen).
    public var corner: Int

    public static let panelWidth = 150
    public static let panelHeight = 200
    /// A safe area shorter than this is "short": cards, the panel's header and the tree card
    /// use their tight spacing. The Duo's is 317.
    public static let shortHeight = 240

    public static func make(width w: Int, height h: Int, insets i: Insets = .zero, corner: Int = Tuning.cornerRadius) -> Layout {
        let s = Rect(i.left, i.top, max(1, w - i.left - i.right), max(1, h - i.top - i.bottom))
        if w >= h {
            let px = s.maxX - min(panelWidth, s.w / 2)
            return Layout(width: w, height: h, board: Rect(0, 0, px, h), panel: Rect(px, 0, w - px, h), landscape: true, safeArea: s, corner: corner)
        } else {
            let py = s.maxY - min(panelHeight, s.h / 2)
            return Layout(width: w, height: h, board: Rect(0, 0, w, py), panel: Rect(0, py, w, h - py), landscape: false, safeArea: s, corner: corner)
        }
    }

    public var short: Bool { safeArea.h < Layout.shortHeight }
    /// The part of the panel you can read and press.
    public var panelContent: Rect { panel.intersection(safeArea) }
    /// The part of the board the system leaves clear.
    public var boardContent: Rect { board.intersection(safeArea) }
    /// The safe area without the columns the rounded corners cut into: anything in here is
    /// clear of them at any height.
    public var clear: Rect {
        let x0 = max(safeArea.x, corner), x1 = min(safeArea.maxX, width - corner)
        return Rect(x0, safeArea.y, max(1, x1 - x0), safeArea.h)
    }

    /// A w x h rectangle centred on the screen, nudged to keep `margin` inside the safe area.
    public func centred(_ w: Int, _ h: Int, margin: Int = 4) -> Rect {
        let s = safeArea
        let x = max(s.x + margin, min(s.maxX - margin - w, (width - w) / 2))
        let y = max(s.y + margin, min(s.maxY - margin - h, (height - h) / 2))
        return Rect(x, y, w, h)
    }

    /// True when the point lies inside the screen's rounded outline (corner radius `corner`),
    /// i.e. not in a cut-off corner.
    public func onScreen(_ x: Int, _ y: Int) -> Bool {
        let r = corner
        guard x >= 0, y >= 0, x <= width, y <= height else { return false }
        let cx = x < r ? r : (x > width - r ? width - r : x)
        let cy = y < r ? r : (y > height - r ? height - r : y)
        let dx = x - cx, dy = y - cy
        return dx * dx + dy * dy <= r * r
    }

    /// True when the whole rectangle is inside the safe area and clear of the rounded corners.
    public func safe(_ rc: Rect) -> Bool {
        let s = safeArea
        guard rc.x >= s.x, rc.y >= s.y, rc.maxX <= s.maxX, rc.maxY <= s.maxY else { return false }
        return onScreen(rc.x, rc.y) && onScreen(rc.maxX, rc.y) && onScreen(rc.x, rc.maxY) && onScreen(rc.maxX, rc.maxY)
    }
}

/// A ball being placed on the board: held at `from` (an open cell), then pulled back to `to`,
/// slingshot style: it flies the opposite way, from `from` away from the finger. A hold with no
/// pull uses the last direction.
public struct LaunchDrag: Equatable, Sendable {
    public var from: Point
    public var to: Point
    /// Game time when the finger first pulled away from the held spot: the hold ring fades
    /// out from then. Nil while it is still resting there.
    public var pulledAt: Double?
    public init(from: Point, to: Point, pulledAt: Double? = nil) { self.from = from; self.to = to; self.pulledAt = pulledAt }
    /// The launch direction (canvas pixels, not normalised): away from the finger. Nil while
    /// the pull is too short to count.
    public var direction: (x: Double, y: Double)? {
        let dx = Double(from.x - to.x), dy = Double(from.y - to.y)
        return dx * dx + dy * dy < Double(LaunchDrag.minPull * LaunchDrag.minPull) ? nil : (dx, dy)
    }
    public static let minPull = 6
}

enum DragMode: Sendable, Equatable { case none, pan, tree, launch, scroll, ignore }

public enum Gesture: Equatable, Sendable {
    /// A first finger went down (it may yet become a tap, long-press or drag).
    case down(Point)
    case tap(Point, time: Double = 0)
    /// The finger has rested still for `PointerTracker.holdTime` (before any long-press).
    case hold(Point)
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
    public static let holdTime = 0.2
    public static let longPressTime = 0.42
    var start: Point?
    var last = Point(0, 0)
    var startTime = 0.0
    var dragging = false
    var longFired = false
    var holdFired = false
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
            start = p; last = p; startTime = t; dragging = false; longFired = false; holdFired = false
            return [.down(p)]
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
        // A drag may still start after a long press: hold on a spot, then pull out to aim.
        if !dragging, abs(p.x - s.x) + abs(p.y - s.y) > PointerTracker.dragThreshold { dragging = true }
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
        guard !pinching, let s = start, !dragging, !longFired else { return [] }
        var out: [Gesture] = []
        if !holdFired, t - startTime >= PointerTracker.holdTime { holdFired = true; out.append(.hold(s)) }
        if t - startTime >= PointerTracker.longPressTime { longFired = true; out.append(.longPress(s)) }
        return out
    }
}

extension Game {
    public func handle(_ g: Gesture) {
        switch g {
        case .down(let p):
            // On an open, visible cell: a short hold places a ball, a quick drag pans.
            ui.launch = nil
            ui.pressOnOpen = nil
            if ui.screen == .game, hit(at: p)?.action == .board, let i = boardCell(p), board.kind[i] == .empty, board.revealed[i] {
                ui.pressOnOpen = p
            }
        case .hold(let p):
            if let o = ui.pressOnOpen, o == p, ui.dragMode == .none {
                ui.launch = LaunchDrag(from: p, to: p)
                events.append(.tap)
            }
        case .tap(let p, _):
            ui.tooltip = nil
            defer { ui.launch = nil; ui.pressOnOpen = nil }
            guard let h = hit(at: p) else { return }
            // A plain tap on an open spot launches along the last direction.
            if h.action == .board, ui.pressOnOpen != nil || ui.launch != nil {
                launchSelected(ui.launch ?? LaunchDrag(from: p, to: p)); return
            }
            perform(h.action, at: p)
        case .longPress(let p):
            // Holding on an open spot keeps the placement: pull out to aim.
            if ui.launch != nil { return }
            guard let h = hit(at: p) else { return }
            if !h.info.isEmpty { ui.tooltip = Tooltip(lines: h.info, at: p, until: self.time + 3) }
            else if h.action == .board { showCellInfo(p) }
            else if case .ballRow(let k) = h.action { ui.selected = k; ui.sheet = k; events.append(.tap) }
        case .drag(let from, let to):
            ui.pressOnOpen = nil
            if ui.dragMode == .none {
                // Decided once, where the finger went down. Anywhere on a scrolling card's
                // body scrolls it, buttons and rows included.
                let h = hit(at: from)?.action ?? .none
                if let a = ui.scrollArea, a.contains(from) {
                    ui.dragMode = .scroll
                } else {
                    switch h {
                    case .board: ui.dragMode = ui.launch != nil ? .launch : .pan
                    case .tree, .selectSkill: ui.dragMode = .tree
                    default: ui.dragMode = .ignore
                    }
                }
                ui.tooltip = nil
            }
            switch ui.dragMode {
            case .pan: ui.camera.pan(Double(to.x - from.x), Double(to.y - from.y))
            case .tree: ui.treeCamera.pan(Double(to.x - from.x), Double(to.y - from.y))
            case .launch:
                ui.launch?.to = to
                if ui.launch?.pulledAt == nil { ui.launch?.pulledAt = time }
            case .scroll: ui.scroll = max(0, min(ui.scrollMax, ui.scroll - (to.y - from.y)))
            case .none, .ignore: break
            }
        case .release:
            if let l = ui.launch, ui.dragMode == .launch || ui.dragMode == .none { launchSelected(l) }
            ui.launch = nil
            ui.pressOnOpen = nil
            ui.dragMode = .none
        case .pinch(let center, let factor, let dx, let dy):
            ui.tooltip = nil
            ui.launch = nil
            ui.pressOnOpen = nil
            if ui.skillsOpen {
                ui.treeCamera.pinch(factor: factor, at: Double(center.x) + 0.5, Double(center.y) + 0.5)
                ui.treeCamera.pan(Double(dx), Double(dy))
            } else if ui.screen == .game, ui.sheet == nil, !ui.paused {
                let v = viewPoint(center)
                ui.camera.pinch(factor: factor, at: v.x, v.y)
                ui.camera.pan(Double(dx), Double(dy))
            }
        case .pinchEnded:
            ui.camera.settle()
            ui.treeCamera.settle()
            ui.dragMode = .none
        }
    }

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

    /// A press (and pull) on an open cell: buy a ball of the selected type right there, flying
    /// toward where the finger was pulled (or the last direction, for a plain tap).
    func launchSelected(_ l: LaunchDrag) {
        let k = mods.unlocked.contains(ui.selected) ? ui.selected : .basic
        let v = viewPoint(l.from)
        let b = ui.camera.toBoard(v.x, v.y)
        let cp = Double(Tuning.cellPixels)
        let ok = buyBall(k, at: (b.x / cp, b.y / cp), direction: l.direction)
        if !ok, balls.count < Tuning.maxBalls {
            ui.tooltip = Tooltip(lines: ["NEED " + coins(ballCost(k)) + " COINS"], at: l.from, until: time + 1.2)
        }
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
        case .howTo: ui.screen = .howTo; ui.scroll = 0; events.append(.tap)
        case .settings: ui.screen = .settings; ui.scroll = 0; ui.confirmResetUntil = -1; events.append(.tap)
        case .backToMenu: ui.screen = .menu; events.append(.tap)
        case .setting(let i):
            switch i {
            case 0: progress.settings.sound.toggle()
            case 1: progress.settings.music.toggle()
            case 2: progress.settings.haptics.toggle()
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
            ui.sheet = nil; ui.skillsOpen = false; ui.paused = false; ui.confirmingRestart = false
            events.append(.tap)
        case .openSkills:
            ui.skillsOpen = true
            ui.sheet = nil
            let f = SkillTree.focus(ranks: progress.skillRanks, selected: ui.selectedSkill)
            ui.treeCamera.look(at: f.x, f.y)
            events.append(.tap)
        case .closeSkills:
            ui.skillsOpen = false
            events.append(.tap)
        case .selectSkill(let id):
            ui.selectedSkill = id
            events.append(.tap)
        case .buySkill(let id): buySkill(id)
        case .pause:
            ui.paused = true; ui.confirmingRestart = false; ui.sheet = nil; ui.launch = nil
            events.append(.tap)
        case .resume:
            ui.paused = false; ui.confirmingRestart = false
            events.append(.tap)
        case .restartLevel:
            ui.confirmingRestart = true
            events.append(.tap)
        case .cancelRestart:
            ui.confirmingRestart = false
            events.append(.tap)
        case .confirmRestart:
            ui.confirmingRestart = false; ui.paused = false
            restartLevel()
            ui.screen = .game
            events.append(.tap)
        case .ballRow(let k):
            if ui.selected == k { ui.sheet = k } else { ui.selected = k }
            events.append(.tap)
        case .buyBall(let k):
            if mods.unlocked.contains(k) { ui.selected = k; buyBall(k) }
            else {
                ui.sheet = nil; ui.skillsOpen = true; ui.selectedSkill = "u-\(k.rawValue)"
                let f = SkillTree.focus(ranks: progress.skillRanks, selected: ui.selectedSkill)
                ui.treeCamera.look(at: f.x, f.y)
                events.append(.tap)
            }
        case .closeSheet:
            ui.sheet = nil
            events.append(.tap)
        case .board: showCellInfo(p)
        case .tree, .panel, .none: break
        }
    }

    public func isPressed(_ a: Action) -> Bool { ui.pressed == a && time < ui.pressedUntil }
}
