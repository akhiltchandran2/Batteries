import AppKit

/// Compact menu row: [device icon] Name ............ 70% [battery glyph]
/// Used as an NSMenuItem custom view so the percentage and battery glyph
/// can be right-aligned like the system battery menu.
final class BatteryRowView: NSView {
    static let rowWidth: CGFloat = 310
    static let sideInset: CGFloat = 16

    private let percentLabel: NSTextField
    private let glyphView: NSImageView?
    private let isComponent: Bool
    private let isMuted: Bool

    init(icon: String? = nil,
         title: String,
         bold: Bool = false,
         percent: Int?,
         charging: Bool = false,
         showGlyph: Bool = true,
         isComponent: Bool = false,
         isMuted: Bool = false) {
        self.isComponent = isComponent
        self.isMuted = isMuted

        let fontSize: CGFloat = isComponent ? 12 : 13
        let textColor: NSColor = isComponent ? .secondaryLabelColor
                                : (isMuted ? .tertiaryLabelColor : .labelColor)
        let dimTint: NSColor = isMuted ? .tertiaryLabelColor : .secondaryLabelColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = bold ? .systemFont(ofSize: fontSize, weight: .semibold)
                               : .menuFont(ofSize: fontSize)
        titleLabel.textColor = textColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let percentLabel = NSTextField(labelWithString: percent.map { "\($0)%" } ?? "—")
        percentLabel.font = .menuFont(ofSize: fontSize)
        percentLabel.textColor = percent == nil ? .secondaryLabelColor : textColor
        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        self.percentLabel = percentLabel

        var glyphView: NSImageView?
        if showGlyph,
           let image = NSImage(systemSymbolName: Self.glyphName(percent: percent, charging: charging),
                               accessibilityDescription: nil) {
            let view = NSImageView(image: image.withSymbolConfiguration(
                .init(pointSize: isComponent ? 11 : 13, weight: .regular)) ?? image)
            view.contentTintColor = dimTint
            view.translatesAutoresizingMaskIntoConstraints = false
            glyphView = view
        }
        self.glyphView = glyphView

        super.init(frame: NSRect(x: 0, y: 0, width: Self.rowWidth,
                                 height: isComponent ? 22 : 28))

        addSubview(titleLabel)
        addSubview(percentLabel)

        var titleLeading = leadingAnchor
        // Component rows (AirPods Left/Right/Case) indent to align with the
        // parent row's title.
        var titleLeadingGap: CGFloat = isComponent ? Self.sideInset + 27 : Self.sideInset
        if let icon,
           let image = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            let iconView = NSImageView(image: image.withSymbolConfiguration(
                .init(pointSize: 13, weight: .regular)) ?? image)
            iconView.contentTintColor = dimTint
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

        var percentTrailing = trailingAnchor
        var percentTrailingGap: CGFloat = -Self.sideInset
        if let glyphView {
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

    /// Updates the displayed percent/charging state in place, without
    /// touching layout — safe to call while this row's menu is on screen
    /// (unlike rebuilding the menu's items, which leaves stale empty space
    /// if done while open). Icon and title never change post-creation, so
    /// they're left alone.
    func update(percent: Int?, charging: Bool) {
        let textColor: NSColor = isComponent ? .secondaryLabelColor
                                : (isMuted ? .tertiaryLabelColor : .labelColor)
        percentLabel.stringValue = percent.map { "\($0)%" } ?? "—"
        percentLabel.textColor = percent == nil ? .secondaryLabelColor : textColor

        if let glyphView,
           let image = NSImage(systemSymbolName: Self.glyphName(percent: percent, charging: charging),
                               accessibilityDescription: nil) {
            glyphView.image = image.withSymbolConfiguration(
                .init(pointSize: isComponent ? 11 : 13, weight: .regular)) ?? image
        }
    }
}

/// Secondary-text line ("Power Source: …", "34m until fully charged") with
/// margins matching BatteryRowView so all text aligns. `indented` nests it
/// under a specific device row (aligned with the name, past the icon) so
/// a per-device status line reads as belonging to that row rather than
/// floating as a separate item in the list.
final class InfoRowView: NSView {
    private let label: NSTextField

    init(text: String, indented: Bool = false) {
        let label = NSTextField(labelWithString: text)
        label.font = .menuFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        self.label = label

        super.init(frame: NSRect(x: 0, y: 0, width: BatteryRowView.rowWidth, height: 20))
        addSubview(label)
        let leadingConstant = indented ? BatteryRowView.sideInset + 27 : BatteryRowView.sideInset
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingConstant),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor,
                                            constant: -BatteryRowView.sideInset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Updates the displayed text in place — safe while the menu is open,
    /// same reasoning as BatteryRowView.update(percent:charging:).
    func update(text: String) {
        label.stringValue = text
    }
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
