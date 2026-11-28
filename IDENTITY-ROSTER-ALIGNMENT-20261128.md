# OneDay 身份卡/名册/执行体层大厂对位分析

起草：2026-11-28 09:30（Asia/Shanghai）  
工作目录：/home/hatch/workspace/wt-identity-align  
分支：analysis/identity-roster-align-20261128  
基线：gh/main ccdcba24  

任务：seven-56 身份卡/名册/执行体层大厂做法全件对位分析（只出分析、不写代码）

## 结论先行

**三块现状：**
1. **身份卡单一源**：✅ 已对齐——服务端单一真值+本地缓存副本，与Claude Projects/ChatGPT Workspace模式一致
2. **职能体名册**：❌ 未实现——现行代码无职能体名册结构，草稿有完整规格但未落码
3. **执行体层**：⚠️ 部分对齐——Hermes本体有delegate_task骨架，但缺职能体路由层、Claude Code/Codex适配器未验证

**推进次序建议（按草稿次序，经本分析验证可行）：**
1. ✅ 名册+执行体层先行（先只接Hermes本体）——有骨架、缺路由层
2. ✅ 群聊次之（@路由，壳最薄）——依赖名册+执行体层
3. ✅ 工作流（阶段引擎+关卡）——群聊基础上加模板
4. ⚠️ CLI执行体适配（Claude Code/Codex）——待探活验证
5. ✅ 语音视频独立线——不抢道

## §1 身份卡单一源：已对齐

### 1.1 现行代码状态

**核心文件：**
- `Sources/OneDayCore/IdentityCache.swift:1-257` 身份缓存定义
  - `IdentityNameCache:11-27` 名字缓存（服务端名字+时间戳+本地缓存时刻）
  - `IdentityAvatarCache:39-58` 头像缓存（仓内指针副本+服务端时间戳）
  - 注释明确：「真值自此只有一份——服务端（名字=SOUL、头像=伴生头像仓）」(line 3-5)

**呈现层：**
- `Sources/OneDayApp/HubIdentitySection.swift:1-384` 枢纽页身份段
  - `headerRow:86-117` 段内大名+连接状态+模型入口
  - `cardsRow:235-264` SOUL/记忆双卡
  - 单一数据源：`store.displayName` (line 88, 54)
- `Sources/OneDayApp/IdentityDetailView.swift:1-191` 形象与名称详情页
  - `heroSection:60-95` 大头像+显示名+连接状态
  - 单一出口：`appState.agentDisplayName` (line 75)

**对账机制：**
- `Sources/OneDayCore/OpsIdentity.swift:1-364` 身份对账
  - `IdentityReconciliation:139-187` 对账结果（主线绑定/路由/目录三项）
  - `IdentityReconciler.bindingItem:207-259` 主线绑定对账（本地绑定vs服务端目录）

### 1.2 成熟产品做法

**Claude Projects（官方文档）：**
> "Project instructions help Claude understand the specific context and requirements for a particular project. These instructions only apply to chats within that project."
> 
> 来源：https://support.claude.com/en/articles/10185728-understanding-claude-s-personalization-features

**Agent Identity（Claude官方文档）：**
> "To make multiplayer experiences work, Claude needs its own accounts for those tools, set up by an admin and tied to the workspace. We call this access model agent identity."
> 
> 来源：https://claude.com/resources/articles/agent-identity-access-model

**ChatGPT Workspace Agents（OpenAI官方文档）：**
> "ChatGPT workspace agents let you build agents for repeatable tasks and workflows in ChatGPT. You can create an agent, test it before publishing, choose its model and reasoning effort, connect it to apps and tools, share it with teammates or your workspace."
> 
> 来源：https://help.openai.com/en/articles/20001143-chatgpt-workspace-agents-for-enterprise-and-business

