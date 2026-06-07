# Apple Watch × HealthKit 数据目录

> Pibo 的设定：**佩戴者的身体数据就是 Pibo 这个生物的食物**。这份文档回答一个工程问题——「Apple Watch 戴在手上，到底能往 HealthKit 里喂进哪些数据、iOS 端又能稳定读到哪些」，并标注每一项是**戴表就一定有**，还是**得有某种生活习惯/特定动作才会产生**。

## 0. 范围与口径

- ✅ **只算这条链路**：`Apple Watch 传感器采集 → 写入 HealthKit → iOS App 读取`。
- ❌ **不算**：iPhone 自身计步/海拔、第三方手环/体脂秤/血压计/血糖仪写入 HealthKit 的数据、用户手动输入的数据。
- 「型号依赖」基于 Apple 公开规格；具体可用性随 watchOS 版本变化，新功能往往需要较新机型 + 较新系统。开发时**永远以运行期** **`HKHealthStore`** **实际返回的样本为准**，不要假设某台表一定有某项数据。
- 所有数据 **读取都需要用户在首次授权弹窗里逐项勾选**。HealthKit 出于隐私设计，对「读权限」是**不可探测**的——`authorizationStatus` 只能告诉你「是否被拒绝写入」，**读权限被拒时查询只会返回空，不会报错**。所以「拿不到数据」和「用户没授权」在代码里长得一样，必须靠兜底逻辑区分。

***

## 1. 可得性分级（最重要的一张表）

把所有数据按「想拿到它，用户需要付出什么」分成四档。Pibo 设计能量来源时应优先吃 A 档（人人都有），把 B 档当「行为奖励」，C/D 档当「彩蛋/特定玩法」。

| 档位                  | 含义                              | 典型数据                                                                                            | 对 Pibo 的意义                         |
| ------------------- | ------------------------------- | ----------------------------------------------------------------------------------------------- | ---------------------------------- |
| **A. 戴表必有（被动）**     | 只要表戴在手上、有基本佩戴时长，系统自动产生，无需用户做任何事 | 步数、距离、活动卡路里、静息卡路里、站立时长/小时、运动分钟、爬楼层数、心率、静息心率、步行心率均值、HRV、步态指标、环境/耳机音量暴露、日照时长                      | **能量基本盘**。保证「只要戴表，Pibo 每天都有饭吃」不会饿死 |
| **B. 习惯触发（半被动/主动）** | 需要用户有某种生活习惯或主动开启一次动作才产生         | 睡眠分析（要戴着睡）、各类 Workout（跑步/骑行/游泳/徒步/攀岩/瑜伽…）、冥想/正念、VO₂max（要户外快走/跑步触发估算）、心率恢复（要有强度运动后冷却）、手腕温度（要戴着睡） | **行为奖励层**。对应建议卡 ✅「完成」加成，养成正反馈      |
| **C. 型号/场景依赖**      | 需要特定 Apple Watch 型号或特定环境才会产生    | 血氧、呼吸频率、手腕皮温、水下深度、水温、滑雪下降距离、跌倒/撞车检测                                                             | **彩蛋 / 进阶玩法**。不能作为核心能量，否则老机型用户喂不饱  |
| **D. 需主动测量（一次性会话）** | 用户必须主动打开 App 做一次测量才有            | ECG 心电图、血氧手动测量、噪声手动测量、体温计 App、用药记录、心理健康状态/情绪记录                                                  | 一般不纳入自动能量循环；可做特殊互动                 |

***

## 2. HealthKit 的四套类型系统

读数据前先理解 HealthKit 把数据分成四种「形状」，**读法完全不同**（这点直接决定 `HealthDataService` 的查询策略）：

