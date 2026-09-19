import SwiftUI

struct MCPServerEditorTarget: Identifiable {
    let server: MCPServer
    let isNew: Bool
    var id: UUID { server.id }
}

/// Adds or edits one server, and can prove it connects before the panel is dismissed.
struct MCPServerEditor: View {
    @Environment(MCPCoordinator.self) private var coordinator
    let target: MCPServerEditorTarget
    let onSave: (MCPServer, MCPSecretStore.Secrets) -> String?
    let onCancel: () -> Void

    private enum Kind: String, CaseIterable, Identifiable {
        case http
        case stdio

        var id: String { rawValue }
        var title: String { self == .http ? "HTTP" : "Command" }
    }

    private enum Probe: Equatable {
        case idle
        case running
        case found(Int)
        case failed(String)
    }

    @State private var usesOAuth: Bool
    @State private var clientID: String
    @State private var clientSecret: String
    // The status label's copy: a view body never reads the Keychain, actions read it fresh.
    @State private var storedOAuth: MCPOAuth.Credentials?
    @State private var operation: Task<Void, Never>?
    @State private var name: String
    @State private var kind: Kind
    @State private var url: String
    @State private var headerName: String
    @State private var headerValue: String
    @State private var command: String
    @State private var argumentText: String
    @State private var environmentText: String
    @State private var isEnabled: Bool
    @State private var trust: MCPTrust
    @State private var probe: Probe = .idle
    @State private var error: String?