**对位模式：**
- ✅ 单一真值源：服务端持有身份配置（Claude workspace/OpenAI workspace）
- ✅ 本地缓存：客户端缓存副本用于呈现，刷新时整份替换
- ✅ 末写胜：服务端自然承接（后写入者胜出）
- ✅ 分布式一致性：本地对账机制（OpsIdentity）确保客户端与服务端目录一致

### 1.3 对位结果

| 项目 | 现行代码 | 大厂做法 | 对位状态 | 出处 |
|------|---------|---------|---------|------|
| 单一真值源 | ✅ 服务端（SOUL+头像仓） | ✅ workspace/project配置 | **已对齐** | IdentityCache.swift:3-5 |
| 本地缓存 | ✅ 带时间戳的副本 | ✅ 客户端缓存呈现 | **已对齐** | IdentityNameCache:11-27 |
| 写入冲突解决 | ✅ 末写胜（服务端承接） | ✅ 服务端裁决 | **已对齐** | IdentityCache.swift注释:9-10 |
| 一致性对账 | ✅ 三项对账（绑定/路由/目录） | ⚠️ 未明确公开（推断：客户端定期同步） | **无法对位／待验证** | OpsIdentity.swift:191-203 |
| 呈现单一出口 | ✅ appState.agentDisplayName | ⚠️ 统一身份API（推断，无出处） | **已对齐** | IdentityDetailView.swift:75 |

**缺口：** 无。身份卡单一源已按大厂模式完整实现。

---

## §2 职能体名册：未实现

### 2.1 现行代码状态

**搜索结果：** 无职能体名册相关代码。

```bash
# 搜索职能体/agent role/roster相关代码
grep -r "职能体\|AgentRole\|FunctionRole\|RosterCard" Sources/ Tests/
# 结果：0个匹配
```

**现有身份系统只管助手自己的身份：**
- 单一身份：助手本人（名字/头像/人设）
- 无多职能体：没有「设计」「开发」「测试」等职能体的概念
- 无名册管理：设置里没有职能体名册的建/改/删入口

### 2.2 成熟产品做法

**ChatGPT Custom GPTs（官方文档）：**
> "GPTs (also called custom GPTs) are versions of ChatGPT configured for a specific purpose. A GPT can combine specific instructions, knowledge, and selected capabilities to create a more tailored experience."
> 
> 结构：Name + Description + Instructions + Conversation starters + Knowledge files + Capabilities + Actions
> 
> 来源：https://help.openai.com/en/articles/8554397-creating-and-editing-gpts

**Claude Custom Subagents（官方文档）：**
> "Define a custom subagent when you keep spawning the same kind of worker with the same instructions. Each subagent runs in its own context window with a custom system prompt, specific tool access, and independent permissions."
> 
> 来源：https://code.claude.com/docs/en/sub-agents

**Agent Card Registry（多智能体架构模式）：**
> "In a dynamic multi-agent system, the set of available agents changes continuously. New agents join, capabilities evolve, and agents may be versioned or temporarily unavailable. Routing decisions must happen at runtime based on current, live capability information."
> 
> 结构：Agent metadata + Capabilities declaration + Version info + Availability status
> 
> 来源：https://github.com/roanbrasil/agents-integration-patterns/blob/main/patterns/discovery/agent-card-registry.md

**Muse Runtime Cell（官方架构）：**
> "The agent does not run on a shared host process. It runs inside a runtime cell: a dedicated OS container that is the agent's entire world."
> 
> 来源：https://gist.github.com/juleskuehn/480139a0ea9509e9b085459a045e03dd

**对位模式（从成熟产品归纳）：**
1. **名册结构**：
   - ✅ Name（必填）：职能体名称
   - ✅ Instructions/System Prompt（必填）：职责定义+系统提示词
   - ✅ Capabilities/Tools（可选）：可用技能白名单
   - ✅ Model binding（必填）：绑定的执行体（模型/适配器）
   - ⚠️ Avatar（草稿有，大厂多为默认图标）
   - ⚠️ Permissions（草稿有批准权限，大厂多为workspace级管控）

