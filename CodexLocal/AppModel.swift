import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject, @unchecked Sendable {
    @Published var authState = AuthState()
    @Published var messages: [ChatMessage] = []
    @Published var timeline: [TimelineEvent] = []
    @Published var workspaceTree: WorkspaceNode? = nil
    @Published var selectedFilePath: String?
    @Published var selectedDocument: EditableDocument?
    @Published var containerState = ContainerState()
    @Published var pendingApprovals: [PendingWriteApproval] = []
    @Published var isBusy = false
    @Published var composerText = ""
    @Published var workspaceDisplayName = "No folder selected"
    @Published var exportFolderName = "No export folder"
    @Published var statusMessage: String?
    @Published var foundationModelStatus = ""
    @Published var settings = AgentSettings() {
        didSet {
            persistSettings()
            foundationModelStatus = LocalCodexEngine.foundationAvailabilityDescription()
            engine.prewarmIfPossible(settings: settings)
        }
    }

    private let bookmarkStore = BookmarkStore()
    private let keychain = KeychainStore()
    private let workspaceService = WorkspaceService()
    private let runtime = ContainerRuntime()
    private let engine: LocalCodexEngine

    private var workspaceURL: URL?
    private var outputFolderURL: URL?
    private var autosaveTask: Task<Void, Never>?

    private static let settingsKey = "CodexLocal.settings"
    private static let localSessionKey = "CodexLocal.localSession"
    private static let workspaceBookmarkKey = "workspaceRoot"
    private static let exportBookmarkKey = "exportRoot"
    private static let apiKeyAccount = "openai.api.key"
    private static let codexAuthAccount = "codex.auth.json"
    private static let googleIDTokenAccount = "google.id.token"
    private static let codexAuthFilenameKey = "CodexLocal.codexAuth.filename"

    init() {
        self.engine = LocalCodexEngine(workspace: workspaceService, runtime: runtime)
        loadPersistedState()
        foundationModelStatus = LocalCodexEngine.foundationAvailabilityDescription()

        timeline = [
            TimelineEvent(
                kind: .info,
                title: "Local-first Codex shell",
                detail: "Pick a writable folder, then the agent can inspect and edit files inside it."
            )
        ]

        Task { [weak self] in
            guard let self else { return }
            await self.restorePersistedFolders()
        }
    }

    deinit {
        autosaveTask?.cancel()
    }

    func signInLocally() {
        authState = AuthState(
            isSignedIn: true,
            displayName: "Local User",
            mode: .localDevice,
            importedCredentialSummary: nil
        )
        UserDefaults.standard.set(true, forKey: Self.localSessionKey)
        showStatus("Local session enabled.")
    }

    func importCodexAuthJSON(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            _ = try JSONSerialization.jsonObject(with: data)
            let text = String(decoding: data, as: UTF8.self)
            try keychain.saveString(text, account: Self.codexAuthAccount)
            UserDefaults.standard.set(url.lastPathComponent, forKey: Self.codexAuthFilenameKey)
            authState = AuthState(
                isSignedIn: true,
                displayName: "Codex credentials",
                mode: .importedCodexAuth,
                importedCredentialSummary: url.lastPathComponent
            )
            UserDefaults.standard.set(false, forKey: Self.localSessionKey)
            showStatus("Imported \(url.lastPathComponent).")
        } catch {
            showStatus("Import failed: \(error.localizedDescription)")
        }
    }

    func saveGoogleIDToken(_ token: String) {
        let trimmed = token.trimmed
        guard !trimmed.isEmpty else {
            showStatus("Paste a non-empty Google ID token first.")
            return
        }

        do {
            try keychain.saveString(trimmed, account: Self.googleIDTokenAccount)
            authState = AuthState(
                isSignedIn: true,
                displayName: "Google session",
                mode: .google,
                importedCredentialSummary: "ID token stored in Keychain"
            )
            UserDefaults.standard.set(false, forKey: Self.localSessionKey)
            showStatus("Google sign-in token saved.")
        } catch {
            showStatus("Could not store Google token: \(error.localizedDescription)")
        }
    }

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmed
        guard !trimmed.isEmpty else {
            showStatus("Paste a non-empty API key first.")
            return
        }

        do {
            try keychain.saveString(trimmed, account: Self.apiKeyAccount)
            authState = AuthState(
                isSignedIn: true,
                displayName: "API key session",
                mode: .apiKey,
                importedCredentialSummary: "Stored in Keychain"
            )
            UserDefaults.standard.set(false, forKey: Self.localSessionKey)
            showStatus("API key stored in Keychain.")
        } catch {
            showStatus("Could not store API key: \(error.localizedDescription)")
        }
    }

    func signOut() {
        keychain.delete(account: Self.apiKeyAccount)
        keychain.delete(account: Self.codexAuthAccount)
        keychain.delete(account: Self.googleIDTokenAccount)
        UserDefaults.standard.removeObject(forKey: Self.codexAuthFilenameKey)
        UserDefaults.standard.set(false, forKey: Self.localSessionKey)
        authState = AuthState()
        isBusy = false
        pendingApprovals.removeAll()
        composerText = ""
        showStatus("Signed out.")
    }

    func attachWorkspaceFolder(_ url: URL) {
        Task { [weak self] in
            guard let self else { return }
            await self.attachWorkspaceFolderAsync(url, persist: true)
        }
    }

    func attachExportFolder(_ url: URL) {
        Task { [weak self] in
            guard let self else { return }
            await self.attachExportFolderAsync(url, persist: true)
        }
    }

    func refreshWorkspace() {
        Task { [weak self] in
            guard let self else { return }
            await self.refreshWorkspaceAsync(reloadSelectedFile: true)
        }
    }

    func selectFile(path: String) {
        selectedFilePath = path
        Task { [weak self] in
            guard let self else { return }
            await self.loadSelectedDocumentAsync(path: path)
        }
    }

    func updateSelectedDocument(_ text: String) {
        guard var doc = selectedDocument else { return }
        doc.currentContent = text
        selectedDocument = doc

        guard settings.autoSaveEditorChanges, !doc.isBinary else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(600))
            await self.saveSelectedDocumentAsync(triggeredByAutosave: true)
        }
    }

    func saveSelectedDocument() {
        Task { [weak self] in
            guard let self else { return }
            await self.saveSelectedDocumentAsync(triggeredByAutosave: false)
        }
    }

    func reloadSelectedDocument() {
        Task { [weak self] in
            guard let self else { return }
            await self.loadSelectedDocumentAsync(path: self.selectedFilePath)
            self.showStatus("Reloaded file from disk.")
        }
    }

    func discardSelectedChanges() {
        guard var doc = selectedDocument else { return }
        doc.currentContent = doc.originalContent
        selectedDocument = doc
        showStatus("Discarded editor changes.")
    }

    func exportSelectedDocument() {
        Task { [weak self] in
            guard let self else { return }
            guard let selectedFilePath else {
                self.showStatus("Select a file before exporting.")
                return
            }
            guard let outputFolderURL else {
                self.showStatus("Pick an export folder first.")
                return
            }

            do {
                let exported = try await self.workspaceService.exportFile(
                    relativePath: selectedFilePath,
                    to: outputFolderURL
                )
                self.showStatus("Exported \(exported).")
            } catch {
                self.showStatus("Export failed: \(error.localizedDescription)")
            }
        }
    }

    func approve(_ approval: PendingWriteApproval) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.workspaceService.writeFile(
                    relativePath: approval.path,
                    content: approval.proposedContent
                )
                await self.runtime.registerChange(path: approval.path)
                self.pendingApprovals.removeAll { $0.id == approval.id }
                self.timeline.insert(
                    TimelineEvent(
                        kind: .result,
                        title: "Write approved",
                        detail: approval.path
                    ),
                    at: 0
                )
                await self.refreshWorkspaceAsync(reloadSelectedFile: approval.path == self.selectedFilePath)
                if self.selectedFilePath == nil {
                    self.selectFile(path: approval.path)
                }
            } catch {
                self.showStatus("Approval write failed: \(error.localizedDescription)")
            }
        }
    }

    func reject(_ approval: PendingWriteApproval) {
        pendingApprovals.removeAll { $0.id == approval.id }
        timeline.insert(
            TimelineEvent(
                kind: .info,
                title: "Write rejected",
                detail: approval.path
            ),
            at: 0
        )
        showStatus("Rejected changes for \(approval.path).")
    }

    func submitPrompt() {
        let prompt = composerText.trimmed
        guard !prompt.isEmpty else { return }
        composerText = ""
        runPrompt(prompt)
    }

    func runQuickPrompt(_ prompt: String) {
        runPrompt(prompt)
    }

    private func runPrompt(_ prompt: String) {
        guard authState.isSignedIn else {
            showStatus("Sign in first.")
            return
        }
        guard workspaceURL != nil else {
            showStatus("Pick a workspace folder first.")
            return
        }
        guard !isBusy else { return }

        let assistantID = UUID()
        messages.append(ChatMessage(role: .user, text: prompt))
        messages.append(ChatMessage(id: assistantID, role: .assistant, text: "", status: .streaming))
        timeline.insert(
            TimelineEvent(
                kind: .thinking,
                title: "Queued prompt",
                detail: prompt.truncated(maxLength: 140)
            ),
            at: 0
        )
        isBusy = true

        Task { [weak self] in
            guard let self else { return }
            let finalText = await self.engine.run(
                prompt: prompt,
                selectedFilePath: self.selectedFilePath,
                exportURL: self.outputFolderURL,
                exportFolderName: self.exportFolderName == "No export folder" ? nil : self.exportFolderName,
                settings: self.settings,
                eventSink: { [weak self] event in
                    guard let self else { return }
                    await self.consume(event: event, assistantID: assistantID)
                },
                approvalSink: { [weak self] approval in
                    guard let self else { return }
                    await self.queueApproval(approval)
                }
            )

            await MainActor.run {
                self.finishAssistantMessage(id: assistantID, text: finalText)
                self.isBusy = false
            }

            await self.refreshWorkspaceAsync(reloadSelectedFile: true)
        }
    }

    private func finishAssistantMessage(id: UUID, text: String) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].text = text
        messages[idx].status = .complete
    }

    private func restorePersistedFolders() async {
        if let restoredWorkspace = try? bookmarkStore.restoreURL(for: Self.workspaceBookmarkKey) {
            await attachWorkspaceFolderAsync(restoredWorkspace, persist: false)
        }
        if let restoredExport = try? bookmarkStore.restoreURL(for: Self.exportBookmarkKey) {
            await attachExportFolderAsync(restoredExport, persist: false)
        }
    }

    private func attachWorkspaceFolderAsync(_ url: URL, persist: Bool) async {
        do {
            if persist {
                try bookmarkStore.save(url: url, for: Self.workspaceBookmarkKey)
            }
            workspaceURL = url
            await workspaceService.attachRoot(url)
            await runtime.bootstrap(cwd: url.lastPathComponent)
            workspaceDisplayName = url.lastPathComponent
            timeline.insert(
                TimelineEvent(kind: .info, title: "Workspace attached", detail: url.lastPathComponent),
                at: 0
            )
            showStatus("Workspace attached.")
            await refreshWorkspaceAsync(reloadSelectedFile: true)
        } catch {
            showStatus("Could not attach workspace: \(error.localizedDescription)")
        }
    }

    private func attachExportFolderAsync(_ url: URL, persist: Bool) async {
        do {
            if persist {
                try bookmarkStore.save(url: url, for: Self.exportBookmarkKey)
            }
            outputFolderURL = url
            exportFolderName = url.lastPathComponent
            showStatus("Export folder attached.")
        } catch {
            showStatus("Could not attach export folder: \(error.localizedDescription)")
        }
    }

    private func refreshWorkspaceAsync(reloadSelectedFile: Bool) async {
        do {
            workspaceTree = try await workspaceService.buildTree()
            containerState = await runtime.snapshot()

            if let selectedFilePath {
                let filePaths = try await workspaceService.filePaths()
                if !filePaths.contains(selectedFilePath) {
                    self.selectedFilePath = nil
                    selectedDocument = nil
                } else if reloadSelectedFile {
                    await loadSelectedDocumentAsync(path: selectedFilePath)
                }
            }
        } catch {
            showStatus("Workspace refresh failed: \(error.localizedDescription)")
        }
    }

    private func loadSelectedDocumentAsync(path: String?) async {
        guard let path else {
            selectedDocument = nil
            return
        }

        do {
            let text = try await workspaceService.readFile(relativePath: path)
            selectedDocument = EditableDocument(
                path: path,
                originalContent: text,
                currentContent: text,
                isBinary: false,
                lastLoadedAt: .init()
            )
        } catch WorkspaceError.binaryFile(_) {
            selectedDocument = EditableDocument(
                path: path,
                originalContent: "",
                currentContent: "Binary preview is unavailable for this file.",
                isBinary: true,
                lastLoadedAt: .init()
            )
        } catch {
            selectedDocument = nil
            showStatus("Could not open file: \(error.localizedDescription)")
        }
    }

    private func saveSelectedDocumentAsync(triggeredByAutosave: Bool) async {
        guard var doc = selectedDocument else { return }
        guard !doc.isBinary else { return }
        guard doc.isModified else { return }

        do {
            try await workspaceService.writeFile(relativePath: doc.path, content: doc.currentContent)
            await runtime.registerChange(path: doc.path)
            doc.originalContent = doc.currentContent
            doc.lastLoadedAt = .init()
            selectedDocument = doc
            containerState = await runtime.snapshot()
            if !triggeredByAutosave {
                showStatus("Saved \(doc.path).")
            }
        } catch {
            showStatus("Save failed: \(error.localizedDescription)")
        }
    }

    private func queueApproval(_ approval: PendingWriteApproval) async {
        pendingApprovals.insert(approval, at: 0)
        timeline.insert(
            TimelineEvent(
                kind: .approval,
                title: "Awaiting approval",
                detail: approval.path
            ),
            at: 0
        )
    }

    private func consume(event: AgentStreamEvent, assistantID: UUID) async {
        switch event {
        case .timeline(let item):
            timeline.insert(item, at: 0)
        case .assistantDraft(let text):
            guard let idx = messages.firstIndex(where: { $0.id == assistantID }) else { return }
            messages[idx].text = text
            messages[idx].status = .streaming
        case .assistantFinal(let text):
            finishAssistantMessage(id: assistantID, text: text)
        case .error(let text):
            guard let idx = messages.firstIndex(where: { $0.id == assistantID }) else { return }
            messages[idx].text = text
            messages[idx].status = .error
            timeline.insert(
                TimelineEvent(kind: .error, title: "Agent error", detail: text.truncated(maxLength: 200)),
                at: 0
            )
        }
    }

    private func loadPersistedState() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(AgentSettings.self, from: data) {
            settings = decoded
        }

        if let _ = keychain.loadString(account: Self.apiKeyAccount) {
            authState = AuthState(
                isSignedIn: true,
                displayName: "API key session",
                mode: .apiKey,
                importedCredentialSummary: "Stored in Keychain"
            )
        } else if let _ = keychain.loadString(account: Self.googleIDTokenAccount) {
            authState = AuthState(
                isSignedIn: true,
                displayName: "Google session",
                mode: .google,
                importedCredentialSummary: "ID token stored in Keychain"
            )
        } else if let imported = keychain.loadString(account: Self.codexAuthAccount) {
            let summary = UserDefaults.standard.string(forKey: Self.codexAuthFilenameKey)
                ?? imported.truncated(maxLength: 40)
            authState = AuthState(
                isSignedIn: true,
                displayName: "Codex credentials",
                mode: .importedCodexAuth,
                importedCredentialSummary: summary
            )
        } else if UserDefaults.standard.bool(forKey: Self.localSessionKey) {
            authState = AuthState(
                isSignedIn: true,
                displayName: "Local User",
                mode: .localDevice,
                importedCredentialSummary: nil
            )
        }
    }

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    private func showStatus(_ message: String) {
        statusMessage = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self else { return }
            if self.statusMessage == message {
                self.statusMessage = nil
            }
        }
    }
}
