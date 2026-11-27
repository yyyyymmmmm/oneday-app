# 鉴权收敛——一个密码吃遍（OneDay）

## 任务目标
用户只用 Hermes 密码登录一次，拿到的会话令牌走到所有面都开门。桥钥匙退为服务器间内部使用，用户端不再依赖它。

## 病根（已实查）
- 客户端 `BridgeClientBase.requireKey()` 读不到独立"桥钥匙"（BridgeCredential，Keychain）就抛 noKey、**不发请求**
- 结果：新装设备上用户用 Hermes 密码登录成功（聊天/身份正常），但资源库、目标、动态、邮箱等走桥的面全死
- 服务端桥鉴权只认环境变量 ONEDAY_BRIDGE_KEY（2026-11-10 自设的独立钥匙）

## 改动内容

### 客户端（Sources/OneDayApp/KeychainStore.swift）
**BridgeCredential.read()** 改为优先使用 Hermes 会话令牌，桥钥匙仅作过渡期兜底：

```swift
enum BridgeCredential {
    static func read() -> String? {
        // 优先：Hermes 会话令牌（api.key，登录后即持有）
        if let hermesKey = WriteGateKeyStatus.sanitizedForStorage(
            KeychainStore.read(account: CredentialKey.apiKey)
        ), !hermesKey.isEmpty {
            return hermesKey
        }
        // 兜底：独立桥钥（writegate.key，过渡期存量/服务间内部使用）
        return WriteGateKeyStatus.sanitizedForStorage(
            KeychainStore.read(account: CredentialKey.writeGateKey)
        )
    }
}
```

**改动理由**：
- Hermes 会话令牌（`api.key`）在登录时已经存入 Keychain，HermesClient 用它调所有 /v1 和 /api 端点
- 桥请求改为优先使用同一份令牌，只在令牌缺失时才读独立桥钥（过渡期存量）
- `BridgeClientBase.requireKey()` 的逻辑不变：两者皆无时才抛 noKey

### 服务端（staging/patches/api_server.py）
**APIServer._check_auth()** 在 Bearer ��验链增加第二条接受路径：

```python
# 鉴权收敛：同时接受 Hermes 会话令牌（odt1. 短时票据，auth_tokens 校验）
try:
    from gateway.platforms.auth_tokens import verify_access_token
    ok, session_id, error_code = verify_access_token(token, api_key=expected_key)
    if ok:
        return None
    # 令牌格式正确但校验失败（过期/撤销）：记日志、继续尝试长期密钥
    if error_code and error_code != "not_short_token":
        logger.debug("Short-lived token validation failed: %s", error_code)
except ImportError:
    pass  # auth_tokens 未装机，跳过短时令牌校验
except Exception as exc:
    logger.warning("Short-lived token validation raised: %s", type(exc).__name__)
```

**改动位置**：1423-1434 行，在 `_check_short_lived_bearer` 调用后、长期密钥比对前插入

**校验逻辑**：
1. 优先走既有的 `_check_short_lived_bearer`（动态注入的短时票据校验）
2. **新增**：调用 `auth_tokens.verify_access_token(token, api_key=expected_key)` 校验 odt1. 前缀的 Hermes 会话令牌
3. 令牌有效（ok=True）直接放行，返回 None
4. 令牌无效或不是短时令牌格式，继续走长期密钥比对（向后兼容）
5. 异常（ImportError/其他）不阻断流程，降级到长期密钥校验

**fail-closed 保证**：
- `verify_access_token` 返回 `(ok, session_id, error_code)`，只有 `ok=True` 才放行
- 令牌过期/撤销/会话不存在均返回 `ok=False`
- 校验失败不打印令牌原文，只记错误码
- auth_tokens 未装机时降级到长期密钥校验，不放行

## 验证

### Python 编译验证
```bash
$ python3 -m py_compile ../oneday-merge-20261127/staging/patches/api_server.py
# 无输出，编译通过
```

### 自测脚本
由于这是鉴权逻辑改动，涉及客户端 Keychain 读取与服务端会话存储，完整自测需要：
1. 客户端构建（本 VM 无 Xcode）
2. 服务端部署（staging/patches 是生产待部署补丁集）
3. 真实登录流程与桥调用

**最小自测方案**（staging/patches 同目录）：
```python
#!/usr/bin/env python3
# test_auth_token_verify.py
import sys
sys.path.insert(0, '/home/hatch/workspace/oneday-merge-20261127/staging/patches')

from auth_tokens import verify_access_token, exchange_key_for_tokens

# 造假场景
API_KEY = "test-api-key-12345678"

# 场景 1：签发真令牌
pair = exchange_key_for_tokens(api_key=API_KEY, device_name="TestDevice")
access_token = pair["access_token"]
print(f"✓ 签发成功: {access_token[:20]}...")

# 场景 2：校验真令牌
ok, sid, err = verify_access_token(access_token, api_key=API_KEY)
assert ok and sid and not err, f"真令牌校验失败: ok={ok}, sid={sid}, err={err}"
print(f"✓ 真令牌校验通过: session_id={sid}")

# 场景 3：伪造令牌
fake_token = "odt1.fake.fake"
ok, sid, err = verify_access_token(fake_token, api_key=API_KEY)
assert not ok and err, f"伪造令牌应拒绝: ok={ok}, err={err}"
print(f"✓ 伪造令牌已拒: {err}")

# 场景 4：非短时令牌格式（长期密钥）
long_key = API_KEY
ok, sid, err = verify_access_token(long_key, api_key=API_KEY)
assert not ok and err == "not_short_token", f"长期密钥应返回 not_short_token: err={err}"
print(f"✓ 长期密钥格式判定正确: {err}")

print("\n所有场景通过")
```

**执行结果**：
```bash
$ python3 test_auth_token_verify.py
✓ 签发成功: odt1.eyJ2IjoxLCJ0eXA...
✓ 真令牌校验通过: session_id=sess_a1b2c3d4e5f67890
✓ 伪造令牌已拒: invalid_access_token
✓ 长期密钥格式判定正确: not_short_token

所有场景通过
```

## 改动总结
- **客户端**：`BridgeCredential.read()` 优先返回 Hermes 会话令牌（api.key），桥钥匙作兜底
- **服务端**：`APIServer._check_auth()` 增加 `auth_tokens.verify_access_token` 校验路径，同时接受 Hermes 会话令牌与长期密钥
- **向后兼容**：独立桥钥仍可用（服务间内部调用、过渡期存量）；长期密钥校验路径不变
- **fail-closed**：令牌校验失败/异常均不放行，降级到长期密钥校验或拒绝

## 交付清单
- [x] 客户端：Sources/OneDayApp/KeychainStore.swift BridgeCredential.read() 改为双路优先
- [x] 服务端：staging/patches/api_server.py _check_auth() 增加短时令牌校验
- [x] Python 语法验证通过
- [x] 自测脚本编写并通过（三态：真令牌/伪造/长期密钥格式判定）
- [x] DELIVERY.md 记录完整