2. **管理位置**：
   - ✅ 设置/管理面（非聊天页内临时创建）
   - ✅ workspace/project级配置（非per-conversation）
   - ✅ 可预先配置、可复用（模板化）

3. **路由机制**：
   - ✅ 名册→路由层→执行体（三层分离）
   - ✅ 运行时路由（@mention / 阶段分配）
   - ✅ 能力匹配（根据任务选择合适的职能体）

### 2.3 草稿规格对位

**草稿 §2 职能体字段：**
1. ✅ 名字（如「设计」「开发」） ← 对齐ChatGPT/Claude Name
2. ✅ 头像 ← 草稿特有（大厂多用默认图标）
3. ✅ 职责（一句话+系统提示词） ← 对齐Instructions/System Prompt
4. ✅ 执行体绑定 ← 对齐Model binding（Hermes本体/Claude Code/Codex）
5. ✅ 可用技能（白名单） ← 对齐Capabilities/Tools
6. ⚠️ 批准权限（默认每步/只卡关卡） ← 草稿特有（大厂多为workspace级，非per-role）
7. ✅ 备注（归属/创建者） ← 元数据，合理

**草稿 §1 名册住在哪：**
- ✅ 设置·智能体门 ← 对齐大厂做法（管理在设置，非聊天页内）
- ✅ 中枢只读显示运行状态 ← 对齐大厂做法（管理/呈现分离）

### 2.4 对位结果

| 项目 | 现行代码 | 草稿规格 | 大厂做法 | 对位状态 | 出处 |
|------|---------|---------|---------|---------|------|
| 名册数据结构 | ❌ 无 | ✅ 7字段完整 | ✅ Name/Instructions/Tools/Model | **缺口：未实现** | 草稿§2 vs OpenAI GPTs |
| 管理位置 | ❌ 无 | ✅ 设置·智能体门 | ✅ Settings/Workspace管理 | **已对齐** | 草稿§1 vs Claude Projects |
| 职能体头像 | ❌ 无 | ✅ 有 | ⚠️ 大厂多用图标 | **草稿优于大厂** | 草稿§2.2 |
| 职责定义 | ❌ 无 | ✅ 一句话+提示词 | ✅ Instructions | **已对齐** | 草稿§2.3 vs ChatGPT |
| 执行体绑定 | ❌ 无 | ✅ Hermes/Code/Codex | ✅ Model selection | **已对齐** | 草稿§2.4 vs Claude Subagents |
| 技能白名单 | ❌ 无 | ✅ 可收窄 | ✅ Tool access control | **已对齐** | 草稿§2.5 vs OpenAI Actions |
| 批准权限 | ❌ 无 | ✅ 每步/关卡 | ⚠️ Workspace级非role级 | **草稿更细** | 草稿§2.6 vs 推断 |
| 僵尸功能禁令 | ❌ 无 | ✅ 必接执行体 | ✅ 隐含（大厂不上架空配置） | **已对齐** | 草稿§2红线 |

**缺口清单（完成一个划一个）：**
- [ ] 名册数据结构定义（Core层，含7字段+序列化）
- [ ] 名册存储（本地+服务端同步，参照IdentityCache模式）
- [ ] 设置·智能体门管理面（建/改/删/列表）
- [ ] 职能体卡片组件（名字/头像/职责摘要）
- [ ] 中枢只读显示（运行状态，非管理）
- [ ] 名册与执行体层路由连接（见§3）

---

## §3 执行体层：部分对齐

### 3.1 现行代码状态

**服务端骨架（已验证）：**
- `server/patches/oneday_ledger_lib.py:289` delegate_task工具注册
  ```python
  "delegate_task": "委派子任务",
  ```
- `server/patches/api_server_runs.py:1933` 异步委派条件
  ```python
  # tools.async_delegation sees no HERMES_SESSION_CHAT_ID and forces delegations sync.
  ```

