import Foundation

/// Unpacks chosen files from a .tar.bz2 (how sherpa-onnx publishes its models) without
/// holding the archive in memory: libbz2 decompresses a megabyte at a time into a
/// streaming tar reader. Handles ustar prefixes, GNU long names and pax path records.
enum ModelArchive {
    enum Failure: LocalizedError {
        case corrupt
        case missing([String])

        var errorDescription: String? {
            switch self {
            case .corrupt: "模型压缩包已损坏，请重新下载。"
            case .missing(let names): "模型压缩包里缺少文件：\(names.joined(separator: "、"))"
            }
        }
    }

    /// `files` maps a member's base name to the name it's saved under in `directory`.
    static func extract(_ archive: URL, files: [String: String], to directory: URL) throws {
        let input = try FileHandle(forReadingFrom: archive)
        defer { try? input.close() }
        let tar = TarReader(files: files, directory: directory)
        defer { tar.abandon() }

        var stream = bz_stream()
        guard BZ2_bzDecompressInit(&stream, 0, 0) == BZ_OK else { throw Failure.corrupt }
        defer { BZ2_bzDecompressEnd(&stream) }

        let outputSize = 1 << 20
        var output = [CChar](repeating: 0, count: outputSize)
        var ended = false
        while !ended {
            guard var chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty else { throw Failure.corrupt }
            try chunk.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
                stream.next_in = raw.baseAddress?.assumingMemoryBound(to: CChar.self)
                stream.avail_in = UInt32(raw.count)
                while !ended {
                    let produced = try output.withUnsafeMutableBufferPointer { buffer -> Int in
                        stream.next_out = buffer.baseAddress
                        stream.avail_out = UInt32(outputSize)
                        let status = BZ2_bzDecompress(&stream)
                        if status == BZ_STREAM_END { ended = true } else if status != BZ_OK { throw Failure.corrupt }
                        return outputSize - Int(stream.avail_out)
                    }
                    try output.withUnsafeBytes { try tar.consume(UnsafeRawBufferPointer(rebasing: $0[0..<produced])) }
                    // Out of input and nothing held back: read the next chunk.
                    if stream.avail_in == 0, produced < outputSize { break }
                }
            }
        }
        try tar.finish()
    }
}

/// Reads a tar stream piece by piece, writing the wanted members as they pass.
private final class TarReader {
    private let files: [String: String]
    private let directory: URL
    private var header = Data()
    private var remaining = 0
    private var padding = 0
    private var output: FileHandle?
    private var outputName: String?
    /// The body of a GNU long-name ("L") or pax ("x") entry, naming the next member.
    private var record: Data?
    private var recordType: UInt8 = 0
    private var nextName: String?
    private var written = Set<String>()

    init(files: [String: String], directory: URL) {
        self.files = files
        self.directory = directory
    }

    func consume(_ bytes: UnsafeRawBufferPointer) throws {
        var offset = 0
        while offset < bytes.count {
            let available = bytes.count - offset
            if remaining > 0 {
                let count = min(remaining, available)
                let piece = Data(bytes: bytes.baseAddress! + offset, count: count)
                if let output { try output.write(contentsOf: piece) } else if record != nil { record?.append(piece) }
                remaining -= count
                offset += count
                if remaining == 0 { try endMember() }
            } else if padding > 0 {
                let count = min(padding, available)
                padding -= count
                offset += count
            } else {
                let count = min(512 - header.count, available)
                header.append(Data(bytes: bytes.baseAddress! + offset, count: count))
                offset += count
                if header.count == 512 {
                    try readHeader([UInt8](header))
                    header.removeAll(keepingCapacity: true)
                }
            }
        }
    }

    func finish() throws {
        let missing = files.filter { !written.contains($0.value) }.map(\.key)
        if !missing.isEmpty { throw ModelArchive.Failure.missing(missing.sorted()) }
    }

    /// Removes a half-written member if extraction stopped partway.
    func abandon() {
        try? output?.close()
        if let outputName { try? FileManager.default.removeItem(at: directory.appending(path: outputName + ".part")) }
    }

    private func readHeader(_ block: [UInt8]) throws {
        if block.allSatisfy({ $0 == 0 }) { return }
        func text(_ range: Range<Int>) -> String {
            let bytes = block[range].prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        let sizeField = text(124..<136).trimmingCharacters(in: .whitespaces)
        guard let size = Int(sizeField, radix: 8) else { throw ModelArchive.Failure.corrupt }
        let type = block[156]
        let prefix = text(257..<263).hasPrefix("ustar") && block[263] == 0x30 ? text(345..<500) : ""
        let name = nextName ?? (prefix.isEmpty ? text(0..<100) : prefix + "/" + text(0..<100))
        nextName = nil
        remaining = size
        padding = (512 - size % 512) % 512

        switch type {
        case UInt8(ascii: "L"), UInt8(ascii: "x"):
            record = Data()
            recordType = type
        case UInt8(ascii: "0"), 0:
            let base = (name as NSString).lastPathComponent
            if let target = files[base] {
                let part = directory.appending(path: target + ".part")
                FileManager.default.createFile(atPath: part.path, contents: nil)
                output = try FileHandle(forWritingTo: part)
                outputName = target
            }
        default:
            break
        }
        if size == 0 { try endMember() }
    }

    private func endMember() throws {
        if let output, let outputName {
            try output.close()
            let destination = directory.appending(path: outputName)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: directory.appending(path: outputName + ".part"), to: destination)
            written.insert(outputName)
        }
        output = nil
        outputName = nil
        if let record {
            let body = String(decoding: record, as: UTF8.self)
            if recordType == UInt8(ascii: "L") {
                nextName = body.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            } else {
                // pax: "<len> key=value\n" records.
                for line in body.split(separator: "\n") {
                    if let range = line.range(of: " path=") { nextName = String(line[range.upperBound...]) }
                }
            }
        }
        record = nil
    }
}
