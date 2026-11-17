import SwiftUI
import PhotosUI

// MARK: - Neuer Raum

struct NewRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RoomStore.self) private var rooms
    @State private var name = ""
    @State private var image: UIImage?
    @State private var pick: PhotosPickerItem?
    @State private var camera = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TextField("Name, z. B. Wohnzimmer", text: $name)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.viewfinder").font(.system(size: 44)).foregroundStyle(Neon.cyan)
                            Text("Fotografier den Raum am besten von der Tür aus – oder mach ein Panorama. Auch ein Foto vom Grundriss geht.")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                        .glass()
                    }

                    HStack(spacing: 10) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { camera = true } label: { Label("Foto machen", systemImage: "camera.fill") }
                                .buttonStyle(GlassButtonStyle())
                        }
                        PhotosPicker(selection: $pick, matching: .images) {
                            Label("Aus Fotos", systemImage: "photo.on.rectangle")
                                .font(.subheadline.weight(.semibold))
                                .padding(.vertical, 12).frame(maxWidth: .infinity)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Raum anlegen") {
                        if let image, rooms.create(name: name.isEmpty ? "Mein Raum" : name, image: image) != nil { dismiss() }
                    }
                    .buttonStyle(NeonButtonStyle())
                    .disabled(image == nil)
                    .opacity(image == nil ? 0.4 : 1)
                }
                .padding()
            }
            .background(NeonBackground())
            .navigationTitle("Neuer Raum")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .fullScreenCover(isPresented: $camera) {
                CameraPicker(image: $image).ignoresSafeArea()
            }
            .onChange(of: pick) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        image = img
                    }
                }
            }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = (info[.originalImage] as? UIImage)?.normalized()
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - Wärmekarte

struct RoomMapView: View {
    let roomID: UUID
    @Environment(RoomStore.self) private var rooms
    @Environment(\.dismiss) private var dismiss
    @State private var measuringAt: CGPoint?
    @State private var showHeat = true
    @State private var selected: MeasurePoint?
    @State private var confirmDelete = false

    private var room: RoomMap? { rooms.rooms.first { $0.id == roomID } }

