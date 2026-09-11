# Pibo 文案工作台（本机版）

管理主页拍一拍的真实中文资源：六个状态、27 个 Core 情境、单句与微章节。
从鸿蒙实际资源及 `PiboPatDebugScenario.ets` 读取内容和场景目录，不维护另一份正式台词库。

## 启动

需要 Node.js 22 或以上，无第三方依赖。在 Pibo 仓库执行：

```sh
node Tools/pibo-copy-console/server.mjs
```

打开 http://127.0.0.1:4317 。默认读取同级 `HarmonyPibo` 工程。
位置或端口不同可以通过以下专用环境变量指定：

```sh
PIBO_COPY_HARMONY_ROOT=/path/to/HarmonyPibo PIBO_COPY_PORT=4317 node Tools/pibo-copy-console/server.mjs
```

`PIBO_COPY_DATA_DIR` 可改变草稿与备份目录，默认 `Tools/pibo-copy-console/.local/`。
不要清理这个目录，除非已导出需要保留的草稿。

## 批量创作 Prompt

可直接复制给 LLM 的批量文案 Prompt 位于 `prompts/LLM-bulk-copy-prompt.md`。它包含声音规则、六状态差异、27 个情境合同、微章节规则、批量产出方法和严格 JSONL 导入格式。

## 日常流程

1. 在六状态目录中选择情境，查看触发条件、回应后行为、语义动作和顺序单元。
2. 修改台词，新增/删除句子、调整句序或同情境单元顺序；首次接触保留三个单元。
3. 右侧预览逐句阅读，可替换步数/睡眠示例值和故事阶段。预览是审稿工具，
   不模拟 Core 状态选择、事件消费、冷却或角色动作。
4. 保存草稿到磁盘。关闭或重启服务后仍可继续；其他窗口的较新草稿会阻止旧版本覆盖。
5. 在“同步与版本”比较正式资源与草稿，点击“确认差异并同步鸿蒙”。
6. 用 DevEco 构建、安装 **手机 Debug 包**。修改 JSONL 本身不会更新已安装 App。
7. 设置 → 拍一拍场景验收（27 个上下文）→ 选择主状态/情境 → 双击 Pibo。
   该验收会话隔离正式健康记录与台词游标。日常模式仍需满足真实健康状态和事件条件。

“文案大纲”保存角色声音、微章节结构、表达边界和每种状态写作方向；决策原文可直接查阅。
大纲不作为运行时配置，不改变 Core 规则，也不会自动生成台词。

## 同步、恢复与校验

- 保存草稿不修改 App；同步只原子替换鸿蒙的
  `entry/src/main/resources/rawfile/pibo-home-pat.zh-Hans.jsonl`。
- 每次保存/载入/恢复前保留草稿快照，同步前另外备份鸿蒙旧版；历史恢复仅生成草稿。
- 若鸿蒙正式资源被其他工具修改，拒绝同步。先导出已保存草稿，再“载入鸿蒙版本”并合并。
- 当前 Core 或调试情境源码变化后，拒绝同步并要求重启重读合同。
- 验证所有场景有内容、首次接触三单元、动作/说话者不变、非空文本、故事阶段可达、
  动态占位符在对应情境有运行时值。超过 40 字给出三秒阅读提醒，不强行改写。
- `steps` 只用于 `stable.steps`；`sleepDuration` 只用于 `stable.sleep/sleepTogether`。
- 故事阶段映射为 `unresponded/event01/event02/event03`，对应鸿蒙 `HomePatInputBuilder`。
- 当前只编辑既有情境的内容。新增跨平台触发条件/场景须先按 Core 发布流程实施，
  不能在控制台随意新增一个不会被运行时选择的 context。
- 只监听本机地址，并校验 Host、Origin、请求令牌；不存在任意路径读写或执行命令 API。
- 不自动运行构建、设备安装、Git 提交或推送；不自动修改 iOS 资源。

## 管理范围

本版完整管理**主页拍一拍**。环境低语、系统 UI、散步涂鸦台词以及后端 LLM 食物观察
仍由现有各自资源管理；编辑大纲不表示这些资源同步变化。iOS 的内容对齐状态显示于同步页，
后续可以在单独审核后同步同一 JSONL。

## 验证

```sh
cd Tools/pibo-copy-console
npm run check
npm test
```

测试使用临时鸿蒙资源副本，覆盖真实读取合同、保存/同步/恢复、非法文本与占位符、
场景覆盖、外部修改冲突、过期草稿与跨站访问。不会改写真实台词。

在 HarmonyPibo 仓库运行：

```sh
node tools/test_pibo_pat_conversations.mjs
node tools/test_pibo_pat_debug_scenarios.mjs
```

## 实现边界

网页只按当前选中的单元顺序审稿，不复制 Rust 规则。触发条件的中文说明是对
决定 033/034/044 与当前 Core/平台行为的人工索引，并非可执行规则；运行时始终以 Core 为准。
冷却显示直接读取已固定 Core 源码，实际判定仍在 App 内调用 Core。
场景中文标题和验收说明来自鸿蒙现有 DEBUG 场景文件。

若浏览器支持 `document.modelContext`，提供只读目录与“暂存台词修改”工具；
不通过工具隐式同步正式资源。无该接口时普通 UI 完全可用。
当前未在支持该提案的浏览器中验收可选 WebMCP 工具。
