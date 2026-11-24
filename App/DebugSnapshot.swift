#if DEBUG
import AppKit

/// Geliştirme: CDU_SHOT="saniye:dosya,saniye:dosya" verilirse pencere içeriğini PNG olarak kaydedip çıkar.
enum DebugSnapshot {
    static func scheduleIfRequested() {
        guard let spec = ProcessInfo.processInfo.environment["CDU_SHOT"] else { return }
        let shots = spec.split(separator: ",").compactMap { part -> (Double, String)? in
            guard let i = part.firstIndex(of: ":"), let t = Double(part[..<i]) else { return nil }
            return (t, String(part[part.index(after: i)...]))
        }
        for (delay, path) in shots {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let view = NSApp.windows.first(where: { $0.isVisible })?.contentView?.superview,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                func tables(_ v: NSView) -> [NSTableView] { (v as? NSTableView).map { [$0] } ?? v.subviews.flatMap(tables) }
                for t in tables(view) { print("tablo satır sayısı:", t.numberOfRows) }
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                if delay == shots.map(\.0).max() { NSApp.terminate(nil) }
            }
        }
    }
}
#endif
