# bo 后端结构与幂等设计参考

> 历史设计参考，表结构不是现行 API 承诺。当前服务端实现以 pibo-server 为准，规则由已发布 Core 负责；本地形成 bo 不要求登录，登录后按决定 031 幂等合并。动画由平台播放。旧“必须登录、服务端权威计算、固定服务端日界、服务端驱动动画”的开发指令与旧接口路线图已删除。

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


### 5.3 幂等设计（回答 #4：不止一个 UUID，用两层）

| 层 | 机制 | 防的问题 |
|---|---|---|
| **A · 请求级** | 端每次 Sync 带 `idempotencyKey`(UUID)，重试复用同一个。服务端表 `idempotency_key` 唯一；命中则**直接返回缓存响应、跳过一切副作用**（TTL 24–48h） | 网络重试 / 后台投递重复触发 → **重复发 bo** |
| **B · 样本级** | 每条 raw 样本带 `dedupKey`；`health_sample_raw` 上 `UNIQUE(user_id, dedup_key)`，`INSERT ... ON CONFLICT DO NOTHING`。算分**只对本次新插入的行**跑 | 不同批次**数据区间重叠**重传 → **重复计数** |

- `dedupKey` 取法：平台给稳定样本 UUID 时（HealthKit `HKSample.uuid` / 华为 Health Kit sample id）直接用；聚合数据（如小时步数桶）用 `sha1(metric|source|bucketStart|bucketEnd)` 派生。行为事件用端生成的 `eventId`，`UNIQUE(user_id, event_id)`。
- 两层缺一不可：A 让**整个 HTTP 调用**可安全重试（重试返回同一份缓存响应，动画也不会重播）；B 让**底层数据**无论怎么分批/重叠都不会重复计入能量。


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