| 类型      | Swift 类型                                                     | 形状                            | 读法                                                                             |
| ------- | ------------------------------------------------------------ | ----------------------------- | ------------------------------------------------------------------------------ |
| **数量型** | `HKQuantityType`                                             | 带单位的标量（步、bpm、kcal、℃…）         | 累加类用 `HKStatisticsQuery`（cumulativeSum）取当日总量；瞬时类用 `HKSampleQuery limit:1` 取最新值 |
| **分类型** | `HKCategoryType`                                             | 离散枚举/区间（睡眠阶段、站立小时、正念时段、心律事件…） | `HKSampleQuery` 取区间，自己累加时长或计数                                                  |
| **运动型** | `HKWorkout` / `HKWorkoutActivityType`                        | 一段带起止、类型、汇总指标的训练              | 锚定查询（anchored）增量拿「刚结束的运动」；或 `HKWorkoutType` 普通查询                               |
| **序列型** | `HKSeriesType`（`HKWorkoutRoute` / `HKHeartbeatSeriesSample`） | 一段连续轨迹/逐拍数据                   | 专用 `HKWorkoutRouteQuery` / `HKHeartbeatSeriesQuery` 分批流式读                      |

> Pibo 现有 `HealthDataService` 已经体现了这种「按 metric 选读法」的策略（见 CLAUDE.md「HealthKit observer architecture」）。新增指标时照搬对应形状的读法即可。

***

## 3. 详细数据清单（数量型 `HKQuantityType`）

标注列说明：**档位** 见 §1；**单位** 为常用读取单位；**采样** 描述数据产生的频率特性。

### 3.1 活动与能量 —— A 档，戴表必有

| 标识符                      | 中文        | 档位 | 单位     | 采样特性                   |
| ------------------------ | --------- | -- | ------ | ---------------------- |
| `stepCount`              | 步数        | A  | count  | 持续累积，全天                |
| `distanceWalkingRunning` | 步行+跑步距离   | A  | m / km | 随移动累积                  |
| `activeEnergyBurned`     | 活动卡路里     | A  | kcal   | 随活动累积（Move 环）          |
| `basalEnergyBurned`      | 静息（基础）卡路里 | A  | kcal   | 全天估算累积                 |
| `appleExerciseTime`      | 运动分钟      | A  | min    | 达到一定强度才计（Exercise 环）   |
| `appleStandTime`         | 站立时长      | A  | min    | 每小时有起身活动才计（配合 Stand 环） |
| `appleMoveTime`          | 移动时间      | A  | min    | 轮椅模式下替代 Exercise       |
| `flightsClimbed`         | 爬楼层数      | A  | count  | 气压计驱动，上楼才计             |

### 3.2 心血管 —— A 档（持续）/ B 档（需运动触发）

| 标识符                          | 中文           | 档位 | 单位        | 采样特性           |
| ---------------------------- | ------------ | -- | --------- | -------------- |
| `heartRate`                  | 心率           | A  | bpm       | 后台每数分钟一次，运动时高频 |
| `restingHeartRate`           | 静息心率         | A  | bpm       | 每天计算一个值        |
| `walkingHeartRateAverage`    | 步行心率均值       | A  | bpm       | 每天一个值          |
| `heartRateVariabilitySDNN`   | 心率变异性 (SDNN) | A  | ms        | 不定期采样（含正念时）    |
| `heartRateRecoveryOneMinute` | 运动后 1 分钟心率恢复 | B  | bpm       | 需一次有强度的运动 + 冷却 |
| `vo2Max`                     | 最大摄氧量        | B  | mL/kg·min | 需户外快走/跑步等触发估算  |

> 逐拍 RR 间期数据走**序列型** `HKHeartbeatSeriesSample`（§6），不是这里的数量型。Pibo 的 CRC 呼吸训练若要做 HRV 细算可关注它。

### 3.3 呼吸与血氧 —— C 档，型号/场景依赖

| 标识符                | 中文    | 档位 | 单位        | 说明                                        |
| ------------------ | ----- | -- | --------- | ----------------------------------------- |
| `oxygenSaturation` | 血氧饱和度 | C  | %         | 需血氧传感器机型（Series 6+，且受地区/型号销售政策影响）；后台测量需戴稳 |
| `respiratoryRate`  | 呼吸频率  | C  | count/min | 主要在**睡眠**时由表估算                            |

### 3.4 体温 —— C 档，需戴着睡

