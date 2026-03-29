import Foundation

enum AuthMode: String, Codable, CaseIterable {
    case localDevice = "On-device"
    case importedCodexAuth = "Imported auth.json"
    case apiKey = "API key"
}

struct AuthState: Codable {
    var isSignedIn: Bool = false
    var displayName: String = "Local User"
    var mode: AuthMode = .localDevice
    var importedCredentialSummary: String?
}

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

enum MessageStatus: String, Codable {
    case complete
    case streaming
    case error
}

struct ChatMessage: Identifiable, Hashable, Codable {
    let id: UUID
    var role: MessageRole
    var text: String
    var status: MessageStatus
    var createdAt: Date

    init(
        id: UUID = UUID(),
        role: MessageRole,
        text: String,
        status: MessageStatus = .complete,
        createdAt: Date = .init()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.status = status
        self.createdAt = createdAt
    }
}

enum TimelineKind: String, Codable, Hashable {
    case thinking
    case tool
    case result
    case terminal
    case approval
    case info
    case error
}

struct TimelineEvent: Identifiable, Hashable, Codable {
    let id: UUID
    var kind: TimelineKind
    var title: String
    var detail: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: TimelineKind,
        title: String,
        detail: String,
        createdAt: Date = .init()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.createdAt = createdAt
    }
}

extension TimelineEvent {
    var iconName: String {
        switch kind {
        case .thinking:
            return "brain.head.profile"
        case .tool:
            return "wrench.and.screwdriver"
        case .result:
            return "checkmark.circle"
        case .terminal:
            return "terminal"
        case .approval:
            return "hand.raised"
        case .info:
            return "info.circle"
        case .error:
            return "exclamationmark.triangle"
        }
    }
}

struct WorkspaceNode: Identifiable, Hashable, Codable {
    var id: String { path }
    var path: String
    var name: String
    var isDirectory: Bool
    var children: [WorkspaceNode]?
    var size: Int64?
    var modifiedAt: Date?

    static let placeholder = WorkspaceNode(
        path: ".",
        name: "No folder selected",
        isDirectory: true,
        children: [],
        size: nil,
        modifiedAt: nil
    )
}

struct EditableDocument: Hashable {
    var path: String
    var originalContent: String
    var currentContent: String
    var isBinary: Bool
    var lastLoadedAt: Date

    var isModified: Bool {
        originalContent != currentContent
    }
}

struct ContainerProcess: Identifiable, Hashable, Codable {
    let id: Int
    var command: String
    var status: String
    var startedAt: Date
}

struct ContainerState: Hashable, Codable {
    var cwd: String = "/"
    var env: [String: String] = [:]
    var processes: [ContainerProcess] = []
    var commandHistory: [String] = []
    var changedFiles: [String] = []
    var logs: [String] = []
}

struct PendingWriteApproval: Identifiable, Hashable {
    let id: UUID
    var path: String
    var originalContent: String
    var proposedContent: String
    var createdAt: Date
    var sourcePrompt: String

    init(
        id: UUID = UUID(),
        path: String,
        originalContent: String,
        proposedContent: String,
        createdAt: Date = .init(),
        sourcePrompt: String
    ) {
        self.id = id
        self.path = path
        self.originalContent = originalContent
        self.proposedContent = proposedContent
        self.createdAt = createdAt
        self.sourcePrompt = sourcePrompt
    }
}

struct AgentSettings: Codable, Hashable {
    var requireWriteApproval: Bool = false
    var autoSaveEditorChanges: Bool = false
    var useOnDeviceFoundationModel: Bool = false
}

struct WorkspaceSnapshot: Hashable {
    var rootName: String
    var totalFiles: Int
    var topLevelPaths: [String]
    var selectedFilePath: String?
    var selectedFilePreview: String?
    var exportFolderName: String?

    var summaryText: String {
        var lines: [String] = []
        lines.append("Workspace root: \(rootName)")
        lines.append("Visible files: \(totalFiles)")
        if !topLevelPaths.isEmpty {
            lines.append("Top-level paths: \(topLevelPaths.joined(separator: ", "))")
        }
        if let selectedFilePath {
            lines.append("Selected file: \(selectedFilePath)")
        }
        if let exportFolderName {
            lines.append("Output folder: \(exportFolderName)")
        }
        if let selectedFilePreview, !selectedFilePreview.isEmpty {
            lines.append("Selected file preview:")
            lines.append(selectedFilePreview)
        }
        return lines.joined(separator: "\n")
    }
}

struct DiffLine: Identifiable, Hashable {
    enum Kind: Hashable {
        case context
        case added
        case removed
    }

    let id = UUID()
    var kind: Kind
    var text: String
}

enum AgentStreamEvent {
    case timeline(TimelineEvent)
    case assistantDraft(String)
    case assistantFinal(String)
    case error(String)
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func truncated(maxLength: Int) -> String {
        guard count > maxLength else { return self }
        let end = index(startIndex, offsetBy: maxLength)
        return String(self[..<end]) + "…"
    }
}
