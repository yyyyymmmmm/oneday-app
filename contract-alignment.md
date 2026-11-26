# 服务端契约对账表

对照服务端正本 `oneday-server/server/patches/credential_vault.py`，全量核对本分支 Vault 相关文件中与服务端契约对位的字符串字面量。

## 对账时间
2024-11-26（返工单 2 修复时）

## 对账范围
- decision 值（fulfill/reject）
- status 值（pending/fulfilled/rejected/expired/superseded/consumed）
- 响应键（credential_ref）
- 请求体键（name/service/domains/values/username）

## 对账结果

| 类型 | 客户端字面量 | 服务端契约 | 位置 | 状态 |
|------|-------------|-----------|------|------|
| **decision 值** |
| fulfill | `"fulfill"` | `body.get("decision") not in ("fulfill", "reject")` | VaultRequestCard.swift:269 | ✅ 已对齐 |
| reject | `"reject"` | 同上 | VaultRequestCard.swift:306 | ✅ 已对齐 |
| **status 值** |
| pending | `"pending"` | 服务端返回状态 | VaultRequestCard.swift（未直接写入，仅判断） | ✅ 已对齐 |
| fulfilled | `"fulfilled"` | 服务端返回状态 | VaultRequestCard.swift:276 | ✅ 已对齐 |
| rejected | `"rejected"` | 服务端返回状态 | RequestCardStatus enum | ✅ 已对齐 |
| expired | `"expired"` | 服务端返回状态（通过错误消息判断） | VaultRequestCard.swift:284,318 | ✅ 已对齐 |
| consumed | `"consumed"` | 服务端返回状态（通过错误消息判断） | VaultRequestCard.swift:286,320 | ✅ 已对齐 |
| superseded | - | 服务端返回状态 | 客户端未显式处理（属于请求已失效类） | ⚠️ 未处理（非关键路径） |
| **响应键** |
| credential_ref | `credentialRef = "credential_ref"` | 服务端响应键 | VaultModels.swift:104 | ✅ 已对齐 |
| **请求体键** |
| name | 结构体字段 `name` | 服务端请求体键 | VaultModels.swift:41,49 | ✅ 已对齐 |
| service | 结构体字段 `service` | 服务端请求体键 | VaultModels.swift:42,50 | ✅ 已对齐 |
| domains | 结构体字段 `domains` | 服务端请求体键 | VaultModels.swift:43,51 | ✅ 已对齐 |
| values | 结构体字段 `values` | 服务端请求体键 | VaultModels.swift:44,52,94 | ✅ 已对齐 |
| username | 结构体字段 `username` | 服务端请求体键 | VaultModels.swift:45,53,95 | ✅ 已对齐 |

## 本次修复
- **decision 值错误**：由 `"approve"` 改为 `"fulfill"`（VaultRequestCard.swift:269），服务端只认 fulfill/reject，approve 会触发 400 错误
- **新增单测**：6 个归属匹配测试，覆盖 service/domain 匹配逻辑的正反样本

## 备注
- `superseded` 状态客户端未显式处理，但不影响核心流程（请求已失效场景会通过其他错误路径处理）
- 所有编码/解码字段通过 `Codable` 自动映射，字段名与服务端契约一致
