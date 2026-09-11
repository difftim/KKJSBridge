# Form body recovery 回归测试

这些测试验证 KKJSBridge 的普通原生表单恢复逻辑。测试源码和本机辅助服务不在 podspec 的生产源码、资源匹配范围内，不随 App 发布。

## 环境与入口

需要 macOS、可用的桌面登录会话、Xcode（`xcrun swiftc` / `xcrun clang`）及 Python 3。Python 仅使用标准库；无需安装 npm 包、Python 包、Pods，也不需要启动 iOS 模拟器。

在 KKJSBridge 仓库根目录运行：

```sh
make test-form-body
```

各套件串行执行；失败返回非零退出码。需要定位单个层次时可运行：

| 命令 | 验证范围 |
| --- | --- |
| `make test-form-body-native` | 真实 Foundation 缓存实现：规则、来源与目标校验、窗口 scope、query 保真、一次性消费、取消、超时及过期 |
| `make test-form-body-webkit` | 真实 macOS WKWebView：submit/formdata 时序、字段保留、取消/重复提交、不支持的表单、两个窗口同时提交 |
| `make test-url-protocol` | 真实 URLProtocol、旧缓存和序列化：同步发包、缓存未命中、取消清理、SSE 回调、表单停止状态隔离；网络和 Cookie 使用替身 |
| `make test-form-body-wire` | 本机 HTTP 回显：比较恢复数据与浏览器实际 POST，校验发送 frame 的来源 |

成功时输出对应 `PASS` 汇总。原生过期测试会实际等待约 10 秒；完整套件还需要编译和启动 WebKit，耗时因机器而异。

## 文件职责

- `URLProtocolIsolationTests.m`：编译生产 URLProtocol、两套缓存和旧 body 序列化；只替换外部网络管理器、Cookie 同步和 JS 执行。刻意保留旧路径在 task 创建期间取消的既有行为，不代表该边界没有历史缺陷。
- `FormBodyStoreTests.m`：直接编译生产缓存实现，不使用缓存替身。
- `FormBodyRecoveryWebKitTests.swift`：加载生产 JS，桥接使用测试替身，取消实际网络导航。包含 SSO 两步表单的回归样例和双窗口隔离测试。
- `form_submit.fixture.js`：提供的 SSO 提交脚本样本，用来保留防重复提交和延迟禁用按钮的行为；更新样本时应说明原因。
- `FormBodyWireTests.swift`：加载生产 JS，通过真实浏览器 POST 与本机回显比对。
- `wire_server.py`：仅监听 `127.0.0.1` 的随机可用端口，提供虚构表单并回显请求体；运行结束后关闭服务，不访问真实 SSO。

## 产物与清理

可执行文件和编译模块缓存统一位于当前仓库的 `.build/form-body-tests/`，已加入 `.gitignore`。不同 checkout 不再共享硬编码的 `/tmp` 可执行文件。需要清理时可删除该目录，下次执行会重新生成。

日志默认输出到终端；若需保存，放入上述已忽略目录。不要提交生成的二进制、模块缓存、运行日志或真实账号/token 样本。生产 JS/原生源码、测试源码、fixture 和 Makefile 应保留在版本控制中。

## 覆盖边界

这些是 macOS 原生组件/WebKit 回归，不等于完整的 iOS KKJSBridge → 网络代理 → SSO 后端测试。WebKit 事件测试使用桥接替身；本机对照测试由浏览器直接发包，不经过 iOS URLProtocol 代理链。

URLProtocol 测试不启动真实 XHR/fetch、不执行 Cookie 同步，也不覆盖代理网络库的重定向处理。

真机仍需验证实际登录、错误重试、重定向和后端收到的 body。文件上传、iframe、新窗口提交、异步修改同一 FormData 等不在当前通用支持承诺内；某个“不介入”测试通过，只说明保留了旧路径，不表示旧路径没有问题。
