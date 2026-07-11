# 华容道关卡资料来源

本项目的华容道规则采用标准 Klotski 定义：在滑块不能重叠或越界的前提下，将指定的 2×2 主块移动到预设出口。规则背景参考 [Wikipedia: Klotski](https://en.wikipedia.org/wiki/Klotski)。

新增关卡的 4×5 初始布局改编自 [BingoCa1t/KlotskiPuzzle](https://github.com/BingoCa1t/KlotskiPuzzle) 的 `assets/mapData`（地图 1–5、21–25），核验版本为 [`df49d788`](https://github.com/BingoCa1t/KlotskiPuzzle/tree/df49d788975f67f0a11276b3587442701cda6bf5)。原数据以左下角为坐标原点；Pibo 转换为 SwiftUI 左上角原点，并将人物棋子替换为 Pibo 的抽象色块。为保持原有玩家记录，项目原先的 3 个确定性种子关卡也保留在关卡目录中。

界面中的“最少步数”不是照搬来源项目的评分阈值，而是按 Pibo 的手势规则重新计算：一次手势可让一个棋块沿同一方向移动任意个合法格。全部新增布局均通过广度优先搜索验证可解；13 关按该口径的最短解长度排序。

## 上游许可证

MIT License

Copyright (c) 2025 BingoCAT Xu_Huawei

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