| 标识符                             | 中文     | 档位 | 单位 | 说明                                   |
| ------------------------------- | ------ | -- | -- | ------------------------------------ |
| `appleSleepingWristTemperature` | 睡眠手腕温度 | C  | ℃  | Series 8 / Ultra 及以上；需戴表入睡，给出相对基线的偏差 |
| `bodyTemperature`               | 体温     | D  | ℃  | **Apple Watch 不直接测**；来自第三方/手动，按口径不纳入 |

### 3.5 跑步动态 —— B 档，跑步 Workout 中产生

> 需要较新机型 + watchOS 9+，且数据在**跑步类 Workout 进行时**才产生。可做「跑姿/配速」类高级玩法。

| 标识符                          | 中文   | 单位  |
| ---------------------------- | ---- | --- |
| `runningSpeed`               | 跑步速度 | m/s |
| `runningPower`               | 跑步功率 | W   |
| `runningStrideLength`        | 步幅   | m   |
| `runningVerticalOscillation` | 垂直振幅 | cm  |
| `runningGroundContactTime`   | 触地时间 | ms  |

### 3.6 步态/移动健康 —— A 档（日常被动估算）

> 系统在日常步行中被动估算，常用于「步态稳定性 / 跌倒风险」。多为低频（每天若干样本）。

| 标识符                              | 中文      | 单位  |
| -------------------------------- | ------- | --- |
| `walkingSpeed`                   | 步行速度    | m/s |
| `walkingStepLength`              | 步长      | cm  |
| `walkingAsymmetryPercentage`     | 步态不对称度  | %   |
| `walkingDoubleSupportPercentage` | 双足支撑占比  | %   |
| `stairAscentSpeed`               | 上楼速度    | m/s |
| `stairDescentSpeed`              | 下楼速度    | m/s |
| `sixMinuteWalkTestDistance`      | 六分钟步行距离 | m   |

### 3.7 专项运动距离 —— B 档，对应 Workout 时产生

| 标识符                          | 中文     | 单位    | 触发                       |
| ---------------------------- | ------ | ----- | ------------------------ |
| `distanceCycling`            | 骑行距离   | km    | 骑行 Workout               |
| `distanceSwimming`           | 游泳距离   | m     | 游泳 Workout               |
| `swimmingStrokeCount`        | 游泳划水次数 | count | 游泳 Workout               |
| `distanceDownhillSnowSports` | 滑雪下降距离 | km    | C 档，Series 5+ 滑雪 Workout |
| `underwaterDepth`            | 水下深度   | m     | C 档，Ultra/Series 6+ 潜水   |
| `waterTemperature`           | 水温     | ℃     | C 档，同上                   |

### 3.8 环境暴露 —— A 档，被动

| 标识符                          | 中文     | 单位     | 说明          |
| ---------------------------- | ------ | ------ | ----------- |
| `environmentalAudioExposure` | 环境噪声暴露 | dBASPL | 后台持续监测      |
| `headphoneAudioExposure`     | 耳机音量暴露 | dBASPL | 连蓝牙耳机播放时    |
| `timeInDaylight`             | 日照时长   | min    | 环境光估算，户外才累积 |

### 3.9 主观/努力度 —— D 档，多为主动或派生

| 标识符                           | 中文      | 说明                  |
| ----------------------------- | ------- | ------------------- |
| `physicalEffort`              | 体力消耗强度  | 部分派生，非 Watch 直采     |
| `workoutEffortScore`          | 运动努力分   | 用户主观录入（watchOS 11+） |
| `estimatedWorkoutEffortScore` | 估算运动努力分 | 系统估算                |

***

## 4. 分类型数据（`HKCategoryType`）

