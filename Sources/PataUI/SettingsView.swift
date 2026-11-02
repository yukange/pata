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
    @State private var copiedPath: Bool = false
    @State private var showColorPopover: Bool = false
    @State private var copiedMCPPrompt: Bool = false
    @State private var copyPromptTimer: DispatchWorkItem? = nil

    private let presetAccents = [
        (name: "蓝色", hex: "#007aff", color: Color(red: 0/255, green: 122/255, blue: 255/255)),
        (name: "紫色", hex: "#af52de", color: Color(red: 175/255, green: 82/255, blue: 222/255)),
        (name: "绿色", hex: "#27836b", color: Color(red: 39/255, green: 131/255, blue: 107/255)),
        (name: "橙色", hex: "#ff9500", color: Color(red: 255/255, green: 149/255, blue: 0/255)),
        (name: "粉色", hex: "#ff2d55", color: Color(red: 255/255, green: 45/255, blue: 85/255)),
        (name: "灰色", hex: "#8e8e93", color: Color(red: 142/255, green: 142/255, blue: 147/255)),
    ]

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: { state.showSettings = false }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 11, weight: .medium))
                        Text("返回")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                }
                .buttonStyle(.plain)

                Text("|")
                    .foregroundColor(Color(nsColor: .separatorColor))

                Text("应用设置")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 24)
            .frame(height: 48)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor).opacity(0.6)), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    appearanceSection
                    storageSection
                    mcpSection
                    transcriptionSection
                }
                .padding(24)
                .frame(maxWidth: 680)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            state.refreshMCPStatus()
        }
    }

    // MARK: - Section 1: 外观

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("外观")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            HStack {
                Text("主题模式")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                HStack(spacing: 2) {
                    themeButton(title: "跟随系统", mode: "system", icon: "display")
                    themeButton(title: "浅色", mode: "light", icon: "sun.max")
                    themeButton(title: "深色", mode: "dark", icon: "moon")
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.stoneBadgeBg))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
            }

            Divider()

            HStack {
                Text("主题强调色")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                HStack(spacing: 8) {
                    Button(action: {
                        state.accentColorHex = ""
                        state.savePreferences()
                    }) {
                        Circle()
                            .fill(Color.stoneBadgeBg)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Image(systemName: "display")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            )
                            .overlay(
                                Circle()
                                    .stroke(state.accentColorHex.isEmpty ? Color.primary : Color.clear, lineWidth: 1.5)
                                    .padding(-2)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("跟随系统")

                    ForEach(presetAccents, id: \.hex) { preset in
                        Button(action: {
                            state.accentColorHex = preset.hex
                            state.savePreferences()
                        }) {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .stroke(state.accentColorHex.lowercased() == preset.hex ? Color.primary : Color.clear, lineWidth: 1.5)
                                        .padding(-2)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                    }

                    let isPreset = presetAccents.contains { $0.hex.lowercased() == state.accentColorHex.lowercased() }
                    let isCustomSelected = !state.accentColorHex.isEmpty && !isPreset
                    let customColor = isCustomSelected ? (Color(hex: state.accentColorHex) ?? .accentColor) : Color.stoneBadgeBg

                    Button(action: { showColorPopover.toggle() }) {
                        Circle()
                            .fill(customColor)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Image(systemName: "paintpalette")
                                    .font(.system(size: 9))
                                    .foregroundColor(isCustomSelected ? customColor.onAccent : .secondary)
                            )
                            .overlay(
                                Circle()
                                    .stroke(isCustomSelected ? Color.primary : Color.clear, lineWidth: 1.5)
                                    .padding(-2)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(isCustomSelected ? "自定义颜色 (\(state.accentColorHex))" : "自定义颜色")
                    .popover(isPresented: $showColorPopover, arrowEdge: .bottom) {
                        ModernColorPickerPopover(accentHex: $state.accentColorHex) {
                            state.savePreferences()
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
    }

    private func themeButton(title: String, mode: String, icon: String) -> some View {
        let isSelected = state.themePreference == mode

        return Button(action: {
            state.themePreference = mode
            state.savePreferences()
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color(nsColor: .textBackgroundColor) : Color.clear))
            .foregroundColor(isSelected ? .primary : .secondary)
            .shadow(color: isSelected ? Color.black.opacity(0.05) : Color.clear, radius: 1, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section 2: 存储

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("存储")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 6) {
                Text("当前 Vault 目录")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    Text(state.vault?.rootPath ?? "未配置 Vault 目录")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.stoneBadgeBg))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))

                    Button(action: copyVaultPath) {
                        Image(systemName: copiedPath ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundColor(copiedPath ? .green : .secondary)
                            .padding(7)
                            .background(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("复制完整路径")
                }
            }

            HStack(spacing: 10) {
                Button(action: selectVaultDirectory) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                        Text(state.vault != nil ? "更换目录" : "选择目录")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button(action: revealInFinder) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11))
                        Text("在 Finder 中打开")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Menu {
                    Button("重新扫描") {
                        state.rescanVault()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
    }

    // MARK: - Section 3: MCP 服务

    private var mcpAgentPrompt: String {
        let endpoint = state.mcpStatus.endpoint.isEmpty ? "http://127.0.0.1:17373/mcp" : state.mcpStatus.endpoint
        return "帮我在当前客户端配置中新增名为 pata 的 MCP 服务，使用 Streamable HTTP 传输协议，连接地址为 \(endpoint)，仅增量修改并保留原有配置，最后通过列出工具验证接入是否成功。"
    }

    private func copyMCPAgentPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(mcpAgentPrompt, forType: .string)
        copiedMCPPrompt = true
        copyPromptTimer?.cancel()
        let item = DispatchWorkItem {
            copiedMCPPrompt = false
        }
        copyPromptTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
    }

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MCP 服务")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(state.mcpStatus.running ? Color(red: 16/255, green: 185/255, blue: 129/255) : Color.secondary.opacity(0.5))
                            .frame(width: 7, height: 7)
                        Text(state.mcpStatus.running ? "运行中 · 127.0.0.1:17373" : "未启动")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(state.mcpStatus.running ? .primary : .secondary)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    if state.mcpStatus.enabled && !state.mcpStatus.running {
                        Button(action: { state.cancelMCPAutoStart() }) {
                            Text("取消自动启动")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: {
                        if state.mcpStatus.running {
                            state.stopMCPServer()
                        } else {
                            state.startMCPServer()
                        }
                    }) {
                        Text(state.mcpStatus.running ? "停止服务" : "启动服务")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(state.mcpStatus.running ? .secondary : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            if state.mcpStatus.vaultChanged {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text("资料库已更换。请停止并重新启动服务，允许 Agent 访问当前资料库。")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            }

            if !state.mcpStatus.error.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                    Text(state.mcpStatus.error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.3), lineWidth: 1))
            }

            if state.mcpStatus.running {
                Divider()
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Agent 接入")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                            Text("在支持 MCP 的客户端中配置接入")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: copyMCPAgentPrompt) {
                            HStack(spacing: 4) {
                                Image(systemName: copiedMCPPrompt ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundColor(copiedMCPPrompt ? .green : .secondary)
                                Text(copiedMCPPrompt ? "已复制" : "复制指令")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(state.mcpStatus.vaultChanged)
                        .help(mcpAgentPrompt)
                    }

                    Text(mcpAgentPrompt)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.stoneBadgeBg))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1))
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
    }

    // MARK: - Section 4: 语音转写

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("语音转写")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Button(action: {
                    if let url = URL(string: "https://bailian.console.aliyun.com/cn-beijing/model/settings/api-key") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 3) {
                        Text("获取 API Key")
                            .font(.system(size: 12))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("API Key 凭据")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                if isEditingKey {
                    HStack(spacing: 8) {
                        SecureField("sk-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))

                        Button("保存") {
                            saveAPIKey()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("取消") {
                            isEditingKey = false
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                    }
                } else {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: state.isASRConfigured ? "checkmark.shield" : "exclamationmark.shield")
                                .font(.system(size: 13))
                                .foregroundColor(state.isASRConfigured ? Color(red: 4/255, green: 120/255, blue: 87/255) : .orange)

                            Text(state.isASRConfigured ? "已配置 · 存储于 macOS Keychain" : "未配置 API Key")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(state.isASRConfigured ? "更换 API Key" : "配置 API Key") {
                            isEditingKey = true
                            apiKeyInput = ""
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
                    }
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
    }

    // MARK: - Helpers

    private func copyVaultPath() {
        if let path = state.vault?.rootPath {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
            copiedPath = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copiedPath = false
            }
        }
    }

    private func revealInFinder() {
        if let path = state.vault?.rootPath {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        }
    }

    private func selectVaultDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择 Vault"

        if panel.runModal() == .OK, let url = panel.url {
            state.openVault(path: url.path)
        }
    }

    private func saveAPIKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        try? state.setASRKey(key)
        isEditingKey = false
    }
}
