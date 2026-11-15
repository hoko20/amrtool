import Foundation
import Observation
import AVFoundation

/// 输出格式（三种语音编码 + 通用音频）
enum OutputFormat: String, CaseIterable, Identifiable {
    case silk
    case nb
    case wb
    case m4a

    var id: String { rawValue }

    var title: String {
        switch self {
        case .silk: return "SILK · .aud"
        case .nb:   return "AMR-NB 12.2k"
        case .wb:   return "AMR-WB 23.85k"
        case .m4a:  return "M4A · AAC 96k"
        }
    }

    var detail: String {
        switch self {
        case .silk: return "微信 / QQ 语音条"
        case .nb:   return "兼容最好，电话音质"
        case .wb:   return "16kHz，明显更清晰"
        case .m4a:  return "接近原音，通用播放"
        }
    }

    var fileExtension: String {
        switch self {
        case .silk:       return "aud"
        case .nb, .wb:    return "amr"
        case .m4a:        return "m4a"
        }
    }
}

struct OutputFile: Identifiable, Hashable {
    let url: URL

    var id: URL { url }
    var name: String { url.lastPathComponent }

    var sizeText: String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var dateText: String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let date = (attrs?[.creationDate] as? Date) ?? Date()
        return Self.formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

@MainActor
@Observable
final class ConversionModel {

    private(set) var busy = false
    private(set) var progress: Double = 0
    private(set) var currentName = ""
    private(set) var statusText = "等待选择文件"
    private(set) var outputs: [OutputFile] = []
    var errorText: String?
    var format: OutputFormat = .silk

    init() {
        outputs = Self.loadExisting()
    }

    // MARK: - 转换入口

    func convert(urls: [URL]) {
        guard !busy, !urls.isEmpty else { return }
        busy = true
        progress = 0
        errorText = nil

        let target = format

        Task {
            for (index, url) in urls.enumerated() {
                currentName = url.lastPathComponent
                progress = 0
                statusText = "导入 \(index + 1)/\(urls.count)：\(url.lastPathComponent)"

                var temporary: URL?
                do {
                    let local = try Self.importCopy(of: url)
                    temporary = local
                    statusText = "转换 \(index + 1)/\(urls.count)：\(url.lastPathComponent)"

                    let out = try await Self.makeOutput(input: local, format: target) { [weak self] value in
                        Task { @MainActor in self?.progress = value }
                    }
                    outputs.insert(OutputFile(url: out), at: 0)
                    statusText = "已生成 \(out.lastPathComponent)"
                } catch {
                    errorText = "\(url.lastPathComponent)：\(Self.describe(error))"
                    statusText = "转换失败"
                }

                if let temporary {
                    try? FileManager.default.removeItem(at: temporary)
                }
            }
            currentName = ""
            busy = false
        }
    }

    // MARK: - 文件操作

    func delete(_ item: OutputFile) {
        try? FileManager.default.removeItem(at: item.url)
        outputs.removeAll { $0.url == item.url }
    }

    func deleteAll() {
        for item in outputs {
            try? FileManager.default.removeItem(at: item.url)
        }
        outputs.removeAll()
    }

    func rename(_ item: OutputFile, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let directory = item.url.deletingLastPathComponent()
        let base = (trimmed as NSString).deletingPathExtension
        let ext = item.url.pathExtension
        var target = directory.appendingPathComponent(base).appendingPathExtension(ext)

        var index = 1
        while FileManager.default.fileExists(atPath: target.path) && target != item.url {
            target = directory.appendingPathComponent("\(base)-\(index)").appendingPathExtension(ext)
            index += 1
        }
        guard target != item.url else { return }

        do {
            try FileManager.default.moveItem(at: item.url, to: target)
            outputs = outputs.map { $0.url == item.url ? OutputFile(url: target) : $0 }
        } catch {
            errorText = "重命名失败：\(Self.describe(error))"
        }
    }

    // MARK: - 输出生成

    private nonisolated static func makeOutput(input: URL,
                                              format: OutputFormat,
                                              progress: @escaping (Double) -> Void) async throws -> URL {
        let output = outputURL(for: input, extension: format.fileExtension)
        if format == .m4a {
            try await exportM4A(input: input, output: output, progress: progress)
            return output
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    _ = try AMREncoder.convertMedia(at: input,
                                                    to: output,
                                                    format: Self.legacyFormat(format),
                                                    progress: progress)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        return output
    }

    private nonisolated static func legacyFormat(_ format: OutputFormat) -> AMROutputFormat {
        switch format {
        case .nb:   return .NB
        case .wb:   return .WB
        default:    return .silk
        }
    }

    private nonisolated static func exportM4A(input: URL,
                                              output: URL,
                                              progress: @escaping (Double) -> Void) async throws {
        let asset = AVURLAsset(url: input)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: AMREncoderErrorDomain, code: 20,
                          userInfo: [NSLocalizedDescriptionKey: "这个文件无法导出为 M4A"])
        }
        try? FileManager.default.removeItem(at: output)
        session.outputURL = output
        session.outputFileType = .m4a

        let poller = Task {
            while !Task.isCancelled {
                progress(min(0.98, Double(session.progress)))
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { poller.cancel() }

        try await session.export()
        progress(1.0)
    }

    // MARK: - 路径与读写

    /// 把外部文件复制到沙盒 tmp，返回本地副本 URL。
    private nonisolated static func importCopy(of url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("incoming", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let suffix = url.pathExtension.isEmpty ? "dat" : url.pathExtension
        let target = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(suffix)

        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: url, to: target)
        return target
    }

    private nonisolated static func outputURL(for input: URL, extension ext: String) -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let base = input.deletingPathExtension().lastPathComponent
        var url = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var index = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base)-\(index)").appendingPathExtension(ext)
            index += 1
        }
        return url
    }

    private nonisolated static func loadExisting() -> [OutputFile] {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                 includingPropertiesForKeys: nil))
            ?? []
        let suffixes: Set<String> = ["amr", "aud", "m4a"]
        return files
            .filter { suffixes.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map(OutputFile.init(url:))
    }

    private nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.localizedDescription)（\(ns.domain) \(ns.code)）"
    }
}
