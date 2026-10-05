import AppKit
import CoreServices
import ServiceManagement
import Darwin

func string<T>(_ buffer: T) -> String {
    var buffer = buffer
    return withUnsafePointer(to: &buffer) {
        $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { String(cString: $0) }
    }
}

struct Service: Codable, Equatable {
    let pid: Int32
    let uid: UInt32
    let startSec: UInt64
    let startUsec: UInt64
    let port: UInt16
    let name: String
    let executable: String
    let directory: String
    var addresses: [String]
    var id: String { "\(pid):\(startSec):\(startUsec):\(port)" }
    var startedAt: Date { Date(timeIntervalSince1970: Double(startSec) + Double(startUsec) / 1_000_000) }
    var system: Bool {
        executable.hasPrefix("/System/") || executable.hasPrefix("/usr/libexec/") || executable.hasPrefix("/usr/sbin/")
    }
    var stoppable: Bool { uid == getuid() && !system && pid > 1 && pid != getpid() }
    var host: String {
        if addresses.contains("0.0.0.0") || addresses.contains("127.0.0.1") { return "127.0.0.1" }
        if addresses.contains("::") || addresses.contains("::1") { return "[::1]" }
        let address = addresses.first ?? "127.0.0.1"
        return address.contains(":") ? "[\(address)]" : address
    }
    func url(https: Bool = false) -> URL { URL(string: "\(https ? "https" : "http")://\(host):\(port)")! }
    var shortDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if directory == home { return "~" }
        return directory.hasPrefix(home + "/") ? "~" + directory.dropFirst(home.count) : directory
    }
    var isProject: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return !system && !executable.hasPrefix("/Applications/") && !executable.hasPrefix(home + "/Applications/")
            && !directory.isEmpty && directory != "/" && directory != home
    }
    var projectName: String {
        if directory.isEmpty || directory == "/" { return "Sin carpeta de proyecto" }
        if directory == FileManager.default.homeDirectoryForCurrentUser.path { return "Carpeta personal" }
        return URL(fileURLWithPath: directory).lastPathComponent
    }
}

