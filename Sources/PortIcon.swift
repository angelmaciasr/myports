import AppKit

/// A vector RJ45 socket, shared by the application icon and the menu bar.
func portIcon(size: CGFloat, application: Bool) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        (AffineTransform(scale: size / 100) as NSAffineTransform).concat()
        if application {
            NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.18, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 7, y: 7, width: 86, height: 86), xRadius: 19, yRadius: 19).fill()
        } else {
            (AffineTransform(translationByX: -12.5, byY: -12.5) as NSAffineTransform).concat()
            (AffineTransform(scale: 1.25) as NSAffineTransform).concat()
        }
        let socket = NSBezierPath()
        socket.move(to: NSPoint(x: 25, y: 70))
        socket.line(to: NSPoint(x: 75, y: 70))
        socket.line(to: NSPoint(x: 75, y: 36))
        socket.line(to: NSPoint(x: 63, y: 36))
        socket.line(to: NSPoint(x: 63, y: 27))
        socket.line(to: NSPoint(x: 37, y: 27))
        socket.line(to: NSPoint(x: 37, y: 36))
        socket.line(to: NSPoint(x: 25, y: 36))
        socket.close()
        socket.lineWidth = application ? 5 : 6
        socket.lineJoinStyle = .round
        (application ? NSColor(calibratedWhite: 0.94, alpha: 1) : NSColor.black).setStroke()
        socket.stroke()
        (application ? NSColor(calibratedRed: 0.30, green: 0.61, blue: 1, alpha: 1) : NSColor.black).setFill()
        let contacts = application ? 6 : 4
        let spacing: CGFloat = application ? 6 : 9
        let width: CGFloat = application ? 3 : 4
        for index in 0..<contacts {
            let x = 50 - CGFloat(contacts - 1) * spacing / 2 - width / 2 + CGFloat(index) * spacing
            NSBezierPath(roundedRect: NSRect(x: x, y: 51, width: width, height: 12), xRadius: width / 2, yRadius: width / 2).fill()
        }
        return true
    }
}