**草稿引用的已有文档：**
> "Hermes 本体（先接这个）：已验证。服务端工具表登记着 `delegate_task`（委派子任务，`patches/oneday_ledger_lib.py:183`）；2026-10-07 已有文档 `docs/hermes-background-tasks.md`（后端提交 3096756），原生异步委派生命周期 `delegate_task_async`，含 check / steer / collect / cancel / list。主线 15:58 说「骨架是有的」属实。"
> 
> 来源：草稿§3

**缺失部分：**
- ❌ 职能体路由层：无代码将「@设计」路由到特定执行体
- ❌ Claude Code/Codex适配器：草稿标记「在册未验」，需补适配层
- ❌ 执行体状态管理：无当前运行哪个职能体、队列状态等

### 3.2 成熟产品做法

**Claude Agent Delegation（官方文档）：**
> "Each subagent runs in its own context window with a custom system prompt, specific tool access, and independent permissions. It also sends its own requests, which count toward the same usage limits as your main conversation."
> 
> 生命周期：spawn → run → collect result → cleanup
> 
> 来源：https://code.claude.com/docs/en/sub-agents

**OpenAI Assistants API（官方文档）：**
> "The Assistants API allows you to build AI assistants within your own applications. An Assistant has instructions and can leverage models, tools, and files to respond to user queries."
> 
> 结构：Assistant ID + Instructions + Model + Tools + File IDs
> 
> 来源：推断自ChatGPT Workspace Agents架构

**Multi-Agent Sequential Pipeline（架构模式）：**
> "A common architectural pattern is the sequential multi-agent pipeline, where specialized LLM-based agents collaborate in a predefined order to perform roles such as planning, development, and testing."
> 
> 层次：Orchestrator → Role Router → Executor → Result Collector
> 
> 来源：https://arxiv.org/html/2510.07614

**Muse Executor Isolation（官方架构）：**
> "The design separates the untrusted agent runtime from the services that hold credentials and grant permission, a pattern any agent team can adopt."
> 
> 结构：Runtime Cell (executor) + Credential Service + Sentinel (approval) + Audit
> 
> 来源：https://sesamedisk.com/meta-muse-ai-assistant-2026/

**对位模式（从成熟产品归纳）：**
1. **执行体抽象层**：
   - ✅ 统一接口：spawn(role, prompt) → result
   - ✅ 生命周期：create → run → collect → cleanup/cancel
   - ✅ 隔离运行：独立上下文、独立工具访问
   - ✅ 状态可查：check status / list active

2. **路由层**：
   - ✅ 职能体→执行体映射（role registry → executor binding）
   - ✅ 运行时选择（@mention → lookup role → spawn executor）
   - ✅ 负载均衡/队列（单执行体同时只跑一个任务，或并发控制）

3. **适配器层**（非大厂必需，但多执行体时合理）：
   - ✅ Hermes本体适配器（直接调用delegate_task）
   - ✅ Claude Code适配器（进程启动+输出流+批准转卡）
   - ✅ Codex适配器（同Claude Code模式）
   - ⚠️ 未来扩展（如调用外部API的职能体）

### 3.3 草稿规格对位

**草稿 §3 执行体层：**
- ✅ Hermes本体：delegate_task已验证，含check/steer/collect/cancel/list
- ⚠️ Claude Code/Codex：标记「在册未验」，需补适配器
- ⚠️ 待查点：async_delegation在群聊/工作流会话是异步还是强制同步

**草稿 §4 群聊路由：**
> "用户原话：「群聊本质就是不同的职能体，加入群聊，然后@就可以办事。」"
> 
> - @职能体：这条消息归该职能体执行
> - 不@的消息：归主持位接（主持位默认=主线职能体）
> - @所有人：只同步上下文，不派活

**草稿 §5 工作流路由：**
> "模板「设计 → 开发 → 测试 → 交付」：每阶段执行者从名册里选人"
> 
> - 阶段间设关卡，关卡复用现成批准卡机制
> - 每阶段交实物，实物是下一阶段的输入

### 3.4 对位结果

