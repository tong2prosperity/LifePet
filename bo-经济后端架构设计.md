# bo 经济系统 · 前后端交互与后台架构设计（MVP）

> 起草：2026-06-29 · 刘通 × Claude 共创
> 状态：✅ 架构决策已对齐，待开工
> 范围：本文覆盖 ①前后端交互架构 ②后台技术选型与理由 ③与 auth_service 的对账绑定 ④MVP 核心交互（Sync）⑤最小事件表 Schema ⑥分阶段路线图。**不含**部署方案（按约定暂缓）。
> 关联文档：`数值系统.xlsx`（bo 产出曲线 / 价目 / 改动边界）、`product-web-prototype/pibo-home-features-spec.md`。

---

## 0. 决策摘要（一眼看全）

| # | 议题 | 结论 |
|---|---|---|
| 1 | 平台 | iOS + 鸿蒙 双端，后台平台无关（REST） |
| 2 | 部署耦合 | bo 经济后台与 auth_service **嵌入同一个 Go 二进制** |
| 3 | 接口风格 | bo 业务接口走**普通 REST/JSON**；鉴权复用 auth 的 JWT |
| 4 | MVP 切片 | 健康事件 → **单接口 Sync（上传+取状态合一）**；动画**服务端驱动** |
| 4b| 幂等 | **两层**：请求级 Idempotency-Key + 样本级自然键去重 |
| 5 | 登录 | **必须登录**后使用；MVP 用**手机号 + 短信验证码**；OAuth 可后加但必须绑手机号 |
| 6 | 部署 | 先本地跑通验证，后上云（本文不展开） |
| 7 | 规模 | MVP **单服务 + 单 PostgreSQL**，不引入 Redis/队列 |
| 8 | 时间 | 一切窗口/日界用**服务端时间 + 服务端固定时区**（建议 `Asia/Shanghai`） |

**贯穿原则**：服务端权威算 bo，端只读数据 + 演动画；先做必要接口（登录 + Sync + state），其余（拔毛/商店/周报）按切片逐步接；`bo_ledger` 全量流水从 Day1 记（错过补不回）。

---

## 1. 设计原则（MVP-first）

1. **服务端权威**：端永远不自己算 bo。端只负责读健康数据、捕捉行为、按服务端指令演动画。这是防刷的根，也是日后能用真实数据重新平衡数值的前提。
2. **必要接口先行**：本切片只实现「登录 + Sync + state」。拔毛、商店、周报、注销都不在本切片，但表结构与流水为它们留位。
3. **不过度设计**：单 Go 服务 + 单 PostgreSQL。不上 Redis、不上消息队列，直到规模逼着上。
4. **数值参数可调**：bo 产出的曲线/阈值/价目走配置（见 §6 `economy_config`），改数值不发版。
5. **数据守恒承诺**：已入账 bo 余额、已解锁道具**永不追溯回收**（仅“头顶未拔的 bo”会枯萎，属拔毛轴，切片2）。

---

## 2. 总体架构

```
        ┌──────────────── 一个 Go 二进制（单服务） ────────────────┐
 iOS ───┤  Chi Router                                              │
HealthKit│   ├── auth_service（嵌入模块, ConnectRPC）  ── 登录/JWT  │──┐
        │   │     /auth.v1.AuthService/*                           │  │
鸿蒙 ───┤   └── bo 经济模块（REST/JSON）                           │  │   ┌─────────────┐
华为Health│        /api/v1/economy/sync                            │  ├──►│ PostgreSQL  │
 Kit     │        /api/v1/economy/state                           │  │   │ (单实例)    │
        │        /api/v1/economy/config                           │──┘   │ users +     │
        │   [JWT 中间件: 复用 authModule.ValidateAccessToken]      │      │ economy_*   │
        └──────────────────────────────────────────────────────────┘   └─────────────┘
```

- **一个二进制**同时托管 auth（登录、JWT、用户表）和 bo 经济（产 bo、对账、状态）。两者共用 Chi 路由与同一个 PostgreSQL。
- 端（iOS 用 HealthKit、鸿蒙用华为 Health Kit）在本地读健康数据，**归一化成同一套 raw 事件**后用 REST 上传。后台平台无关。
- 经济接口的鉴权直接套用 auth 模块的 JWT 校验，从 token 里取 `user_id`（ULID），无需任何跨服务调用。

---

## 3. 技术选型与理由

