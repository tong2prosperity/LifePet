# 运动完成的旧弹窗退役

依据决定 055，以及用户本轮对模拟运动旧弹窗的反馈。

核对结果：HarmonyOS 已实现森林内回应，相关生命周期／通知／角色接线检查通过；
iOS 仍调用 `PiboAchievementModal`，这是此次旧弹窗的来源。

iOS 修复：

- 删除成就 Sheet 目的地、旧 Modal、白色汇聚帧和旧 Sheet 呈现协调器。
- 运动与步数事件改为原地动作、Pibo 台词和一行事实，约 7.2 秒自动结束，无确认按钮。
  双击／单击身体、点击气泡或打开浮层可结束；后台停留不足 3 秒会在返回后重演。
- 结束时按 presentation ID 消费同一条待回应记录，后到的新运动不会被旧回调误消费。
  不额外发放 bo，不再播放确认 toast／收集反馈；历史与真实健康数据路径保留。
- 调试「模拟运动完成」和旧预览参数均接入同一条表现链，不恢复弹窗。
- 不再创建运动 Live Activity，启动时清理旧实例；前台不发重复运动／步数系统横幅。

验证：iOS 全量 475 项测试通过，新增森林回应生命周期回归；Debug／Release 模拟器构建通过。
最后的状态切换保护与通知排队检查也经过定向构建／测试。
HarmonyOS 的 `test_forest_answer`、`check_character_animation_port`、`check_sleep_notifications_port`、
`check_companion_port`、`test_retired_platform_cleanup` 全部通过。

同一次实际「模拟运动」流程的画面：

- [第 2 秒：森林内回应](iphone-workout-response.png)
- [第 9 秒：气泡已结束，继续森林活动](iphone-workout-after.png)

截图来自 iPhone 17 模拟器，明确使用调试运动和表现覆盖，没有真机健康事实或额外 bo 奖励。
本轮不将决定 055 的其他历史差异（当天资格／观察起点等）一并标为已验收。
