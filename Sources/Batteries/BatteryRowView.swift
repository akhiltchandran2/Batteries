import AppKit

/// Compact menu row: [device icon] Name ............ 70% [battery glyph]
/// Used as an NSMenuItem custom view so the percentage and battery glyph
/// can be right-aligned like the system battery menu.
final class BatteryRowView: NSView {
    static let rowWidth: CGFloat = 310
    static let sideInset: CGFloat = 16

    init(icon: String? = nil,
         title: String,
         bold: Bool = false,
         percent: Int?,
         charging: Bool = false,
         showGlyph: Bool = true,
         detail: String? = nil,
         isComponent: Bool = false) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.rowWidth,
                                 height: isComponent ? 22 : 28))
        toolTip = detail

        let fontSize: CGFloat = isComponent ? 12 : 13
        let textColor: NSColor = isComponent ? .secondaryLabelColor : .labelColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = bold ? .systemFont(ofSize: fontSize, weight: .semibold)
                               : .menuFont(ofSize: fontSize)
        titleLabel.textColor = textColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        var titleLeading = leadingAnchor
        // Component rows (AirPods Left/Right/Case) indent to align with the
        // parent row's title.
        var titleLeadingGap: CGFloat = isComponent ? Self.sideInset + 27 : Self.sideInset
        if let icon,
           let image = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            let iconView = NSImageView(image: image.withSymbolConfiguration(
                .init(pointSize: 13, weight: .regular)) ?? image)
            iconView.contentTintColor = .secondaryLabelColor
            iconView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(iconView)
            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.sideInset),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 20),
            ])
            titleLeading = iconView.trailingAnchor
            titleLeadingGap = 7
        }

        let percentLabel = NSTextField(labelWithString: percent.map { "\($0)%" } ?? "—")
        percentLabel.font = .menuFont(ofSize: fontSize)
        percentLabel.textColor = percent == nil ? .secondaryLabelColor : textColor
        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(percentLabel)

        var percentTrailing = trailingAnchor
        var percentTrailingGap: CGFloat = -Self.sideInset
        if showGlyph,
           let image = NSImage(systemSymbolName: Self.glyphName(percent: percent, charging: charging),
                               accessibilityDescription: nil) {
            let glyphView = NSImageView(image: image.withSymbolConfiguration(
                .init(pointSize: isComponent ? 11 : 13, weight: .regular)) ?? image)
            glyphView.contentTintColor = .secondaryLabelColor
            glyphView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(glyphView)
            NSLayoutConstraint.activate([
                glyphView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.sideInset),
                glyphView.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            percentTrailing = glyphView.leadingAnchor
            percentTrailingGap = -7
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: titleLeading, constant: titleLeadingGap),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            percentLabel.trailingAnchor.constraint(equalTo: percentTrailing, constant: percentTrailingGap),
            percentLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: percentLabel.leadingAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Secondary-text line ("Power Source: …", "34m until fully charged") with
/// margins matching BatteryRowView so all text aligns.
final class InfoRowView: NSView {
    init(text: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: BatteryRowView.rowWidth, height: 20))
        let label = NSTextField(labelWithString: text)
        label.font = .menuFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: BatteryRowView.sideInset),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor,
                                            constant: -BatteryRowView.sideInset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

extension BatteryRowView {
    /// Header variant ("Battery   93%") — bold, no glyph, slightly taller.
    convenience init(header title: String, percent: Int?) {
        self.init(title: title, bold: true, percent: percent, showGlyph: false)
        setFrameSize(NSSize(width: Self.rowWidth, height: 30))
    }

    static func glyphName(percent: Int?, charging: Bool) -> String {
        guard let percent else { return "battery.0percent" }
        if charging { return "battery.100percent.bolt" }
        switch percent {
        case 90...: return "battery.100percent"
        case 60..<90: return "battery.75percent"
        case 35..<60: return "battery.50percent"
        case 10..<35: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}
