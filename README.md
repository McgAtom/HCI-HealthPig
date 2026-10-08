# 走走猪猪 · 人机交互课程项目

用 Apple Watch 的真实动作数据驱动猪猪，完成健康主题课程中的模型训练、交互设计与公平性分析。

## 内容

- `01-lesson-1/watch-pig-live/`：SwiftUI 手表应用，约10秒真实加速度采集、本地步行／坐站识别、HealthKit只读记录和每日装饰。
- `01-lesson-1/capture24-walking/`：CAPTURE-24处理、24特征、逻辑回归与随机森林训练，附已运行的汇总指标。
- `01-lesson-1/nhanes-sleep/`：供公平性实验复用的NHANES睡眠历史模型。
- `02-fairness/`：Fairlearn MetricFrame审核、EqualizedOdds约束实验和可运行的审核页面。

## 运行手表应用

用Xcode打开 `01-lesson-1/watch-pig-live/HealthPig.xcodeproj`，选择自己的开发团队，设置唯一的Bundle Identifier，连接已开启开发者模式的手表。当前工程最低watchOS版本为27.0；安装者自行决定健康读取授权。

应用已包含实际训练的轻量模型，无须先下载训练数据。HealthKit展示已有心率、睡眠和步数；这些记录不参与本次动作分类。健康数据只在设备本地处理。

## 查看公平性页面

```sh
python3 -m http.server 8782 --bind 127.0.0.1 --directory 02-fairness/prototype
```

打开 `http://127.0.0.1:8782`。页面数据是公开数据实验的群体汇总，无个体记录。

模型与数据复现见 [REPRODUCE.md](REPRODUCE.md)，过程记录见 [CHANGELOG.md](CHANGELOG.md)。

## 实验范围

CAPTURE-24有151名成年人、68,687个合格窗口，按人分为90/30/31。部署逻辑回归的离线准确率86.04%、平衡准确率84.25%、步行召回率81.76%，精确率50.78%；多数类准确率85.67%。最初验证规则选择随机森林，测试准确率84.60%；后来部署已冻结的逻辑回归时测试结果已可见。设备迁移准确率尚未量化，模型分数不是正确率保证。

公平性实验沿用另一阶段的NHANES睡眠模型，和手表动作模型是两个独立任务。约束方案在验证集未达到推荐替换条件；测试性别EO差值0.0606→0.0523，但Bootstrap区间包含0，不能据此断言可靠改善。

## 仓库范围

公开版本保存代码、模型参数、实验计划、公开数据来源与汇总结果。个人照片、演示原片、健康记录、用户测试资料、学校身份信息、开发账号配置和完整实验数据均保留在本地。

克隆后可启用本地提交与推送检查：`git config core.hooksPath .githooks`。远端也运行公开文件检查。

代码和模型用于课程学习，不作为医疗诊断依据。数据归原发布者，来源及许可见 [DATA-SOURCES.md](DATA-SOURCES.md)。
