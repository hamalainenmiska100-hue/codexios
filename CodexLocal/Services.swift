import Foundation
import Security

enum WorkspaceError: LocalizedError {
    case noWorkspaceSelected
    case pathEscapesWorkspace(String)
    case fileTooLarge(String)
    case binaryFile(String)
    case fileNotFound(String)
    case bookmarkAccessFailed(String)

    var errorDescription: String? {
        switch self {
        case .noWorkspaceSelected:
            return "Select a workspace folder first."
        case .pathEscapesWorkspace(let path):
            return "Refused to access a path outside the selected folder: \(path)"
        case .fileTooLarge(let path):
            return "The file is too large to open safely inside the editor: \(path)"
        case .binaryFile(let path):
            return "The file appears to be binary and cannot be opened as text: \(path)"
        case .fileNotFound(let path):
            return "The file could not be found: \(path)"
        case .bookmarkAccessFailed(let name):
            return "The app could not restore access to \(name). Pick the folder again."
        }
    }
}

final class BookmarkStore {
    static let workspaceKey = "bookmark.workspace"
    static let exportKey = "bookmark.export"

    private static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
#if os(macOS)
        return .withSecurityScope
#else
        return []
#endif
    }

    private static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
#if os(macOS)
        return [.withSecurityScope, .withoutUI]
#else
        return []
#endif
    }

    func save(url: URL, for key: String) throws {
        let data = try url.bookmarkData(
            options: Self.bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: key)
    }

    func restoreURL(for key: String) throws -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: Self.bookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            try save(url: url, for: key)
        }

#if os(macOS)
        guard url.startAccessingSecurityScopedResource() else {
            throw WorkspaceError.bookmarkAccessFailed(url.lastPathComponent)
        }
#endif

        return url
    }
}

final class KeychainStore {
    private let service = "CodexLocal"

