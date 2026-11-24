import Foundation

/// Model dosyalarını Hugging Face'ten ilk kullanımda indirir.
public enum ModelStore {
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CommonsDiversifiedUploader/models/Florence-2-base-ft", isDirectory: true)
    }

    /// - Parameter progress: 0…1 arası toplam ilerleme ve o an inen dosyanın adı.
    public static func ensure(at directory: URL = defaultDirectory, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        let files = FlorenceOCR.modelFiles
        for (i, file) in files.enumerated() {
            let target = directory.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: target.path) { continue }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            var request = URLRequest(url: URL(string: "https://huggingface.co/\(FlorenceOCR.repository)/resolve/main/\(file)")!)
            request.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")
            let delegate = Delegate { fraction in progress((Double(i) + fraction) / Double(files.count), file) }
            let (temp, response) = try await URLSession.shared.download(for: request, delegate: delegate)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw HTTP.Failure(message: "Model indirilemedi: \(file)") }
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: temp, to: target)
        }
        progress(1, "")
    }

    private final class Delegate: NSObject, URLSessionDownloadDelegate {
        let onProgress: @Sendable (Double) -> Void
        init(_ onProgress: @escaping @Sendable (Double) -> Void) { self.onProgress = onProgress }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            if totalBytesExpectedToWrite > 0 { onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
        }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }
}
