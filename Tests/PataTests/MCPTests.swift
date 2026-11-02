import Testing
@testable import PataMCP
@testable import PataCore
@testable import PataUI
import Foundation

@Suite("MCP Tests")
struct MCPTests {
    @Test("MCP Server Tool execution and agent attribution")
    func mcpToolsAndAttribution() throws {
        let tempVaultDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("pata_mcp_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: tempVaultDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(atPath: tempVaultDir)
        }

        let vault = try Vault(rootPath: tempVaultDir)
        let server = MCPServer()
        server.setVault(vault)

        // Helper to invoke JSON-RPC request
        func sendRequest(_ dict: [String: Any]) throws -> [String: Any] {
            let reqData = try JSONSerialization.data(withJSONObject: dict)
            let resData = server.handleMCPRequestData(reqData)
            guard let json = try JSONSerialization.jsonObject(with: resData) as? [String: Any] else {
                Issue.record("Response is not JSON object")
                return [:]
            }
            return json
        }

        // 1. Initialize
        let initRes = try sendRequest([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [:]
        ])
        #expect(initRes["error"] == nil)
        let initResult = initRes["result"] as? [String: Any]
        #expect(initResult?["protocolVersion"] as? String == "2024-11-05")

        // 2. Tools list
        let toolsRes = try sendRequest([
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list",
            "params": [:]
        ])
        #expect(toolsRes["error"] == nil)
        let toolsResult = toolsRes["result"] as? [String: Any]
        let tools = toolsResult?["tools"] as? [[String: Any]]
        #expect(tools?.count == 7)

        // 3. Create task via pata_create_task
        let createRes = try sendRequest([
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": [
                "name": "pata_create_task",
                "arguments": [
                    "title": "Agent Task",
                    "tags": ["AI"]
                ]
            ]
        ])
        #expect(createRes["error"] == nil)
        let createResult = createRes["result"] as? [String: Any]
        guard let content = createResult?["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String,
              let textData = text.data(using: .utf8),
              let taskJson = try? JSONSerialization.jsonObject(with: textData) as? [String: Any],
              let dataDict = taskJson["data"] as? [String: Any] ?? taskJson as? [String: Any],
              let taskId = dataDict["id"] as? String else {
            Issue.record("Failed to parse create_task result")
            return
        }

        #expect(taskId.hasPrefix("t-"))
        let task = vault.index.getTask(taskId)
        #expect(task != nil)
        #expect(task?.createdBy == SourceAgent)

        // 4. Add activity via pata_append_activity
        let addActRes = try sendRequest([
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": [
                "name": "pata_append_activity",
                "arguments": [
                    "task_id": taskId,
                    "body": "Activity created by agent"
                ]
            ]
        ])
        #expect(addActRes["error"] == nil)
        let updatedTask = vault.index.getTask(taskId)
        #expect(updatedTask?.activities.count == 1)
        #expect(updatedTask?.activities.first?.by == SourceAgent)

        // 5. Update task status via pata_set_task_status
        let updateStatusRes = try sendRequest([
            "jsonrpc": "2.0",
            "id": 5,
            "method": "tools/call",
            "params": [
                "name": "pata_set_task_status",
                "arguments": [
                    "id": taskId,
                    "status": "done"
                ]
            ]
        ])
        #expect(updateStatusRes["error"] == nil)
        let doneTask = vault.index.getTask(taskId)
        #expect(doneTask?.status == TaskStatus.done)
        #expect(doneTask?.statusEvents.last?.by == SourceAgent)

        // 6. Read task by URI via pata_read
        let getUriRes = try sendRequest([
            "jsonrpc": "2.0",
            "id": 6,
            "method": "tools/call",
            "params": [
                "name": "pata_read",
                "arguments": [
                    "kind": "task",
                    "id": "pata://task/\(taskId)"
                ]
            ]
        ])
        #expect(getUriRes["error"] == nil)
    }

    @MainActor
    @Test("AppState MCP start, stop, cancel auto-start and status updates")
    func appStateMCPControls() throws {
        let appState = AppState(loadPreferences: false)

        // 1. Starting without vault sets error
        appState.startMCPServer()
        #expect(!appState.mcpStatus.running)
        #expect(appState.mcpStatus.error.contains("资料库"))

        // 2. Starting with vault
        let tempVaultDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("pata_appstate_mcp_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: tempVaultDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(atPath: tempVaultDir)
            appState.stopMCPServer()
        }

        appState.openVault(path: tempVaultDir, persist: false)
        #expect(appState.vault != nil)

        appState.startMCPServer()
        #expect(appState.mcpStatus.enabled)
        #expect(appState.mcpStatus.running)
        #expect(appState.mcpStatus.endpoint.contains("127.0.0.1:17373/mcp"))
        #expect(appState.mcpStatus.error.isEmpty)
        #expect(!appState.mcpStatus.vaultChanged)

        // 3. Stopping server
        appState.stopMCPServer()
        #expect(!appState.mcpStatus.running)
        #expect(!appState.mcpStatus.enabled)

        // 4. Cancel auto start
        appState.cancelMCPAutoStart()
        #expect(!appState.mcpStatus.enabled)
        #expect(!appState.mcpStatus.running)
    }
}