| 选型 | 选择 | 理由 |
|---|---|---|
| 语言/框架 | **Go + Chi**（沿用 auth_service） | auth_service 设计成可嵌入 Go 模块（`auth.NewAuthModule({DB})`），同栈零摩擦复用 |
| bo 接口协议 | **REST/JSON** | 鸿蒙(ArkTS)+iOS 双端手写 REST client 最稳；auth 的 Connect 接口端侧照用其现成方式 |
| 鉴权 | **复用 auth 的 JWT（HS256）** | token 已带 `user_id`/`roles`/`epoch`，`ValidateAccessToken` 直接可用，含吊销/黑名单 |
| 身份 | **auth 的 `users.id`（ULID, varchar(26)）** | 全局唯一、跨设备稳定，作经济一切数据的主键/外键 |
| 数据库 | **单 PostgreSQL**，经济表与 users 同库 | 外键可直连 users；GORM 沿用；事务保证花费/解锁的一致性 |
| 缓存/队列 | **MVP 不用** | 单服务足够；token 吊销 epoch 可暂用内存/PG，Redis 留到上量再加 |

**为什么嵌入同一二进制（而非独立服务）**：MVP 阶段省掉跨服务 token introspection、独立部署、双 DB 同步的全部复杂度；user 身份天然一致；一次部署搞定。代价是耦合，但在 MVP 完全可接受，未来要拆也只是把经济模块抽出、改用共享 JWT 密钥校验即可。

---

## 4. 身份与对账（绑定 auth_service）

### 4.1 鉴权链路
1. 端登录（见 §4.3）→ auth 返回 `access`(15min) + `refresh`(7d) JWT。
2. 端每个经济请求带 `Authorization: Bearer <access>`。
3. bo 模块的 JWT 中间件用 `authModule` 的 `ValidateAccessToken(token)` 校验签名+过期+吊销，从 `claims.user_id` 拿到 ULID 注入 context。
4. access 过期 → 经济接口返回 `401`；端用 refresh 换新 token 后重放请求。

### 4.2 对账（Reconciliation）的定义
- 经济一切数据以 `user_id`(ULID) 为键，**服务端是唯一真值**。
- 端本地缓存的 bo 数量、Pibo 状态**仅供显示**；每次 `Sync` 或前台 `GET /state`，以服务端返回为准，**冲突一律服务端赢**。
- 端**无任何写 bo 的权限**——端能做的只是「上传原始数据」和「上报行为」，价值由服务端算。这天然防作弊，也是对账成立的根本。

### 4.3 登录策略（回答 #5）
- **MVP 唯一登录方式 = 手机号 + 短信验证码（OTP）**。一步同时完成「验证手机号」和「登录」，无密码可丢，摩擦最低；auth_service 已内置（`CodeChannelSMS`，`StartCodeLogin`/`CompleteCodeLogin`）。
- **必须登录后才能使用 App**（无游客态）。对账最干净，避免“游客→绑定→数据合并”的复杂迁移。
- OAuth（华为账号 / Apple）**可后加**，但因为业务要求“必须有手机号”，OAuth 之后仍需一步**手机号绑定 + 短信验证**，多出屏幕，故 MVP 不做。
- ⚠ **两个实操点**：
  - **iOS 审核**：只提供手机号登录时，**无需** Sign in with Apple（该要求仅在你提供了第三方 OAuth 如微信/Google 时触发）。只做手机登录反而让 iOS 提审更简单。
  - **短信服务商**：auth 默认 Twilio，对国内手机号不稳/贵。需换**国内服务商**（阿里云短信 / 腾讯云短信 / 华为云），`SmsService` 的 provider 是可配置的，作为接入点。

---

## 5. MVP 核心交互：Sync（健康事件 → 上传 → 状态）

### 5.1 流程
1. 端收到系统健康事件（iOS：HealthKit observer + 后台投递；鸿蒙：华为 Health Kit 订阅）。
2. 端读取自上次水位以来的**增量原始样本**，归一化。
3. 端调用**单接口** `POST /api/v1/economy/sync`（上传 + 取状态合一）。
4. 服务端：去重入库 raw → 按数值曲线算能量 → 累计能量池 → 跨阈值则铸 bo → 更新状态 → 写流水。
5. 服务端返回 `{余额, 新增bo, Pibo状态, 待演动画[]}`。
6. 端按 `animations[]` **照单播放**（服务端驱动，端不自行决定演不演）。
7. 后台投递/锁屏期间无网或时间不够 → 端**本地排队**，下次前台/联网补传；前台打开额外调 `GET /state` 兜底对账。

### 5.2 `POST /api/v1/economy/sync`

