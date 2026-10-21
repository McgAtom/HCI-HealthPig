import SwiftUI

// Original visual system; researched applications informed task structure, not copied UI code.
enum PigTheme {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.075)
    static let panel = Color(red: 0.115, green: 0.105, blue: 0.135)
    static let rose = Color(red: 1, green: 0.67, blue: 0.73)
    static let mint = Color(red: 0.64, green: 0.87, blue: 0.76)
    static let cream = Color(red: 1, green: 0.92, blue: 0.81)
    static func color(for series: String) -> Color {
        switch series {
        case "点心铺": return rose
        case "秘密花园": return mint
        case "天气收藏": return Color(red: 0.69, green: 0.8, blue: 1)
        default: return Color(red: 0.83, green: 0.73, blue: 1)
        }
    }
}

enum PigText {
    static func compact(_ short: String, full: String) -> String {
#if os(watchOS)
        short
#else
        full
#endif
    }
}

struct PigArtwork: View {
    let card: PigCard
    var size: CGFloat = 140
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [PigTheme.color(for: card.series).opacity(0.24), .clear], center: .center, startRadius: 8, endRadius: size * 0.52))
            Image(card.assetName).resizable().scaledToFit().padding(size * 0.035)
        }
        .frame(maxWidth: .infinity).frame(height: size)
        .accessibilityElement(children: .ignore).accessibilityLabel(card.name)
    }
}

struct PigPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).background(PigTheme.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct PigScreen<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: screenSpacing) { content }
#if os(watchOS)
                .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 32)
#else
                .padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
#endif
        }
        .background(PigTheme.background)
    }
    private var screenSpacing: CGFloat {
#if os(watchOS)
        12
#else
        16
#endif
    }
}

struct PigPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
#if os(watchOS)
        configuration.label.font(.headline).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity).padding(.horizontal, 10).padding(.vertical, 10).frame(minHeight: 44)
            .foregroundStyle(PigTheme.background)
            .background(PigTheme.rose.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
            .contentShape(Capsule())
#else
        configuration.label.font(.headline).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 14).frame(minHeight: 44)
            .foregroundStyle(PigTheme.background)
            .background(PigTheme.rose.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
            .contentShape(Capsule())
#endif
    }
}

struct StatusNote: View {
    let title: String
    let message: String
    var symbol = "info.circle"
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text(message).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

struct StoreErrorView: View {
    @ObservedObject var store: PigStore
    var body: some View {
        if !store.error.isEmpty {
            PigPanel {
                StatusNote(title: "记录需要处理", message: store.error, symbol: "exclamationmark.triangle")
                Button("重新读取本机记录") { store.reload() }
                if store.canRestoreBackup { Button("恢复上一份本机备份") { store.restoreBackup() } }
            }
        } else if !store.notice.isEmpty {
            Label(store.notice, systemImage: "checkmark.circle").font(.caption).foregroundStyle(PigTheme.mint)
        }
    }
}

// A deterministic layout check only in Debug; normal use follows system Dynamic Type.
struct PigAccessibilityTestSize: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--large-text-check") {
            content.environment(\.dynamicTypeSize, .accessibility3)
        } else { content }
#else
        content
#endif
    }
}
