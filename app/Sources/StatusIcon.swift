// Menubar icon: the Lidless mark (a closed laptop, lid and base split by a seam), with what it is doing drawn above it.
import AppKit

enum StatusIcon {
    enum State { case waiting, working, paused }

    static func image(_ state: State) -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            // Closed lid, drawn like the app's glass mark: the lid's top surface in perspective,
            // a hairline seam, then the base as one thin slab.
            let lid = NSBezierPath()
            lid.move(to: NSPoint(x: 4.6, y: 7.6))
            lid.line(to: NSPoint(x: 15.4, y: 7.6))
            lid.line(to: NSPoint(x: 18.4, y: 4.3))
            lid.line(to: NSPoint(x: 1.6, y: 4.3))
            lid.close()
            lid.lineWidth = 1.3
            lid.lineJoinStyle = .round
            lid.stroke()
            NSBezierPath(roundedRect: NSRect(x: 1.4, y: 1.2, width: 17.2, height: 1.7), xRadius: 0.85, yRadius: 0.85).fill()

            switch state {
            case .working:
                // ">_": the agent is still typing away under the closed lid.
                let chevron = NSBezierPath()
                chevron.move(to: NSPoint(x: 6.2, y: 16.6))
                chevron.line(to: NSPoint(x: 9.2, y: 13.8))
                chevron.line(to: NSPoint(x: 6.2, y: 11.0))
                chevron.lineWidth = 1.6
                chevron.lineCapStyle = .round
                chevron.lineJoinStyle = .round
                chevron.stroke()
                NSBezierPath(roundedRect: NSRect(x: 10.6, y: 10.3, width: 4.2, height: 1.6), xRadius: 0.8, yRadius: 0.8).fill()
            case .paused:
                // "!": held back by the battery or heat guard.
                NSBezierPath(roundedRect: NSRect(x: 9.2, y: 12.4, width: 1.6, height: 4.8), xRadius: 0.8, yRadius: 0.8).fill()
                NSBezierPath(ovalIn: NSRect(x: 9.15, y: 9.6, width: 1.7, height: 1.7)).fill()
            case .waiting:
                // A cursor bar: waiting for an agent to start.
                NSBezierPath(roundedRect: NSRect(x: 8, y: 10.3, width: 4, height: 1.6), xRadius: 0.8, yRadius: 0.8).fill()
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Lidless"
        return img
    }
}
