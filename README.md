# 走走猪猪 · 人机交互课程项目

走走猪猪是 iOS 与 watchOS 的健康陪伴应用。用户在腕上计步陪走、看睡眠计划，也能在手机上查看健康记录和动作模型的判断依据。

## 当前原生双端入口

[原生工程 0.8.15](apps/healthpig-native/HealthPigNative.xcodeproj)可用 Xcode 打开。iPhone 选择 `HealthPigPhone`，Apple Watch 选择 `HealthPigWatch`。随包提供模型参数和图表数据，可直接运行。 [原生应用说明](apps/healthpig-native/README.md)

历史目录保留原始模型实验与早期手表代码。公开Git记录实际导出时间，不用补造的提交日期代替早期本地迭代证据。

## 作业四 · 模型判断

iPhone 底栏「判断」展示腕部动作分类器使用的特征。首屏有五项代表输入，点击条形可查验证集分布和样本量。固定 CAPTURE-24 验证集包含 30 人、12,993 个窗口，基线平衡准确率为 85.3261%。24 项特征各置换 40 次，平均偏差的分数下降最多，为 42.69 个百分点。图表保留零线、负值和重复置换的范围。 [计算代码](04-model-insights/code/compute_importance.py) · [汇总数据](apps/healthpig-native/Resources/model-insights.json) · [复现说明](REPRODUCE.md#作业四模型判断)

「判断 → 睡眠」展示实睡时长预测的十项输入及置换影响。UVA 外部验证基线误差为 58.05 分钟，打乱近七天平均实睡时长后误差增加最多，为 3.16 分钟。 [训练与结果](research/sleep-forecast/README.md#睡眠输入的置换重要性)

## 历史内容

- `01-lesson-1/watch-pig-live/`：SwiftUI 手表应用，约10秒真实加速度采集、本地步行／坐站识别、HealthKit只读记录和每日装饰。
- `01-lesson-1/capture24-walking/`：CAPTURE-24处理、24特征、逻辑回归与随机森林训练，附已运行的汇总指标。
- `01-lesson-1/nhanes-sleep/`：供公平性实验复用的NHANES睡眠历史模型。
- `02-fairness/`：Fairlearn MetricFrame审核、EqualizedOdds约束实验和可运行的审核页面。

## 运行手表应用

用Xcode打开 `01-lesson-1/watch-pig-live/HealthPig.xcodeproj`，选择自己的开发团队，设置唯一的Bundle Identifier，连接已开启开发者模式的手表。当前工程最低watchOS版本为27.0；安装者自行决定健康读取授权。

顶部运行目标选择实际Apple Watch；`Any watchOS Device`只能构建，不能启动。若Xcode提示解锁设备，在手表上解锁后继续运行。Mac本地预览需要另行安装watchOS模拟器运行时。

共享HealthPig方案的普通Run不等待调试器，适合安装和演示。若需断点，在Product → Scheme → Edit Scheme → Run → Info勾选“Debug executable”；“Waiting to attach”表示调试连接尚未完成。

应用已包含实际训练的轻量模型，无须先下载训练数据。HealthKit展示已有心率、睡眠和步数；这些记录不参与本次动作分类。健康数据只在设备本地处理。

## 历史公平性网页（冻结原型）

```sh
python3 -m http.server 8782 --bind 127.0.0.1 --directory 02-fairness/prototype
```

打开 `http://127.0.0.1:8782` 仅用于重放历史原型。当前公平性审核在原生双端应用中，网页数据是历史公开实验群体汇总，无个体记录。

模型与数据复现见 [REPRODUCE.md](REPRODUCE.md)，过程记录见 [CHANGELOG.md](CHANGELOG.md)。

## 实验范围

CAPTURE-24有151名成年人、68,687个合格窗口，按人分为90/30/31。部署逻辑回归的离线准确率86.04%、平衡准确率84.25%、步行召回率81.76%，精确率50.78%；多数类准确率85.67%。最初验证规则选择随机森林，测试准确率84.60%；后来部署已冻结的逻辑回归时测试结果已可见。设备迁移准确率尚未量化，模型分数不是正确率保证。

公平性实验沿用另一阶段的NHANES睡眠模型，和手表动作模型是两个独立任务。约束方案在验证集未达到推荐替换条件；测试性别EO差值0.0606→0.0523，但Bootstrap区间包含0，不能据此断言可靠改善。

## 仓库范围

公开版本保存代码、模型参数、实验计划、公开数据来源与汇总结果。个人照片、演示原片、健康记录、用户测试资料、学校身份信息、开发账号配置和完整实验数据均保留在本地。

克隆后可启用本地提交与推送检查：`git config core.hooksPath .githooks`。远端也运行公开文件检查。

代码和模型用于课程学习，不作为医疗诊断依据。数据归原发布者，来源及许可见 [DATA-SOURCES.md](DATA-SOURCES.md)。
