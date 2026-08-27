import Foundation

enum CodexLocatorError: LocalizedError, Equatable, Sendable {
    case notFound(searchedPaths: [String])
    case configuredExecutableUnavailable(path: String)
    case configurationUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Codex CLI was not found. Install Codex or choose its executable in Settings."
        case let .configuredExecutableUnavailable(path):
            return "The configured Codex executable is unavailable at \(path). Choose another executable in Settings."
        case let .configurationUnavailable(message):
            return "AgentQuota could not read or save its Codex configuration: \(message)"
        }
    }
}

private struct CodexExecutableConfiguration: Codable {
    let version: Int
    let executablePath: String
}

private enum CodexExecutableConfigurationError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            return "Unsupported configuration version \(version)."
        }
    }
}

struct CodexExecutableConfigurationStore {
    let configurationDirectory: URL

    private let fileManager: FileManager

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        configurationDirectory = homeDirectory
            .appending(path: ".agentquota", directoryHint: .isDirectory)
        self.fileManager = fileManager
    }

    var configurationFile: URL {
        configurationDirectory.appending(path: "config.json", directoryHint: .notDirectory)
    }

    func load() throws -> URL? {
        guard fileManager.fileExists(atPath: configurationFile.path) else {
            return nil
        }

        let data = try Data(contentsOf: configurationFile)
        let configuration = try JSONDecoder().decode(
            CodexExecutableConfiguration.self,
            from: data
        )
        guard configuration.version == 1 else {
            throw CodexExecutableConfigurationError.unsupportedVersion(configuration.version)
        }
        return URL(filePath: configuration.executablePath, directoryHint: .notDirectory)
            .standardizedFileURL
    }

    func save(executableURL: URL) throws {
        try fileManager.createDirectory(
            at: configurationDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let configuration = CodexExecutableConfiguration(
            version: 1,
            executablePath: executableURL.standardizedFileURL.path
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(configuration)
        data.append(0x0A)
        try data.write(to: configurationFile, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: configurationFile.path
        )
    }
}

struct CodexLocator {
    private let environment: [String: String]
    private let homeDirectory: URL
    private let fileManager: FileManager
    private let systemDirectories: [String]
    private let configurationStore: CodexExecutableConfigurationStore

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        systemDirectories: [String] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/Applications/Codex.app/Contents/Resources",
        ],
        configurationStore: CodexExecutableConfigurationStore? = nil
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.systemDirectories = systemDirectories
        self.configurationStore = configurationStore
            ?? CodexExecutableConfigurationStore(
                homeDirectory: homeDirectory,
                fileManager: fileManager
            )
    }

    func locate() throws -> URL {
        if let configured = try configuredExecutable() {
            guard isExecutableFile(configured) else {
                throw CodexLocatorError.configuredExecutableUnavailable(path: configured.path)
            }
            return configured
        }

        let inheritedPaths = environment["PATH", default: ""]
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)
        let fallbackDirectories = [
            homeDirectory.appending(path: ".local/bin").path,
            homeDirectory.appending(path: ".superset/bin").path,
        ]

        var seen = Set<String>()
        let candidates = (systemDirectories + inheritedPaths + fallbackDirectories)
            .compactMap { directory -> URL? in
                let candidate = URL(filePath: directory, directoryHint: .isDirectory)
                    .appending(path: "codex", directoryHint: .notDirectory)
                    .standardizedFileURL
                return seen.insert(candidate.path).inserted ? candidate : nil
            }

        guard let executable = candidates.first(where: isExecutableFile) else {
            throw CodexLocatorError.notFound(searchedPaths: candidates.map(\.path))
        }

        try persist(executable)
        return executable
    }

    func configuredExecutable() throws -> URL? {
        do {
            return try configurationStore.load()
        } catch {
            throw CodexLocatorError.configurationUnavailable(error.localizedDescription)
        }
    }

    func selectExecutable(_ executableURL: URL) throws {
        let stableURL = executableURL.standardizedFileURL
        guard isExecutableFile(stableURL) else {
            throw CodexLocatorError.configuredExecutableUnavailable(path: stableURL.path)
        }
        try persist(stableURL)
    }

    private func persist(_ executableURL: URL) throws {
        do {
            try configurationStore.save(executableURL: executableURL)
        } catch {
            throw CodexLocatorError.configurationUnavailable(error.localizedDescription)
        }
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