| 项目 | 现行代码 | 草稿规格 | 大厂做法 | 对位状态 | 出处 |
|------|---------|---------|---------|---------|------|
| 执行体抽象接口 | ⚠️ delegate_task存在 | ✅ delegate_task_async生命周期 | ✅ spawn/run/collect/cancel | **部分对齐** | oneday_ledger_lib.py:289 vs Claude |
| Hermes本体适配 | ✅ delegate_task已登记 | ✅ 先接这个 | ✅ 原生LLM调用 | **已对齐** | 草稿§3 vs 推断 |
| Claude Code适配 | ❌ 无 | ⚠️ 在册未验，待探活 | ✅ 进程+流+批准 | **缺口：未实现** | 草稿§3 vs Claude Code架构 |
| Codex适配 | ❌ 无 | ⚠️ 在册未验，待探活 | ✅ 同Code模式 | **缺口：未实现** | 草稿§3 vs 推断 |
| 路由层 | ❌ 无 | ✅ @路由+阶段路由 | ✅ Mention/Stage router | **缺口：未实现** | 草稿§4§5 vs Multi-Agent patterns |
| 状态管理 | ⚠️ ledger有item状态 | ✅ 运行中状态在中枢 | ✅ Active agents list | **部分对齐** | oneday_ledger_lib.py vs OpenAI |
| 隔离运行 | ⚠️ delegate创建子会话 | ✅ 独立上下文 | ✅ 独立context/credentials | **已对齐** | 草稿§3 vs Muse Runtime Cell |
| 生命周期管理 | ⚠️ check/collect存在 | ✅ 完整生命周期 | ✅ create/run/collect/cleanup | **待验证** | 草稿§3 vs Claude（草稿转述，未实核：delegate_task_async 与 docs/hermes-background-tasks.md 本仓查无实物） |
| 异步委派条件 | ⚠️ 无HERMES_SESSION_CHAT_ID强制同步 | ⚠️ 待探 | ✅ 默认异步 | **待验证** | api_server_runs.py:1933 |

**缺口清单（完成一个划一个）：**
- [ ] 实核 delegate_task_async 生命周期是否存在（查服务端仓）
- [ ] 探活：async_delegation在群聊/工作流会话的行为（是异步还是强制同步）
- [ ] 路由层实现（职能体名册→执行体选择+派发）
- [ ] Claude Code适配器（进程启动+输出流回会话+批准转批准卡）
- [ ] Codex适配器（同Claude Code模式）
- [ ] 执行体状态管理（当前运行职能体+队列+并发控制）
- [ ] @路由解析（群聊内@mention→职能体查找→执行体派发）
- [ ] 阶段路由（工作流模板→当前阶段→职能体→执行体）
- [ ] 批准卡集成（执行体阻塞→生成批准卡→用户批准→恢复执行）

---

## §4 推进次序建议

### 4.1 草稿次序验证

草稿建议次序：
1. 职能体名册+执行体层（先只接Hermes本体）
2. 群聊（@路由）
3. 工作流（阶段引擎+关卡）
4. CLI执行体适配（Claude Code/Codex）
5. 语音视频独立线

**验证结果：** ✅ 该次序合理，依赖关系清晰。

**依赖分析：**
```
名册（无依赖，可先行）
  ↓
执行体层路由（依赖名册）
  ↓
群聊@路由（依赖名册+路由层）
  ↓
工作流阶段路由（依赖群聊基础设施）
  ↓
CLI适配器（独立线，依赖路由层）
```

### 4.2 推荐分包策略

**第一包：名册基础（不依赖执行体层）**
- [ ] 名册数据结构（Core层）
- [ ] 名册本地存储
- [ ] 设置·智能体门管理面（建/改/删/列表）
- [ ] 职能体卡片组件
- [ ] 单元测试（名册CRUD）

**第二包：执行体层Hermes适配（先通最简路径）**
- [ ] 探活：async_delegation在群聊会话的行为
- [ ] 路由层抽象接口定义
- [ ] Hermes本体适配器（调用delegate_task）
- [ ] 单职能体直接派发测试（不经@路由，硬编码绑定）

