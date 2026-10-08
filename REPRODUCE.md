# 运行与复现

在仓库根目录建立Python环境：

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r 02-fairness/requirements.txt -r 01-lesson-1/nhanes-sleep/requirements.txt
```

## 动作模型

从DATA-SOURCES中的Oxford入口获取完整归档，放到`01-lesson-1/stress-study/data/raw/capture24/capture24.zip`（约6.9GB）。

```sh
.venv/bin/python 01-lesson-1/capture24-walking/setup_capture24.py
.venv/bin/python 01-lesson-1/capture24-walking/prepare.py
.venv/bin/python 01-lesson-1/capture24-walking/train.py
```

setup从归档提取必要的标签字典，并用已保存的划分摘要在本地恢复原划分；原始ID不发布。prepare生成本机共享CSV与数值一致性核对窗口。训练脚本首次可在默认目录运行，重复运行必须使用新的`--output-dir`，不覆盖已有指标。原始计划对部分特征方向不变性的表述过强：单轴标准差最小／最大值仍受佩戴方向影响。

手表已经自带原部署模型。复训不会自动替换它；`export_deployed.py`重导出原冻结逻辑回归，需先有对应的训练结果与数值核对文件。新的候选应另建实验计划，不能继续根据已披露的测试结果选方案。

## 睡眠基线与公平性

```sh
.venv/bin/python 01-lesson-1/nhanes-sleep/download_data.py
.venv/bin/python 01-lesson-1/nhanes-sleep/train.py
.venv/bin/python 02-fairness/run_experiment.py --verify-only
.venv/bin/python 02-fairness/run_experiment.py
.venv/bin/python 02-fairness/verify_results.py
```

NHANES训练会生成Fairlearn所需的共享CSV、划分和基线模型。公平性代码检查冻结的文件SHA256，哈希不一致时停止，不能将另一基线冒充原实验；库版本及序列化差异可能影响模型文件字节。公平性运行拒绝覆盖，复跑使用新的`--run-id`。

审核页已有原实验的群体汇总，可独立启动。正式报告、个人安装验证和同学测试材料不在公开仓库。
