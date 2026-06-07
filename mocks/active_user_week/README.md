# Mock：爱运动用户的一周 HealthKit 数据

模拟一个规律健身用户「阿凯」一周（**2026-06-01 周一 ~ 06-07 周日**）通过 Apple Watch 写入 HealthKit、iOS 端能读到的数据。口径与 [`docs/health-data/apple-watch-healthkit-data-catalog.md`](../../docs/health-data/apple-watch-healthkit-data-catalog.md) 一致：**只含手表采集的数据**，不含手机/第三方/手动输入。

- `active_user_week.jsonl` —— 主数据，552 条，一行一条记录，按 `start` 时间排序。
- `generate.py` —— 生成器（固定随机种子 `20260601`，可复现）。改训练计划重跑即可。

## 人物画像

> 阿凯，28 岁，静息心率 ~50bpm，VO₂max ~48，HRV 基线 ~65ms，戴表入睡。

| 日期 | 主训练 | 步数 | 距离km | 活动kcal | 运动min | 爬楼 | 训练心率 |
|---|---|---|---|---|---|---|---|
| 周一 06-01 | 晨跑 8km（变速，含每公里 lap） | 16800 | 12.1 | 720 | 58 | 9 | 151–178 |
| 周二 06-02 | 力量训练 52min | 9600 | 6.9 | 560 | 54 | 6 | 125–155 |
| 周三 06-03 | 骑行 35km | 8200 | 5.9 | 810 | 82 | 4 | 141–169 |
| 周四 06-04 | 恢复日·瑜伽+2 次冥想 | 11200 | 8.1 | 380 | 41 | 7 | 94–112 |
| 周五 06-05 | HIIT 25min | 12400 | 8.9 | 610 | 38 | 8 | 154–179 |
| 周六 06-06 | 越野徒步 15km（爬升 720m） | 24600 | 17.7 | 1280 | 168 | 41 | 119–157 |
| 周日 06-07 | 游泳 1500m + 散步 + 冥想 | 7800 | 5.6 | 520 | 47 | 3 | 132–157 |

每天另含：睡眠分阶段（core/deep/REM/awake）、夜间呼吸频率/手腕温度/血氧、静息心率、步行心率均值、晨间 HRV、全天散点心率、站立小时、环境噪声、日照时长。VO₂max 周一/周五各一次；运动后心率恢复随每次训练给出。

## 记录 Schema

每条记录是一个扁平 JSON 对象，按 `sampleClass` 分四种形状（对应 HealthKit 的四套类型系统）。

**通用字段**

| 字段 | 说明 |
|---|---|
| `type` | HealthKit 标识符，如 `stepCount` / `heartRate` / `sleepAnalysis` / `workout` |
| `sampleClass` | `quantity` \| `category` \| `workout` |
| `start` / `end` | ISO8601 带时区（`+08:00`）。累计型 start=当日 00:00 end=23:59；瞬时型 start=end |
| `source` | 数据来源（统一 `Apple Watch Series 9`） |
| `tier` | 可得性分级 `A`/`B`/`C`：戴表必有 / 习惯触发 / 型号依赖（见数据目录文档 §1） |
| `context` | 可选，标注采样场景：`morning` / `sleep` / `workout` / `mindful` / `outdoor-workout` |

**1. quantity（数量型）** —— 带 `value` + `unit`
```json
{"type":"stepCount","sampleClass":"quantity","value":16800,"unit":"count",
 "start":"2026-06-01T00:00:00+08:00","end":"2026-06-01T23:59:00+08:00",
 "source":"Apple Watch Series 9","tier":"A"}
```

**2. category（分类型）** —— `value` 为枚举字符串
```json
{"type":"sleepAnalysis","sampleClass":"category","value":"asleepDeep",
 "start":"2026-06-01T00:18:00+08:00","end":"2026-06-01T01:02:00+08:00",
 "source":"Apple Watch Series 9","tier":"B"}
```
`sleepAnalysis` 取值：`inBed` / `asleepCore` / `asleepDeep` / `asleepREM` / `awake`。
其余：`appleStandHour=stood`、`mindfulSession=session`。

**3. workout（运动型）** —— 一段训练的汇总，含 `metadata`，跑步日含 `laps`
```json
{"type":"workout","sampleClass":"workout","activityType":"running",
 "start":"2026-06-01T06:30:00+08:00","end":"2026-06-01T07:16:00+08:00",
 "durationSec":2760,"totalDistance_m":8000,"totalEnergyBurned_kcal":545,
 "avgHeartRate_bpm":156,"maxHeartRate_bpm":181,"source":"Apple Watch Series 9","tier":"B",
 "metadata":{"indoor":false,"weather":"晴 21℃","elevationAscended_m":78,
             "avgPace":"5:45/km","heartRateRecoveryOneMinute_bpm":32},
 "laps":[{"lap":1,"start":"...","end":"...","distance_m":1000,"pace":"5:43/km","avgHR_bpm":150}, ...]}
```
跑步日（周一）另带逐段 **跑步动态** 样本（`runningSpeed` / `runningPower` / `runningStrideLength` / `runningVerticalOscillation` / `runningGroundContactTime`），每 2 分钟一条。

## 怎么用

- 喂给 `PetStateStore` 的 PRD 公式做端到端验证：累计型直接对应「步数/运动分钟/活动卡路里」(体力)、`sleepAnalysis` 各阶段时长 → 精力、`heartRateVariabilitySDNN` + `mindfulSession` → 心情。
- 验证「建议卡自动翻牌」：`workout` / `mindfulSession` / `sleepAnalysis` 记录到达时应自动勾选对应建议卡。
- 验证日切换 / 衰减：7 天连续数据可直接驱动 `checkDayRollover` → `applyDecayCatchup`。
- 想造「久坐 / 不运动」对照组：复制 `generate.py`，把 PLAN 里的 workout 改 None、调低 steps/exercise 即可。

```bash
# 重新生成
cd mocks/active_user_week && python3 generate.py

# 快速浏览某天某类型
grep '"2026-06-06' active_user_week.jsonl | grep '"workout"'
```
