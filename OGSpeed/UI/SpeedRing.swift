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
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                // Spur
                Circle()
                    .trim(from: 0, to: arc)
                    .stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 24, lineCap: .round))
                    .rotationEffect(.degrees(135))
                // Fortschritt der Phase (dünner Außenring)
                Circle()
                    .trim(from: 0, to: arc * (phase == .idle ? 0 : progress))
                    .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(-20)
                    .animation(.linear(duration: 0.2), value: progress)
                // Wert
                Circle()
                    .trim(from: 0, to: arc * fill)
                    .stroke(AngularGradient(colors: colors, center: .center, startAngle: .degrees(0), endAngle: .degrees(270 * max(fill, 0.01))),
                            style: StrokeStyle(lineWidth: 24, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .neonGlow(colors[0], radius: 12)
                    .animation(.spring(response: 0.45, dampingFraction: 0.75), value: fill)

                // Skala
                if phase == .download || phase == .upload || phase == .done {
                    ForEach(SpeedScale.marks, id: \.self) { m in
                        let a = Angle.degrees(135 + 270 * SpeedScale.fraction(m))
                        Text(m >= 1000 ? "1G" : "\(Int(m))")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .position(x: size / 2 + cos(a.radians) * (size / 2 - 44),
                                      y: size / 2 + sin(a.radians) * (size / 2 - 44))
                    }
                }

                center(size: size)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
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
