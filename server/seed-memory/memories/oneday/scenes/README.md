# scenes — 场景记忆

按场景分文件：一个长期主题一个文件（如 work.md、home.md、project-<名>.md）。开始新任务时先判断属于哪个场景，只读对应文件，不把别的场景的结论套过来。

## 条目格式

```markdown
## <条目ID> · <一句话标题>
正文：事实、口径、决定，写清日期与出处。
<!-- odmem: id=scenes/<文件>#<序号>, first=YYYY-MM-DD, last=YYYY-MM-DD, src=user|session:<会话id>|distill:YYYY-MM-DD, status=active, valid_from=YYYY-MM-DD, invalid_from=-, superseded_by=- -->
```

- 事实被新口径取代时，不删旧条目：旧条目标 `status=superseded, invalid_from=<日期>, superseded_by=<新条目ID>`，新条目正常写入。
- 热度与检索由 oneday_memory 模块统一处理，手写时只需保证尾注字段齐全。
