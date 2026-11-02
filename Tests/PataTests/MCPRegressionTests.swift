import Foundation
import Testing
@testable import PataCore
@testable import PataMCP

@Suite("Audit: MCP regressions")
struct MCPRegressionTests {
    private func call(_ server: MCPServer, tool: String, args: [String: Any]) throws -> [String: Any] {
        let request: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": tool, "arguments": args]]
        let response = server.handleMCPRequestData(try JSONSerialization.data(withJSONObject: request))
        return try #require(JSONSerialization.jsonObject(with: response) as? [String: Any])
    }

    private func toolData(_ response: [String: Any]) throws -> [String: Any] {
        let result = try #require(response["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        let value = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        return try #require(value["data"] as? [String: Any])
    }

    @Test func listenerServesLoopbackAndRejectsOtherInterfaces() async throws {
        let fixture = try AuditVaultFixture()
        let server = MCPServer(port: 0)
        try server.start(vault: fixture.vault)
        defer { server.stop() }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, server.getStatus().endpoint.contains(":0/") {
            try await _Concurrency.Task.sleep(for: .milliseconds(20))
        }
        let url = try #require(URL(string: server.getStatus().endpoint))
        let port = try #require(url.port)
        #expect(port != 0)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 1
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self).contains("pata_search"))
        if let address = Host.current().addresses.first(where: { $0.contains(".") && !$0.hasPrefix("127.") && $0 != "0.0.0.0" }) {
            request.url = URL(string: "http://\(address):\(port)/mcp")
            request.setValue("127.0.0.1:\(port)", forHTTPHeaderField: "Host")
            do {
                _ = try await session.data(for: request)
                Issue.record("MCP accepted a request through a non-loopback interface")
            } catch {
                #expect(error is URLError)
            }
        }
    }

    @Test func nonemptyListsAndSearchEncodeAndPaginate() throws {
        let fixture = try AuditVaultFixture()
        _ = try fixture.vault.createTask(title: "matching one")
        _ = try fixture.vault.createTask(title: "matching two")
        let server = MCPServer()
        server.setVault(fixture.vault)
        for (tool, args) in [("pata_list", ["kind": "task", "limit": 1] as [String: Any]), ("pata_search", ["query": "matching", "limit": 1])] {
            let first = try toolData(call(server, tool: tool, args: args))
            #expect((first["items"] as? [[String: Any]])?.count == 1)
            #expect(first["total"] as? Int == 2)
            #expect(first["next_offset"] as? Int == 1)
            var nextArgs = args
            nextArgs["offset"] = 1
            let second = try toolData(call(server, tool: tool, args: nextArgs))
            #expect((second["items"] as? [[String: Any]])?.count == 1)
            #expect(second["next_offset"] as? Int == -1)
        }
    }

    @Test func rejectsMissingTitlesInvalidStatusAndTraversal() throws {
        let fixture = try AuditVaultFixture()
        let server = MCPServer()
        server.setVault(fixture.vault)
        for tool in ["pata_create_task", "pata_create_note", "pata_append_activity"] {
            #expect(try call(server, tool: tool, args: [:])["error"] != nil)
        }
        #expect(try call(server, tool: "pata_create_task", args: ["title": "test", "status": "invalid"])["error"] != nil)
        #expect(try call(server, tool: "pata_append_activity", args: ["date": "../../escaped", "body": "test"])["error"] != nil)
        #expect(fixture.vault.index.listTasks().isEmpty)
        #expect(fixture.vault.index.listNotes().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("escaped.md").path))
    }

    @Test func changingVaultRevokesExistingAccess() throws {
        let original = try AuditVaultFixture()
        let other = try AuditVaultFixture()
        let server = MCPServer()
        server.setVault(original.vault)
        #expect(try call(server, tool: "pata_create_task", args: ["title": "old"])["error"] == nil)
        server.setVault(other.vault)
        #expect(server.getStatus().vaultChanged)
        #expect(!server.getStatus().enabled)
        #expect(try call(server, tool: "pata_create_task", args: ["title": "must not write"])["error"] != nil)
        #expect(other.vault.index.listTasks().isEmpty)
        #expect(original.vault.index.listTasks().count == 1)
    }

    @Test func accumulatesFragmentedHeadersAndUTF8Body() throws {
        let body = Data("{\"message\":\"中文正文\"}".utf8)
        let header = Data("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:17373\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
        let request = header + body
        for count in 0..<request.count {
            #expect(try MCPServer.completeHTTPRequest(Data(request.prefix(count))) == nil)
        }
        #expect(try MCPServer.completeHTTPRequest(request) == request)
    }

    @Test func rejectsAmbiguousOrOversizedHTTPBodies() {
        for header in [
            "Content-Length: -1", "Content-Length: 4194305", "Content-Length: 1\r\nContent-Length: 1",
            "Transfer-Encoding: chunked", "Content-Length: invalid"
        ] {
            let data = Data("POST /mcp HTTP/1.1\r\n\(header)\r\n\r\n".utf8)
            #expect(throws: (any Error).self) { try MCPServer.completeHTTPRequest(data) }
        }
        #expect(throws: (any Error).self) {
            try MCPServer.completeHTTPRequest(Data(repeating: 65, count: MCPServer.maximumRequestSize + 1))
        }
    }
}