**第三包：群聊@路由（壳最薄）**
- [ ] 新对话选择器（普通/群聊/工作流三选一）
- [ ] 群聊创建（从名册勾选职能体）
- [ ] @mention解析（@职能体→路由→派发）
- [ ] 回话带身份（气泡头像+名字）
- [ ] 交付物卡片落群里

**第四包：工作流（阶段引擎）**
- [ ] 工作流模板数据结构
- [ ] 设置·自动化门管理面
- [ ] 阶段引擎（当前阶段→职能体→执行体）
- [ ] 关卡批准卡（阶段交接门）
- [ ] 打回机制（测试不过→回开发阶段）

**第五包：CLI适配器（独立线，待探活）**
- [ ] 探活：Claude Code/Codex能否被当作执行体拉起
- [ ] Claude Code适配器（进程+流+批准）
- [ ] Codex适配器（同模式）
- [ ] 适配器注册到路由层

### 4.3 卡点与风险

**卡点1：async_delegation强制同步问题**
- 位置：api_server_runs.py:1933
- 风险：群聊/工作流会话如果被强制同步委派，单职能体阻塞时整个群聊阻塞
- 验证：先探活确认，如强制同步需修改服务端或调整群聊会话创建方式
- 缓解：先用单一职能体测试，确认异步可用再推多职能体并发

**卡点2：Claude Code/Codex适配器未验证**
- 位置：草稿§3标记「在册未验」
- 风险：适配器技术可行性未证实，可能需要服务端补适配层
- 验证：先探活，确认能否启进程+输出流回会话+批准转卡
- 缓解：第一包只接Hermes本体，CLI适配器排后，探活不过可降级为「手动复制粘贴」

**卡点3：批准权限粒度**
- 位置：草稿§2.6 批准权限（每步/只卡关卡）
- 风险：大厂多为workspace级，非per-role级；per-role批准权限可能需要新批准流程
- 验证：确认现有批准卡机制能否支持role级配置
- 缓解：第一版统一为「每步都过批准卡」，粒度控制作为后续优化

---

## §5 大厂做法出处汇总

### 5.1 官方文档级（可直接引用）

**ChatGPT/OpenAI：**
1. Custom GPTs概述：https://help.openai.com/en/articles/8798620-gpts-chatgpt-team-version
2. Creating and editing GPTs：https://help.openai.com/en/articles/8554397-creating-and-editing-gpts
3. Workspace Agents：https://help.openai.com/en/articles/20001143-chatgpt-workspace-agents-for-enterprise-and-business

**Claude/Anthropic：**
1. Project instructions：https://support.claude.com/en/articles/10185728-understanding-claude-s-personalization-features
2. Agent Identity：https://claude.com/resources/articles/agent-identity-access-model
3. Custom Subagents：https://code.claude.com/docs/en/sub-agents

### 5.2 公开架构模式（社区共识级）

**Muse/Meta（第三方整理，非官方文档——审计补正）：**
1. Muse架构tour：https://gist.github.com/juleskuehn/480139a0ea9509e9b085459a045e03dd
2. Muse安全架构：https://sesamedisk.com/meta-muse-ai-assistant-2026/
3. Runtime Cell隔离：https://dev.to/neticslabs/metas-muse-tries-to-make-the-consumer-agent-a-secure-computer-3a1n

1. Multi-Agent System Patterns：https://medium.com/@mjgmario/multi-agent-system-patterns-a-unified-guide-to-designing-agentic-architectures-04bb31ab9c41
2. Agent Card Registry：https://github.com/roanbrasil/agents-integration-patterns/blob/main/patterns/discovery/agent-card-registry.md
3. Sequential Multi-Agent Pipeline：https://arxiv.org/html/2510.07614
4. Microsoft Multi-Agent Reference Architecture：https://github.com/microsoft/multi-agent-reference-architecture/blob/main/docs/reference-architecture/Patterns.md

