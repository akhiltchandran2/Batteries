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

        // One combined buds+case product image for the model, over a soft
        // animated ripple that gives the card a "live" feel. The image's
        // transparent background lets the rings show through around it.
        let art = NSImageView(image: deviceImage(model: battery.model, name: name))
        art.imageScaling = .scaleProportionallyUpOrDown
        art.translatesAutoresizingMaskIntoConstraints = false

        let ripple = RippleView()
        ripple.translatesAutoresizingMaskIntoConstraints = false

        let artContainer = NSView()
        artContainer.translatesAutoresizingMaskIntoConstraints = false
        artContainer.addSubview(ripple)
        artContainer.addSubview(art)
        NSLayoutConstraint.activate([
            artContainer.heightAnchor.constraint(equalToConstant: 150),
            artContainer.widthAnchor.constraint(equalToConstant: 220),
            ripple.centerXAnchor.constraint(equalTo: artContainer.centerXAnchor),
            ripple.centerYAnchor.constraint(equalTo: artContainer.centerYAnchor),
            ripple.widthAnchor.constraint(equalToConstant: 200),
            ripple.heightAnchor.constraint(equalToConstant: 150),
            art.centerXAnchor.constraint(equalTo: artContainer.centerXAnchor),
            art.centerYAnchor.constraint(equalTo: artContainer.centerYAnchor),
            art.heightAnchor.constraint(equalToConstant: 132),
            art.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
        ])

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

        let stack = NSStackView(views: [title, subtitle, artContainer, batteries])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .centerX
        stack.setCustomSpacing(12, after: subtitle)
        stack.setCustomSpacing(14, after: artContainer)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let closeImage = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")?
            .withSymbolConfiguration(.init(pointSize: 24, weight: .regular))
        let close = NSButton(image: closeImage ?? NSImage(), target: self, action: #selector(closeTapped))
        close.isBordered = false
        close.imageScaling = .scaleProportionallyUpOrDown
        close.contentTintColor = NSColor(white: 0.75, alpha: 1)
        close.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(close)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -28),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 44),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -44),
            close.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            close.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            close.widthAnchor.constraint(equalToConstant: 28),
            close.heightAnchor.constraint(equalToConstant: 28),
            card.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
        ])
        card.layoutSubtreeIfNeeded()
        let size = card.fittingSize

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = card

        var finalOrigin = NSPoint.zero
        if let screen = NSScreen.main {
            let f = screen.frame
            finalOrigin = NSPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2)
        }
        // Start slightly higher and settle down into place while fading in.
        panel.setFrameOrigin(NSPoint(x: finalOrigin.x, y: finalOrigin.y + 26))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(finalOrigin)
        }
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

    /// The bundled product image, chosen from the Apple model identifier in the
    /// broadcast (the device name has no model number), falling back to a
    /// name guess, then to an SF Symbol.
    private func deviceImage(model: UInt16, name: String) -> NSImage {
        let asset = assetForModel(model) ?? assetForName(name)
        if let url = Bundle.main.url(forResource: asset, withExtension: "png", subdirectory: "AirPodsArt"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "airpods", accessibilityDescription: nil) ?? NSImage()
    }

    /// Apple proximity model IDs (0x20XX) → bundled art. nil = unknown model.
    private func assetForModel(_ model: UInt16) -> String? {
        switch model {
        case 0x2002, 0x200F: return "airpods"        // AirPods 1 / 2
        case 0x2013: return "airpods-3"              // AirPods 3
        case 0x2019, 0x201B: return "airpods-4"      // AirPods 4 / 4 ANC
        case 0x200E: return "airpods-pro"            // AirPods Pro
        case 0x2014, 0x2024: return "airpods-pro"    // AirPods Pro 2 (Lightning / USB-C)
        case 0x200A, 0x201F: return "airpods-max"    // AirPods Max (Lightning / USB-C)
        default: return nil
        }
    }

    private func assetForName(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("max") { return "airpods-max" }
        if n.contains("pro") { return n.contains("3") ? "airpods-pro3" : "airpods-pro" }
        if n.contains("4") { return "airpods-4" }
        if n.contains("3") { return "airpods-3" }
        return "airpods"
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

/// Soft concentric rings that gently expand and fade behind the AirPods image,
/// giving the card a subtle "live" pulse. Purely decorative.
private final class RippleView: NSView {
    private var started = false

    override func layout() {
        super.layout()
        guard !started, window != nil, bounds.width > 0 else { return }
        started = true
        startRipples()
    }

    private func startRipples() {
        wantsLayer = true
        layer?.masksToBounds = false
        let dim = min(bounds.width, bounds.height) + 50
        let ringCount = 3
        for i in 0..<ringCount {
            let ring = CALayer()
            ring.frame = CGRect(x: (bounds.width - dim) / 2, y: (bounds.height - dim) / 2,
                                width: dim, height: dim)
            ring.cornerRadius = dim / 2
            ring.borderWidth = 1.5
            ring.borderColor = NSColor(white: 0.55, alpha: 1).cgColor
            ring.opacity = 0
            layer?.addSublayer(ring)

            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.4
            scale.toValue = 1.0
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.18
            fade.toValue = 0.0
            let group = CAAnimationGroup()
            group.animations = [scale, fade]
            group.duration = 3.0
            group.beginTime = CACurrentMediaTime() + Double(i)   // stagger by 1s
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ring.add(group, forKey: "ripple")
        }
    }
}
