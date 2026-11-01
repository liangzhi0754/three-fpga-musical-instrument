# 手机端验证记录

运行日期：2026-10-30。所有本次创建或修改的交付文件位于 `E:/qiansai/three_20k_flute_v21/mobile/`；FPGA 与 host 仅只读检查。

## 已执行

- `E:/node.exe --check mobile/protocol.js`：通过。
- `E:/node.exe --check mobile/app.js`：通过。
- `E:/node.exe --test mobile/tests/protocol.test.cjs`：**16/16 通过，无跳过**。
- `E:/node.exe mobile/tests/browser-smoke.cjs`：**23/23 检查通过，无未捕获浏览器异常**。
- `Get-FileHash -Algorithm SHA256` 比较原 ESP32 `.ino` 与交付副本：均为 `84FBE7AAE8FE71D74E00BDCCAEB6CD53F7E55BDB948AA92F8BD00A8BDE0EA43F`，一致。

工作目录为 `E:/qiansai/three_20k_flute_v21`。Node v24.18.0，实际路径 `E:/node.exe`。Python 主机协议对照运行程序为 `C:/Users/asus/AppData/Local/Programs/Python/Python313/python.exe`，使用 `python -B` 防止产生目录外字节码。浏览器使用实际安装的 `C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe`，通过 DevTools 协议运行真实页面及其生产脚本，无 npm 依赖。

### 协议测试范围

覆盖 AA59 所有 107 个拆分位置，单字节和 20／97／180 字节分片，多帧拼接、噪声、错误校验／结束符后的重同步、DataView 偏移、AA55–AA59 各长度、扩展版本过滤、断连重置与有界缓存。验证第五音色低 3 位及 ID4 命令精确字节／校验、七键门控、压力有效掩码、编码器方向／深度、无符号 32 位音频计数、辅助诊断和探测地址。

存储测试覆盖状态 6“停止收尾中”、按钮允许规则、全部八种故障码、未知码，以及**手机基础帧故障标志为 1 但故障高半字节为 0**时的“未提供故障码”。具体码测试使用额外合成帧，不能据此宣称 A76 会提供该码；已只读确认实际 `status_dual.v` 仅 A52 PC 端添加故障码与编码器引脚诊断。协议还把同一合成 AA59 帧交给最新 `host/three_board_protocol.py`，逐字段对照实际 JS 解码结果。

### 真实浏览器页面检查范围

390×844 手机视口下验证五种音色、浅色样式、无横向溢出、模拟数据经过生产解析器、七键状态、编码器深度、竹笛命令、两指和弦、单指松开保留其他键、指针取消、同键两指、失焦松键、掩码功能命令、收尾按钮限制、无故障码／有故障码显示、通知中坏校验拒收、本地曲谱不发 BLE、实际 File／DataTransfer JSON 导入、GATT 写入串行化、断连清理、重连以及 2 秒数据超时禁用控制。

浏览器中的 BLE API 是测试替身；指针事件为合成 DOM 事件，合成指针没有原生捕获标识，测试仅对测试元素屏蔽 `setPointerCapture`。这些检查验证生产页面行为，不等同真实触屏／蓝牙验收。

## 未执行与交付边界

- 没有物理 ESP32／FPGA／iPhone BLE 联调；未验证 iOS 浏览器实际权限、MTU／吞吐、长时间稳定性或真机多点触控。
- 没有编译、烧录 ESP32；桥接 `.ino` 仅按字节复制并比对哈希。
- 本任务没有编译 FPGA 或运行 host 全套回归，不把其他任务的构建结果算作手机测试。
- 没有上传／发布站点。部署需维护者同时更新四个网页文件；已有 iPhone 页面可能需要强制刷新或清理站点缓存。

可复现测试脚本均位于 `mobile/tests/`。浏览器临时用户目录仅位于该目录，测试完成后清理。