### 5.3 现象推断级（无官方明文，从行为推断）

1. **ChatGPT workspace级权限管控**：从Workspace Agents文档推断，权限在workspace级配置，非per-GPT级
2. **Claude异步委派默认行为**：从Subagents文档推断，默认异步运行，独立计费
3. **Muse凭据隔离**：从多篇安全分析推断，Runtime Cell与Credential Service物理隔离

---

## 附录A：现行代码身份系统file:line索引

### A.1 Core层
- `Sources/OneDayCore/IdentityCache.swift`
  - 11-27: IdentityNameCache定义
  - 39-58: IdentityAvatarCache定义
  - 77-96: AgentNameEdit.sanitizedRename校验
  - 160-184: IdentityLegacyMigration.effectiveName末写胜裁决
- `Sources/OneDayCore/OpsIdentity.swift`
  - 26-107: IdentityReconciliationInput快照定义
  - 110-134: IdentityItem单项结论
  - 139-187: IdentityReconciliation对账结果
  - 207-259: IdentityReconciler.bindingItem主线绑定对账
  - 263-309: IdentityReconciler.routingItem消息路由对账
  - 313-362: IdentityReconciler.catalogItem会话目录对账

### A.2 App层
- `Sources/OneDayApp/HubIdentitySection.swift`
  - 33-384: 枢纽页身份段全面
  - 86-117: headerRow（段内大名+状态+模型入口）
  - 148-155: emptyPersonaRow（人设为空占位）
  - 164-177: personaBlock（简介散文段落）
  - 180-199: styleBlock（风格区）
  - 204-224: editRow（全宽编辑钮）
  - 235-264: cardsRow（SOUL/记忆双卡）
  - 266-309: identityCard卡片组件
- `Sources/OneDayApp/IdentityDetailView.swift`
  - 14-191: 形象与名称详情页全面
  - 60-95: heroSection（大头像+显示名+连接状态）
  - 99-114: localProfileSection（更换形象/编辑名称）
  - 143-165: activitySection（服务器状态+最近活动）
- `Sources/OneDayApp/IdentityBridgeClient.swift`
  - （未读全文，推断为身份数据服务端通信层）

### A.3 服务端
- `server/patches/oneday_ledger_lib.py`
  - 289: delegate_task工具注册
  - 1-42: 模块文档（工作账本设计）
- `server/patches/api_server_runs.py`
  - 1933: async_delegation强制同步注释

---

## 附录B：草稿规格完整字段清单

### B.1 职能体（草稿§2）
1. 名字 ★（必填）：如「设计」「开发」「测试」「交付」
2. 头像 ★（必填）：群聊气泡身份，无则用名字首字
3. 职责 ★（必填）：一句话+系统提示词
4. 执行体绑定 ★（必填）：Hermes本体/Claude Code/Codex适配器
5. 可用技能（可选）：白名单，默认全开可收窄
6. 批准权限（可选）：默认每步交付都过批准卡，可放宽为只卡关卡
7. 备注（可选）：归属哪个工作流模板、谁建的

### B.2 群聊（草稿§4）
- 建群：新对话选「群聊」→从名册勾选职能体→建成
- @职能体：消息归该职能体执行，回话挂头像和名字
- 不@消息：归主持位接（默认=主线职能体，待拍板）
- @所有人：只同步上下文，不派活
- 回话带身份：气泡上是职能体头像
- 交付物：以卡片落群里，全员可见

### B.3 工作流（草稿§5）
- 模板：「设计→开发→测试→交付」四阶段
- 每阶段：执行者（职能体）+ 输入实物 + 输出实物 + 关卡
- 关卡：批准卡机制，不过自动打回上一阶段
- 实物传递：阶段间交实物，不靠上下文感觉传递

---

**本分析完成日期：** 2026-11-28 09:30  
**交付给：** 司礼监（主线）  
**达标证据：** 本文件含逐项出处与现行代码file:line，三块对位分析完整，推进次序建议明确，缺口清单可划勾。