    init(
        target: MCPServerEditorTarget,
        onSave: @escaping (MCPServer, MCPSecretStore.Secrets) -> String?,
        onCancel: @escaping () -> Void
    ) {
        self.target = target
        self.onSave = onSave
        self.onCancel = onCancel
        let server = target.server
        let secrets = target.isNew ? MCPSecretStore.Secrets() : MCPSecretStore().secrets(for: server.id)
        _usesOAuth = State(initialValue: server.oauth == true)
        _clientID = State(initialValue: secrets.oauth?.clientID ?? "")
        _clientSecret = State(initialValue: secrets.oauth?.clientSecret ?? "")
        _storedOAuth = State(initialValue: secrets.oauth)
        _name = State(initialValue: server.name)
        _isEnabled = State(initialValue: server.isEnabled)
        _trust = State(initialValue: server.trust)
        _headerValue = State(initialValue: secrets.headerValue)
        _environmentText = State(
            initialValue: secrets.environment.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }.joined(separator: "\n"))
        switch server.transport {
        case .http(let url, let headerName):
            _kind = State(initialValue: .http)
            _url = State(initialValue: url)
            _headerName = State(initialValue: headerName)
            _command = State(initialValue: "")
            _argumentText = State(initialValue: "")
        case .stdio(let command, let arguments, _):
            _kind = State(initialValue: .stdio)
            _url = State(initialValue: "")
            _headerName = State(initialValue: MCPTransportKind.defaultHeaderName)
            _command = State(initialValue: command)
            _argumentText = State(initialValue: arguments.joined(separator: " "))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(
                title: target.isNew ? "Add MCP Server" : "Edit MCP Server"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.top, Theme.Spacing.dialogInset)
            .padding(.bottom, Theme.Spacing.xl)

            Form {
                Section {
                    field("Name") {
                        TextField("Name", text: $name, prompt: Text("GitHub"))
                            .settingsEditorTextField()
                    }
                    field("Handle") {
                        Text("@\(MCPSlug.normalize(name.isEmpty ? target.server.slug : name))")
                            .foregroundStyle(.secondary)
                    }
                    field("Connection") {
                        Picker("Connection", selection: $kind) {
                            ForEach(Kind.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                    if kind == .http {
                        field("URL") {
                            TextField("URL", text: $url, prompt: Text("https://example.com/mcp"))
                                .settingsEditorTextField()
                        }
                        field("Authentication") {
                            Picker("Authentication", selection: $usesOAuth) {
                                Text("Header").tag(false)
                                Text("OAuth").tag(true)
                            }
                            .labelsHidden()
                        }
                        if usesOAuth {
                            oauthFields
                        } else {
                            field("Header") {
                                TextField("Header", text: $headerName, prompt: Text("Authorization"))
                                    .settingsEditorTextField()
                            }
                            field("Value") {
                                SecureField("Value", text: $headerValue, prompt: Text("Bearer …"))
                                    .settingsEditorTextField()
                            }
                        }
                    } else {
                        field("Command") {
                            TextField("Command", text: $command, prompt: Text("npx"))
                                .settingsEditorTextField()
                        }
                        field("Arguments") {
                            TextField(
                                "Arguments", text: $argumentText,
                                prompt: Text("-y @modelcontextprotocol/server-filesystem ~/Desktop")
                            )
                            .settingsEditorTextField()
                        }
                        field("Environment") {
                            TextField(
                                "Environment", text: $environmentText,
                                prompt: Text("GITHUB_TOKEN=…"), axis: .vertical
                            )
                            .textFieldStyle(.plain)
                            .lineLimit(2...5)
                            .settingsEditorTextArea(height: Theme.Size.editorTextHeight)
                        }
                    }
                } footer: {
                    Text(
                        kind == .http
                            ? "Remote endpoints must use HTTPS. Credentials are stored in your "
                                + "login Keychain, never in preferences."
                            : "The command runs on this Mac with your own account. One "
                                + "NAME=value per line; values are stored in your login Keychain."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Offer this server's tools", isOn: $isEnabled)
                    field("Trust") {
                        Picker("Trust", selection: $trust) {
                            ForEach(MCPTrust.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }
                    HStack(spacing: Theme.Spacing.lg) {
                        Button("Test Connection", action: test)
                            .disabled(operation != nil)
                        probeLabel
                    }
                    if let error {
                        Text(error).foregroundStyle(.orange)
                    }
                } footer: {
                    Text(
                        "Ask Each Chat puts the first tool call of every conversation through a "
                            + "confirmation. Never Allow withholds the server without removing it."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            HStack(spacing: Theme.Spacing.md) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .disabled(operation != nil)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.dialogInset)
        }
        .frame(width: 620, height: 560)
        .settingsEditorPanelSurface()
        .onDisappear {
            operation?.cancel()
            coordinator.cancelSignIn(target.server.id)
            if target.isNew { coordinator.discardUnsaved(target.server.id) }
        }
        .onChange(of: url) { cancelOperation() }
        .onChange(of: usesOAuth) { cancelOperation() }
        .onChange(of: kind) { cancelOperation() }
        .onChange(of: clientID) { cancelOperation() }
        .onChange(of: clientSecret) { cancelOperation() }
    }

    private var oauthFields: some View {
        Group {
            field("Client ID") {
                TextField("Client ID", text: $clientID, prompt: Text("Optional — register automatically"))
                    .settingsEditorTextField()
            }
            field("Client secret") {
                SecureField("Client secret", text: $clientSecret, prompt: Text("Optional"))
                    .settingsEditorTextField()
            }
            field("Sign-in") {
                HStack(spacing: Theme.Spacing.lg) {
                    switch authenticationStatus {
                    case .signedIn: Button("Sign Out", action: signOut).disabled(operation != nil)
                    case .signingIn: Button("Cancel", action: cancelOperation)
                    default: Button("Sign In", action: signIn).disabled(operation != nil)
                    }
                    Text(authenticationStatus.label)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // A pasted ID often ends in a newline, and Google answers that with "client not found".
    private var suppliedClientID: String { clientID.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var suppliedClientSecret: String { clientSecret.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var authenticationStatus: MCPOAuthManager.Status {
        var server = target.server
        server.transport = .http(
            url: url.trimmingCharacters(in: .whitespaces),
            headerName: headerName.trimmingCharacters(in: .whitespaces))
        let status = coordinator.authenticationStatus(server, stored: storedOAuth)
        guard storedOAuth?.clientID == suppliedClientID, storedOAuth?.clientSecret == suppliedClientSecret,
            storedOAuth?.registration?.resource == (try? MCPOAuth.resource(url)) else {
            if case .signingIn = status { return status }
            if case .failed = status { return status }
            return .signedOut
        }
        return status
    }

    private func signIn() {
        if let message = validate() { error = message; return }
        error = nil
        let draft = draft
        guard let credentials = draft.secrets.oauth else { return }
        operation = Task {
            defer { operation = nil }
            do {
                try await coordinator.signIn(draft.server, credentials: credentials)
                storedOAuth = MCPSecretStore().secrets(for: target.server.id).oauth
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func signOut() {
        do {
            try coordinator.signOut(target.server.id)
            storedOAuth?.token = nil
            probe = .idle
            error = nil
        } catch { self.error = "The credentials could not be removed from your login Keychain." }
    }

    private func cancelOperation() {
        operation?.cancel()
        coordinator.cancelSignIn(target.server.id)
        probe = .idle
    }

    @ViewBuilder private var probeLabel: some View {
        switch probe {
        case .idle:
            EmptyView()
        case .running:
            ProgressView().controlSize(.small)
        case .found(let count):
            Label(count == 1 ? "1 tool" : "\(count) tools", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func field<Content: View>(
        _ label: String, @ViewBuilder content: () -> Content
    ) -> some View {
        SettingsEditorField(label, content: content)
    }

    private var draft: (server: MCPServer, secrets: MCPSecretStore.Secrets) {
        var server = target.server
        server.name = name
        server.isEnabled = isEnabled
        server.trust = trust
        let environment = Self.environment(from: environmentText)
        switch kind {
        case .http:
            server.transport = .http(
                url: url.trimmingCharacters(in: .whitespaces),
                headerName: headerName.trimmingCharacters(in: .whitespaces))
            server.oauth = usesOAuth ? true : nil
            var secrets = MCPSecretStore.Secrets(headerValue: usesOAuth ? "" : headerValue)
            if usesOAuth {
                var credentials = MCPSecretStore().secrets(for: server.id).oauth ?? MCPOAuth.Credentials()
                if credentials.clientID != suppliedClientID || credentials.clientSecret != suppliedClientSecret {
                    credentials = MCPOAuth.Credentials(clientID: suppliedClientID, clientSecret: suppliedClientSecret)
                }
                if let registration = credentials.registration,
                    registration.resource != (try? MCPOAuth.resource(url)) { credentials.token = nil }
                secrets.oauth = credentials
            }
            return (server, secrets)
        case .stdio:
            server.oauth = nil
            server.transport = .stdio(
                command: command.trimmingCharacters(in: .whitespaces),
                arguments: Self.arguments(from: argumentText),
                environmentKeys: environment.keys.sorted())
            return (server, MCPSecretStore.Secrets(environment: environment))
        }
    }

    /// A real handshake, so a typo is caught here rather than in the middle of a conversation.
    private func test() {
        guard validate() == nil else {
            error = validate()
            return
        }
        error = nil
        probe = .running
        let draft = draft
        operation = Task {
            defer { operation = nil }
            let status = await coordinator.test(draft.server, secrets: draft.secrets)
            guard !Task.isCancelled else { return }
            switch status {
            case .ready(let tools): probe = .found(tools)
            case .failed(let message): probe = .failed(message)
            case .signInRequired: probe = .failed("Sign-in required")
            default: probe = .failed("The server did not answer.")
            }
        }
    }

    private func save() {
        if let message = validate() {
            error = message
            return
        }
        let draft = draft
        error = onSave(draft.server, draft.secrets)
    }

    private func validate() -> String? {
        switch kind {
        case .http:
            do {
                _ = try AIEndpointPolicy.validate(url)
            } catch {
                return error.localizedDescription
            }
        case .stdio where command.trimmingCharacters(in: .whitespaces).isEmpty:
            return "Enter the command that starts this server."
        case .stdio:
            break
        }
        return nil
    }

    /// Whitespace-separated, with quoting for the one argument that is a path holding a space.
    private static func arguments(from text: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var quote: Character?
        for character in text {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { arguments.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { arguments.append(current) }
        return arguments
    }

    private static func environment(from text: String) -> [String: String] {
        var environment: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            environment[key] = String(line[line.index(after: separator)...])
        }
        return environment
    }
}
