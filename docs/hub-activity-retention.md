# 中枢活动记录保留期限

## 调研过程

搜索关键词：
1. "Muse app activity retention policy how long keep records"
2. "Meta Muse chat history retention how long stored"

搜索结果未找到 Anthropic Claude Muse（工作台账）的文档化保留期限政策——搜索结果混着其他同名产品（Meta Muse AI 聊天助手、音乐协作软件 Muse、脑波头带 Muse），均非本项目所指的 Anthropic Claude 工作台账功能。

## 可观察行为

当前 `HubLedgerSection` 实现：
- 所有条目来自 `store.allItems`（服务端返回的全量数据）
- 客户端按天分组展示，无时间窗口裁剪逻辑
- 分组逻辑在 `LedgerListSnapshot` 内，仅做呈现层聚合，不过滤时间范围

## 结论

**客户端暂不裁剪**——服务端如有保留期限策略，以服务端返回数据为准；客户端接收并完整展示服务端提供的所有条目，不在客户端侧实施额外的时间窗口过滤。

## 代码位置

折叠初始化逻辑位于 `HubLedgerSection.swift:initializeCollapsedDays`，仅控制展开/折叠态，不涉及数据裁剪。
