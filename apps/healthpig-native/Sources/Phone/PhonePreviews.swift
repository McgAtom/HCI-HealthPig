import SwiftUI

#Preview("今日 · 初始状态") {
    let store = PigStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("HealthPigDesignPreview"))
    NavigationStack { PhoneTodayView(store: store, health: HealthReader()) }
        .preferredColorScheme(.dark).tint(PigTheme.rose)
}

#Preview("独立审核入口") {
    NavigationStack { AuditCatalogView() }.preferredColorScheme(.dark).tint(PigTheme.rose)
}
