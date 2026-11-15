import Foundation
import Observation

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
    private(set) var outputs: [OutputFile] = []
    var errorText: String?

    init() {
        outputs = Self.loadExisting()
    }

    func convert(urls: [URL]) {
        guard !busy, !urls.isEmpty else { return }
        busy = true
        progress = 0
        errorText = nil

        Task {
            for url in urls {
                currentName = url.lastPathComponent
                progress = 0

                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }

                do {
                    let out = try await Self.perform(input: url) { [weak self] value in
                        Task { @MainActor in self?.progress = value }
                    }
                    outputs.insert(OutputFile(url: out), at: 0)
                } catch {
                    errorText = "\(url.lastPathComponent)：\(error.localizedDescription)"
                }
            }
            currentName = ""
            busy = false
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
}
