# 动态生成线「Billing or credits exhausted」定因报告（2026-11-12 晚）

## 结论先行

**不是额度玄学，是桥里写死了一个模型名。** 伴生桥 `oneday_bridge.py` 把所有生成步的模型写死为 `deepseek-flash`，每次请求都显式带这个模型名提交 Hermes；而 `deepseek-flash` 经网关落到 **#14 DeepSeek 通道**，其后的 DeepSeek 官方账户余额已耗尽，回 HTTP 402。聊天主链 17:00 已切默认 `claude-sonnet-4-6`（laogou8 通道），但生成线根本不走默认——它自己带名，切换默认对它无效。

本报告只定因＋给方案，**未动任何生产配置**。

## 一、生成线走的路（代码实证，生产容器内 /opt/companion/modules/oneday_bridge.py）

- 第 1832 行：`GEN_MODEL = "deepseek-flash"` —— 全桥唯一模型常量。
- 唯一提交函数 `_hermes_submit_run()`（第 2636 行起）：`POST {HERMES_BASE_URL}/v1/runs`，请求体 `{"input": prompt, "model": GEN_MODEL}`，Bearer 为桥自己的 HERMES_API_KEY；若网关要求会话，先建专用会话 `oneday-ideas-gen` 再带 `session_id` 重提（模型名照带）。
- 动态线的规划步（第 6381 行）、选题步（第 6671 行）、著帖步（第 6223 行），以及点子线与桥内其余模型管道（第 2078/2905/2971/3008/3428/3601/5344/5781/5859/6072 行），**全部共用这一个提交函数**——即全桥模型调用只有一个模型名、一颗写死的常量。
- 不走 auxiliary、不读 Hermes 默认模型、与会话模型锁无关：run 请求自带 `model` 字段，Hermes 按名解析供应商。

## 二、复现与上游归属（今晚实测）

用桥自己的密钥与端点（https://hermes.example.com）提交两个最小 run（输入仅「只回复两个字：你好」）：

| run | model | 结果 |
|---|---|---|
| run_45f6441d87a14e74ab67aa62cb45bc34 | deepseek-flash | **failed**，output＝`Billing or credits exhausted: HTTP 402: Insufficient Balance (request_id: 717ec6d1-57f7-4cc8-9c45-f49ca514f4ad)` ＋「Custom reported…」——与生产失败原文逐字一致 |
| run_5d35eae2a66d4ea0ba8f39cc89325cb7 | claude-sonnet-4-6 | **completed**，output＝「你好」|

网关（New API）日志同期实锤（22:17 CST，与复现同分钟）：

```
[ERR] channel error (channel #14, status code: 402): Insufficient Balance (request_id: a3b89f31-…)
[ERR] relay error: Insufficient Balance
[GIN] 402 POST /v1/chat/completions
```

**归属定案**：402 出自网关 **#14 通道（DeepSeek → api.deepseek.com）后的 DeepSeek 官方账户余额耗尽**；不是 laogou8 额度（同分钟 sonnet 经 #15 laogou8 通道正常完成），不是 Hermes 本身故障。flash 与 v4-pro 同属这一个欠费账户（今日 15:39 已查实），换 v4-pro 同样 402。

## 三、为什么聊天没事、生成线有事

- 聊天走 Hermes **默认模型**：17:00 已切 `claude-sonnet-4-6`（laogou8），17:23 用户真机对话有回复。
- 生成线走**请求内写死模型名**：默认切到天上也轮不到它。这就是同一晚「聊天活、动态死」的全部原因。

## 四、影响面

- 动态 feedGen：今日共 **四轮**全 failed/produced=0——16:00 hourly（选题步）、17:00 hourly（选题步）、19:13 visit（选题步）、19:30 schedule-b（规划步）。今日 B 版未出，动态流今日无新帖；错过轮次不自动补跑。
- 点子 ideasGen：今日 07:30 轮为 ok（跑在余额耗尽暴露之前）；**明早 07:30 起将同病失败**（同一颗 GEN_MODEL）。
- 桥内其余共用该提交函数的模型管道（如 briefGen 等）同理，触发即 402。

## 五、修法选项（未执行，待主线呈报用户拍板）

- **A. 改桥常量（推荐先行）**：`GEN_MODEL` 由 `deepseek-flash` 改为 `claude-sonnet-4-6`，随伴生版本部署（伴生自动部署授权在案，但按本单纪律仍先呈报）。一处一行，全桥生成线即刻复活，走已验通的 laogou8 路。代价：Sonnet 单价高于 flash（生成量小、日均个位数 run，可忽略量级）；提示词原按 flash 调教，桥内有严格 JSON 折叠闸门兜底，风险低。缺点：仍是写死，下次换供应商还要改代码。
- **B. 改走默认（结构解，需先验证）**：提交体去掉 `model` 字段，让 run 跟随 Hermes 当前默认。好处：今后切默认一处生效、生成线自动跟随。风险：`/v1/runs` 省略 model 时的解析语义本轮未验证（可能必填/可能落到非预期供应商），须先在测试 run 上验明再改；且默认若日后被切回死供应商，生成线会跟着静默死。
- **C. 给 DeepSeek 充值**：零代码，flash 路即刻复活。但与用户 17:00「切离 DeepSeek 走 laogou8」的方向相悖，等于为桥单独养一个计费账户；结构脆弱不变。不推荐。
- **D. 网关侧改名映射**：在 New API 把 `deepseek-flash` 指向 laogou8 通道。桥零改动，但模型名与实物不符、污染网关日志与计费归属（该网关已有记账标签混杂问题在案），后患大。不推荐。

**建议组合**：A 立即止血；B 待验证省略-model 语义后作为结构收尾（或把 GEN_MODEL 改为读 companion.env 配置，部署侧可改、不动代码——同属 A 的变体，落地时二选一）。

## 证据边界

- 402 归属证据为三段同分钟互证：生产 history 原文、复现 run 的 failed output、网关 channel #14 错误日志。
- DeepSeek 账户余额数字本身未查（无该账户面板入口），「耗尽」以其官方 API 连续回 402 Insufficient Balance 为据。
- 本轮未验证 `/v1/runs` 省略 model 的行为（选项 B 的前置），未动任何生产配置、未重启任何容器；服务器内存全程约 57%。
