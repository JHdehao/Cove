import Foundation
import Observation

/// The on-device speech models: SenseVoice (zh / en / ja / ko / yue, with punctuation)
/// and Silero VAD. Downloaded once from their official hosts, about 240 MB.
@MainActor @Observable
final class SpeechModels {
    static let shared = SpeechModels()

    struct File: Sendable {
        let name: String
        let url: URL
        let size: Int64
    }

    nonisolated static let files: [File] = [
        File(name: "sense-voice.int8.onnx",
             url: URL(string: "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09/resolve/main/model.int8.onnx")!,
             size: 237_115_547),
        File(name: "sense-voice-tokens.txt",
             url: URL(string: "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09/resolve/main/tokens.txt")!,
             size: 300_000),
        File(name: "silero_vad.onnx",
             url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx")!,
             size: 643_854),
    ]

    nonisolated static let directory: URL = {
        var url = URL.applicationSupportDirectory.appending(path: "Models", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }()

    nonisolated static var modelPath: String { directory.appending(path: files[0].name).path }
    nonisolated static var tokensPath: String { directory.appending(path: files[1].name).path }
    nonisolated static var vadPath: String { directory.appending(path: files[2].name).path }

    nonisolated static var filesPresent: Bool {
        files.allSatisfy { FileManager.default.fileExists(atPath: directory.appending(path: $0.name).path) }
    }

    private(set) var isDownloading = false
    private(set) var progress: Double = 0
    var error: String?

    /// Re-read after downloads and removals (the file system isn't observed).
    private(set) var isInstalled = SpeechModels.filesPresent

    func download() async {
        guard !isDownloading else { return }
        isDownloading = true
        error = nil
        progress = 0
        defer { isDownloading = false }
        let total = Double(Self.files.reduce(0) { $0 + $1.size })
        var done: Int64 = 0
        do {
            for file in Self.files {
                let destination = Self.directory.appending(path: file.name)
                if FileManager.default.fileExists(atPath: destination.path) {
                    done += file.size
                    continue
                }
                let base = Double(done)
                let temporary = try await Self.fetch(file.url) { received in
                    Task { @MainActor in self.progress = min(1, (base + Double(received)) / total) }
                }
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporary, to: destination)
                done += file.size
            }
            progress = 1
            isInstalled = Self.filesPresent
        } catch {
            self.error = "模型下载失败：\(error.localizedDescription)"
        }
    }

    func remove() {
        for file in Self.files {
            try? FileManager.default.removeItem(at: Self.directory.appending(path: file.name))
        }
        isInstalled = false
    }

    /// Downloads to a temporary file, reporting bytes received.
    private nonisolated static func fetch(_ url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        let delegate = DownloadDelegate(progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Int64) -> Void
    var continuation: CheckedContinuation<URL, Error>?

    init(progress: @escaping @Sendable (Int64) -> Void) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            continuation?.resume(throwing: URLError(.badServerResponse))
            continuation = nil
            return
        }
        // The file is deleted when this returns; keep it.
        let kept = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            continuation?.resume(returning: kept)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
