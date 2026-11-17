import SwiftUI

/// Logarithmische Skala, damit 10 und 1000 Mbit/s beide gut sichtbar sind
enum SpeedScale {
    static let marks: [Double] = [0, 5, 10, 50, 100, 250, 500, 1000]
    static func fraction(_ v: Double) -> Double {
        guard v > 0 else { return 0 }
        return min(1, log10(1 + v) / log10(1001))
    }
    static func pingFraction(_ ms: Double) -> Double {
        // Ping: voller Ring = sehr gut (niedrig)
        max(0.05, min(1, 1 - log10(1 + ms) / log10(301)))
    }
}

struct SpeedRing: View {
    var phase: TestPhase
    var value: Double
    var progress: Double
    var startAction: () -> Void

    @State private var pulse = false
    private let arc: Double = 0.75   // 270°-Ring, Lücke unten

    private var colors: [Color] {
        switch phase {
        case .upload: return [Neon.magenta, Neon.purple, Neon.magenta]
        case .ping: return [Neon.lime, Neon.green, Neon.cyan]
        default: return [Neon.cyan, Neon.purple, Neon.magenta]
        }
    }

    private var fill: Double {
        switch phase {
        case .ping: return SpeedScale.pingFraction(value)
        case .download, .upload, .done: return SpeedScale.fraction(value)
        case .preparing: return 0.02
        default: return 0
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size: CGFloat = min(geo.size.width, geo.size.height)
            ZStack {
                trackRing
                progressRing
                valueRing
                if showScale { scaleLabels(size: size) }
                center(size: size)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var showScale: Bool { phase == .download || phase == .upload || phase == .done }

    private var trackRing: some View {
        Circle()
            .trim(from: 0, to: arc)
            .stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 24, lineCap: .round))
            .rotationEffect(.degrees(135))
    }

    private var progressRing: some View {
        let amount: Double = phase == .idle ? 0 : progress
        return Circle()
            .trim(from: 0, to: CGFloat(arc * amount))
            .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(135))
            .padding(-20)
            .animation(.linear(duration: 0.2), value: progress)
    }

    private var valueRing: some View {
        let f: Double = fill
        let endDeg: Double = 270 * Swift.max(f, 0.01)
        let gradient = AngularGradient(colors: colors, center: .center,
                                       startAngle: .degrees(0), endAngle: .degrees(endDeg))
        let style = StrokeStyle(lineWidth: 24, lineCap: .round)
        return Circle()
            .trim(from: 0, to: CGFloat(arc * f))
            .stroke(gradient, style: style)
            .rotationEffect(.degrees(135))
            .neonGlow(colors[0], radius: 12)
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: f)
    }

    private func scaleLabels(size: CGFloat) -> some View {
        ForEach(SpeedScale.marks, id: \.self) { m in
            ScaleMark(mark: m, size: size)
        }
    }

    @ViewBuilder
    private func center(size: CGFloat) -> some View {
        switch phase {
        case .idle, .failed:
            Button(action: startAction) {
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    Circle().strokeBorder(LinearGradient(colors: [Neon.cyan, Neon.magenta], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
                        .neonGlow(Neon.cyan, radius: pulse ? 14 : 6)
                    VStack(spacing: 2) {
                        Text("START").font(.system(size: 34, weight: .heavy, design: .rounded))
                        Text("Tippen zum Testen").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: size * 0.52, height: size * 0.52)
                .scaleEffect(pulse ? 1.04 : 0.98)
            }
            .buttonStyle(.plain)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
            }
        default:
            VStack(spacing: 2) {
                Label(phase.title, systemImage: phaseIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors[0])
                Text(phase == .preparing ? "…" : (phase == .ping ? Fmt.ms(value) : Fmt.mbps(value)))
                    .font(.system(size: size * 0.2, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: value))
                    .animation(.snappy, value: value)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(phase == .ping ? "ms" : "Mbit/s")
                    .font(.headline).foregroundStyle(.secondary)
            }
            .frame(width: size * 0.6)
        }
    }

    private var phaseIcon: String {
        switch phase {
        case .ping: return "bolt.horizontal.fill"
        case .download: return "arrow.down"
        case .upload: return "arrow.up"
        case .done: return "checkmark"
        default: return "network"
        }
    }
}

private struct ScaleMark: View {
    let mark: Double
    let size: CGFloat

    var body: some View {
        let radians: Double = (135.0 + 270.0 * SpeedScale.fraction(mark)) * Double.pi / 180.0
        let half: Double = Double(size) / 2.0
        let r: Double = half - 44.0
        let x: Double = half + cos(radians) * r
        let y: Double = half + sin(radians) * r
        let label: String = mark >= 1000 ? "1G" : "\(Int(mark))"
        return Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .position(x: CGFloat(x), y: CGFloat(y))
    }
}