    var body: some View {
        ScrollView {
            if let room, let img = rooms.image(for: room) {
                VStack(spacing: 16) {
                    Text(measuringAt == nil ? "Stell dich an eine Stelle und tippe sie auf dem Foto an." : "Messe … bitte kurz stillhalten")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    mapCanvas(room: room, image: img)

                    Toggle("Wärmekarte anzeigen", isOn: $showHeat).tint(Neon.cyan).glass(radius: 18, padding: 12)

                    summary(room)

                    if let sel = selected { pointCard(sel, room: room) }
                }
                .padding()
            }
        }
        .scrollIndicators(.hidden)
        .background(NeonBackground())
        .navigationTitle(room?.name ?? "Raum")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Alle Messpunkte löschen", role: .destructive) {
                        if var r = room { r.points = []; rooms.update(r); selected = nil }
                    }
                    Button("Raum löschen", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog("Raum wirklich löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let room { rooms.delete(room) }
                dismiss()
            }
        }
    }

    private func mapCanvas(room: RoomMap, image: UIImage) -> some View {
        let ratio = image.size.width / max(image.size.height, 1)
        return GeometryReader { geo in
            let size = geo.size
            ZStack {
                Image(uiImage: image).resizable().scaledToFill().frame(width: size.width, height: size.height).clipped()
                    .overlay(Color.black.opacity(showHeat ? 0.25 : 0))
                if showHeat && !room.points.isEmpty {
                    HeatLayer(points: room.points, size: size)
                        .blendMode(.screen)
                        .allowsHitTesting(false)
                }
                ForEach(room.points) { p in
                    let isBest = p.id == room.best?.id && room.points.count > 1
                    ZStack {
                        Circle().fill(p.sample.level.color).frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .neonGlow(p.sample.level.color, radius: 6)
                        if isBest {
                            Image(systemName: "star.fill").font(.system(size: 18)).foregroundStyle(Neon.yellow)
                                .neonGlow(Neon.yellow, radius: 6).offset(y: -20)
                        }
                    }
                    .position(x: p.x * size.width, y: p.y * size.height)
                    .onTapGesture { selected = p }
                }
                if let m = measuringAt {
                    ProgressView().tint(.white).padding(10).background(.ultraThinMaterial, in: Circle())
                        .position(x: m.x * size.width, y: m.y * size.height)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { e in
                guard measuringAt == nil else { return }
                let pt = CGPoint(x: e.location.x / size.width, y: e.location.y / size.height)
                if let near = room.points.first(where: { hypot(($0.x - pt.x) * size.width, ($0.y - pt.y) * size.height) < 22 }) {
                    selected = near
                    return
                }
                measure(at: pt)
            })
        }
        .aspectRatio(ratio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 1))
    }

    private func measure(at pt: CGPoint) {
        measuringAt = pt
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            let sample = await QuickProbe.measure(downloadSeconds: 3)
            if var r = room {
                let point = MeasurePoint(x: pt.x, y: pt.y, sample: sample)
                r.points.append(point)
                rooms.update(r)
                selected = point
            }
            measuringAt = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    @ViewBuilder
    private func summary(_ room: RoomMap) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Auswertung", systemImage: "sparkles").font(.headline)
            if room.points.count < 3 {
                Text("Miss an mindestens 3–5 Stellen (Sofa, Schreibtisch, Bett, Ecke am Fenster …). Je mehr Punkte, desto genauer die Karte.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let best = room.best, let worst = room.worst, room.points.count >= 2 {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "star.fill").foregroundStyle(Neon.yellow)
                    Text("**Bester Platz** (Stern): \(describe(best.sample))").font(.subheadline)
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(Neon.red)
                    Text("**Schlechtester Platz:** \(describe(worst.sample))").font(.subheadline)
                }
                Text(advice(room)).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }

    private func describe(_ s: QuickSample) -> String {
        var parts: [String] = []
        if let sig = s.signal { parts.append("\(sig) % Signal") }
        if let d = s.downMbps { parts.append("\(Fmt.mbps(d)) Mbit/s") }
        if let p = s.pingMs { parts.append("\(Fmt.ms(p)) ms Ping") }
        if let b = s.band { parts.append(b) }
        return parts.joined(separator: " · ")
    }

    private func advice(_ room: RoomMap) -> String {
        guard let best = room.best, let worst = room.worst else { return "" }
        let spread = best.sample.score - worst.sample.score
        if best.sample.score < 40 {
            return "Im ganzen Raum ist das WLAN schwach. Ein Mesh-Repeater zwischen Router und Raum würde viel bringen."
        }
        if spread > 35 {
            return "Großer Unterschied im Raum! Stell Konsole oder Schreibtisch möglichst in die Nähe des Sterns."
        }
        if worst.sample.score >= 70 {
            return "Überall im Raum top – hier musst du nichts verändern."
        }
        return "Der Raum ist recht gleichmäßig versorgt. Für Gaming lieber am Stern spielen."
    }

    private func pointCard(_ p: MeasurePoint, room: RoomMap) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Messpunkt").font(.headline)
                Spacer()
                LevelPill(level: p.sample.level)
            }
            HStack(spacing: 10) {
                StatTile(title: "Signal", value: p.sample.signal.map { "\($0)" } ?? "–", unit: "%", icon: "wifi")
                StatTile(title: "Tempo", value: p.sample.downMbps.map(Fmt.mbps) ?? "–", unit: "Mbit/s", icon: "arrow.down")
                StatTile(title: "Ping", value: p.sample.pingMs.map(Fmt.ms) ?? "–", unit: "ms", icon: "bolt.horizontal.fill")
            }
            HStack {
                Text("Gesamt: \(Int(p.sample.score)) von 100 Punkten").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Punkt löschen", role: .destructive) {
                    var r = room
                    r.points.removeAll { $0.id == p.id }
                    rooms.update(r)
                    selected = nil
                }
                .font(.caption.weight(.semibold))
            }
        }
        .glass()
    }
}

/// Farbige Wolken je Messpunkt (grün = gut, rot = schlecht)
struct HeatLayer: View {
    let points: [MeasurePoint]
    let size: CGSize

    var body: some View {
        Canvas { ctx, sz in
            let radius = max(sz.width, sz.height) * 0.28
            for p in points {
                let c = CGPoint(x: p.x * sz.width, y: p.y * sz.height)
                let color = heatColor(p.sample.score)
                let rect = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
                ctx.fill(Path(ellipseIn: rect),
                         with: .radialGradient(Gradient(colors: [color.opacity(0.75), color.opacity(0.25), .clear]),
                                               center: c, startRadius: 0, endRadius: radius))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func heatColor(_ score: Double) -> Color {
        switch score {
        case 75...: return Neon.green
        case 55..<75: return Neon.lime
        case 35..<55: return Neon.yellow
        default: return Neon.red
        }
    }
}
