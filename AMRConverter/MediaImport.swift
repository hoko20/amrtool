import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// PhotosPicker 取出的视频：复制到临时目录后交给转换流程。
struct MovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("incoming", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let target = directory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: received.file, to: target)
            return Self(url: target)
        }
    }
}
