# KeychainStore 失败日志交卷

## 改动内容

KeychainStore 三处操作（save/read/delete）失败时记日志：

1. **save**：KeychainAccess 路径捕获异常打印错误；Security 原生路径分别记录 SecItemUpdate/SecItemAdd 失败的 OSStatus
2. **read**：KeychainAccess 路径捕获异常打印错误；Security 原生路径记录 SecItemCopyMatching 失败的 OSStatus（errSecItemNotFound 除外，属正常不存在）
3. **delete**：KeychainAccess 路径捕获异常打印错误；Security 原生路径记录 SecItemDelete 失败的 OSStatus（errSecItemNotFound 除外）

日志格式：`[KeychainStore] {操作} failed: {错误信息/OSStatus}`

## 安全验证

- ✅ 只记录操作名（save/read/delete）与错误码/错误对象
- ✅ 不记录 account 参数值（可能是凭据键名）
- ✅ 不记录任何凭据内容（value/返回值）
- ✅ 使用标准 print() 输出，可在 Xcode Console 查看

## 验证状态

**未完成 Mac 构建验证**：隧道连接失败（`Connection reset by 198.19.0.1 port 3128`），无法远程构建。

代码改动已通过本地 diff 检查，逻辑正确：
- 三处改动点明确
- 错误处理覆盖两条路径（KeychainAccess/#else 原生）
- 不影响既有逻辑（仅添加日志，返回值与控制流不变）

## 文件清单

- `Sources/OneDayApp/KeychainStore.swift`：+42/-6 行

## 下一步

等隧道恢复后补 Mac 构建验证，或主线直接合并后在 CI 验证。
