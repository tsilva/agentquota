import Foundation

enum CodexLocatorError: LocalizedError, Equatable, Sendable {
    case notFound(searchedPaths: [String])

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Codex CLI was not found. Install Codex, ensure it is executable, then choose Retry."
        }
    }
}

struct CodexLocator {
    private let environment: [String: String]
    private let homeDirectory: URL
    private let fileManager: FileManager
    private let systemDirectories: [String]

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        systemDirectories: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.systemDirectories = systemDirectories
    }

    func locate() throws -> URL {
        let inheritedPaths = environment["PATH", default: ""]
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)

        let knownDirectories = [
            homeDirectory.appending(path: ".superset/bin").path,
            homeDirectory.appending(path: ".local/bin").path
        ] + systemDirectories

        var seen = Set<String>()
        let candidates = (inheritedPaths + knownDirectories).compactMap { directory -> URL? in
            let candidate = URL(filePath: directory, directoryHint: .isDirectory)
                .appending(path: "codex", directoryHint: .notDirectory)
                .standardizedFileURL
            return seen.insert(candidate.path).inserted ? candidate : nil
        }

        for candidate in candidates where isExecutableFile(candidate) {
            return candidate.resolvingSymlinksInPath()
        }

        throw CodexLocatorError.notFound(searchedPaths: candidates.map(\.path))
    }

    private func isExecutableFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }
        return fileManager.isExecutableFile(atPath: url.path)
    }
}
