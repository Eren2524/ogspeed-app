import WidgetKit
import SwiftUI

struct Entry: TimelineEntry {
    let date: Date
    let result: SpeedResult?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        var r = SpeedResult()
        r.downMbps = 248; r.upMbps = 42; r.pingMs = 14; r.jitterMs = 2; r.loadedPingMs = 30; r.connection = .wifi
        return Entry(date: Date(), result: r)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : Entry(date: Date(), result: SharedStore.lastResult))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: Date(), result: SharedStore.lastResult)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
    }
}

struct OGSpeedWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        Group {
            if let r = entry.result {
                switch family {
                case .systemMedium: medium(r)
                case .accessoryRectangular: rectangular(r)
                case .accessoryCircular: circular(r)
                default: small(r)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "speedometer").font(.title).foregroundStyle(Neon.cyan)
                    Text("Tippen zum Testen").font(.caption.weight(.semibold))
                }
            }
        }
        .widgetURL(URL(string: "ogspeed://test"))
        .containerBackground(for: .widget) {
            ZStack {
                Neon.bg
                Circle().fill(Neon.purple.opacity(0.5)).blur(radius: 40).offset(x: -40, y: -40)
                Circle().fill(Neon.cyan.opacity(0.35)).blur(radius: 40).offset(x: 50, y: 50)
            }
        }
    }

    private func small(_ r: SpeedResult) -> some View {
        let o = Rating.overall(r)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("OGSpeed").font(.caption2.weight(.heavy)).foregroundStyle(Neon.cyan)
                Spacer()
                Circle().fill(o.level.color).frame(width: 9, height: 9).shadow(color: o.level.color, radius: 4)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(Fmt.mbps(r.downMbps)).font(.system(size: 34, weight: .heavy, design: .rounded)).minimumScaleFactor(0.6)
                Text("↓").font(.headline).foregroundStyle(.secondary)
            }
            Text("\(Fmt.mbps(r.upMbps)) ↑ · \(Fmt.ms(r.pingMs)) ms").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text(o.title).font(.caption2.weight(.bold)).foregroundStyle(o.level.color).lineLimit(1)
            Text(r.date, style: .relative).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
    }

    private func medium(_ r: SpeedResult) -> some View {
        let o = Rating.overall(r)
        let parts = Rating.all(r)
        return HStack(spacing: 14) {
            small(r)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(parts) { v in
                    HStack(spacing: 6) {
                        Image(systemName: v.icon).font(.caption2).foregroundStyle(v.level.color).frame(width: 14)
                        Text(v.title).font(.caption2.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 0)
                        Circle().fill(v.level.color).frame(width: 7, height: 7)
                    }
                }
                Text(o.text).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
            }
            .foregroundStyle(.white)
        }
    }

    private func rectangular(_ r: SpeedResult) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("OGSpeed").font(.caption2.weight(.bold))
            Text("\(Fmt.mbps(r.downMbps)) ↓  \(Fmt.mbps(r.upMbps)) ↑").font(.headline.monospacedDigit())
            Text("Ping \(Fmt.ms(r.pingMs)) ms · \(Rating.overall(r).level.label)").font(.caption2)
        }
    }

    private func circular(_ r: SpeedResult) -> some View {
        Gauge(value: min(1, log10(1 + r.downMbps) / 3)) {
            Image(systemName: "arrow.down")
        } currentValueLabel: {
            Text(Fmt.mbps(r.downMbps)).font(.system(size: 12, weight: .bold))
        }
        .gaugeStyle(.accessoryCircular)
    }
}

@main
struct OGSpeedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OGSpeedWidget", provider: Provider()) { entry in
            OGSpeedWidgetView(entry: entry)
        }
        .configurationDisplayName("OGSpeed")
        .description("Dein letzter Speedtest mit Ampel. Tippen startet einen neuen Test.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}
