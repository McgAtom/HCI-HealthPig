import SwiftUI

struct HealthReadStateView: View {
    @ObservedObject var health: HealthReader
    var body: some View {
        if health.loading { ProgressView("读取中…").accessibilityIdentifier("health.loading") }
        else if !health.error.isEmpty {
            PigPanel {
                StatusNote(title: "读取未完成", message: "检查授权与同步后重试。", symbol: "exclamationmark.triangle")
                Button("重试读取") { Task { await health.refresh() } }.accessibilityIdentifier("health.retry")
                NavigationLink("检查数据与授权") { HealthRecordView(health: health) }
            }
        }
    }
}
