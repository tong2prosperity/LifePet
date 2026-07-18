# Pibo Leaf Rig Lab

Godot 4.6 参数调试工程，用六节 `Bone2D` 预览 Pibo 头顶草叶的弹簧骨骼运动。

```bash
/Applications/Godot.app/Contents/MacOS/Godot --editor --path Tools/PiboLeafRigGodot
```

- 调整柔韧度、阻尼、风力、阵风和风向。
- Space 或按钮触发阵风；拖动叶尖测试直接操作与回弹；R 复位。
- Godot 工程负责视觉调参，iOS 运行时由 `PiboHeadRigDeformer` 使用同一组公式驱动 `SKWarpGeometryGrid`。