    func saveString(_ value: String, account: String) throws {
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func loadString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

actor WorkspaceService {
    private var rootURL: URL?

    func attachRoot(_ url: URL) {
        rootURL = url
    }

    func detachRoot() {
        rootURL = nil
    }

    func currentRootURL() -> URL? {
        rootURL
    }

    func currentRootName() -> String {
        rootURL?.lastPathComponent ?? "No folder selected"
    }

    func buildTree() throws -> WorkspaceNode? {
        guard let rootURL else { return nil }
        return try makeNode(at: rootURL, relativeTo: rootURL)
    }

    func listFiles(relativePath: String?) throws -> [String] {
        let base = try safeURL(for: relativePath ?? ".")
        let baseRoot = rootURL ?? base
        let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var output: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            let relative = url.path.replacingOccurrences(of: baseRoot.path + "/", with: "")
            output.append(relative)
            if output.count >= 300 {
                break
            }
        }
        return output.sorted()
    }

    func filePaths() throws -> [String] {
        try listFiles(relativePath: ".")
            .filter { !$0.hasSuffix("/") }
    }

    func readFile(relativePath: String, maxBytes: Int = 800_000) throws -> String {
        let url = try safeURL(for: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WorkspaceError.fileNotFound(relativePath)
        }

        let data = try Data(contentsOf: url)
        if data.count > maxBytes {
            throw WorkspaceError.fileTooLarge(relativePath)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw WorkspaceError.binaryFile(relativePath)
        }

        return text
    }

    func writeFile(relativePath: String, content: String) throws {
        let url = try safeURL(for: relativePath)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func search(query: String, maxResults: Int = 30) throws -> [String] {
        let trimmed = query.trimmed
        guard !trimmed.isEmpty else { return [] }

        let candidates = try filePaths()
        var results: [String] = []

        for path in candidates {
            guard results.count < maxResults else { break }
            guard let text = try? readFile(relativePath: path, maxBytes: 250_000) else { continue }

            let lines = text.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() where line.localizedCaseInsensitiveContains(trimmed) {
                let snippet = line.trimmed.truncated(maxLength: 160)
                results.append("\(path):\(index + 1): \(snippet)")
                if results.count >= maxResults {
                    break
                }
            }
        }

        return results
    }

    func exportFile(relativePath: String, to destinationRoot: URL) throws -> String {
        let source = try safeURL(for: relativePath)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw WorkspaceError.fileNotFound(relativePath)
        }

        let destination = destinationRoot.appendingPathComponent(source.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination.lastPathComponent
    }

    func snapshot(
        selectedFilePath: String?,
        exportFolderName: String?
    ) throws -> WorkspaceSnapshot {
        let files = try filePaths()
        let topLevel = try topLevelPaths()
        let preview: String?

        if let selectedFilePath,
           let selectedContent = try? readFile(relativePath: selectedFilePath, maxBytes: 20_000) {
            preview = selectedContent.truncated(maxLength: 1_500)
        } else {
            preview = nil
        }

        return WorkspaceSnapshot(
            rootName: currentRootName(),
            totalFiles: files.count,
            topLevelPaths: Array(topLevel.prefix(24)),
            selectedFilePath: selectedFilePath,
            selectedFilePreview: preview,
            exportFolderName: exportFolderName
        )
    }

    func bestMatchingFile(for prompt: String) throws -> String? {
        let promptLower = prompt.lowercased()
        let candidates = try filePaths()
        guard !candidates.isEmpty else { return nil }

        let regexPattern = #"([A-Za-z0-9_./-]+\.[A-Za-z0-9_]+)"#
        if let regex = try? NSRegularExpression(pattern: regexPattern) {
            let nsPrompt = prompt as NSString
            if let match = regex.firstMatch(in: prompt, range: NSRange(location: 0, length: nsPrompt.length)) {
                let raw = nsPrompt.substring(with: match.range(at: 1))
                if let exact = candidates.first(where: { $0.lowercased() == raw.lowercased() || ($0 as NSString).lastPathComponent.lowercased() == raw.lowercased() }) {
                    return exact
                }
            }
        }

        let scored = candidates
            .map { candidate -> (String, Int) in
                let last = (candidate as NSString).lastPathComponent.lowercased()
                var score = 0
                if promptLower.contains(candidate.lowercased()) { score += 6 }
                if promptLower.contains(last) { score += 4 }
                if selectedExtensions(in: promptLower).contains((candidate as NSString).pathExtension.lowercased()) { score += 1 }
                return (candidate, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 { return lhs.0.count < rhs.0.count }
                return lhs.1 > rhs.1
            }

        return scored.first(where: { $0.1 > 0 })?.0
    }

    private func topLevelPaths() throws -> [String] {
        guard let rootURL else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return urls
            .map { $0.lastPathComponent }
            .sorted()
    }

    private func makeNode(at url: URL, relativeTo root: URL) throws -> WorkspaceNode {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
        let relativePath: String

        if url.path == root.path {
            relativePath = "."
        } else {
            relativePath = url.path.replacingOccurrences(of: root.path + "/", with: "")
        }

        if values.isDirectory == true {
            let children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            .sorted(by: compareURLs)
            .map { try makeNode(at: $0, relativeTo: root) }

            return WorkspaceNode(
                path: relativePath,
                name: url.lastPathComponent,
                isDirectory: true,
                children: children,
                size: nil,
                modifiedAt: values.contentModificationDate
            )
        } else {
            return WorkspaceNode(
                path: relativePath,
                name: url.lastPathComponent,
                isDirectory: false,
                children: nil,
                size: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate
            )
        }
    }

    private func safeURL(for relativePath: String) throws -> URL {
        guard let rootURL else {
            throw WorkspaceError.noWorkspaceSelected
        }

        let root = rootURL.standardizedFileURL
        let normalized = relativePath.trimmed
        let resolved: URL

        if normalized.isEmpty || normalized == "." {
            resolved = root
        } else {
            resolved = root.appendingPathComponent(normalized).standardizedFileURL
        }

        guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
            throw WorkspaceError.pathEscapesWorkspace(relativePath)
        }

        return resolved
    }

    private func compareURLs(lhs: URL, rhs: URL) -> Bool {
        let fileManager = FileManager.default
        let lhsIsDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let rhsIsDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

        if lhsIsDir != rhsIsDir {
            return lhsIsDir && !rhsIsDir
        }
        return fileManager.displayName(atPath: lhs.path).localizedCaseInsensitiveCompare(
            fileManager.displayName(atPath: rhs.path)
        ) == .orderedAscending
    }

    private func selectedExtensions(in prompt: String) -> [String] {
        let common = ["swift", "md", "json", "yml", "yaml", "js", "ts", "tsx", "css", "html"]
        return common.filter { prompt.contains(".\($0)") || prompt.contains($0) }
    }
}

actor ContainerRuntime {
    private var state = ContainerState()
    private var nextProcessID: Int = 1

    func bootstrap(cwd: String) {
        state.cwd = cwd
        state.env = [
            "PWD": cwd,
            "SHELL": "/bin/zsh",
            "TERM": "xterm-256color",
            "CODEX_SIMULATED_CONTAINER": "1"
        ]
        if state.logs.isEmpty {
            state.logs.append("Container initialized for \(cwd)")
        }
    }

    func snapshot() -> ContainerState {
        state
    }

    func registerChange(path: String) {
        if !state.changedFiles.contains(path) {
            state.changedFiles.append(path)
        }
        state.logs.append("Modified \(path)")
    }

    func simulate(command: String, workspace: WorkspaceService) async -> String {
        let trimmed = command.trimmed
        guard !trimmed.isEmpty else { return "No command provided." }

        state.commandHistory.append(trimmed)
        state.logs.append("$ \(trimmed)")

        if trimmed == "pwd" {
            return state.cwd
        }

        if trimmed == "ps" || trimmed == "ps aux" {
            guard !state.processes.isEmpty else {
                return "No simulated background processes are running."
            }
            return state.processes
                .map { "\($0.id)\t\($0.status)\t\($0.command)" }
                .joined(separator: "\n")
        }

        if trimmed.hasPrefix("kill ") {
            let maybeID = trimmed
                .split(separator: " ")
                .dropFirst()
                .first
                .flatMap { Int($0) }

            if let processID = maybeID,
               let index = state.processes.firstIndex(where: { $0.id == processID }) {
                let removed = state.processes.remove(at: index)
                state.logs.append("Stopped process #\(removed.id)")
                return "Stopped simulated process #\(removed.id): \(removed.command)"
            }
            return "Could not find a simulated process to stop."
        }

        if trimmed.hasPrefix("ls") {
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            let path = parts.count > 1 ? String(parts[1]) : "."
            let listing = (try? await workspace.listFiles(relativePath: path)) ?? []
            if listing.isEmpty {
                return "No visible files."
            }
            return listing.prefix(120).joined(separator: "\n")
        }

        if trimmed.hasPrefix("cat ") {
            let path = String(trimmed.dropFirst(4))
            if let content = try? await workspace.readFile(relativePath: path, maxBytes: 120_000) {
                return content.truncated(maxLength: 4_000)
            }
            return "Could not read \(path)."
        }

        if trimmed.hasPrefix("git status") {
            if state.changedFiles.isEmpty {
                return "On branch main\nnothing to commit, working tree clean"
            }
            let changed = state.changedFiles
                .map { " M \($0)" }
                .joined(separator: "\n")
            return "On branch main\nChanges not staged for commit:\n\(changed)"
        }

        if trimmed.contains("npm install") || trimmed.contains("pnpm install") || trimmed.contains("yarn install") {
            let message = "Simulated install completed. Added 120 packages in 4.2s."
            state.logs.append(message)
            return message
        }

        if trimmed.contains("npm test") || trimmed.contains("pnpm test") || trimmed.contains("yarn test") || trimmed.contains("xcodebuild test") {
            let message = "Simulated test run completed. 12 passed, 0 failed."
            state.logs.append(message)
            return message
        }

        if trimmed.contains("npm run dev") || trimmed.contains("pnpm dev") || trimmed.contains("vite") || trimmed.contains("next dev") || trimmed.contains("python -m http.server") {
            let process = ContainerProcess(
                id: nextProcessID,
                command: trimmed,
                status: "running",
                startedAt: .init()
            )
            nextProcessID += 1
            state.processes.append(process)
            let message = "Started simulated background process #\(process.id)."
            state.logs.append(message)
            return message
        }

        if trimmed.contains("xcodebuild") {
            let message = "Simulated xcodebuild completed. BUILD SUCCEEDED."
            state.logs.append(message)
            return message
        }

        let message = "Simulated container executed `\(trimmed)` in \(state.cwd)."
        state.logs.append(message)
        return message
    }
}

enum DiffBuilder {
    static func makeLines(old: String, new: String) -> [DiffLine] {
        guard old != new else { return [] }

        let oldLines = old.components(separatedBy: .newlines)
        let newLines = new.components(separatedBy: .newlines)
        let maxCount = max(oldLines.count, newLines.count)

        var output: [DiffLine] = []
        for index in 0..<maxCount {
            let oldLine = index < oldLines.count ? oldLines[index] : nil
            let newLine = index < newLines.count ? newLines[index] : nil

            switch (oldLine, newLine) {
            case let (lhs?, rhs?) where lhs == rhs:
                if output.count < 180 {
                    output.append(DiffLine(kind: .context, text: lhs))
                }
            case let (lhs?, rhs?):
                output.append(DiffLine(kind: .removed, text: lhs))
                output.append(DiffLine(kind: .added, text: rhs))
            case let (lhs?, nil):
                output.append(DiffLine(kind: .removed, text: lhs))
            case let (nil, rhs?):
                output.append(DiffLine(kind: .added, text: rhs))
            default:
                break
            }

            if output.count >= 320 {
                break
            }
        }

        return output
    }
}
