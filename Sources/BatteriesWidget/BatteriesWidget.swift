import WidgetKit
import SwiftUI

struct BatteriesWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct BatteriesWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteriesWidgetEntry {
        BatteriesWidgetEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteriesWidgetEntry) -> Void) {
        completion(BatteriesWidgetEntry(date: Date(), snapshot: WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteriesWidgetEntry>) -> Void) {
        let entry = BatteriesWidgetEntry(date: Date(), snapshot: WidgetSnapshot.read())
        // The main app writes a fresh snapshot every 1-5 minutes; asking
        // WidgetKit to check back in 10 keeps the widget current without
        // polling faster than the underlying data actually changes.
        let nextUpdate = Date().addingTimeInterval(600)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct BatteriesWidgetView: View {
    var entry: BatteriesWidgetProvider.Entry

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 6) {
                if let mac = snapshot.mac {
                    row(mac)
                }
                ForEach(snapshot.devices.prefix(4)) { device in
                    row(device)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        } else {
            VStack {
                Text("Open Batteries to start monitoring")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private func row(_ entry: WidgetSnapshot.Entry) -> some View {
        HStack(spacing: 6) {
            Image(systemName: entry.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(entry.name)
                .font(.footnote)
                .lineLimit(1)
            Spacer()
            if let percent = entry.percent {
                Text("\(percent)%")
                    .font(.footnote.weight(.medium))
            } else {
                Text("—")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if entry.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
    }
}

struct BatteriesWidget: Widget {
    let kind = "BatteriesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BatteriesWidgetProvider()) { entry in
            BatteriesWidgetView(entry: entry)
        }
        .configurationDisplayName("Batteries")
        .description("Battery levels for your Mac and connected devices.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
