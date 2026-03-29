import Foundation

typealias AgentEventSink = @Sendable (AgentStreamEvent) async -> Void
typealias ApprovalSink = @Sendable (PendingWriteApproval) async -> Void

@MainActor
final class LocalCodexEngine {
    private let workspace: WorkspaceService
    private let runtime: ContainerRuntime

    init(workspace: WorkspaceService, runtime: ContainerRuntime) {
        self.workspace = workspace
        self.runtime = runtime
    }

    static func foundationAvailabilityDescription() -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return OnDeviceCodexRunner.availabilityDescription
        }
        return "Foundation Models requires iOS 26."
        #else
        return "Foundation Models is unavailable in this build."
        #endif
    }

    func prewarmIfPossible(settings: AgentSettings) {
        #if canImport(FoundationModels)
        guard settings.useOnDeviceFoundationModel else { return }
        if #available(iOS 26.0, *) {
            OnDeviceCodexRunner.prewarmIfPossible()
        }
        #endif
    }

    func run(
        prompt: String,
        selectedFilePath: String?,
        exportURL: URL?,
        exportFolderName: String?,
        settings: AgentSettings,
        eventSink: @escaping AgentEventSink,
        approvalSink: @escaping ApprovalSink
    ) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), settings.useOnDeviceFoundationModel, OnDeviceCodexRunner.isReady {
            do {
                return try await OnDeviceCodexRunner.run(
                    prompt: prompt,
                    workspace: workspace,
                    runtime: runtime,
                    selectedFilePath: selectedFilePath,
                    exportURL: exportURL,
                    exportFolderName: exportFolderName,
                    settings: settings,
                    eventSink: eventSink,
                    approvalSink: approvalSink
                )
            } catch {
                await eventSink(.timeline(
                    TimelineEvent(
                        kind: .error,
                        title: "On-device model fallback",
                        detail: error.localizedDescription
                    )
                ))
            }
        }
        #endif

        return await heuristicRun(
            prompt: prompt,
            selectedFilePath: selectedFilePath,
            exportURL: exportURL,
            settings: settings,
            eventSink: eventSink,
            approvalSink: approvalSink
        )
    }

    private func heuristicRun(
        prompt: String,
        selectedFilePath: String?,
        exportURL: URL?,
        settings: AgentSettings,
        eventSink: @escaping AgentEventSink,
        approvalSink: @escaping ApprovalSink
    ) async -> String {
        await eventSink(.timeline(
            TimelineEvent(kind: .thinking, title: "Scanning workspace", detail: "Preparing a local fallback plan.")
        ))

        let lower = prompt.lowercased()
        let allFiles = (try? await workspace.filePaths()) ?? []

        if lower.contains("run ") || lower.contains("execute ") || lower.contains("command") || lower.contains("terminal") || lower.contains("!") {
            let command = extractCommand(from: prompt) ?? "git status --short"
            await eventSink(.timeline(
                TimelineEvent(kind: .terminal, title: "Simulated command", detail: command)
            ))
            let output = await runtime.simulate(command: command, workspace: workspace)
            return "Simulated command completed.\n\n```\n\(output)\n```"
        }

        if lower.contains("list") || lower.contains("tree") || lower.contains("folder") || lower.contains("files") {
            let listing = ((try? await workspace.listFiles(relativePath: ".")) ?? []).prefix(120)
            if listing.isEmpty {
                return "The selected folder does not contain visible files yet."
            }
            let joined = listing.joined(separator: "\n")
            return "Visible files in the selected folder:\n\n```\n\(joined)\n```"
        }

        if lower.contains("search") || lower.contains("find") || lower.contains("grep") {
            let query = extractSearchQuery(from: prompt) ?? (selectedFilePath ?? "TODO")
            let matches = (try? await workspace.search(query: query, maxResults: 24)) ?? []
            if matches.isEmpty {
                return "I could not find `\(query)` in the selected folder."
            }
            return "Found `\(query)` here:\n\n```\n\(matches.joined(separator: "\n"))\n```"
        }

        if lower.contains("open") || lower.contains("read") || lower.contains("show") || lower.contains("display") {
            let target = (try? await workspace.bestMatchingFile(for: prompt)) ?? selectedFilePath
            if let target, let content = try? await workspace.readFile(relativePath: target, maxBytes: 120_000) {
                await eventSink(.timeline(
                    TimelineEvent(kind: .tool, title: "Read file", detail: target)
                ))
                return "Here is `\(target)`:\n\n```\n\(content.truncated(maxLength: 4000))\n```"
            }
        }

        if lower.contains("export") || lower.contains("save to") || lower.contains("send file") {
            guard let selectedFilePath else {
                return "Select a file first, then I can export it to the chosen output folder."
            }
            guard let exportURL else {
                return "Choose an output folder first, then ask again."
            }
            do {
                let exported = try await workspace.exportFile(relativePath: selectedFilePath, to: exportURL)
                await eventSink(.timeline(
                    TimelineEvent(kind: .result, title: "Exported file", detail: exported)
                ))
                return "Exported `\(selectedFilePath)` to the selected output folder as `\(exported)`."
            } catch {
                return error.localizedDescription
            }
        }

        if lower.contains("create ") || lower.contains("new file") || lower.contains("write ") || lower.contains("make ") {
            let target = (try? await workspace.bestMatchingFile(for: prompt)) ?? extractFilenameCandidate(from: prompt) ?? "Notes/Generated.md"
            let content = scaffoldContent(for: target, prompt: prompt)
            return await applyWrite(
                path: target,
                content: content,
                prompt: prompt,
                settings: settings,
                eventSink: eventSink,
                approvalSink: approvalSink
            )
        }

        if let selectedFilePath, (lower.contains("edit") || lower.contains("update") || lower.contains("append") || lower.contains("modify")) {
            let current = (try? await workspace.readFile(relativePath: selectedFilePath, maxBytes: 120_000)) ?? ""
            let appended = current + "\n\n// Updated locally by CodexLocal\n// Prompt: \(prompt.trimmed)\n"
            return await applyWrite(
                path: selectedFilePath,
                content: appended,
                prompt: prompt,
                settings: settings,
                eventSink: eventSink,
                approvalSink: approvalSink
            )
        }

        let snapshot = (try? await workspace.snapshot(
            selectedFilePath: selectedFilePath,
            exportFolderName: nil
        )) ?? WorkspaceSnapshot(
            rootName: "Unknown",
            totalFiles: allFiles.count,
            topLevelPaths: Array(allFiles.prefix(12)),
            selectedFilePath: selectedFilePath,
            selectedFilePreview: nil,
            exportFolderName: nil
        )

        return """
        I am running in local fallback mode. Here is the current workspace summary.

        \(snapshot.summaryText)

        Ask me to list files, read a specific file, search text, export the selected file, write a new file, or run a simulated command.
        """
    }

    private func applyWrite(
        path: String,
        content: String,
        prompt: String,
        settings: AgentSettings,
        eventSink: @escaping AgentEventSink,
        approvalSink: @escaping ApprovalSink
    ) async -> String {
        let existing = (try? await workspace.readFile(relativePath: path, maxBytes: 200_000)) ?? ""

        if settings.requireWriteApproval {
            let approval = PendingWriteApproval(
                path: path,
                originalContent: existing,
                proposedContent: content,
                sourcePrompt: prompt
            )
            await approvalSink(approval)
            await eventSink(.timeline(
                TimelineEvent(kind: .approval, title: "Write queued for approval", detail: path)
            ))
            return "Queued a write for approval at `\(path)`. Approve it from the inspector panel to apply the change."
        }

        do {
            try await workspace.writeFile(relativePath: path, content: content)
            await runtime.registerChange(path: path)
            await eventSink(.timeline(
                TimelineEvent(kind: .result, title: "Wrote file", detail: path)
            ))
            return "Wrote `\(path)` locally."
        } catch {
            return error.localizedDescription
        }
    }

    private func extractCommand(from prompt: String) -> String? {
        if let backticked = extractBetweenBackticks(prompt) {
            return backticked
        }

        let lower = prompt.lowercased()
        if let range = lower.range(of: "run ") {
            return String(prompt[range.upperBound...]).trimmed
        }
        if let range = lower.range(of: "execute ") {
            return String(prompt[range.upperBound...]).trimmed
        }
        return nil
    }

    private func extractSearchQuery(from prompt: String) -> String? {
        if let quoted = extractBetweenQuotes(prompt) {
            return quoted
        }

        let lowered = prompt.lowercased()
        let separators = ["search for", "find", "grep", "search"]
        for separator in separators {
            if let range = lowered.range(of: separator) {
                return String(prompt[range.upperBound...]).trimmed
            }
        }
        return nil
    }

    private func extractFilenameCandidate(from prompt: String) -> String? {
        let pattern = #"([A-Za-z0-9_./-]+\.[A-Za-z0-9_]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsPrompt = prompt as NSString
        guard let match = regex.firstMatch(in: prompt, range: NSRange(location: 0, length: nsPrompt.length)) else {
            return nil
        }
        return nsPrompt.substring(with: match.range(at: 1))
    }

    private func extractBetweenQuotes(_ text: String) -> String? {
        let pattern = #""([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else {
            return nil
        }
        return nsText.substring(with: match.range(at: 1))
    }

    private func extractBetweenBackticks(_ text: String) -> String? {
        let pattern = #"`([^`]+)`"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else {
            return nil
        }
        return nsText.substring(with: match.range(at: 1))
    }

    private func scaffoldContent(for path: String, prompt: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        let escapedPrompt = prompt.replacingOccurrences(of: "\"", with: "\\\"").truncated(maxLength: 180)

        switch ext {
        case "swift":
            return """
            import SwiftUI

            struct GeneratedView: View {
                var body: some View {
                    VStack(spacing: 12) {
                        Text("Generated locally")
                            .font(.title2)
                        Text("\(prompt.truncated(maxLength: 120))")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
            """
        case "md":
            return """
            # Generated file

            Prompt:
            \(prompt.trimmed)

            This file was created inside CodexLocal.
            """
        case "json":
            return """
            {
              "generated": true,
              "prompt": "\(escapedPrompt)"
            }
            """
        case "yml", "yaml":
            return """
            generated: true
            prompt: "\(escapedPrompt)"
            """
        default:
            return """
            Generated locally by CodexLocal.

            Prompt:
            \(prompt.trimmed)
            """
        }
    }
}