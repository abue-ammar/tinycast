import Foundation

enum OpenCodeMCPLaunch {
    static func configuration(
        server: String, url: String, bearer: String, tools: [AITool]
    ) throws -> String {
        var permissions: [[String: String]] = [
            ["action": "*", "resource": "*", "effect": "deny"]
        ]
        permissions += tools.indices.map {
            ["action": server + "_" + toolName(at: $0), "resource": "*", "effect": "allow"]
        }
        let config: [String: Any] = [
            "share": "disabled", "snapshots": false,
            "agents": [
                InstalledAIKind.openCodeAgent: [
                    "system": "You are generating text inside Tinycast. Use only the supplied MCP tools.",
                    "permissions": permissions
                ]
            ],
            "mcp": [
                "servers": [
                    server: [
                        "type": "remote", "url": url, "oauth": false, "codemode": false,
                        "headers": ["Authorization": "Bearer " + bearer]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw AIProviderError.malformedResponse
        }
        return text
    }

    static func toolName(at index: Int) -> String { "tool_\(index)" }
}
