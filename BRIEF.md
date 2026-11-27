# 任务：鉴权收敛——一个密码吃遍（OneDay）

你在 git worktree ~/workspace/wt-auth（分支 feat/auth-one-token，基线 main 3f493e10）里施工。只许改本任务相关文件；不许碰其他分支；完工后在本分支提交（可多笔），并写 DELIVERY.md 记录改了什么、为什么、怎么验。

## 病根（已实查，不必重新论证）
- 客户端 `Sources/OneDayApp/BridgeClientBase.swift` 的 `requireKey()` 读不到独立"桥钥匙"（BridgeCredential，Keychain）就抛 noKey、**不发请求**。结果：新装设备上用户用 Hermes 密码登录成功（聊天/身份正常），但资源库、目标、动态、邮箱等走桥的面全死。
- 服务端桥鉴权在 `server/companion/modules/oneday_bridge.py` 的 `_authed()`：只认环境变量 ONEDAY_BRIDGE_KEY（2026-11-10 自设的独立钥匙）。同仓 `server/patches/auth_tokens.py` 是 Hermes 本体的令牌体系（odt1. 前缀令牌，HermesClient 登录后持有的就是它）。

## 目标形态（业主原话：一个密码吃遍；能用 Hermes 本来的就用 Hermes 本来的）
用户只用 Hermes 密码登录一次，拿到的 Hermes 会话令牌走到所有面都开门。桥钥匙退为服务器间内部使用，用户端不再依赖它。

## 施工内容
### 客户端（本 worktree 的 Sources/）
1. 先查清 HermesClient 登录后把会话令牌存在哪（Keychain/ServerConfig 周边），找到单一真源。
2. `BridgeClientBase`：桥请求的 Bearer 改为优先使用该 Hermes 会话令牌；桥钥匙仅作过渡期兜底（令牌缺失时才读 BridgeCredential）。`requireKey()` 的 noKey 只在两者皆无时抛。
3. 受影响面不止 OneDayBridgeClient：CompanionFrontClient 等凡走 BridgeClientBase 取钥的，一并受益，不许逐个打补丁——收口在 BridgeClientBase 一处。
4. 不许改登录流程本身，不许动 UI。

### 服务端（生产形态在 ../oneday-merge-20261127/staging/patches/，那是即将部署的 2.19.0 补丁集；仓库 server/patches 是旧基线，不要在旧基线上做）
5. 读 staging/patches 里的 auth_tokens.py，搞清 odt1. 令牌的校验函数（同步/异步、从哪读会话存储）。
6. staging/patches 里对应生产 oneday_bridge 的文件（若桥在 companion 形态则看 ../oneday-merge-20261127/server/companion/modules/oneday_bridge.py 的生产对应物——以 staging/patches 清单为准）：给 `_authed` 加第二条接受路径：请求 Bearer 若是合法 Hermes 会话令牌（经 auth_tokens 校验）同样放行；桥钥匙路径保留（服务间调用）。
7. front_gateway、write_gate_gateway 若也面向 App 流量且各有独立鉴权，同法加认；纯服务间的不要动。动前在 DELIVERY.md 里逐个写清判断依据。
8. 校验必须 fail-closed：令牌无效/过期/存储读不到，一律拒绝，不许异常放行。校验失败不许打日志输出令牌原文。

## 纪律
- 这里是 Linux VM，没有 Xcode，不能构建 iOS；Swift 改动保持语法严谨、最小 diff，交付后由 Mac 构建验。
- Python 改动必须过 `python3 -m py_compile`；给 _authed 的新路径写一个最小自测脚本（造假令牌/真令牌/过期令牌三态）放 staging 同目录并跑通，输出贴进 DELIVERY.md。
- 不许改 staging 里 oneday_db 迁移相关文件；不许动无关文件。
- 提交信息用中文说清事由。
