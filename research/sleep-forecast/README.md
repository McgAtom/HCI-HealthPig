# 当晚主睡眠时长预测 · 校园数据实验

本实验学习的是保持过往行为时，当晚主要一段睡眠的设备估计时长。20:00 为数据截点，只用过去七个当地日内已经结束的夜晚，至少需要三晚。原生端也仅使用这些已结束的记录。第二天最晚起床时间和想达到的作息由用户设置，作息安排与闹钟仍使用这些目标。

## 数据与方法

- NetHealth v1 的睡眠、活动 CSV 共约 56 MB，由发布页的 MD5 校验。以 `dataDate` 作记录结束日，按时钟是否跨午夜重建起点，剔除时钟差与卧床分钟不一致超过 61 分钟的记录。表没有主睡标记，因此在当地晚 20:00 至次日中午的窗内，选结束日在当天、开始在早 06:00 前、实睡 180–720 分钟的最长记录。UVA 使用数据内主睡标记，并用同一时间与时长条件。两队列公开的边界属于 Fitbit 日志。Apple HealthKit 提供睡眠阶段区间，计时边界会有测量差异。 [NetHealth v1](https://zenodo.org/records/21904040) · [NetHealth 采集字段](https://conferences.computer.org/COMPSAC2020/pdfs/COMPSAC2020-7r2yh3mCdmuNATjWZbeuiI/730300a545/730300a545.pdf) · [UVA 数据与学术使用授权](https://github.com/HAI-lab-UVA/Human-Rhythms-Dataset/tree/3fe83300ca9726a1ff6755d235347bc63a976022)
- NetHealth 共 333,708 行睡眠日志，经过筛选后有 619 人的 271,240 晚。满足近七天最少记录数后，按人分成训练 364 人、模型选择 61 人、区间校准 61 人、封存测试 122 人；另 11 人的记录不满足历史要求。UVA 读取固定版本的 161 份概要文件，共 35,446 行。筛选和历史要求后，得到 160 人的 26,031 个外测夜晚。训练内的人也不会出现在 NetHealth 验证或测试中，逐夜构造特征时只查目标日前七天。
- 特征包含历史时长中位数、均值、波动、近两晚平均、最近一晚、时钟中位数、记录数、最近记录间隔和次晨是否为周末。比较近七晚中位数、Ridge 与 70 棵深度最多 3 的梯度提升树。NetHealth 选择集 MAE 分别为 66.96、63.96、63.54 分钟，据此选梯度提升树。在独立校准人群按绝对残差第 80 百分位得到 ±98 分钟，再在保留集与 UVA 检查覆盖率。

## 结果

| 样本 | 参与者／夜数 | 七日中位数 MAE | 提升树 MAE | MAE 改善及 95% CI | 原始预测区间覆盖 |
| --- | ---: | ---: | ---: | ---: | ---: |
| NetHealth 留出 | 122／50,628 | 67.15 分 | 63.26 分 | 3.89 分 [3.45, 4.32] | 78.3% |
| UVA 外部验证 | 160／26,031 | 60.74 分 | 58.05 分 | 2.68 分 [2.29, 3.08] | 81.8% |

差值的置信区间用同一夜两模型的成对误差，并按参与者重采样 1,000 次。UVA 平均高估 6.70 分。NetHealth 同一批 46,844 个可配对留出夜中，添加最近一个完整日的步数、中高强度活动分钟与平均心率，MAE 由 62.98 变为 62.96 分钟。原生版本采用睡眠历史模型。当前主要边界包括 Fitbit 到 Apple Watch 的设备迁移、当晚已提前入睡或低于三小时的覆盖，以及新计划对实际睡眠的效果。分钟误差和区间宽度不足以用预测自动触发闹钟。

## 复现

在工作区根目录执行以下命令。使用 Python 3.11 与本目录依赖，已有虚拟环境时可直接使用。下载约 59 MB，原始记录与运行缓存均在 Git 忽略目录内。输出保存按参与者划分的聚合指标与模型参数。

```sh
python3.11 -m venv .venv
.venv/bin/python -m pip install -r research/sleep-forecast/requirements.txt
.venv/bin/python research/sleep-forecast/download.py all
.venv/bin/python research/sleep-forecast/train.py --output research/sleep-forecast/runs/reproduction
```

训练入口不覆盖已有输出目录。训练权重约 38 KB，原生资源 `Resources/sleep-forecast.json`。双端在「睡眠计划 → 推荐依据」展示向外取整到 15 分钟的「沿用作息 · 实睡预测」。记录不足时保留已有的作息入口。核心检查用合成睡眠记录逐项核对 Python 特征和预测值与 Swift 一致，测试包含跨午夜、目标夜排除、缺数及区间取整。 [指标文件](results.json)

## 睡眠输入的置换重要性

在 iPhone 的「判断 → 睡眠」可查五项代表输入及全部十项。分数为打乱一个输入后平均绝对误差的增加量，单位是分钟。模型与目标值固定，在 UVA 同一批 160 人、26,031 晚上逐列打乱，每项 40 次，种子为 20261120。条形和圆点是平均增加，细线是 40 次的最小至最大。跨参与者置换会产生平常少见的组合，相关的历史时长均值与中位数也可能相互替代。指标刻画整批样本中的模型依赖。

原始误差为 58.054096 分钟。近七天平均实睡时长贡献最高，打乱后误差增加 3.1629 分钟；时长中位数增加 1.2747 分钟，次晨是否为周末增加 0.6238 分钟。原生睡眠预测使用近期睡眠历史和次晨日历，步数和心率仍用于各自的健康记录。正式作息和闹钟继续依据用户设置与时间约束。

复算只需下载 UVA 睡眠概要，然后直接加载部署权重：

```sh
.venv/bin/python research/sleep-forecast/download.py uva
.venv/bin/python research/sleep-forecast/compute_importance.py \
  --model apps/healthpig-watch/native-app/Resources/sleep-forecast.json \
  --uva research/sleep-forecast/data/uva-sleep \
  --output /tmp/healthpig-sleep-insights.json
```

公开 GitHub 路径中的应用目录为 `apps/healthpig-native/`。复算默认输出汇总数据。课程工程另展示两条去标识的夜晚记录，按绝对误差不超过 30 分钟与至少 90 分钟分组，分别选取组内偏差居中的一晚。
