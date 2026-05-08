import SwiftUI
import AppKit

enum BubbleState: Equatable {
    case loading
    case streaming(String)
    case result(String)
    case error(String)
}

struct TranslationBubbleView: View {
    let state: BubbleState
    var onCopy: ((String) -> Void)?
    var onDismiss: (() -> Void)?
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch state {
            case .loading:
                loadingContent
            case .streaming(let text):
                streamingContent(text: text)
            case .result(let text):
                resultContent(text: text)
            case .error(let message):
                errorContent(message: message)
            }
        }
        .padding(16)
        .frame(maxWidth: 420, maxHeight: 300)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private var loadingContent: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("翻译中...")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Button("取消") {
                onDismiss?()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func streamingContent(text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    Text(text)
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 1.5, height: 16)
                        .opacity(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)

            HStack {
                Spacer()
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
    }

    private func resultContent(text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                Text(text)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)

            HStack {
                Spacer()
                Button {
                    onCopy?(text)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("复制")

                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
    }

    private func errorContent(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 20))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                if onRetry != nil {
                    Button("重试") {
                        onRetry?()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                }
                Button("关闭") {
                    onDismiss?()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
