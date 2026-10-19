import AppKit
import IMCore

extension CatSkin {
    /// Renders one frame. `canvasRows` adds transparent rows below the cat and `lift` moves it down
    /// into them, which is how the busy animation bobs without changing the image size.
    func image(blinking: Bool = false, pointSize: CGFloat = 1, canvasRows: Int? = nil, lift: Int = 0) -> NSImage {
        let rows = blinking ? (blink ?? awake) : awake
        let palette = palette.mapValues {
            NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha)
        }
        let size = NSSize(width: CGFloat(width) * pointSize, height: CGFloat(canvasRows ?? height) * pointSize)
        let image = NSImage(size: size, flipped: true) { _ in
            for (y, row) in rows.enumerated() {
                for (x, pixel) in row.enumerated() {
                    guard let color = palette[pixel] else { continue }
                    color.setFill()
                    NSRect(x: CGFloat(x) * pointSize, y: CGFloat(y + lift) * pointSize, width: pointSize, height: pointSize).fill()
                }
            }
            return true
        }
        image.accessibilityDescription = localizedName
        return image
    }
}

/// Drives the menu bar cat: eyes closed when disconnected, blinking now and then when connected, bobbing while busy.
@MainActor
final class CatAnimator {
    enum Mood { case asleep, idle, busy }

    var mood: Mood = .asleep {
        didSet { if mood != oldValue { restart() } }
    }

    var skin: CatSkin {
        didSet {
            if skin != oldValue {
                frames = Frames(skin)
                restart()
            }
        }
    }

    private struct Frames {
        let awake, blink, bobbed: NSImage

        init(_ skin: CatSkin) {
            let rows = skin.height + 1
            awake = skin.image(canvasRows: rows)
            blink = skin.image(blinking: true, canvasRows: rows)
            bobbed = skin.image(canvasRows: rows, lift: 1)
        }
    }

    private let show: (NSImage) -> Void
    private var frames: Frames
    private var timer: Timer?
    private var tick = 0
    private var upcoming: [NSImage] = []

    init(skin: CatSkin, show: @escaping (NSImage) -> Void) {
        self.skin = skin
        self.show = show
        frames = Frames(skin)
        restart()
    }

    private func restart() {
        timer?.invalidate()
        timer = nil
        tick = 0
        upcoming = []
        switch mood {
        case .asleep:
            show(frames.blink)
        case .idle:
            schedule(every: 0.2)
        case .busy:
            schedule(every: 0.25)
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
        switch mood {
        case .asleep:
            show(frames.blink)
        case .busy:
            show(tick.isMultiple(of: 2) ? frames.bobbed : frames.awake)
        case .idle:
            if upcoming.isEmpty {
                // Mostly still; now and then a blink, sometimes a double blink.
                let roll = Double.random(in: 0..<1)
                if roll < 0.03 {
                    upcoming = [frames.blink]
                } else if roll < 0.04 {
                    upcoming = [frames.blink, frames.awake, frames.blink]
                }
            }
            show(upcoming.isEmpty ? frames.awake : upcoming.removeFirst())
        }
    }
}
