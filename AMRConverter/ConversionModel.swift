import Foundation
import Observation
import PhotosUI

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

    init() {
        outputs = Self.loadExisting()
    }

    // MARK: - 来自「文件」App

    func convert(urls: [URL]) {
        guard !busy, !urls.isEmpty else { return }
        busy = true
        progress = 0
        errorText = nil

        Task {
            for (index, url) in urls.enumerated() {
                currentName = url.lastPathComponent
                progress = 0
                statusText = "导入 \(index + 1)/\(urls.count)：\(url.lastPathComponent)"

                var temporary: URL?
                do {
                    // 先把文件复制进沙盒，避免安全作用域 URL 在后台线程读不到
                    let local = try Self.importCopy(of: url)
                    temporary = local
                    statusText = "转换 \(index + 1)/\(urls.count)：\(url.lastPathComponent)"

                    let out = try await Self.perform(input: local) { [weak self] value in
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

    // MARK: - 来自相册

    func convert(pickedItem item: PhotosPickerItem) {
        guard !busy else { return }
        busy = true
        progress = 0
        errorText = nil
        statusText = "正在从相册读取视频…"

        Task {
            do {
                guard let movie = try await item.loadTransferable(type: MovieFile.self) else {
                    errorText = "无法从相册读取这个视频"
                    statusText = "等待选择文件"
                    busy = false
                    return
                }
                busy = false
                convert(urls: [movie.url])
            } catch {
                errorText = "相册读取失败：\(Self.describe(error))"
                statusText = "等待选择文件"
                busy = false
            }
        }
    }

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

    // MARK: - 转换执行

    private nonisolated static func perform(input: URL,
                                            progress: @escaping (Double) -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let output = outputURL(for: input)
                    _ = try AMREncoder.convertMedia(at: input, to: output, progress: progress)
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

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

    private nonisolated static func outputURL(for input: URL) -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let base = input.deletingPathExtension().lastPathComponent
        var url = directory.appendingPathComponent(base).appendingPathExtension("amr")
        var index = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base)-\(index)").appendingPathExtension("amr")
            index += 1
        }
        return url
    }

    private nonisolated static func loadExisting() -> [OutputFile] {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                 includingPropertiesForKeys: nil))
            ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "amr" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map(OutputFile.init(url:))
    }

    private nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.localizedDescription)（\(ns.domain) \(ns.code)）"
    }
}
