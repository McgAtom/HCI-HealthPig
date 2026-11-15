import SwiftUI

#Preview("今日 · 无健康记录") {
    let store = PigStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("HealthPigDesignPreview"))
    NavigationStack {
        WatchTodayView(store: store, health: HealthReader(), walk: PigWalk())
            .navigationTitle("走走猪猪")
    }.preferredColorScheme(.dark).tint(PigTheme.rose)
}

#Preview("今日 · 大字体") {
    let store = PigStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("HealthPigDesignPreview"))
    NavigationStack { WatchTodayView(store: store, health: HealthReader(), walk: PigWalk()).navigationTitle("走走猪猪") }
        .environment(\.dynamicTypeSize, .accessibility1)
        .preferredColorScheme(.dark).tint(PigTheme.rose)
}
