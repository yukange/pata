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
    @State private var autoCheckUpdates: Bool = true
    @State private var copiedPath: Bool = false

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
            // Header: ← 返回 | 应用设置
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

            // Content Area - Single page vertically stacked
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Section 1: 外观
                    appearanceSection

                    // Section 2: 存储
                    storageSection

                    // Section 3: 智能体 MCP 服务
                    mcpSection

                    // Section 4: 语音转写
                    transcriptionSection

                    // Section 5: 软件更新
                    updaterSection
                }
                .padding(24)
                .frame(maxWidth: 680)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Section 1: 外观

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("外观")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            // Theme Mode
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

            // Accent Color
            HStack {
                Text("主题强调色")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                HStack(spacing: 8) {
                    // Follow System
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

                    // Presets
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

    // MARK: - Section 3: 智能体 MCP 服务

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("智能体 MCP 服务")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            Text("提供本地 stdio/HTTP MCP 协议端点，供 Claude Code、Cursor 等外部 AI 工具接入读写 Pata 数据。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineSpacing(2)

            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 4/255, green: 120/255, blue: 87/255))
                        .frame(width: 8, height: 8)
                    Text("服务运行中 · 端口 8808")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("停止服务") {
                    // MCP control
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
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

    // MARK: - Section 5: 软件更新

    private var updaterSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("软件更新")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            HStack {
                Text("自动检查更新")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Toggle("", isOn: $autoCheckUpdates)
                    .labelsHidden()
                    .toggleStyle(.switch)
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
