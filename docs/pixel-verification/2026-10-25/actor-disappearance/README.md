# iOS 上拉后整个 Pibo 消失：根因与修复

用户澄清消失的是整个 Pibo 形象。上一轮收取测试只带账本与舞台，没有带返家陪伴状态，因而没有覆盖这个根因。

## 已复现的路径

1. 返家时满足旧版陪伴捉迷藏条件，但成熟 bo 会挡住旧版 mood。
2. 上拉收取最后一枚成熟 bo 后，余额正常增加，成熟阻挡解除。
3. 下一次 `HomeCompanionController.tick()` 触发旧版 `hideAndSeek`，`mood.hidesBody` 变为 true。
4. Home 将旧标记作为 `piboVisible = false` 传给像素舞台，整个角色停止绘制。像素日程没有接手这套旧动画的寻回过程，所以界面只剩森林。

用临时账本、返家记忆和真实已发布 Core 复现：收取前角色可见，收取后余额为 1，角色不可见。新回归在旧接线下出现 8 个断言失败（控制器和窗口两类测试），并捕获到了角色消失的截图。

## 修改

- Home 明确声明像素日程拥有角色表现；陪伴控制器保留提问、记忆和对白，在像素模式下不再启动旧版 mood 动画。已有旧 mood 会被清除，并撤下其临时组件状态文字。
- 从 `HomePixelStageInput` 移除旧的全局角色隐藏输入，Home 不再把 `companion.mood.hidesBody` 接入像素绘制。
- 当前像素日程自己的捉迷藏、进屋、探索离场及返回仍由 `PixelDayDirector` 控制；没有改成永远显示角色。
- 没有修改 Core 的情绪或捉迷藏阈值、健康规则、账本或素材。

## 验证

- 针对返家收取，验证第 1、3、30 秒角色仍可见，余额为 1，不伪造「找到 Pibo」的事件。
- 针对真实像素捉迷藏，验证角色能藏起来，并在找到后通过正式日程回到可见位置。
- 窗口夹具加入真实 `HomeCompanionController` 和返家记忆，并使用生产 `HomePixelStageInput`，补上上一轮缺失的条件。
- 定向 14 tests / 4 suites 通过；全量 512 tests / 102 suites 通过。
- Debug 测试构建与 Release iOS Simulator 构建通过；`git diff --check` 通过。

## 窗口截图

每行分别展示同一夹具在收取前后的状态。修复后夹具改为从生产成长适配器读取外观，而非旧夹具固定的体型及默认季节；本轮没有修改角色或森林美术。

| 场景 | 收取前 | 收取后、提示结束 |
| --- | --- | --- |
| 旧接线，已复现消失 | [角色可见](before-fix-before-collection.png) | [整个角色消失，余额为 1](before-fix-after-collection.png) |
| 修复后，带返家陪伴状态 | [角色可见](after-fix-before-collection.png) | [角色仍可见，余额为 1](after-fix-after-collection.png) |

截图由模拟器中的真实 UIWindow/UIHostingController 渲染，使用独立临时 UserDefaults；并非真机或完整 Home 截图。没有写入真实健康事实或用户资产。本轮真机触摸与长期恢复路径尚未复验。
