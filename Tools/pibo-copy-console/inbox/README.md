# 批量文案收件箱

- `gemini-code-*.txt`：LLM 原始输出，逐行 JSONL；本次已检查 14 个文件。
- `pibo-home-pat.zh-Hans.merged.jsonl`：合并候选，不是已发布文件。它保留鸿蒙原有 45 个单元，并追加收件箱中除 `stable.touchDiscovery` 外的 422 个单元，共 467 个。
- `merge-report.json`：文件、情境数量与格式校验结果。
- `merge-review.md`：格式通过后的语义审稿提示。提示项保留在合并候选中，需在控制台人工筛选。

合并候选要进入 App：打开文案控制台 →「同步与版本」→「导入 LLM JSONL」→ 选择“替换当前草稿”并粘贴文件内容 → 审阅 → 保存 → 同步鸿蒙。同步不会自动构建或安装。
