import SwiftUI

/// Dunkler Hintergrund mit langsam wandernden Neon-Lichtern
struct NeonBackground: View {
    @State private var move = false

    var body: some View {
        ZStack {
            Neon.bg
            Circle().fill(Neon.purple.opacity(0.45)).frame(width: 380).blur(radius: 120)
                .offset(x: move ? -120 : -60, y: move ? -260 : -180)
            Circle().fill(Neon.cyan.opacity(0.30)).frame(width: 320).blur(radius: 120)
                .offset(x: move ? 140 : 90, y: move ? 120 : 220)
            Circle().fill(Neon.magenta.opacity(0.25)).frame(width: 260).blur(radius: 110)
                .offset(x: move ? 60 : 130, y: move ? -40 : -120)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { move = true }
        }
    }
}

/// Glas-Karte
struct Glass: ViewModifier {
    var radius: CGFloat = 26
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}

extension View {
    func glass(radius: CGFloat = 26, padding: CGFloat = 16) -> some View {
        modifier(Glass(radius: radius, padding: padding))
    }

    func neonGlow(_ c: Color, radius: CGFloat = 10) -> some View {
        shadow(color: c.opacity(0.9), radius: radius).shadow(color: c.opacity(0.4), radius: radius * 2)
    }
}

/// Ampel-Punkt mit Leuchten
struct AmpelDot: View {
    let level: Level
    var size: CGFloat = 12
    var body: some View {
        Circle().fill(level.color).frame(width: size, height: size).neonGlow(level.color, radius: size / 2)
    }
}

/// Kleines Ampel-Etikett: "● Top"
struct LevelPill: View {
    let level: Level
    var body: some View {
        HStack(spacing: 6) {
            AmpelDot(level: level, size: 8)
            Text(level.label).font(.caption.weight(.bold))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(level.color.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(level.color.opacity(0.5), lineWidth: 1))
        .foregroundStyle(level.color)
    }
}

struct NeonButtonStyle: ButtonStyle {
    var colors: [Color] = [Neon.cyan, Neon.magenta]
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.black)
            .padding(.vertical, 14).frame(maxWidth: .infinity)
            .background(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing), in: Capsule())
            .neonGlow(colors[0], radius: 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25), value: configuration.isPressed)
    }
}

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 12).frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Kleine Info-Kachel: Titel, Wert, Einheit, Ampel
struct StatTile: View {
    let title: String
    let value: String
    let unit: String
    var level: Level?
    var icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption)
                Text(title).font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                if let level { AmpelDot(level: level, size: 7) }
            }
            .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text(unit).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 20, padding: 12)
    }
}
