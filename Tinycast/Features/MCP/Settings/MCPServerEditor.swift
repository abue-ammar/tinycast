import SwiftUI

struct MCPServerEditorTarget: Identifiable {
    let server: MCPServer
    let isNew: Bool
    var id: UUID { server.id }
}

/// Adds or edits one server, and can prove it connects before the sheet is dismissed.
struct MCPServerEditor: View {
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
            Form {
                Section {
                    field("Name") {
                        TextField("Name", text: $name, prompt: Text("GitHub"))
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
                        }
                        field("Header") {
                            TextField("Header", text: $headerName, prompt: Text("Authorization"))
                        }
                        field("Value") {
                            SecureField("Value", text: $headerValue, prompt: Text("Bearer …"))
                        }
                    } else {
                        field("Command") {
                            TextField("Command", text: $command, prompt: Text("npx"))
                        }
                        field("Arguments") {
                            TextField(
                                "Arguments", text: $argumentText,
                                prompt: Text("-y @modelcontextprotocol/server-filesystem ~/Desktop"))
                        }
                        field("Environment") {
                            TextField(
                                "Environment", text: $environmentText,
                                prompt: Text("GITHUB_TOKEN=…"), axis: .vertical
                            )
                            .lineLimit(2...5)
                        }
                    }
                } header: {
                    Text(target.isNew ? "Add MCP Server" : "Edit MCP Server")
                } footer: {
                    Text(
                        kind == .http
                            ? "Remote endpoints must use HTTPS. The header value is stored in your "
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
                            .disabled(probe == .running)
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

            Divider()
            HStack(spacing: Theme.Spacing.lg) {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.xl)
        }
        .frame(width: 620, height: 560)
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

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        LabeledContent(label) { content() }
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
            return (server, MCPSecretStore.Secrets(headerValue: headerValue))
        case .stdio:
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
        Task {
            let connection = MCPServerConnection(server: draft.server, secrets: draft.secrets)
            await connection.start()
            switch connection.status {
            case .ready(let tools): probe = .found(tools)
            case .failed(let message): probe = .failed(message)
            default: probe = .failed("The server did not answer.")
            }
            connection.stop()
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
