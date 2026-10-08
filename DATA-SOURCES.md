# 数据来源

## CAPTURE-24

- [Oxford官方入口](https://ora.ox.ac.uk/objects/uuid:99d7c092-d865-4a19-b096-cc16440cd001)
- [作者仓库](https://github.com/OxWearables/capture24)
- CC BY 4.0；原始腕部加速度100Hz，151名成年人。
- 标签使用发布者`label:Willetts2018`中的walking与sit-stand；其他动作不在模型范围内。
- 原始归档SHA256：`69740c22d3e000367988373336dc6486c10fe3f3f929811fd66e4d84861e40e2`。
- 本仓库只提供划分校验摘要，原始记录、人口属性表与个人ID清单在使用者本机生成。

## NHANES

- [CDC NHANES](https://wwwn.cdc.gov/nchs/nhanes/)
- 2011–2012、2013–2014的PAXDAY与DEMO公开文件；下载URL和SHA256见`01-lesson-1/nhanes-sleep/source-files.json`。
- 5,888名成人、19,329条合格日记录。任务是用已完成日的睡眠历史预测次日算法总睡眠是否少于420分钟，包含午睡。
- 个体数据与模型joblib均由下载、处理和训练代码在本机生成，Git不上传这些文件。

发布者原始论文、数据说明和许可优先；两个任务均不代表诊断、因果判断或儿童适用性。
