# 三段角色动画 · 原生验证

用户批准的 `pibo_design/motion-lab-v1` 三段动作已进入共享媒体数据与 iOS / HarmonyOS 原生播放器。
未发布应用；完整变更记录见 HarmonyPibo 的
`docs/harmony-first/2026-09-05-三段已批准角色动画原生接入.md`。

## iOS 验证

- Debug 模拟器构建成功。
- `PiboSampledMotionTests`：采样循环、单次归位、重复双击姿态连续性、状态取消、减少动态，通过。
- `PiboAnimationIntegrationTests` / `HomeAnimationStateResolverTests`：新增精力充足素材与 sampled-pose 原语，通过。
- `HomeAnimationPresentationControllerTests` / `PiboStageRenderControllerTests`：呈现及舞台生命周期，通过。
- 后续增加确定性截图入口并修正首次请求后，重新运行前三项，全部通过。

截图使用 iPhone 17 / iOS 26.5，原生 SpriteKit Character Lab，300×300 原始画板。
bo 显示当前原生空容器状态；未伪造健康增长值去匹配网页满绿芽。

```bash
xcrun simctl launch --terminate-running-process <device> <built-bundle-id> \
  -PiboCharacterLab -PiboLabClean -PiboLabArtboard \
  -PiboLabState pibo-state-energetic-forest-idle \
  -PiboLabMotionClip energetic -PiboLabMotionTime 2.46
```

`energetic-airborne.png`：2.46 秒空中峰值。`energetic-landing.png`：2.86 秒落地压缩。
姿态截图与数值验证不等同于完整森林内真机流畅度验收。
