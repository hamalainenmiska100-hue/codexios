#if canImport(FoundationModels)
import Foundation
import FoundationModels

@available(iOS 26.0, *)
enum OnDeviceCodexRunner {
    static var isReady: Bool { true }

    static var availabilityDescription: String {
        "Foundation Models is available in this build. This app keeps on-device generation optional because file-edit automation is handled by the local Codex-style engine."
    }

    static func prewarmIfPossible() {}

    static func run(
        prompt: String,
        workspace: WorkspaceService,
        runtime: ContainerRuntime,
        selectedFilePath: String?,
        exportURL: URL?,
        exportFolderName: String?,
        settings: AgentSettings,
        eventSink: @escaping AgentEventSink,
        approvalSink: @escaping ApprovalSink
    ) async throws -> String {
        let snapshot = try await workspace.snapshot(
            selectedFilePath: selectedFilePath,
            exportFolderName: exportFolderName
        )
        let container = await runtime.snapshot()

        await eventSink(.timeline(
            TimelineEvent(
                kind: .thinking,
                title: "On-device model",
                detail: "Generating a local answer with Foundation Models."
            )
        ))

        let context = """
        You are a local coding assistant running inside an iOS app.
        You can see a summary of a writable workspace and a simulated container.
        Give practical coding guidance grounded in the visible workspace only.
        Do not claim to run shell commands or install packages.
        If the user asks to change files, describe the changes clearly. The app may still use the local heuristic engine for file automation.

        Workspace summary:
        \(snapshot.summaryText)

        Simulated container state:
        cwd: \(container.cwd)
        changed files: \(container.changedFiles.joined(separator: ", "))
        command history: \(container.commandHistory.suffix(12).joined(separator: " | "))
        """

        let session = LanguageModelSession(instructions: context)
        let response = try await session.respond(to: prompt)
        let text = response.content.trimmed
        await eventSink(.assistantDraft(text))
        return text
    }
}
#else
import Foundation

enum OnDeviceCodexRunner {
    static var isReady: Bool { false }
    static var availabilityDescription: String {
        "Foundation Models is unavailable in this build."
    }
    static func prewarmIfPossible() {}
    static func run(
        prompt: String,
        workspace: WorkspaceService,
        runtime: ContainerRuntime,
        selectedFilePath: String?,
        exportURL: URL?,
        exportFolderName: String?,
        settings: AgentSettings,
        eventSink: @escaping AgentEventSink,
        approvalSink: @escaping ApprovalSink
    ) async throws -> String {
        throw NSError(
            domain: "CodexLocal.FoundationModels",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Foundation Models is unavailable."]
        )
    }
}
#endif
