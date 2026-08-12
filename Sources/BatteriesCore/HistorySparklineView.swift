import AppKit

/// One row in the "Battery History" submenu: device name, latest reading,
/// and a compact 24h line chart. Drawn with plain NSBezierPath — a sparkline
/// this simple doesn't need a charting dependency.
final class HistorySparklineView: NSView {
    init(name: String, samples: [BatteryHistory.Sample]) {
        super.init(frame: NSRect(x: 0, y: 0, width: BatteryRowView.rowWidth, height: 48))

        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .menuFont(ofSize: 12)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        let latestLabel = NSTextField(labelWithString: "\(samples.last?.percent ?? 0)%")
        latestLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        latestLabel.textColor = .labelColor
        latestLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(latestLabel)

        let chart = SparklineChartView(samples: samples)
        chart.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chart)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: BatteryRowView.sideInset),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            latestLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -BatteryRowView.sideInset),
            latestLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: latestLabel.leadingAnchor, constant: -8),
            chart.leadingAnchor.constraint(equalTo: leadingAnchor, constant: BatteryRowView.sideInset),
            chart.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -BatteryRowView.sideInset),
            chart.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            chart.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class SparklineChartView: NSView {
    private let samples: [BatteryHistory.Sample]

    init(samples: [BatteryHistory.Sample]) {
        self.samples = samples
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        guard samples.count >= 2, bounds.width > 0, bounds.height > 0 else { return }

        let values = samples.map { CGFloat($0.percent) }
        let range: CGFloat = 100

        func point(_ index: Int) -> NSPoint {
            let x = bounds.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = (values[index] / range) * (bounds.height - 2) + 1
            return NSPoint(x: x, y: y)
        }

        let line = NSBezierPath()
        line.move(to: point(0))
        for index in 1..<values.count { line.line(to: point(index)) }

        let fill = NSBezierPath()
        fill.move(to: NSPoint(x: 0, y: 0))
        for index in 0..<values.count { fill.line(to: point(index)) }
        fill.line(to: NSPoint(x: bounds.width, y: 0))
        fill.close()

        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        fill.fill()

        NSColor.controlAccentColor.setStroke()
        line.lineWidth = 1.3
        line.stroke()
    }
}
