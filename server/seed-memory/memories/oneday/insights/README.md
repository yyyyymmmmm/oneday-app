# insights — 洞见治理账

`insights.jsonl` 一行一条行为规则洞见（JSON）：

```json
{"id": "ins-...", "rule": "规则文本", "scope": "适用范围", "votes_up": 0, "votes_down": 0, "relapse_count": 0, "status": "candidate|active|retired", "src": "出处", "first": "ISO时间", "last": "ISO时间"}
```

治理规则（ExpeL 式）：纠错先入 candidate；被实践验证 upvote，满 2 票升 active 并同步写进 identity/RULES.md；被反例命中 downvote，down 超过 up 2 票自动 retired。读写走 oneday_memory 模块的 insight_apply（网关进程内或容器内 CLI），不要手工拼行。
