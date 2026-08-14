import AppKit

/// A small horizontal battery indicator like iOS shows — rounded outline,
/// green proportional fill, optional charging bolt. Drawn for a light card.
final class BatteryPillView: NSView {
    private let percent: Int
    private let charging: Bool

    init(percent: Int, charging: Bool) {
        self.percent = percent
        self.charging = charging
        super.init(frame: NSRect(x: 0, y: 0, width: 30, height: 15))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: 30, height: 15) }

    override func draw(_ dirtyRect: NSRect) {
        let body = NSRect(x: 0.5, y: 1.5, width: 25, height: 12)
        let outline = NSBezierPath(roundedRect: body, xRadius: 3.5, yRadius: 3.5)
        outline.lineWidth = 1
        NSColor(white: 0.72, alpha: 1).setStroke()
        outline.stroke()
        NSColor(white: 0.72, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 26, y: 5, width: 2.2, height: 4),
                     xRadius: 1, yRadius: 1).fill()
        let inner = body.insetBy(dx: 1.8, dy: 1.8)
        let w = max(2, inner.width * CGFloat(min(max(percent, 0), 100)) / 100)
        NSColor.systemGreen.setFill()
        NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: w, height: inner.height),
                     xRadius: 1.8, yRadius: 1.8).fill()
        if charging, let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) {
            let img = bolt.withSymbolConfiguration(.init(pointSize: 9, weight: .bold)) ?? bolt
            img.isTemplate = true
            NSColor.white.set()
            img.draw(in: NSRect(x: body.midX - 4.5, y: body.midY - 4.5, width: 9, height: 9),
                     from: .zero, operation: .sourceAtop, fraction: 1)
        }
    }
}

/// The AirBuddy-style card: a white panel in the center of the screen with the
/// AirPods name, a "Click to connect" hint, a photographic buds-and-case image
/// for the specific model, and the earbud and case battery levels. Click the
/// card to connect; × to dismiss.
final class AirPodsPopup {
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?
    private var deviceName = ""

    func show(name: String, battery: AirPodsBattery) {
        dismiss()
        deviceName = name
        let connected = isConnected(name: name)

        let card = ClickView()
        card.appearance = NSAppearance(named: .aqua)   // light card in any theme
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 18
        card.translatesAutoresizingMaskIntoConstraints = false
        card.onClick = { [weak self] in self?.cardClicked(connected: connected) }

        let title = label(name, size: 22, weight: .bold, color: .black)
        title.alignment = .center
        let subtitle = label(connected ? "Connected" : "Click to connect",
                             size: 13, weight: .regular, color: NSColor(white: 0.6, alpha: 1))
        subtitle.alignment = .center

        // One combined buds+case product image for the model, sized to a fixed
        // height with the aspect ratio preserved.
        let art = NSImageView(image: deviceImage(for: name))
        art.imageScaling = .scaleProportionallyUpOrDown
        art.translatesAutoresizingMaskIntoConstraints = false
        let imageHeight: CGFloat = 132
        art.heightAnchor.constraint(equalToConstant: imageHeight).isActive = true
        art.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true

        // Both batteries below, side by side: earbuds and case.
        var cells: [NSView] = []
        if let pods = battery.minPod {
            cells.append(batteryCell("AirPods", pods,
                                     charging: battery.leftCharging || battery.rightCharging))
        }
        if let caseLevel = battery.caseLevel {
            cells.append(batteryCell("Case", caseLevel, charging: battery.caseCharging))
        }
        let batteries = NSStackView(views: cells)
        batteries.orientation = .horizontal
        batteries.spacing = 44
        batteries.alignment = .centerY

        let stack = NSStackView(views: [title, subtitle, art, batteries])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .centerX
        stack.setCustomSpacing(16, after: subtitle)
        stack.setCustomSpacing(18, after: art)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let close = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill",
                                            accessibilityDescription: "Close") ?? NSImage(),
                             target: self, action: #selector(closeTapped))
        close.isBordered = false
        close.contentTintColor = NSColor(white: 0.78, alpha: 1)
        close.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(close)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -28),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 44),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -44),
            close.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            close.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            close.widthAnchor.constraint(equalToConstant: 22),
            close.heightAnchor.constraint(equalToConstant: 22),
            card.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
        ])
        card.layoutSubtreeIfNeeded()
        let size = card.fittingSize

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = card

        if let screen = NSScreen.main {
            let f = screen.frame
            panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        self.panel = panel

        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    /// One battery reading: caption, green pill, percentage.
    private func batteryCell(_ caption: String, _ level: Int, charging: Bool) -> NSView {
        let cap = label(caption, size: 12, weight: .regular, color: NSColor(white: 0.55, alpha: 1))
        let pill = BatteryPillView(percent: level, charging: charging)
        let value = label("\(level)%", size: 16, weight: .semibold, color: .black)
        let cell = NSStackView(views: [cap, pill, value])
        cell.orientation = .vertical
        cell.spacing = 5
        cell.alignment = .centerX
        return cell
    }

    // MARK: - Device → image

    /// The bundled product image for the model, or an SF Symbol fallback.
    private func deviceImage(for name: String) -> NSImage {
        let n = name.lowercased()
        let asset: String
        if n.contains("max") { asset = "airpods-max" }
        else if n.contains("pro") { asset = (n.contains("3") ? "airpods-pro3" : "airpods-pro") }
        else if n.contains("4") { asset = "airpods-4" }
        else if n.contains("3") { asset = "airpods-3" }
        else { asset = "airpods" }

        if let url = Bundle.main.url(forResource: asset, withExtension: "png", subdirectory: "AirPodsArt"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        // Fallback for a model we have no art for (or a non-bundled dev run).
        return NSImage(systemSymbolName: "airpods", accessibilityDescription: nil) ?? NSImage()
    }

    // MARK: - Helpers

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.alignment = .center
        return l
    }

    private func isConnected(name: String) -> Bool {
        BluetoothControl.pairedDevices().first { $0.name == name }?.connected ?? false
    }

    private func cardClicked(connected: Bool) {
        guard !connected else { return }
        let name = deviceName
        DispatchQueue.global(qos: .userInitiated).async { BluetoothControl.connect(name: name) }
        dismiss()
    }

    @objc private func closeTapped() { dismiss() }

    func dismiss() {
        dismissWork?.cancel(); dismissWork = nil
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 },
                                             completionHandler: { panel.close() })
    }
}

/// A view that reports plain clicks — used to make the whole card "click to
/// connect", the way the AirBuddy card behaves.
private final class ClickView: NSView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}
