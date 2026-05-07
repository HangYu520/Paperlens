import SwiftUI

struct FloatingButtonView: View {
    var onTap: (() -> Void)?

    @State private var isVisible: Bool = false

    var body: some View {
        Button {
            onTap?()
        } label: {
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)

                Image(systemName: "character.book.closed")
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .opacity(isVisible ? 1.0 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
    }

    func dismiss(completion: @escaping () -> Void) {
        withAnimation(.easeOut(duration: 0.15)) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            completion()
        }
    }
}

struct PositionCalculator {
    static func positionForButton(near bounds: NSRect, buttonSize: CGSize = CGSize(width: 36, height: 36)) -> NSPoint {
        guard let screen = NSScreen.main else {
            return NSPoint(x: bounds.maxX + 8, y: bounds.maxY - 8)
        }

        let screenFrame = screen.visibleFrame
        let offset: CGFloat = 8

        var x = bounds.maxX + offset
        var y = bounds.maxY - offset - buttonSize.height

        if x + buttonSize.width > screenFrame.maxX {
            x = bounds.minX - offset - buttonSize.width
        }
        if y < screenFrame.minY {
            y = bounds.minY + offset
        }
        if y + buttonSize.height > screenFrame.maxY {
            y = screenFrame.maxY - offset - buttonSize.height
        }

        return NSPoint(x: max(screenFrame.minX, x), y: max(screenFrame.minY, y))
    }

    static func positionForBubble(near buttonPoint: NSPoint, buttonSize: CGSize = CGSize(width: 36, height: 36)) -> NSPoint {
        guard let screen = NSScreen.main else {
            return NSPoint(x: buttonPoint.x, y: buttonPoint.y - 12)
        }

        let screenFrame = screen.visibleFrame
        let bubbleWidth: CGFloat = 420
        let bubbleMaxHeight: CGFloat = 320
        let offset: CGFloat = 12

        var x = buttonPoint.x + (buttonSize.width / 2) - (bubbleWidth / 2)
        var y = buttonPoint.y - offset - bubbleMaxHeight

        x = max(screenFrame.minX + 16, min(x, screenFrame.maxX - bubbleWidth - 16))

        if y < screenFrame.minY {
            y = buttonPoint.y + buttonSize.height + offset
        }

        return NSPoint(x: x, y: max(screenFrame.minY, y))
    }
}