请求：
```json
{
  "idempotencyKey": "a1b2c3d4-....",      // 本次请求 UUID，重试时复用同一个
  "clientTime": "2026-06-29T21:05:00+08:00", // 仅诊断参考，不参与判定
  "samples": [
    { "metric": "steps",   "value": 320, "unit": "count",
      "startTs": "2026-06-29T20:00:00Z", "endTs": "2026-06-29T21:00:00Z",
      "sourcePlatform": "ios", "externalSampleId": "HK-UUID-...", "dedupKey": "..." },
    { "metric": "sleep",   "value": 27000, "unit": "sec",
      "startTs": "2026-06-29T15:00:00Z", "endTs": "2026-06-29T22:30:00Z",
      "sourcePlatform": "ios", "externalSampleId": "HK-UUID-...", "dedupKey": "..." }
  ],
  "actions": [
    { "eventId": "evt-uuid-...", "actionType": "photo", "occurredAt": "2026-06-29T20:40:00Z" }
  ]
}
```

响应：
```json
{
  "boPending": 5,            // 头顶未拔的 bo（本切片“BO 数量”即此）
  "boBalance": 12,           // 已入账可花（拔毛后，切片2）
  "minted": [ { "reason": "mint_health", "delta": 1 } ], // 本次新增，用于决定演不演
  "piboState": "active",     // 6 态机之一
  "animations": ["energy_collected", "bo_grown"], // 端照单播放
  "serverTime": "2026-06-29T13:05:01Z"
}
```

- **动画即响应**：端只在 `animations` 非空时播放；空则只静默更新数字。
- **minted 决定“是否更新 BO”**：`minted` 有值才让头顶 bo 数 +N 并播 `bo_grown`。

### 5.3 幂等设计（回答 #4：不止一个 UUID，用两层）

| 层 | 机制 | 防的问题 |
|---|---|---|
| **A · 请求级** | 端每次 Sync 带 `idempotencyKey`(UUID)，重试复用同一个。服务端表 `idempotency_key` 唯一；命中则**直接返回缓存响应、跳过一切副作用**（TTL 24–48h） | 网络重试 / 后台投递重复触发 → **重复发 bo** |
| **B · 样本级** | 每条 raw 样本带 `dedupKey`；`health_sample_raw` 上 `UNIQUE(user_id, dedup_key)`，`INSERT ... ON CONFLICT DO NOTHING`。算分**只对本次新插入的行**跑 | 不同批次**数据区间重叠**重传 → **重复计数** |

- `dedupKey` 取法：平台给稳定样本 UUID 时（HealthKit `HKSample.uuid` / 华为 Health Kit sample id）直接用；聚合数据（如小时步数桶）用 `sha1(metric|source|bucketStart|bucketEnd)` 派生。行为事件用端生成的 `eventId`，`UNIQUE(user_id, event_id)`。
- 两层缺一不可：A 让**整个 HTTP 调用**可安全重试（重试返回同一份缓存响应，动画也不会重播）；B 让**底层数据**无论怎么分批/重叠都不会重复计入能量。

### 5.4 时间与日界（回答 #8）
- 拔毛窗口（22:00–02:00）、每日上限、3 天衰减——**一律用服务端时间 + 服务端固定时区**（建议 `Asia/Shanghai`，待确认）。
- 端上报的 `clientTime` 仅作诊断，**不参与任何判定**（防改设备时钟穿越）。

---

## 6. 最小事件表 Schema（PostgreSQL / GORM）

> 约定：沿用 auth 的 `BaseModel`（ULID 主键、软删除）。外键指向 `users.id`(varchar(26))。**切片1 必建 1–5；6–7 为后续切片占位。**

