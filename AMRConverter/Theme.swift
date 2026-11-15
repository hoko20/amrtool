import SwiftUI

// 与 WCMigrate-Sandbox 保持一致的单色设计语言：
// 浅灰画布、白色圆角卡片、近黑文字，界面里不出现系统蓝。
enum Palette {
    static let background = Color(hex: 0xF2F2F6)
    static let card = Color.white
    static let ink = Color(hex: 0x121216)
    static let secondary = Color(hex: 0x8A8A90)
    static let tertiary = Color(hex: 0xB7B7BE)
    static let selected = Color(hex: 0xE8E8ED)
    static let placeholder = Color(hex: 0xEEEFF2)
    static let separator = Color(hex: 0xE9E9EE)
    static let warning = Color(hex: 0xB4692C)
    static let danger = Color(hex: 0xC0453B)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

struct CardBox<Content: View>: View {
    private let radius: CGFloat
    private let padding: CGFloat
    private let content: Content

    init(radius: CGFloat = 20, padding: CGFloat = 18,
         @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Color.black.opacity(0.035), radius: 12, x: 0, y: 4)
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Palette.secondary)
            .textCase(.none)
    }
}

struct ThinSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Palette.separator)
            .frame(height: 1)
    }
}

struct InlineNotice: View {
    let text: String
    var tone: Color = Palette.warning

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tone)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(tone.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct EmptyCard: View {
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.tertiary)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    /// iOS 26 大标题导航栏：滚动时自动收敛并套用系统液态玻璃背景。
    func glassNavigationBar(title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.automatic, for: .navigationBar)
    }
}
