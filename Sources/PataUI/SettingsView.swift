import SwiftUI
import AppKit
import PataCore
import PataKeychain
import PataAudio
import PataMCP

public struct SettingsView: View {
    @ObservedObject var state: AppState

    @State private var apiKeyInput: String = ""
    @State private var isEditingKey: Bool = false
    @State private var keyMessage: String = ""

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Header
                HStack {
                    Button(action: { state.showSettings = false }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("返回")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)

                    Spacer()

                    Text("设置")
                        .font(.system(size: 16, weight: .bold))

                    Spacer()

                    // Balance layout
                    Text("返回").opacity(0)
                }
                .padding(.bottom, 8)

                // 1. Appearance Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("外观")
                        .font(.system(size: 14, weight: .bold))

                    HStack(spacing: 20) {
                        Text("主题模式")
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)

                        Picker("", selection: $state.themePreference) {
                            Text("跟随系统").tag("system")
                            Text("浅色").tag("light")
                            Text("深色").tag("dark")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                        .onChange(of: state.themePreference) { _ in
                            state.savePreferences()
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

                // 2. Storage Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("存储")
                        .font(.system(size: 14, weight: .bold))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("当前资料库 (Vault)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        Text(state.vault?.rootPath ?? "未选择")
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))

                        HStack(spacing: 12) {
                            Button("更换目录...") {
                                selectVaultDirectory()
                            }
                            .buttonStyle(.bordered)

                            Button("重新扫描") {
                                state.rescanVault()
                            }
                            .buttonStyle(.bordered)

                            Button("在 Finder 中显示") {
                                if let path = state.vault?.rootPath {
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

                // 3. Audio ASR Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("语音转写")
                        .font(.system(size: 14, weight: .bold))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("服务说明")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        Text("阿里云百炼 · \(ASRConstants.defaultModel) · \(ASRConstants.defaultRegion)")
                            .font(.system(size: 13))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("API Key")
                                .font(.system(size: 13))
                                .frame(width: 80, alignment: .leading)

                            if state.isASRConfigured && !isEditingKey {
                                HStack(spacing: 8) {
                                    Text("已配置 (存入 macOS Keychain)")
                                        .font(.system(size: 13))
                                        .foregroundColor(.green)

                                    Button("更换 Key") {
                                        apiKeyInput = ""
                                        isEditingKey = true
                                    }
                                    .buttonStyle(.bordered)
                                }
                            } else {
                                HStack(spacing: 8) {
                                    SecureField("输入 DashScope API Key (sk-...)", text: $apiKeyInput)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: 280)

                                    Button("保存") {
                                        saveAPIKey()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                    if isEditingKey {
                                        Button("取消") {
                                            isEditingKey = false
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        if !keyMessage.isEmpty {
                            Text(keyMessage)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

                // 4. Native MCP Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("本机 MCP")
                        .font(.system(size: 14, weight: .bold))

                    HStack(spacing: 12) {
                        Text("服务状态:")
                            .font(.system(size: 13))

                        Text(state.mcpStatus.running ? "运行中" : "已停止")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(state.mcpStatus.running ? .green : .secondary)

                        Spacer()

                        Button(state.mcpStatus.running ? "停止服务" : "启动服务") {
                            toggleMCPServer()
                        }
                        .buttonStyle(.bordered)
                    }

                    if state.mcpStatus.running {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("接入地址")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)

                            Text(state.mcpStatus.endpoint)
                                .font(.system(size: 13, design: .monospaced))
                                .textSelection(.enabled)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("客户端配置示例 (Claude Desktop / Cursor)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)

                            let mcpConfigSnippet = """
                            {
                              "mcpServers": {
                                "pata": {
                                  "url": "http://127.0.0.1:17373/mcp"
                                }
                              }
                            }
                            """
                            Text(mcpConfigSnippet)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                                .textSelection(.enabled)

                            Button("复制配置") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(mcpConfigSnippet, forType: .string)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            }
            .padding(24)
            .frame(maxWidth: 680)
        }
    }

    private func selectVaultDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.title = "选择 Pata Vault 目录"

        if panel.runModal() == .OK, let url = panel.url {
            state.openVault(path: url.path)
        }
    }

    private func saveAPIKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try state.setASRKey(trimmed)
            isEditingKey = false
            keyMessage = "API Key 保存成功"
        } catch {
            keyMessage = "保存失败: \(error.localizedDescription)"
        }
    }

    private func toggleMCPServer() {
        if state.mcpStatus.running {
            MCPServer.shared.stop()
            state.mcpStatus = MCPServer.shared.getStatus()
            state.savePreferences()
        } else if let v = state.vault {
            do {
                try MCPServer.shared.start(vault: v)
                state.mcpStatus = MCPServer.shared.getStatus()
                state.savePreferences()
            } catch {
                print("Failed to start MCP: \(error)")
            }
        }
    }
}