func scan() throws -> [Service] {
    var count: Int32 = 0
    let pointer = ports_scan(&count)
    defer { ports_free(pointer) }
    guard count >= 0 else { throw NSError(domain: "Puertos", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se pudieron consultar los procesos."]) }
    guard let pointer else { return [] }
    var groups: [String: Service] = [:]
    for record in UnsafeBufferPointer(start: pointer, count: Int(count)) {
        let service = Service(pid: record.pid, uid: record.uid, startSec: record.start_sec,
            startUsec: record.start_usec, port: record.port, name: string(record.name),
            executable: string(record.executable), directory: string(record.directory), addresses: [string(record.address)])
        if var existing = groups[service.id] {
            if !existing.addresses.contains(service.addresses[0]) { existing.addresses.append(service.addresses[0]); existing.addresses.sort() }
            groups[service.id] = existing
        } else { groups[service.id] = service }
    }
    return groups.values.sorted { $0.port == $1.port ? $0.pid < $1.pid : $0.port < $1.port }
}

// The same scanner and stopping guards are usable in repeatable integration tests.
if CommandLine.arguments.contains("--list") {
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(data: try encoder.encode(scan()), encoding: .utf8)!)
        exit(0)
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}
if let index = CommandLine.arguments.firstIndex(of: "--stop") {
    let args = Array(CommandLine.arguments.dropFirst(index + 1))
    guard args.count >= 4, let pid = Int32(args[0]), let sec = UInt64(args[1]),
        let usec = UInt64(args[2]), let port = UInt16(args[3]), port > 0 else {
        fputs("Uso: --stop PID START_SEC START_USEC PORT [--force]\n", stderr); exit(2)
    }
    let result = ports_stop(pid, sec, usec, port, args.contains("--force") ? 1 : 0)
    if result != 0 { fputs("\(String(cString: strerror(result)))\n", stderr) }
    exit(result == 0 ? 0 : 1)
}

// Tracking events can arrive after a view moves or a window is reopened.
// Resolve hover against the current screen position and the final clipped bounds.
func pointerIsInside(_ view: NSView) -> Bool {
    guard let window = view.window, window.isVisible, window.isKeyWindow,
        !window.isMiniaturized, !view.isHiddenOrHasHiddenAncestor,
        view.bounds.width > 0, view.bounds.height > 0 else { return false }
    let visible = view.visibleRect.intersection(view.bounds)
    guard !visible.isEmpty else { return false }
    let point = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    return visible.contains(point)
}

class ServiceButton: NSButton {
    var service: Service?
    private var hoverArea: NSTrackingArea?
    var hovered = false { didSet { if oldValue != hovered { needsDisplay = true } } }
    override var isEnabled: Bool {
        didSet {
            if !isEnabled { hovered = false }
            window?.invalidateCursorRects(for: self)
        }
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled { addCursorRect(visibleRect, cursor: .pointingHand) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
        synchronizeHover()
    }
    func synchronizeHover() { hovered = isEnabled && pointerIsInside(self) }
    override func mouseEntered(with event: NSEvent) { synchronizeHover() }
    override func mouseExited(with event: NSEvent) { synchronizeHover() }
    override func draw(_ dirtyRect: NSRect) {
        let hovered = self.hovered && pointerIsInside(self)
        if !isBordered && image == nil {
            if hovered && isEnabled {
                NSColor.systemBlue.withAlphaComponent(0.08).setFill()
                NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6).fill()
            }
            let text = NSAttributedString(string: title, attributes: [
                .font: font ?? NSFont.systemFont(ofSize: 13),
                .foregroundColor: isEnabled ? (hovered ? NSColor.systemBlue : NSColor.labelColor) : NSColor.disabledControlTextColor
            ])
            let size = text.size()
            text.draw(at: NSPoint(x: alignment == .left ? 4 : (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        } else {
            super.draw(dirtyRect)
            if hovered && isEnabled {
                NSColor.systemBlue.withAlphaComponent(0.14).setFill()
                NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6).fill()
            }
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

enum ProcessTime {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "dd/MM/yy HH:mm"
        return formatter
    }()
    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        return formatter
    }()
    static func elapsed(since start: Date, at now: Date) -> String {
        let seconds = Int(max(0, now.timeIntervalSince(start)))
        if seconds >= 86_400 { return "\(seconds / 86_400) d \(seconds % 86_400 / 3_600) h" }
        if seconds >= 3_600 { return "\(seconds / 3_600) h \(seconds % 3_600 / 60) min" }
        if seconds >= 60 { return "\(seconds / 60) min \(seconds % 60) s" }
        return "\(seconds) s"
    }
}

final class DangerServiceButton: ServiceButton {
    override func draw(_ dirtyRect: NSRect) {
        let red = NSColor.systemRed.blended(withFraction: isHighlighted ? 0.3 : (hovered && pointerIsInside(self) ? 0.06 : 0.18), of: .black) ?? .systemRed
        (isEnabled ? red : NSColor.quaternaryLabelColor).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: isEnabled ? NSColor.white : NSColor.disabledControlTextColor
        ]
        let text = NSAttributedString(string: title, attributes: attributes)
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

final class CardSurface: NSView {
    override var isFlipped: Bool { true }
    var hovered = false { didSet { if oldValue != hovered { needsDisplay = true } } }
    override func draw(_ dirtyRect: NSRect) {
        let hovered = self.hovered && pointerIsInside(self)
        let width: CGFloat = hovered ? 1.5 : 1
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: width / 2, dy: width / 2), xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        (hovered ? NSColor.systemBlue : NSColor.separatorColor.withAlphaComponent(0.6)).setStroke()
        path.lineWidth = width
        path.stroke()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

final class ServiceCard: NSView {
    override var isFlipped: Bool { true }
    let surface = CardSurface()
    let icon = NSImageView()
    let name = NSTextField(labelWithString: "")
    let state = NSTextField(labelWithString: "En escucha")
    let port = ServiceButton()
    let location = NSTextField(labelWithString: "")
    let project = NSTextField(labelWithString: "")
    let directory = NSTextField(labelWithString: "")
    let metadata = NSTextField(labelWithString: "")
    let started = NSTextField(labelWithString: "")
    let elapsed = NSTextField(labelWithString: "")
    let open = ServiceButton()
    let stop = DangerServiceButton()
    let more = ServiceButton()
    let divider = NSBox()
    var represented: Service?
    private var hoverArea: NSTrackingArea?

    init(service: Service, dashboard: Dashboard) {
        super.init(frame: .zero)
        addSubview(surface)
        [icon, name, state, port, location, project, directory, metadata, started, elapsed, open, stop, more, divider].forEach { addSubview($0) }
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        state.font = .systemFont(ofSize: 11, weight: .medium)
        state.alignment = .right
        port.isBordered = false
        port.alignment = .left
        port.font = .monospacedSystemFont(ofSize: 28, weight: .semibold)
        port.contentTintColor = .labelColor
        port.target = dashboard
        port.action = #selector(Dashboard.openService(_:))
        location.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        location.textColor = .secondaryLabelColor
        location.lineBreakMode = .byTruncatingMiddle
        project.font = .systemFont(ofSize: 13, weight: .medium)
        project.lineBreakMode = .byTruncatingMiddle
        directory.font = .systemFont(ofSize: 11)
        directory.textColor = .secondaryLabelColor
        directory.lineBreakMode = .byTruncatingMiddle
        metadata.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        metadata.textColor = .secondaryLabelColor
        metadata.lineBreakMode = .byTruncatingMiddle
        started.font = .systemFont(ofSize: 11)
        started.textColor = .secondaryLabelColor
        started.lineBreakMode = .byTruncatingTail
        elapsed.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        elapsed.textColor = .secondaryLabelColor
        elapsed.alignment = .right
        elapsed.setAccessibilityLabel("Tiempo activo del proceso")
        divider.boxType = .separator
        open.title = "Abrir ↗"
        open.bezelStyle = .rounded
        open.controlSize = .small
        open.font = .systemFont(ofSize: 12, weight: .medium)
        open.target = dashboard
        open.action = #selector(Dashboard.openService(_:))
        stop.bezelStyle = .rounded
        stop.controlSize = .small
        stop.font = .systemFont(ofSize: 12, weight: .medium)
        stop.target = dashboard
        stop.action = #selector(Dashboard.stopService(_:))
        more.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Opciones del servicio")
        more.isBordered = false
        more.target = dashboard
        more.action = #selector(Dashboard.showServiceOptions(_:))
        update(service: service, stoppingSince: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
        synchronizeHover()
    }
    func synchronizeHover() { surface.hovered = pointerIsInside(self) }
    override func mouseEntered(with event: NSEvent) { synchronizeHover() }
    override func mouseExited(with event: NSEvent) { synchronizeHover() }

    func update(service: Service, stoppingSince: Date?) {
        if represented != service {
            represented = service
            name.stringValue = service.name
            name.toolTip = service.executable
            icon.image = NSImage(systemSymbolName: service.isProject ? "terminal" : "app", accessibilityDescription: nil)
            icon.contentTintColor = .secondaryLabelColor
            port.title = ":\(service.port)"
            port.toolTip = "Abrir \(service.url().absoluteString)"
            port.setAccessibilityLabel("Abrir puerto \(service.port) en el navegador")
            port.menu = menuFor(service)
            project.stringValue = service.projectName
            location.stringValue = "\(service.host):\(service.port)"
            directory.stringValue = service.shortDirectory.isEmpty ? "Carpeta no disponible" : service.shortDirectory
            directory.toolTip = service.directory
            metadata.stringValue = "PID \(service.pid) · \(service.addresses.joined(separator: ", "))"
            metadata.toolTip = metadata.stringValue
            started.stringValue = "Desde \(ProcessTime.shortDate.string(from: service.startedAt))"
            started.toolTip = "Inicio del proceso: \(ProcessTime.fullDate.string(from: service.startedAt))"
            [port, open, stop, more].forEach { $0.service = service }
            open.setAccessibilityLabel("Abrir \(service.name), puerto \(service.port)")
            more.setAccessibilityLabel("Opciones de \(service.name), puerto \(service.port)")
            open.toolTip = "Abrir con HTTP en el navegador"
            more.toolTip = "HTTPS, copiar URL y mostrar carpeta"
        }
        let canForce = stoppingSince.map { Date().timeIntervalSince($0) >= 4 } ?? false
        state.stringValue = stoppingSince == nil ? (service.stoppable ? "En escucha" : "Protegido") : "Deteniendo…"
        state.textColor = stoppingSince == nil ? (service.stoppable ? .systemGreen : .secondaryLabelColor) : .systemOrange
        stop.title = stoppingSince == nil ? "Detener" : (canForce ? "Forzar…" : "Parando…")
        stop.isEnabled = service.stoppable && (stoppingSince == nil || canForce)
        stop.toolTip = service.stoppable ? "Detener el proceso \(service.pid) y todos sus puertos" : "Proceso del sistema o de otro usuario"
        stop.setAccessibilityLabel("\(stop.title) \(service.name), puerto \(service.port)")
        updateActivity(at: Date())
        needsLayout = true
    }

    func updateActivity(at now: Date) {
        guard let service = represented else { return }
        let duration = ProcessTime.elapsed(since: service.startedAt, at: now)
        if elapsed.stringValue != duration { elapsed.stringValue = duration }
        elapsed.toolTip = "Tiempo activo del proceso: \(duration)"
    }

    func menuFor(_ service: Service) -> NSMenu? { (port.target as? Dashboard)?.serviceMenu(service) }

    override func layout() {
        super.layout()
        let w = bounds.width
        surface.frame = bounds
        icon.frame = NSRect(x: 16, y: 17, width: 16, height: 16)
        name.frame = NSRect(x: 39, y: 17, width: max(0, w - 143), height: 18)
        state.frame = NSRect(x: w - 108, y: 19, width: 92, height: 15)
        port.frame = NSRect(x: 12, y: 42, width: w - 28, height: 38)
        location.frame = NSRect(x: 16, y: 82, width: w - 32, height: 16)
        project.frame = NSRect(x: 16, y: 112, width: w - 32, height: 19)
        directory.frame = NSRect(x: 16, y: 135, width: w - 32, height: 16)
        metadata.frame = NSRect(x: 16, y: 159, width: w - 32, height: 15)
        started.frame = NSRect(x: 16, y: 183, width: w - 152, height: 16)
        elapsed.frame = NSRect(x: w - 128, y: 183, width: 112, height: 16)
        divider.frame = NSRect(x: 16, y: 209, width: w - 32, height: 1)
        open.frame = NSRect(x: 14, y: 221, width: 88, height: 26)
        stop.frame = NSRect(x: w - 139, y: 221, width: 91, height: 26)
        more.frame = NSRect(x: w - 41, y: 221, width: 27, height: 26)
    }
}

final class CardsGrid: NSView {
    override var isFlipped: Bool { true }
    var cards: [ServiceCard] = []
    var columns = 3
    func resize(width: CGFloat, minimumHeight: CGFloat) {
        columns = max(1, min(3, Int((width + 14) / 314)))
        let rows = (cards.count + columns - 1) / columns
        let height = max(minimumHeight, CGFloat(rows) * 276 - (rows > 0 ? 14 : 0))
        setFrameSize(NSSize(width: width, height: height))
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let gap: CGFloat = 14
        let width = (bounds.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
        for (index, card) in cards.enumerated() {
            card.frame = NSRect(x: CGFloat(index % columns) * (width + gap), y: CGFloat(index / columns) * 276, width: width, height: 262)
        }
    }
}

final class DashboardMetric: NSView {
    override var isFlipped: Bool { true }
    let value = NSTextField(labelWithString: "—")
    let label: NSTextField
    init(_ title: String) {
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        value.font = .monospacedDigitSystemFont(ofSize: 24, weight: .semibold)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        addSubview(value)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        value.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 30)
        label.frame = NSRect(x: 0, y: 35, width: bounds.width, height: 18)
    }
}

final class Dashboard: NSViewController, NSSearchFieldDelegate, NSWindowDelegate {
    let grid = CardsGrid()
    let scroll = NSScrollView()
    let scope = NSSegmentedControl(labels: ["Todos", "Proyectos", "Apps"], trackingMode: .selectOne, target: nil, action: nil)
    var cardsByID: [String: ServiceCard] = [:]
    let serviceMetric = DashboardMetric("Puertos activos")
    let processMetric = DashboardMetric("Procesos")
    let projectMetric = DashboardMetric("Carpetas de proyectos")
    let search = NSSearchField()
    let footer = NSTextField(labelWithString: "Consultando puertos…")
    let empty = NSTextField(labelWithString: "")
    let countLabel = NSTextField(labelWithString: "")
    let settingsButton = ServiceButton()
    var services: [Service] = []
    var filtered: [Service] = []
    var stopping: [String: Date] = [:]
    var timer: Timer?
    var scanning = false
    var active = false
    var interval: TimeInterval { let saved = UserDefaults.standard.double(forKey: "interval"); return saved > 0 ? saved : 2 }
    var showSystem: Bool { UserDefaults.standard.bool(forKey: "showSystem") }
    var ownOnly: Bool { !UserDefaults.standard.bool(forKey: "otherUsers") }
    let worker = DispatchQueue(label: "local.puertos.scan", qos: .utility)

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1040, height: 720))
        let title = NSTextField(labelWithString: "Puertos")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor
        search.placeholderString = "Buscar puerto, proceso o carpeta"
        search.delegate = self
        search.setAccessibilityLabel("Buscar servicios")
        let refresh = ServiceButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Actualizar ahora")!, target: self, action: #selector(refreshNow))
        refresh.bezelStyle = .texturedRounded
        refresh.toolTip = "Actualizar ahora (⌘R)"
        refresh.keyEquivalent = "r"
        refresh.keyEquivalentModifierMask = .command
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Opciones")
        settingsButton.bezelStyle = .texturedRounded
        settingsButton.target = self
        settingsButton.action = #selector(showSettings)
        settingsButton.toolTip = "Opciones"
        let header = NSStackView(views: [title, NSView(), refresh, settingsButton])
        header.orientation = .horizontal
        header.spacing = 12
        let overview = NSStackView(views: [serviceMetric, processMetric, projectMetric])
        overview.orientation = .horizontal
        overview.distribution = .fillEqually
        overview.spacing = 24
        scope.selectedSegment = 0
        scope.target = self
        scope.action = #selector(scopeChanged)
        scope.controlSize = .regular
        scope.setAccessibilityLabel("Filtrar servicios")
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.documentView = grid
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .secondaryLabelColor
        empty.font = .systemFont(ofSize: 14)
        empty.textColor = .secondaryLabelColor
        empty.alignment = .center
        empty.maximumNumberOfLines = 3
        [header, overview, scope, search, countLabel, scroll, footer, empty].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            header.heightAnchor.constraint(equalToConstant: 30),
            overview.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20),
            overview.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            overview.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            overview.heightAnchor.constraint(equalToConstant: 54),
            scope.topAnchor.constraint(equalTo: overview.bottomAnchor, constant: 20),
            scope.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            scope.widthAnchor.constraint(equalToConstant: 232),
            scope.heightAnchor.constraint(equalToConstant: 28),
            search.centerYAnchor.constraint(equalTo: scope.centerYAnchor),
            search.leadingAnchor.constraint(equalTo: scope.trailingAnchor, constant: 20),
            search.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            search.heightAnchor.constraint(equalToConstant: 28),
            countLabel.topAnchor.constraint(equalTo: scope.bottomAnchor, constant: 16),
            countLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            countLabel.heightAnchor.constraint(equalToConstant: 18),
            scroll.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            footer.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            empty.widthAnchor.constraint(lessThanOrEqualTo: scroll.widthAnchor, constant: -40)
        ])
    }

    override func viewDidLayout() { super.viewDidLayout(); resizeGrid() }
    func resizeGrid() {
        grid.resize(width: scroll.contentView.bounds.width, minimumHeight: scroll.contentView.bounds.height)
    }

    func synchronizeHoverStates(clear: Bool = false) {
        func visit(_ current: NSView) {
            if let button = current as? ServiceButton {
                if clear { button.hovered = false } else { button.synchronizeHover() }
            }
            if let card = current as? ServiceCard {
                if clear { card.surface.hovered = false } else { card.synchronizeHover() }
            }
            current.subviews.forEach(visit)
        }
        visit(view)
    }
    func begin() {
        active = true
        view.layoutSubtreeIfNeeded()
        grid.layoutSubtreeIfNeeded()
        synchronizeHoverStates()
        restartTimer()
        refreshNow()
    }
    func pause() {
        active = false
        timer?.invalidate()
        timer = nil
        synchronizeHoverStates(clear: true)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { pause(); sender.orderOut(nil); return false }
    func windowDidMiniaturize(_ notification: Notification) { pause() }
    func windowDidDeminiaturize(_ notification: Notification) { begin() }
    func windowDidResignKey(_ notification: Notification) { synchronizeHoverStates(clear: true) }
    func windowDidBecomeKey(_ notification: Notification) { synchronizeHoverStates() }

    func restartTimer() {
        timer?.invalidate()
        guard active else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refreshNow() }
        timer?.tolerance = min(interval * 0.2, 1)
    }

    @objc func refreshNow() {
        guard active && !scanning else { return }
        scanning = true
        worker.async { [weak self] in
            let result = Result { try scan() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                guard self.active else { return }
                switch result {
                case .success(let next):
                    let changed = self.services != next
                    self.services = next
                    let ids = Set(next.map(\.id))
                    self.stopping = self.stopping.filter { ids.contains($0.key) }
                    if changed || !self.stopping.isEmpty { self.applyFilter() }
                    else if self.cardsByID.isEmpty { self.applyFilter() }
                    let now = Date()
                    self.grid.cards.forEach { $0.updateActivity(at: now) }
                    let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                    self.footer.stringValue = "TCP en escucha · cada \(Int(self.interval)) s · \(time) · sin sondeos al cerrar"
                case .failure(let error): self.footer.stringValue = error.localizedDescription
                }
            }
        }
    }

    func applyFilter() {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let visible = services.filter { (showSystem || !$0.system) && (!ownOnly || $0.uid == getuid()) }
        let scoped = visible.filter { scope.selectedSegment == 0 || (scope.selectedSegment == 1 ? $0.isProject : !$0.isProject) }
        filtered = scoped.filter { query.isEmpty || "\($0.port) \($0.pid) \($0.name) \($0.executable) \($0.directory) \($0.addresses.joined(separator: " "))".lowercased().contains(query) }
        serviceMetric.value.stringValue = String(Set(visible.map(\.port)).count)
        processMetric.value.stringValue = String(Set(visible.map(\.pid)).count)
        projectMetric.value.stringValue = String(Set(visible.filter(\.isProject).map(\.directory)).count)
        countLabel.stringValue = "\(filtered.count) \(filtered.count == 1 ? "servicio" : "servicios")" + (scope.selectedSegment == 1 ? " de proyectos" : (scope.selectedSegment == 2 ? " de aplicaciones" : " en escucha"))
        let ids = Set(filtered.map(\.id))
        for (id, card) in cardsByID where !ids.contains(id) { card.removeFromSuperview() }
        cardsByID = cardsByID.filter { ids.contains($0.key) }
        grid.cards = filtered.map { service in
            let card: ServiceCard
            if let existing = cardsByID[service.id] { card = existing }
            else {
                card = ServiceCard(service: service, dashboard: self)
                grid.addSubview(card)
                cardsByID[service.id] = card
            }
            card.update(service: service, stoppingSince: stopping[service.id])
            return card
        }
        resizeGrid()
        grid.layoutSubtreeIfNeeded()
        synchronizeHoverStates()
        empty.isHidden = !filtered.isEmpty
        empty.stringValue = query.isEmpty ? (visible.isEmpty ? "No hay servicios locales en escucha.\nAl arrancar uno, aparecerá aquí automáticamente." : "No hay servicios en este filtro.") : "No hay servicios que coincidan con «\(search.stringValue)»."
    }
    func controlTextDidChange(_ obj: Notification) { applyFilter() }
    @objc func scopeChanged() { applyFilter() }
    @objc func showServiceOptions(_ sender: ServiceButton) {
        guard let service = sender.service else { return }
        serviceMenu(service).popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    func serviceMenu(_ service: Service) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (title, action) in [("Abrir con HTTP", #selector(openHTTP(_:))), ("Abrir con HTTPS", #selector(openHTTPS(_:))), ("Copiar URL", #selector(copyURL(_:))), ("Mostrar carpeta en Finder", #selector(showFolder(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = service
            item.isEnabled = action != #selector(showFolder(_:)) || !service.directory.isEmpty
            menu.addItem(item)
        }
        return menu
    }
    @objc func openService(_ sender: ServiceButton) { if let service = sender.service { NSWorkspace.shared.open(service.url()) } }
    @objc func openHTTP(_ sender: NSMenuItem) { if let service = sender.representedObject as? Service { NSWorkspace.shared.open(service.url()) } }
    @objc func openHTTPS(_ sender: NSMenuItem) { if let service = sender.representedObject as? Service { NSWorkspace.shared.open(service.url(https: true)) } }
    @objc func copyURL(_ sender: NSMenuItem) {
        guard let service = sender.representedObject as? Service else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(service.url().absoluteString, forType: .string)
    }
    @objc func showFolder(_ sender: NSMenuItem) {
        if let service = sender.representedObject as? Service, !service.directory.isEmpty {
            NSWorkspace.shared.open(URL(fileURLWithPath: service.directory, isDirectory: true))
        }
    }

    @objc func stopService(_ sender: ServiceButton) {
        guard let service = sender.service, service.stoppable else { return }
        let force = stopping[service.id] != nil
        let ports = services.filter { $0.pid == service.pid && $0.startSec == service.startSec && $0.startUsec == service.startUsec }.map { String($0.port) }.joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = force ? "¿Forzar el cierre de \(service.name)?" : "¿Detener \(service.name)?"
        alert.informativeText = "Se \(force ? "forzará el cierre" : "solicitará el cierre") del proceso \(service.pid). Afectará a todos sus puertos: \(ports)." + (force ? " Puede perder trabajo sin guardar." : " Si un supervisor lo reinicia, volverá a aparecer.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: force ? "Forzar cierre" : "Detener proceso")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let result = ports_stop(service.pid, service.startSec, service.startUsec, service.port, force ? 1 : 0)
        if result == 0 {
            let date = Date()
            services.filter { $0.pid == service.pid }.forEach { stopping[$0.id] = date }
            applyFilter()
        } else if result != ESRCH && result != ESTALE {
            let failure = NSAlert()
            failure.messageText = "No se pudo detener el proceso"
            failure.informativeText = String(cString: strerror(result))
            failure.runModal()
        }
        refreshNow()
    }

    @objc func showSettings() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let login = NSMenuItem(title: "Abrir al iniciar sesión", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.target = self
        menu.addItem(login)
        for (title, action, checked) in [("Mostrar servicios de macOS", #selector(toggleSystem), showSystem), ("Solo procesos de mi usuario", #selector(toggleUser), ownOnly)] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.state = checked ? .on : .off
            item.target = self
            menu.addItem(item)
        }
        let update = NSMenuItem(title: "Actualizar cada…", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for seconds in [1, 2, 5, 10] {
            let item = NSMenuItem(title: "\(seconds) segundos", action: #selector(changeInterval(_:)), keyEquivalent: "")
            item.tag = seconds; item.target = self; item.state = Int(interval) == seconds ? .on : .off
            submenu.addItem(item)
        }
        update.submenu = submenu
        menu.addItem(update)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Salir de Puertos", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: settingsButton.bounds.height + 4), in: settingsButton)
    }
    @objc func toggleSystem() { UserDefaults.standard.set(!showSystem, forKey: "showSystem"); applyFilter() }
    @objc func toggleUser() { UserDefaults.standard.set(ownOnly, forKey: "otherUsers"); applyFilter() }
    @objc func changeInterval(_ sender: NSMenuItem) { UserDefaults.standard.set(sender.tag, forKey: "interval"); restartTimer(); refreshNow() }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "No se pudo cambiar el inicio automático"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var status: NSStatusItem!
    lazy var dashboard = Dashboard()
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = status.button {
            button.image = portIcon(size: 18, application: false)
            button.image?.accessibilityDescription = "Puertos locales"
            button.image?.isTemplate = true
            button.toolTip = "Puertos · servicios locales"
            button.target = self
            button.action = #selector(toggleDashboard)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let mainMenu = NSMenu()
        let root = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Salir de Puertos", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = appMenu
        mainMenu.addItem(root)
        let edit = NSMenuItem(title: "Edición", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edición")
        editMenu.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu
        mainMenu.addItem(edit)
        let windowRoot = NSMenuItem(title: "Ventana", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Ventana")
        let minimize = NSMenuItem(title: "Minimizar", action: #selector(minimizeDashboard(_:)), keyEquivalent: "w")
        minimize.keyEquivalentModifierMask = .command
        minimize.target = self
        windowMenu.addItem(minimize)
        windowRoot.submenu = windowMenu
        mainMenu.addItem(windowRoot)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = mainMenu
        // Manual launches open the panel; the OS login event leaves only the menu icon.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let atLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if CommandLine.arguments.contains("--show") || (!atLogin && !CommandLine.arguments.contains("--background")) {
            showDashboard()
        }
    }
    func showDashboard() {
        if window == nil {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Puertos"
            window.contentViewController = dashboard
            window.delegate = dashboard
            window.minSize = NSSize(width: 720, height: 480)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("PuertosDashboardCards")
            if !window.setFrameUsingName("PuertosDashboardCards") { window.center() }
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        dashboard.begin()
    }
    @objc func toggleDashboard() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let open = NSMenuItem(title: "Abrir Puertos", action: #selector(openDashboard), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
            let quit = NSMenuItem(title: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            quit.target = NSApp
            menu.addItem(quit)
            if let button = status.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button) }
        } else if window?.isVisible == true && window?.isMiniaturized == false {
            dashboard.pause(); window.orderOut(nil)
        } else { showDashboard() }
    }
    @objc func openDashboard() { showDashboard() }
    @objc func minimizeDashboard(_ sender: Any?) {
        guard let window, window.isVisible, !window.isMiniaturized else { return }
        dashboard.pause()
        window.performMiniaturize(sender)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showDashboard(); return true }
    func applicationWillTerminate(_ notification: Notification) { if window != nil { dashboard.pause() } }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()
