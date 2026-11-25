# admission — 技能准入账

`skill_admission.jsonl` 一行一个技能的准入记录（JSON）：

```json
{"skill": "<技能名>", "created_by": "agent|user", "verify": {"method": "自测脚本|演练|人工验收", "evidence": "<证据指针：文件路径/输出摘要>", "at": "ISO时间"}, "status": "admitted", "first": "ISO时间"}
```

准入纪律（Voyager 式）：新技能在写明「可用」之前，必须先跑通它自带的一条验证（自测/演练），把证据指针记进本账。模块清扫线程与周体检只对账审计（无账/无证据的技能列入审计报告），不代替验证本身。