```go
// 1) 账户：每用户一行（服务端权威状态）
type EconomyAccount struct {
    UserID     string    `gorm:"type:varchar(26);primaryKey"`        // FK -> users.id
    EnergyPool float64   `gorm:"not null;default:0"`                 // 未满一根 bo 的累计能量
    BoPending  int       `gorm:"not null;default:0"`                 // 头顶未拔的 bo（切片1 的“BO 数量”）
    BoBalance  int       `gorm:"not null;default:0"`                 // 已入账可花（拔毛后，切片2）
    LastPluckAt *time.Time
    LastSyncAt  *time.Time
    CreatedAt  time.Time
    UpdatedAt  time.Time
}

// 2) 原始健康样本日志（append + 去重）—— “错过补不回”的那张表
type HealthSampleRaw struct {
    BaseModel
    UserID         string    `gorm:"type:varchar(26);index;not null"`
    Metric         string    `gorm:"type:varchar(32);not null"`     // steps/sleep/workout/hrv/rhr...
    Value          float64   `gorm:"not null"`
    Unit           string    `gorm:"type:varchar(16)"`
    StartTs        time.Time `gorm:"not null;index"`
    EndTs          time.Time `gorm:"not null"`
    SourcePlatform string    `gorm:"type:varchar(16)"`              // ios / harmony
    ExternalSampleID *string `gorm:"type:varchar(128)"`
    DedupKey       string    `gorm:"type:varchar(80);not null"`
    IngestedAt     time.Time `gorm:"autoCreateTime"`
    // 唯一约束：UNIQUE(user_id, dedup_key)
}

// 3) App 行为事件（拍照/小游戏/拍一拍）
type EconomyActionRaw struct {
    BaseModel
    UserID       string         `gorm:"type:varchar(26);index;not null"`
    EventID      string         `gorm:"type:varchar(64);not null"`  // 端生成 UUID
    ActionType   string         `gorm:"type:varchar(32);not null"`  // photo/game/pat
    Payload      datatypes.JSON `gorm:"type:jsonb"`
    EnergyAwarded float64       `gorm:"not null;default:0"`
    OccurredAt   time.Time
    // 唯一约束：UNIQUE(user_id, event_id)
}

// 4) bo 流水（只增不改）—— 对账/重平衡/周报全靠它
type BoLedger struct {
    BaseModel
    UserID       string `gorm:"type:varchar(26);index;not null"`
    Delta        int    `gorm:"not null"`                            // +铸造 / -花费 / -枯萎
    Reason       string `gorm:"type:varchar(32);not null"`           // mint_health/mint_action/pluck/spend_item/decay
    Ref          string `gorm:"type:varchar(128)"`                   // idempotencyKey / itemId 等
    BalanceAfter int    `gorm:"not null"`
    CreatedAt    time.Time `gorm:"autoCreateTime;index"`
}

// 5) 请求幂等键
type IdempotencyKey struct {
    UserID    string         `gorm:"type:varchar(26);primaryKey"`
    Key       string         `gorm:"type:varchar(64);primaryKey"`
    Endpoint  string         `gorm:"type:varchar(64)"`
    Response  datatypes.JSON `gorm:"type:jsonb"`                      // 缓存的响应
    CreatedAt time.Time
    ExpiresAt time.Time      `gorm:"index"`
}

// 6) 远程配置（占位，切片2）：曲线参数/价目/封顶，key-value 或单行 jsonb
// 7) 商店（占位，切片3）：ItemCatalog / UserUnlock
```

**算分逻辑（服务端，Sync 内一个事务）**：去重插入 `HealthSampleRaw`/`EconomyActionRaw` → 对**新插入行**按 `数值系统.xlsx` 的曲线算能量 → `EnergyPool += 增量`（封顶）→ `while EnergyPool >= 每个bo所需能量: EnergyPool -= 阈值; BoPending += 1; 记 BoLedger(mint)` → 返回状态 + 动画。

---

## 7. 接口清单

**切片1（本次必做）**
- 登录：复用 auth `POST /auth.v1.AuthService/StartCodeLogin` + `CompleteCodeLogin`（短信验证码）
- `POST /api/v1/economy/sync` — 上传增量 + 取状态（§5.2）
- `GET  /api/v1/economy/state` — 前台对账兜底（返回与 sync 同构的状态，不含 minted/animations）
- `GET  /api/v1/economy/config` — 远程配置（MVP 可先返回静态默认值）

**后续切片**
- `POST /api/v1/economy/pluck`（切片2，拔毛：pending→balance，校验窗口/评级）
- `POST /api/v1/economy/shop/redeem`（切片3，兑换道具）
- `GET  /api/v1/economy/report/weekly`（切片4，周报）
- `POST /api/v1/account/delete`（切片5，注销=删数据，合规）

---

## 8. 分阶段路线图

| 切片 | 内容 | 产出 |
|---|---|---|
| **1（本次）** | 登录 + Sync + state + config + 最小事件表(1–5) + 服务端权威算分 + 两层幂等 + 服务端固定时区 | 本地跑通「健康事件→产 bo→端演动画」闭环 |
| 2 | 拔毛轴（pending→balance、22:00–02:00 窗口、3 天衰减）+ 远程配置表落库 | |
| 3 | 商店（道具目录/解锁/故事卡） | |
| 4 | 周报（聚合 raw → 简报/拼贴） | |
| 5 | 账号注销=删数据（合规）+ 上云部署 + 按量级评估 Redis/队列 | |

**从 Day1 起就要做对的横切项**：`bo_ledger` 全量流水（错过补不回）、服务端固定时区、REST + 复用 JWT、两层幂等。

---

## 9. 待确认 / 留给后续

1. 服务端固定时区取值（建议 `Asia/Shanghai`）。
2. 国内短信服务商选型（阿里 / 腾讯 / 华为云）。
3. 数值曲线落地形态：配置表 vs 配置文件（影响 §6 表6）。
4. 端侧：iOS HealthKit 与鸿蒙华为 Health Kit 的健康事件订阅 API 差异、样本是否提供稳定 UUID（影响 `dedupKey` 取法）。
5. `economy_config` 的字段对齐 `数值系统.xlsx` 的「参数」页。
