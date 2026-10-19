import AppKit

/// Pixel-art cat drawn in code, so there are no image assets to ship. `#` is a filled pixel.
enum CatSprite: CaseIterable {
    case awake, blink, tail

    private var pixels: [String] {
        switch self {
        case .awake: [
            "..#.....#.........",
            "..##...##.........",
            "..#######.........",
            ".#########........",
            ".#########........",
            ".##.###.##........",
            ".##.###.##........",
            ".#########........",
            "..#######.........",
            "...#####......##..",
            "..#######.......#.",
            ".#########......#.",
            ".##########.....#.",
            ".###########...##.",
            ".############.##..",
            "..####.#######....",
        ]
        case .blink: [
            "..#.....#.........",
            "..##...##.........",
            "..#######.........",
            ".#########........",
            ".#########........",
            ".#########........",
            ".##..#..##........",
            ".#########........",
            "..#######.........",
            "...#####......##..",
            "..#######.......#.",
            ".#########......#.",
            ".##########.....#.",
            ".###########...##.",
            ".############.##..",
            "..####.#######....",
        ]
        case .tail: [
            "..#.....#.........",
            "..##...##.........",
            "..#######.........",
            ".#########........",
            ".#########........",
            ".##.###.##........",
            ".##.###.##........",
            ".#########........",
            "..#######.........",
            "...#####..........",
            "..#######.........",
            ".#########......#.",
            ".##########.....#.",
            ".###########....#.",
            ".############.##..",
            "..####.#######....",
        ]
        }
    }

    /// A template image (tinted by the system) where each pixel is `pointSize` points wide.
    func image(pointSize: CGFloat = 1) -> NSImage {
        let rows = pixels
        let size = NSSize(width: CGFloat(rows[0].count) * pointSize, height: CGFloat(rows.count) * pointSize)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            for (y, row) in rows.enumerated() {
                for (x, pixel) in row.enumerated() where pixel == "#" {
                    NSRect(x: CGFloat(x) * pointSize, y: CGFloat(y) * pointSize, width: pointSize, height: pointSize).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "im"
        return image
    }
}

/// Drives the menu bar cat: asleep when disconnected, idling when connected, wagging while busy.
@MainActor
final class CatAnimator {
    enum Mood { case asleep, idle, busy }

    var mood: Mood = .asleep {
        didSet { if mood != oldValue { restart() } }
    }

    private let frames = Dictionary(uniqueKeysWithValues: CatSprite.allCases.map { ($0, $0.image()) })
    private let show: (NSImage) -> Void
    private var timer: Timer?
    private var tick = 0
    private var upcoming: [CatSprite] = []

    init(show: @escaping (NSImage) -> Void) {
        self.show = show
        restart()
    }

    private func restart() {
        timer?.invalidate()
        timer = nil
        tick = 0
        upcoming = []
        switch mood {
        case .asleep:
            show(frames[.blink]!)
        case .idle:
            schedule(every: 0.25)
        case .busy:
            schedule(every: 0.15)
        }
    }

    private func schedule(every interval: TimeInterval) {
        step()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    private func step() {
        tick += 1
        let sprite: CatSprite
        switch mood {
        case .asleep:
            sprite = .blink
        case .busy:
            sprite = tick.isMultiple(of: 2) ? .tail : .awake
        case .idle:
            if upcoming.isEmpty {
                // Mostly sit still, now and then blink or flick the tail.
                let roll = Double.random(in: 0..<1)
                if roll < 0.04 {
                    upcoming = [.blink]
                } else if roll < 0.07 {
                    upcoming = [.tail, .awake, .tail]
                }
            }
            sprite = upcoming.isEmpty ? .awake : upcoming.removeFirst()
        }
        show(frames[sprite]!)
    }
}
