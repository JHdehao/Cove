import Foundation
import Observation

/// The on-device speech models, downloaded once from their official hosts (about 310 MB):
/// - X-ASR zh-en streaming (SJTU and others, Apache-2.0): a true streaming Zipformer transducer
///   with punctuation, 160 ms chunks, for the live captions while someone is speaking.
/// - X-ASR zh-en offline: the same family read over each finished sentence for the final line.
///   Measured on a far-field AISHELL-4 meeting (2026-10-04, see PLAN §2.0) it beat SenseVoice
///   as the finisher, 13.5% vs 17.0% CER, and is smaller.
/// - Silero VAD: where sentences start and end.
@MainActor @Observable
final class SpeechModels {
    static let shared = SpeechModels()

    struct Download: Sendable {
        let url: URL
        let size: Int64
        /// A single file saved under this name, or a .tar.bz2 whose members (by base name) are saved under the mapped names.
        let save: Save

        enum Save: Sendable {
            case file(String)
            case archive([String: String])
        }

        var names: [String] {
            switch save {
            case .file(let name): [name]
            case .archive(let map): Array(map.values)
            }
        }
    }

    nonisolated static let downloads: [Download] = [
        Download(url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-x-asr-160ms-streaming-zipformer-transducer-zh-en-punct-int8-2026-06-05.tar.bz2")!,
                 size: 133_898_007,
                 save: .archive(["encoder.int8.onnx": "xasr-encoder.int8.onnx", "decoder.onnx": "xasr-decoder.onnx",
                                 "joiner.int8.onnx": "xasr-joiner.int8.onnx", "tokens.txt": "xasr-tokens.txt"])),
        Download(url: URL(string: "\(SpeechModels.offlineRepo)/encoder-epoch-99-avg-1.int8.onnx")!,
                 size: 161_744_450, save: .file("xasr-offline-encoder.int8.onnx")),
        Download(url: URL(string: "\(SpeechModels.offlineRepo)/decoder-epoch-99-avg-1.onnx")!,
                 size: 11_309_084, save: .file("xasr-offline-decoder.onnx")),
        Download(url: URL(string: "\(SpeechModels.offlineRepo)/joiner-epoch-99-avg-1.int8.onnx")!,
                 size: 2_581_422, save: .file("xasr-offline-joiner.int8.onnx")),
        Download(url: URL(string: "\(SpeechModels.offlineRepo)/tokens.txt")!,
                 size: 58_806, save: .file("xasr-offline-tokens.txt")),
        Download(url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx")!,
                 size: 643_854, save: .file("silero_vad.onnx")),
    ]

    private nonisolated static let offlineRepo =
        "https://huggingface.co/csukuangfj2/sherpa-onnx-x-asr-zipformer-transducer-zh-en-punct-int8-2026-06-03/resolve/main"

    nonisolated static let directory: URL = {
        var url = URL.applicationSupportDirectory.appending(path: "Models", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }()

    nonisolated static func path(_ name: String) -> String { directory.appending(path: name).path }

    nonisolated static var filesPresent: Bool {
        downloads.flatMap(\.names).allSatisfy { FileManager.default.fileExists(atPath: path($0)) }
    }

    /// The download size, for the button: "约 370 MB".
    nonisolated static var totalMB: Int { Int(downloads.reduce(0) { $0 + $1.size } / 1_000_000) }

    private(set) var isDownloading = false
    private(set) var progress: Double = 0
    private(set) var phase = ""
    var error: String?

    /// Re-read after downloads and removals (the file system isn't observed).
    private(set) var isInstalled = SpeechModels.filesPresent

    func download() async {
        guard !isDownloading else { return }
        isDownloading = true
        error = nil
        progress = 0
        defer { isDownloading = false; phase = "" }
        let total = Double(Self.downloads.reduce(0) { $0 + $1.size })
        var done: Int64 = 0
        do {
            for item in Self.downloads {
                if item.names.allSatisfy({ FileManager.default.fileExists(atPath: Self.path($0)) }) {
                    done += item.size
                    continue
                }
                phase = String(localized: "正在下载")
                let base = Double(done)
                let temporary = try await Self.fetch(item.url) { received in
                    Task { @MainActor in self.progress = min(1, (base + Double(received)) / total) }
                }
                defer { try? FileManager.default.removeItem(at: temporary) }
                switch item.save {
                case .file(let name):
                    let destination = Self.directory.appending(path: name)
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: temporary, to: destination)
                case .archive(let map):
                    phase = String(localized: "正在解压")
                    try await Task.detached(priority: .userInitiated) {
                        try ModelArchive.extract(temporary, files: map, to: Self.directory)
                    }.value
                }
                done += item.size
            }
            progress = 1
            isInstalled = Self.filesPresent
        } catch {
            self.error = String(localized: "模型下载失败：\(error.localizedDescription)")
        }
    }

    func remove() {
        for name in Self.downloads.flatMap(\.names) {
            try? FileManager.default.removeItem(atPath: Self.path(name))
        }
        isInstalled = false
    }

    /// Downloads to a temporary file, reporting bytes received.
    nonisolated static func fetch(_ url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
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
