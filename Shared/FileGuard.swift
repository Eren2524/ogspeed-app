import Foundation

/// Schreibt Dateien verschlüsselt (iOS-Dateischutz).
/// `.completeFileProtection`: nur lesbar, solange das iPhone entsperrt ist.
/// `.completeUntilFirstUserAuthentication`: für Dateien, die das Widget auch im
/// gesperrten Zustand noch braucht – vor der ersten Entsperrung nach dem Start
/// ist die Datei auch dann nicht lesbar.
enum FileGuard {
    @discardableResult
    static func write(_ data: Data, to url: URL, widgetReadable: Bool = false) -> Bool {
        let options: Data.WritingOptions = widgetReadable
            ? [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            : [.atomic, .completeFileProtection]
        do {
            try data.write(to: url, options: options)
            return true
        } catch {
            // Ältere Datei ohne Schutz kann das Überschreiben blockieren: einmal nachhelfen.
            try? FileManager.default.removeItem(at: url)
            return (try? data.write(to: url, options: options)) != nil
        }
    }

    /// Ordner so markieren, dass neue Dateien darin geschützt sind
    static func protect(directory url: URL) {
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete],
                                               ofItemAtPath: url.path)
    }
}

