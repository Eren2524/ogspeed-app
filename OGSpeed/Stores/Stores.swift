import Foundation
import Observation
import UIKit
import WidgetKit

@MainActor @Observable
final class HistoryStore {
    var results: [SpeedResult] = []

    init() { results = SharedStore.loadHistory() }

    func add(_ r: SpeedResult) {
        results.insert(r, at: 0)
        if results.count > 2000 { results.removeLast(results.count - 2000) }
        persist()
    }

    func delete(_ ids: Set<UUID>) {
        results.removeAll { ids.contains($0.id) }
        persist()
    }

    func clear() { results = []; persist() }

    private func persist() {
        SharedStore.saveHistory(results)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Räume für die WLAN-Wärmekarte

struct MeasurePoint: Codable, Identifiable, Hashable {
    var id = UUID()
    var x: Double   // 0…1 relativ zum Foto
    var y: Double
    var date = Date()
    var sample: QuickSample
}

struct RoomMap: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var created = Date()
    var imageFile: String
    var points: [MeasurePoint] = []

    var best: MeasurePoint? { points.max { $0.sample.score < $1.sample.score } }
    var worst: MeasurePoint? { points.min { $0.sample.score < $1.sample.score } }
}

@MainActor @Observable
final class RoomStore {
    var rooms: [RoomMap] = []

    private var folder: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Rooms", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.complete])
        }
        FileGuard.protect(directory: url)
        return url
    }
    private var indexURL: URL { folder.appendingPathComponent("rooms.json") }

    init() {
        if let d = try? Data(contentsOf: indexURL), let list = try? JSONDecoder.iso.decode([RoomMap].self, from: d) {
            rooms = list
        }
    }

    func image(for room: RoomMap) -> UIImage? {
        UIImage(contentsOfFile: folder.appendingPathComponent(room.imageFile).path)
    }

    @discardableResult
    func create(name: String, image: UIImage) -> RoomMap? {
        let file = "\(UUID().uuidString).jpg"
        let scaled = image.scaledDown(maxSide: 2000)
        guard let data = scaled.jpegData(compressionQuality: 0.85) else { return nil }
        guard FileGuard.write(data, to: folder.appendingPathComponent(file)) else { return nil }
        let room = RoomMap(name: name, imageFile: file)
        rooms.insert(room, at: 0)
        save()
        return room
    }

    func update(_ room: RoomMap) {
        if let i = rooms.firstIndex(where: { $0.id == room.id }) { rooms[i] = room; save() }
    }

    func delete(_ room: RoomMap) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(room.imageFile))
        rooms.removeAll { $0.id == room.id }
        save()
    }

    private func save() {
        if let d = try? JSONEncoder.iso.encode(rooms) { FileGuard.write(d, to: indexURL) }
    }
}

extension UIImage {
    func scaledDown(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self.normalized() }
        let f = maxSide / longest
        let target = CGSize(width: size.width * f, height: size.height * f)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }

    /// Dreht das Foto richtig herum (Kamera-Fotos haben oft eine Orientierungs-Markierung)
    func normalized() -> UIImage {
        guard imageOrientation != .up else { return self }
        return UIGraphicsImageRenderer(size: size).image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
