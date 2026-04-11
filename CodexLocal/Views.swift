import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.authState.isSignedIn {
                MainShellView()
            } else {
                SignInView()
            }
        }
    }
}

struct SignInView: View {
    @EnvironmentObject private var model: AppModel
    @State private var apiKey = ""
    @State private var googleIDToken = ""
    @State private var showingAuthImport = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black, .indigo.opacity(0.9), .blue.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("CodexLocal")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("A fully local iOS coding shell with a writable folder sandbox, local container simulation, approval gates, and a modern multi-pane editor.")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))

                        HStack(spacing: 10) {
                            FeaturePill(text: "Folder sandbox")
                            FeaturePill(text: "Container lane")
                            FeaturePill(text: "Local-first")
                            FeaturePill(text: "Unsigned IPA workflow")
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                    VStack(spacing: 16) {
                        SignInCard(
                            title: "Start fully local",
                            subtitle: "This keeps everything on device. No server is required.",
                            buttonTitle: "Use local session",
                            tint: .blue
                        ) {
                            model.signInLocally()
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Bring existing Codex credentials")
                                .font(.headline)
                            Text("Import a Codex auth.json file into Keychain. Handy if you want the app to mirror an existing local Codex setup.")
                                .foregroundStyle(.secondary)

                            Button {
                                showingAuthImport = true
                            } label: {
                                Label("Import auth.json", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Google sign in wrapper")
                                .font(.headline)
                            Text("Paste a Google ID token from your existing sign-in wrapper flow and store it locally in Keychain.")
                                .foregroundStyle(.secondary)

                            SecureField("Google ID token", text: $googleIDToken)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(14)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                            Button {
                                model.saveGoogleIDToken(googleIDToken)
                                googleIDToken = ""
                            } label: {
                                Label("Save Google token", systemImage: "globe")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Store an API key")
                                .font(.headline)
                            Text("Optional. Saves the key in Keychain on this device.")
                                .foregroundStyle(.secondary)

                            SecureField("sk-...", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(14)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                            Button {
                                model.saveAPIKey(apiKey)
                                apiKey = ""
                            } label: {
                                Label("Save API key", systemImage: "key.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    .padding(6)
                }
                .padding(24)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showingAuthImport) {
            SystemDocumentPicker(contentTypes: [.json, .data], allowsFolders: false) { url in
                model.importCodexAuthJSON(from: url)
            }
        }
    }
}

struct MainShellView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingWorkspacePicker = false
    @State private var showingExportPicker = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                showingWorkspacePicker: $showingWorkspacePicker,
                showingExportPicker: $showingExportPicker
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 320)
        } content: {
            ChatCenterView()
                .navigationTitle("Session")
                .navigationBarTitleDisplayMode(.inline)
        } detail: {
            InspectorView()
        }
        .overlay(alignment: .top) {
            if let status = model.statusMessage {
                StatusToast(text: status)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showingWorkspacePicker) {
            SystemDocumentPicker(contentTypes: [.folder], allowsFolders: true) { url in
                model.attachWorkspaceFolder(url)
            }
        }
        .sheet(isPresented: $showingExportPicker) {
            SystemDocumentPicker(contentTypes: [.folder], allowsFolders: true) { url in
                model.attachExportFolder(url)
            }
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showingWorkspacePicker: Bool
    @Binding var showingExportPicker: Bool

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.authState.displayName)
                        .font(.headline)
                    Text(model.authState.mode.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let summary = model.authState.importedCredentialSummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Workspace") {
                Button {
                    showingWorkspacePicker = true
                } label: {
                    Label("Choose workspace folder", systemImage: "folder.badge.plus")
                }

                Button {
                    showingExportPicker = true
                } label: {
                    Label("Choose export folder", systemImage: "square.and.arrow.up")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.workspaceDisplayName)
                        .font(.subheadline.weight(.semibold))
                    Text(model.exportFolderName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let root = model.workspaceTree {
                    OutlineGroup([root], children: \.children) { node in
                        FileTreeRow(
                            node: node,
                            isSelected: model.selectedFilePath == node.path
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !node.isDirectory {
                                model.selectFile(path: node.path)
                            }
                        }
                    }
                } else {
                    Text("No folder selected yet.")
                        .foregroundStyle(.secondary)
                }

                Button {
                    model.refreshWorkspace()
                } label: {
                    Label("Refresh workspace", systemImage: "arrow.clockwise")
                }
            }

            Section("Agent settings") {
                Toggle("Require write approval", isOn: $model.settings.requireWriteApproval)
                Toggle("Autosave editor changes", isOn: $model.settings.autoSaveEditorChanges)
                Toggle("On-device Foundation Models", isOn: $model.settings.useOnDeviceFoundationModel)

                Text(model.foundationModelStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pending approvals") {
                if model.pendingApprovals.isEmpty {
                    Text("No pending writes.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.pendingApprovals) { approval in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(approval.path)
                                .font(.subheadline.weight(.semibold))
                            Text(approval.sourcePrompt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }

            Section("Container") {
                HStack {
                    Label("cwd", systemImage: "terminal")
                    Spacer()
                    Text(model.containerState.cwd)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack {
                    Label("changed files", systemImage: "doc.badge.gearshape")
                    Spacer()
                    Text("\(model.containerState.changedFiles.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Label("commands", systemImage: "list.bullet.rectangle")
                    Spacer()
                    Text("\(model.containerState.commandHistory.count)")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(role: .destructive) {
                    model.signOut()
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("CodexLocal")
    }
}

struct ChatCenterView: View {
    @EnvironmentObject private var model: AppModel

    private let quickPrompts = [
        "Summarize this workspace.",
        "List files in the selected folder.",
        "Create a README for this project.",
        "Run npm test.",
        "Search for TODO."
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Workspace")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(model.workspaceDisplayName)
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                if model.isBusy {
                    Label("Codex is working", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.blue.opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 8)

            TimelineLaneView(events: model.timeline)
                .padding(.horizontal, 18)
                .padding(.bottom, 10)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if model.messages.isEmpty {
                        EmptyChatState()
                    }

                    ForEach(model.messages) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding(20)
            }

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(quickPrompts, id: \.self) { prompt in
                        Button(prompt) {
                            model.runQuickPrompt(prompt)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }

            HStack(alignment: .bottom, spacing: 14) {
                TextEditor(text: $model.composerText)
                    .frame(minHeight: 76, maxHeight: 140)
                    .padding(10)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if model.composerText.isEmpty {
                            Text("Ask Codex to inspect files, edit code, search the workspace, or simulate a command.")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }

                Button {
                    model.submitPrompt()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy || model.composerText.trimmed.isEmpty)
            }
            .padding(18)
            .background(.bar)
        }
    }
}

struct InspectorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedPane = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $selectedPane) {
                Text("File").tag(0)
                Text("Container").tag(1)
                Text("Approvals").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(16)

            Divider()

            Group {
                switch selectedPane {
                case 0:
                    fileInspector
                case 1:
                    containerInspector
                default:
                    approvalsInspector
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Inspector")
    }

    private var fileInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let doc = model.selectedDocument {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(doc.path)
                            .font(.headline)
                        HStack(spacing: 10) {
                            if doc.isModified {
                                Label("Modified", systemImage: "pencil")
                                    .foregroundStyle(.orange)
                            } else {
                                Label("Saved", systemImage: "checkmark.circle")
                                    .foregroundStyle(.green)
                            }

                            if doc.isBinary {
                                Label("Binary", systemImage: "doc.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption.weight(.semibold))
                    }

                    HStack(spacing: 10) {
                        Button("Save") {
                            model.saveSelectedDocument()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(doc.isBinary || !doc.isModified)

                        Button("Reload") {
                            model.reloadSelectedDocument()
                        }
                        .buttonStyle(.bordered)

                        Button("Discard") {
                            model.discardSelectedChanges()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!doc.isModified)

                        Button("Export") {
                            model.exportSelectedDocument()
                        }
                        .buttonStyle(.bordered)
                    }

                    TextEditor(
                        text: Binding(
                            get: { model.selectedDocument?.currentContent ?? "" },
                            set: { model.updateSelectedDocument($0) }
                        )
                    )
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 560)
                    .padding(12)
                    .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .disabled(doc.isBinary)
                } else {
                    PlaceholderCard(
                        title: "No file selected",
                        subtitle: "Pick a file from the workspace tree to inspect or edit it."
                    )
                }
            }
            .padding(18)
        }
    }

    private var containerInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PlaceholderCard(
                    title: "Container summary",
                    subtitle: "This app simulates a local Codex-style container. File writes are real inside the chosen folder. Shell commands are intentionally emulated."
                )

                VStack(alignment: .leading, spacing: 10) {
                    Label("Environment", systemImage: "gearshape.2")
                        .font(.headline)
                    ForEach(model.containerState.env.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key)
                            Spacer()
                            Text(model.containerState.env[key] ?? "")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Processes", systemImage: "cpu")
                        .font(.headline)
                    if model.containerState.processes.isEmpty {
                        Text("No processes")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.containerState.processes) { process in
                            HStack {
                                Text("#\(process.id)")
                                    .font(.system(.caption, design: .monospaced))
                                Text(process.command)
                                Spacer()
                                Text(process.status)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Changed files", systemImage: "doc.badge.gearshape")
                        .font(.headline)
                    if model.containerState.changedFiles.isEmpty {
                        Text("Nothing changed yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.containerState.changedFiles, id: \.self) { path in
                            Text(path)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Command history", systemImage: "terminal")
                        .font(.headline)
                    if model.containerState.commandHistory.isEmpty {
                        Text("No commands yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(model.containerState.commandHistory.enumerated()), id: \.offset) { item in
                            Text("$ \(item.element)")
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Logs", systemImage: "text.append")
                        .font(.headline)
                    if model.containerState.logs.isEmpty {
                        Text("No logs yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(model.containerState.logs.enumerated()), id: \.offset) { item in
                            Text(item.element)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private var approvalsInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.pendingApprovals.isEmpty {
                    PlaceholderCard(
                        title: "No approvals waiting",
                        subtitle: "Turn on write approval in the sidebar if you want every file change to pause here first."
                    )
                } else {
                    ForEach(model.pendingApprovals) { approval in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(approval.path)
                                .font(.headline)
                            Text(approval.sourcePrompt)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            DiffPreviewView(lines: DiffBuilder.makeLines(old: approval.originalContent, new: approval.proposedContent))
                            HStack {
                                Button("Approve") {
                                    model.approve(approval)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Reject") {
                                    model.reject(approval)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(16)
                        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
            .padding(18)
        }
    }
}

struct SignInCard: View {
    let title: String
    let subtitle: String
    let buttonTitle: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .foregroundStyle(.secondary)

            Button(action: action) {
                Label(buttonTitle, systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct FileTreeRow: View {
    let node: WorkspaceNode
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.text")
                .foregroundStyle(node.isDirectory ? .blue : .secondary)
            Text(node.name)
                .foregroundStyle(isSelected ? .blue : .primary)
            Spacer()
            if !node.isDirectory, let size = node.size {
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .assistant {
                bubble(alignment: .leading, tint: .secondary.opacity(0.14))
                Spacer(minLength: 24)
            } else {
                Spacer(minLength: 24)
                bubble(alignment: .leading, tint: .blue.opacity(0.14))
            }
        }
    }

    private func bubble(alignment: Alignment, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    message.role == .assistant ? "Codex" : "You",
                    systemImage: message.role == .assistant ? "sparkles" : "person.fill"
                )
                .font(.caption.weight(.semibold))

                Spacer()

                if message.status == .streaming {
                    ProgressView()
                        .controlSize(.small)
                } else if message.status == .error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Text(message.text.isEmpty ? "Thinking..." : message.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: alignment)
        }
        .padding(16)
        .background(tint, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct TimelineLaneView: View {
    let events: [TimelineEvent]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(events.prefix(16)) { event in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(event.title, systemImage: event.iconName)
                            .font(.caption.weight(.semibold))
                        Text(event.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(14)
                    .frame(width: 220, alignment: .leading)
                    .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
    }
}

struct DiffPreviewView: View {
    let lines: [DiffLine]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if lines.isEmpty {
                    Text("No textual diff.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { item in
                        let line = item.element
                        HStack(alignment: .top, spacing: 8) {
                            Text(prefix(for: line.kind))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(color(for: line.kind))
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(background(for: line.kind))
                    }
                }
            }
        }
        .frame(minHeight: 220, maxHeight: 320)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func prefix(for kind: DiffLine.Kind) -> String {
        switch kind {
        case .added: return "+"
        case .removed: return "-"
        case .context: return " "
        }
    }

    private func color(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: return .green
        case .removed: return .red
        case .context: return .secondary
        }
    }

    private func background(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: return .green.opacity(0.10)
        case .removed: return .red.opacity(0.10)
        case .context: return .clear
        }
    }
}

struct PlaceholderCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct EmptyChatState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ready to work")
                .font(.title2.weight(.bold))
            Text("Pick a workspace folder, choose a file if you want, then ask the local Codex shell to inspect the project, search files, generate code, or simulate terminal commands.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct FeaturePill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.12), in: Capsule())
            .foregroundStyle(.white)
    }
}

struct StatusToast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(radius: 12, y: 6)
    }
}

struct SystemDocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let allowsFolders: Bool
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
