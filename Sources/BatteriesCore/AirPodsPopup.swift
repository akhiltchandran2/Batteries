import AppKit

/// A small horizontal battery indicator like iOS shows — rounded outline,
/// green proportional fill, optional charging bolt.
final class BatteryPillView: NSView {
    private let percent: Int
    private let charging: Bool

    init(percent: Int, charging: Bool) {
        self.percent = percent
        self.charging = charging
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 13))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: 26, height: 13) }

    override func draw(_ dirtyRect: NSRect) {
        let body = NSRect(x: 0.5, y: 1, width: 21.5, height: 11)
        let outline = NSBezierPath(roundedRect: body, xRadius: 3.5, yRadius: 3.5)
        outline.lineWidth = 1
        NSColor.tertiaryLabelColor.setStroke()
        outline.stroke()
        // nub
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 23, y: 4.6, width: 2, height: 3.8),
                     xRadius: 1, yRadius: 1).fill()
        // green proportional fill
        let inner = body.insetBy(dx: 1.7, dy: 1.7)
        let w = max(2, inner.width * CGFloat(min(max(percent, 0), 100)) / 100)
        let green = NSColor.systemGreen
        green.setFill()
        NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: w, height: inner.height),
                     xRadius: 1.8, yRadius: 1.8).fill()
        if charging, let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
            let img = bolt.withSymbolConfiguration(cfg) ?? bolt
            img.isTemplate = true
            NSColor.white.set()
            let r = NSRect(x: body.midX - 4, y: body.midY - 4, width: 8, height: 8)
            img.draw(in: r, from: .zero, operation: .sourceAtop, fraction: 1)
        }
    }
}

/// The AirBuddy/iPhone-style card that drops in near the top of the screen when
/// the AirPods case is opened: a large AirPods graphic, the name, and green
/// battery pills for the earbuds and the case. Auto-dismisses. Main-thread only.
final class AirPodsPopup {
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?
    private var deviceName = ""

    func show(name: String, battery: AirPodsBattery) {
        dismiss()
        deviceName = name

        let card = NSVisualEffectView()
        card.material = .popover
        card.blendingMode = .behindWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 22
        card.translatesAutoresizingMaskIntoConstraints = false

        // Large AirPods graphic, centered (iPhone-card style).
        let symbol = symbolName(for: name)
        let art = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            ?? NSImage())
        art.symbolConfiguration = .init(pointSize: 64, weight: .regular)
        art.contentTintColor = .labelColor

        let title = NSTextField(labelWithString: name)
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.alignment = .center

        let pods = pill(caption: "AirPods", level: battery.minPod,
                        charging: battery.leftCharging || battery.rightCharging)
        let caseCell = pill(caption: "Case", level: battery.caseLevel, charging: battery.caseCharging)
        let pillsRow = NSStackView(views: [pods, caseCell].compactMap { $0 })
        pillsRow.orientation = .horizontal
        pillsRow.spacing = 28
        pillsRow.distribution = .equalSpacing

        let content = NSStackView(views: [art, title, pillsRow])
        content.orientation = .vertical
        content.spacing = 10
        content.alignment = .centerX
        content.edgeInsets = NSEdgeInsets(top: 22, left: 28, bottom: 22, right: 28)
        content.translatesAutoresizingMaskIntoConstraints = false

        if !isConnected(name: name) {
            let connect = NSButton(title: "Connect", target: self, action: #selector(connectTapped))
            connect.bezelStyle = .rounded
            connect.controlSize = .large
            connect.keyEquivalent = "\r"
            content.setCustomSpacing(16, after: pillsRow)
            content.addArrangedSubview(connect)
        }

        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            content.topAnchor.constraint(equalTo: card.topAnchor),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            card.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
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
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.maxY - size.height - 12))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.22; panel.animator().alphaValue = 1 }
        self.panel = panel

        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    /// A vertical cell: percentage, a green battery pill, and a caption.
    private func pill(caption: String, level: Int?, charging: Bool) -> NSView? {
        guard let level else { return nil }
        let value = NSTextField(labelWithString: "\(level)%")
        value.font = .systemFont(ofSize: 17, weight: .semibold)
        value.alignment = .center
        let bar = BatteryPillView(percent: level, charging: charging)
        let cap = NSTextField(labelWithString: caption)
        cap.font = .systemFont(ofSize: 12)
        cap.textColor = .secondaryLabelColor
        cap.alignment = .center
        let stack = NSStackView(views: [value, bar, cap])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.alignment = .centerX
        return stack
    }

    private func symbolName(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("max") { return "airpodsmax" }
        if n.contains("pro") { return "airpodspro" }
        return "airpods"
    }

    private func isConnected(name: String) -> Bool {
        BluetoothControl.pairedDevices().first { $0.name == name }?.connected ?? false
    }

    @objc private func connectTapped() {
        let name = deviceName
        DispatchQueue.global(qos: .userInitiated).async { BluetoothControl.connect(name: name) }
        dismiss()
    }

    func dismiss() {
        dismissWork?.cancel(); dismissWork = nil
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 },
                                             completionHandler: { panel.close() })
    }
}
