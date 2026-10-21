import SwiftUI

struct AccessibilityHelpView: View {
    var body: some View {
        PigScreen {
            StatusNote(title: "放大文字", message: "在系统“辅助功能”中调整文字大小。放大后可继续滚动；收藏会减少每行卡片数量。", symbol: "textformat.size")
            StatusNote(title: "用读屏操作", message: "系统开启VoiceOver后，按顺序浏览按钮与状态。圆环同时提供数字和闭合文字，图表下有逐日记录。", symbol: "speaker.wave.2")
            StatusNote(title: "减少动画", message: "系统开启“减少动态效果”后，猪猪停止走动动画，文字回应继续显示。", symbol: "hand.raised")
#if os(iOS)
            StatusNote(title: "键盘操作", message: "开启系统完整键盘控制后，使用Tab移动焦点、空格激活按钮。逐项输入时Return提交、Escape取消；批量输入保留换行。也提供Command+Return应用或分析快捷键。", symbol: "keyboard")
#else
            StatusNote(title: "表冠与触控", message: "转动表冠上下滚动；横向滑动切换首页、趋势和收藏。也可从页面中的文字入口进入任务。", symbol: "digitalcrown.horizontal.arrow.clockwise")
#endif
            StatusNote(title: "暂时没有数据", message: "进入“数据与授权”检查读取及同步。未读取不等于零；不必等睡眠数据才能使用其他页面。", symbol: "tray")
            StatusNote(title: "没有采到动作", message: "模拟器没有真实加速度采集。可重试或进入有明确标记的公开模型样本；样本不写入个人记录。", symbol: "arrow.clockwise")
        }.navigationTitle(PigText.compact("操作帮助", full: "显示与操作帮助"))
    }
}

struct CompanionGuideView: View {
    var body: some View {
        PigScreen {
            StatusNote(title: "走走或休息", message: "步行时猪猪一起走，坐站时停下来，拿不准时等待。每完成一个约10秒片段再回应，不是逐秒判断。", symbol: "figure.walk")
            StatusNote(title: "按自己的节奏", message: "可选择1段或3段；随时结束。休息和不确定都不会扣奖励。动作片段不换算全天活动时长。", symbol: "pause.circle")
            StatusNote(title: "能量来自系统圆环", message: "陪伴模型不改变抽卡资格。只适用于步行与坐站，不识别跑步，也不判断健康好坏。", symbol: "flame")
            NavigationLink("模型来源与适用范围") { ModelExplanationView() }
        }.navigationTitle("陪伴玩法")
    }
}