| 标识符                         | 中文           | 档位 | 形状      | 说明                                                                                                 |
| --------------------------- | ------------ | -- | ------- | -------------------------------------------------------------------------------------------------- |
| `sleepAnalysis`             | 睡眠分析         | B  | 区间 + 阶段 | 需**戴表入睡**。区间含 inBed / asleepUnspecified / asleepCore / asleepDeep / asleepREM / awake。Pibo「精力」核心来源 |
| `mindfulSession`            | 正念/冥想时段      | B  | 时间区间    | 来自「正念」App / 呼吸训练。Pibo「心情」加成来源                                                                      |
| `appleStandHour`            | 站立小时         | A  | 离散事件    | 每小时是否起身（Stand 环的小时计数）                                                                              |
| `highHeartRateEvent`        | 高心率事件        | A  | 事件      | 静息时心率超阈值                                                                                           |
| `lowHeartRateEvent`         | 低心率事件        | A  | 事件      | 低于阈值                                                                                               |
| `irregularHeartRhythmEvent` | 不规则心律（疑房颤）事件 | C  | 事件      | 需开启心律不齐通知                                                                                          |
| `lowCardioFitnessEvent`     | 心肺适能偏低事件     | B  | 事件      | VO₂max 持续偏低时                                                                                       |
| `handwashingEvent`          | 洗手事件         | A  | 事件      | 检测到洗手动作                                                                                            |

> ⚠️ 睡眠/正念是「半被动」：表能采，但用户得养成**戴着睡 / 主动冥想**的习惯才有数据——这正好契合 Pibo「养成」叙事，适合做建议卡。

***

## 5. 运动型数据（`HKWorkout` + `HKWorkoutActivityType`）

一次 Workout = 一段带 `activityType`、起止时间、汇总指标（总距离、总能量、平均心率）的训练记录。Apple Watch 的「体能训练」App 及第三方运动 App 都会写入。

### 5.1 常见活动类型（`HKWorkoutActivityType`）

Apple Watch 支持 **80+ 种** 运动类型，常见的有：

- 有氧：`running`、`walking`、`hiking`、`cycling`、`elliptical`、`rowing`、`stairClimbing`
- 水上：`swimming`（含泳池/开放水域子类）、`waterFitness`、`paddleSports`
- 力量/综合：`traditionalStrengthTraining`、`functionalStrengthTraining`、`crossTraining`、`highIntensityIntervalTraining`(HIIT)
- 攀爬：`climbing`（攀岩/攀爬）
- 身心：`yoga`、`pilates`、`mindAndBody`、`coreTraining`、`flexibility`、`taiChi`
- 球类：`basketball`、`soccer`、`tennis`、`badminton`、`tableTennis`、`golf`…
- 冬季：`downhillSkiing`、`crossCountrySkiing`、`snowboarding`
- 兜底：`other`（任何未归类训练）

> 完整枚举见 Apple 文档，约 80 项。Pibo 不必逐一适配——只需把 `activityType` 映射到几个**能量大类**（耐力/力量/身心/户外）即可。

### 5.2 一次 Workout 能直接读到的指标

| 字段                                   | 内容                                                           |
| ------------------------------------ | ------------------------------------------------------------ |
| `workoutActivityType`                | 运动类型                                                         |
| `duration` / `startDate` / `endDate` | 时长与起止                                                        |
| `totalDistance`                      | 总距离（适用类型）                                                    |
| `totalEnergyBurned`                  | 总活动能量                                                        |
| `statistics(for:)`                   | 该段内某 quantity 的统计（如平均/最大心率）                                  |
| `metadata`                           | 平均速度、室内/室外、天气、海拔等键值                                          |
| `workoutEvents`                      | **lap（圈）/ segment（分段）/ pause / resume** 标记——「分段跑」的载体（需录制时写入） |

> 「每公里配速 / 分段跑」HealthKit **没有现成字段**：要么读 `workoutEvents` 里的 lap 标记，要么从 `HKWorkoutRoute` 的 GPS 点或 distance 时间序列自己切公里算。两者都依赖跑步当时被完整记录（户外、有 GPS）。

***

## 6. 序列型数据（`HKSeriesType`）

| 类型                        | 内容                                                      | 读法                         | 用途                        |
| ------------------------- | ------------------------------------------------------- | -------------------------- | ------------------------- |
| `HKWorkoutRoute`          | 一次户外 Workout 的 GPS 轨迹，逐点 `CLLocation`（经纬度、时间戳、speed、海拔） | `HKWorkoutRouteQuery` 分批流式 | 自行计算每公里配速、爬升、轨迹图          |
| `HKHeartbeatSeriesSample` | 逐拍心跳间期（RR/IBI）序列                                        | `HKHeartbeatSeriesQuery`   | 精细 HRV、呼吸耦合（与 CRC 呼吸训练相关） |

