import CryptoKit
import Foundation

enum ArtifactHash {
    static func sha256(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(url: URL) throws -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw FidelityError.pathDoesNotExist(url.path)
        }
        if isDirectory.boolValue {
            let files = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ).filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            return try sha256(files: files, namesRelativeTo: url)
        }
        if url.pathExtension.lowercased() == "m3u8" {
            return try sha256(files: [url] + LocalHLS.componentURLs(from: url), namesRelativeTo: url.deletingLastPathComponent())
        }
        return sha256(data: try Data(contentsOf: url))
    }

    private static func sha256(files: [URL], namesRelativeTo root: URL) throws -> String {
        var hasher = SHA256()
        for url in files {
            let relative = String(url.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            hasher.update(data: Data(relative.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: try Data(contentsOf: url))
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
