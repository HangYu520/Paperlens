import SwiftUI

private enum TestStatus: Equatable {
    case idle
    case testing
    case success
    case failed(String)
}

struct SettingsView: View {
    @AppStorage("deepseekModel") private var model: String = "deepseek-chat"
    @AppStorage("detailedTranslation") private var detailed: Bool = false
    @AppStorage("autoTranslateSelectedText") private var autoTranslateSelectedText: Bool = true
    @State private var apiKeyInput: String = ""
    @State private var isKeyVisible: Bool = false
    @State private var apiKeyLoaded: Bool = false
    @State private var testStatus: TestStatus = .idle

    var body: some View {
        VStack(spacing: 20) {
            Text("设置")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("API Key")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack {
                    if isKeyVisible {
                        TextField("sk-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("sk-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        isKeyVisible.toggle()
                    } label: {
                        Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("模型")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack {
                    TextField("deepseek-chat", text: $model)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: model) {
                            testStatus = .idle
                        }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("选中后自动翻译", isOn: $autoTranslateSelectedText)
                    .toggleStyle(.switch)

                Text(autoTranslateSelectedText ? "选中文字后直接显示翻译气泡。" : "选中文字后先显示悬浮按钮。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    testConnection()
                } label: {
                    HStack(spacing: 6) {
                        if testStatus == .testing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                            Text("测试中...")
                        } else {
                            Text("测试连接")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(testStatus == .testing)

                switch testStatus {
                case .idle:
                    EmptyView()
                case .testing:
                    EmptyView()
                case .success:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("连接成功")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                case .failed(let message):
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $detailed) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("详细翻译")
                            .font(.subheadline)
                        Text("包含术语标注、句式解析和学术背景补充")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("快捷键")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("⌘ ⇧ T")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
            }

            Divider()

            HStack {
                Text("版本 1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("PaperLens")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(width: 340)
        .fixedSize()
        .onAppear {
            if !apiKeyLoaded {
                apiKeyInput = KeychainManager.load() ?? ""
                apiKeyLoaded = true
            }
        }
        .onChange(of: apiKeyInput) {
            guard apiKeyLoaded else { return }
            testStatus = .idle
            if apiKeyInput.isEmpty {
                KeychainManager.delete()
            } else {
                KeychainManager.save(apiKeyInput)
            }
        }
    }

    private func testConnection() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            testStatus = .failed("请先填入 API Key")
            return
        }

        testStatus = .testing

        TranslatorService.shared.translateStream(
            "Hello",
            apiKey: key,
            model: model,
            onToken: { _ in },
            onComplete: { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        testStatus = .success
                    case .failure(let error):
                        testStatus = .failed(error.localizedDescription)
                    }
                }
            }
        )
    }
}