***

## 7. 技术要点（接入时必看）

1. **授权**：首次启动一次性 `requestAuthorization(toShare:read:)` 把所有要读的类型一起请求。读权限**不可探测**——查询返回空时无法区分「没数据」还是「没授权」，需 UI 兜底引导用户去「健康」App 检查。
2. **后台投递**：`enableBackgroundDelivery(for:frequency:)` + `HKObserverQuery` 让 Watch 同步新数据时唤醒 iOS App。频率上限受系统约束（多数 `.immediate` 实际是分钟级，并非真正实时）。Watch 的数据**不是实时流**，而是**事后批量同步**到 iPhone 的 HealthKit（息屏/充电时同步更积极）。
3. **读策略按形状选**（见 §2）：累加量用 `HKStatisticsQuery`，瞬时值用 `limit:1` 取最新，运动用锚定增量查询，序列用专用 query。
4. **单位**：每个 quantity 有规定单位族，读写都要显式 `HKUnit`，别假设默认单位（如距离别默认米/千米，心率用 `count/min`）。
5. **去重与来源**：同一指标可能有多个 `HKSource`（表、手机、第三方 App）。若严格「只要 Watch」，可用 `HKQuery.predicateForObjects(from:)` 按 `HKSource`/`HKSourceRevision` 过滤，但通常按系统优先级聚合即可。
6. **延迟与补偿**：数据可能延迟数分钟到数十分钟到达。前台 `scenePhase == .active` 时做一次 `reconcile()` 兜底补算，是必须的（Pibo 已采用）。
7. **隐私文案**：`Info.plist` 需 `NSHealthShareUsageDescription`（读）；写入才需 `NSHealthUpdateUsageDescription`。Pibo 只读，前者即可。

***

## 8. 映射到 Pibo 三维能量（建议）

> 与 PRD v0.7 三维公式对齐（`StatKind` = vitality / energy / mood，UI 星光化）。粗体为已在用，其余为可扩展的「加料」来源。

| Pibo 维度                 | A 档基本盘                                   | B 档行为奖励                       | 可选 C 档彩蛋                 |
| ----------------------- | ---------------------------------------- | ----------------------------- | ------------------------ |
| **✦ 活力**（vitality / 体力） | **步数 · 运动分钟 · 活动卡路里 · 站立时长** · 爬楼 · 步行距离 | 各类 Workout 完成 · 跑步动态 · VO₂max | 滑雪/潜水等户外专项               |
| **☾ 静息**（energy / 精力）   | （睡眠为主，见右）                                | **睡眠总时长 · 深睡 · REM** · 心率恢复   | 睡眠手腕温度 · 睡眠呼吸频率          |
| **❤️ 心绪**（mood / 心情）    | **HRV · 心率稳定度** · 静息心率趋势                 | **正念/冥想时段** · 深呼吸             | 血氧 · 逐拍 HRV 序列（CRC 呼吸训练） |

设计原则：**核心能量只吃 A 档**保证人人喂得饱；**B 档对应建议卡 ✅ 加成**强化养成正反馈；**C 档做彩蛋**，绝不让老机型用户因为缺血氧/皮温而饿死 Pibo。

***

## 参考

- [HKQuantityTypeIdentifier — Apple Developer](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier)
- [HealthKit Data Types — Apple Developer](https://developer.apple.com/documentation/healthkit/data-types)
- [HKCategoryTypeIdentifier — Apple Developer](https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier)
- [HKWorkout / HKWorkoutActivityType — Apple Developer](https://developer.apple.com/documentation/healthkit/hkworkout)
- [HKWorkoutRoute — Apple Developer](https://developer.apple.com/documentation/healthkit/hkworkoutroute)
- [HKWorkoutEvent（lap / segment）— Apple Developer](https://developer.apple.com/documentation/healthkit/hkworkoutevent)
- [HKHeartbeatSeriesSample — Apple Developer](https://developer.apple.com/documentation/healthkit/hkheartbeatseriessample)

