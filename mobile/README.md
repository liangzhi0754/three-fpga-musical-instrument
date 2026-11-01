# 七音竹笛 v21 · 手机 BLE 页面

本目录是从 `E:/qiansai/bluetooth_work_v1/bluetooth_work_v1/mobile_deploy/index.html` 及同级 `esp32c3_bridge` 基线更新的手机端。浅色简洁界面，支持七键多点触控、本地 JSON 曲谱指引、设备录制／重演、压力升降音表情、编码器颤音及传感器诊断。

五种音色 ID：0 正弦、1 锯齿、2 方波、3 大提琴32、4 空灵竹笛32。扩展状态音色取低 **3** 位；32 表示每音谐波数，最多七键同时发声。声音由已烧录的 FPGA 产生，网页不合成声音。配套 FPGA v21 已更新第五音色；本目录不包含 FPGA／PC 的修改或编译工作。

## 交付文件与更新路径

网页部署所需 **4 个文件**，必须一起更新并保持在同一目录：

| 文件 | 用途 |
|---|---|
| `index.html` | 手机页面入口 |
| `styles.css` | 浅色样式 |
| `protocol.js` | 实际运行的二进制协议解析与命令构造 |
| `app.js` | BLE 连接、界面、多点弹奏及本地曲谱 |

本地交付目录：`E:/qiansai/three_20k_flute_v21/mobile/`。另外包含中文说明、`esp32c3_bridge/esp32c3_bridge.ino` 源码副本、`tests/` 与 `TEST_RESULTS.md`，它们无需部署到网站。

更新现有手机入口：由网站维护者把以上 4 文件放到**现有已托管 URL 对应的目录**，替换入口 HTML 并添加／更新其余三个文件。原手机收藏／入口 URL 可以继续使用。不能只替换 HTML，否则会缺少脚本或样式。原基线 `mobile_deploy/` 没有被修改；请从这里取新版文件。

若另建入口，由维护者把这 4 文件上传至一个 HTTPS 静态站点目录，并在手机打开其 `index.html`。本次没有上传、发布或修改任何公共网站。

**原有 iPhone 页面可能仍使用缓存。更新后请强制刷新，或完全关闭旧页面再打开原 HTTPS 地址；必要时在所用 BLE 浏览器中清除该站点缓存。** 如托管缓存仍未更新，可临时在入口 URL 加 `?v=21`，同时清理／刷新站点脚本与样式缓存。可用五个音色按钮、第五项“空灵竹笛32”和浅色界面确认新版已经载入。

## iPhone 使用方式

这仍是 Web Bluetooth HTML 页面，不是新打包的原生 iOS App。iPhone 必须使用原来支持 Web Bluetooth 的兼容 iOS BLE 浏览器，并确认该浏览器当前版本提供 `navigator.bluetooth`。**Safari 不支持 Web Bluetooth，不能连接；添加 Safari 主屏幕入口也不会获得 BLE 能力。** 页面会提示浏览器不支持，仍可使用模拟演示与本地曲谱。

1. 设备上电，ESP32 广播 `FPGA-Instrument-C3`。
2. 在兼容 BLE 浏览器打开现有更新后的 HTTPS 入口，允许蓝牙权限。
3. 点“连接蓝牙”，选择设备，等待“数据在线”。初始收到有效状态后才能发送设备操作。
4. 选择“空灵竹笛32”，同时按多个键检查和弦；松手应停止手机音符。页面切后台、丢失焦点、指针取消和断连会释放手机按键。按住期间每 150 ms 刷新，FPGA 还保留 500 ms 超时保护。
5. 压力片释放后可设置“压力零点”。“编码器颤音”使用旋转编码器；旧距离传感器不再控制颤音。
6. 录制先“准备／擦除”（会删除已有演奏记录），再开始录制。停止后等待“停止收尾中”结束，再重演／保存。网页按设备状态限制按钮；手机命令回显只说明设备收到了该序号，操作结果以状态为准。

普通局域网 HTTP 手机地址通常不能使用 Web Bluetooth；正式手机入口用 HTTPS。本机 `localhost`／`127.0.0.1` 仅供桌面测试。实际可用性取决于兼容浏览器、权限及设备连接，尚未在物理 iPhone 上验证。

## 接线：手机与 PC 使用独立串口

UART 为 **115200、8N1、3.3 V 逻辑**，所有相关设备共地。

| 输出端 → 输入端 | 用途 |
|---|---|
| FPGA A76（手机 TX）→ ESP32-C3 GPIO5（UART1 RX） | FPGA 状态到手机 |
| ESP32-C3 GPIO4（UART1 TX）→ FPGA A80（手机 RX） | 手机命令到 FPGA |
| FPGA A52（PC TX）→ USB-TTL RXD | FPGA 状态到 PC |
| USB-TTL TXD → FPGA A86（PC RX） | PC 命令到 FPGA |
| FPGA GND ↔ ESP32 GND ↔ USB-TTL GND | 共地 |

**不要把两个 TX 输出并接。** PC 的 USB-TTL TXD 接 A86，不接已由 ESP32 GPIO4 驱动的 A80；PC RXD 接 A52。ESP32 通过自己的 USB 供电，USB-TTL 的 VCC 和 ESP32 电源脚不接 FPGA 电源轨。引脚以实际板子丝印为准。

## 协议与现有 ESP32 固件兼容性

`esp32c3_bridge/esp32c3_bridge.ino` 是原基线的**逐字节原样副本**，SHA-256：

`84FBE7AAE8FE71D74E00BDCCAEB6CD53F7E55BDB948AA92F8BD00A8BDE0EA43F`

已实际比对原件与副本哈希一致，记录见 `TEST_RESULTS.md`。桥接程序已经接受 AA55／56／57／58／59 长度、完整帧校验、108 字节 AA59、按 MTU 分片 Notify，以及原样转发 8 字节 CM 命令；不解释音色 ID、编码器或存储业务字段。因此此次页面更新不要求修改桥接源码；已使用该基线固件的设备通常无需因本次 UI 更新而重刷。**本次未编译或烧录 ESP32 固件，不声称固件编译成功。** 如需首次刷入，请参阅桥接目录说明并在本地 Arduino 环境验证。

BLE UUID 保持原值：服务 `6e400001-b5a3-f393-e0a9-e50e24dcca9e`；手机写入 `6e400002-b5a3-f393-e0a9-e50e24dcca9e`；状态通知 `6e400003-b5a3-f393-e0a9-e50e24dcca9e`。

已核对 v20 `src/board_a/status_extended.v`、v21 `host/three_board_protocol.py`／`instrument_panel.py`，并额外核对实际连接的 v21 `status_dual.v`：

| AA59 字节（从 0 开始） | 当前含义 |
|---|---|
| 0–3 | AA59、帧序号、版本 1 |
| 4 / 5 | 七键门控低 7 位／音色低 3 位 |
| 6–9 | 音高／音量旋钮，小端 16 位 |
| 10–14 | MPR／ADC 有效位、功能低 3 位、ADS 在线低 3 位、辅助在线低 2 位、B/C 链路 |
| 15 / 16 / 17 | 存储状态低半字节、存储标志、手机命令回显 |
| 18–19 | 编码器：bit15 转动、bit14 方向、低 14 位颤音深度；不是距离 |
| 20–35 | 手势、压力有效掩码、七路 16 位压力 ADC；前两路为升／降音片 |
| 36–71 | 九个 32 位音频链路计数器 |
| 72–85 / 86–105 | 辅助诊断／I²C 探测 |
| 106 / 107 | 字节 2–105 的加和模 256／0D |

**当前 A76 手机端使用基础状态快照：字节 15 高半字节恒为 0，没有具体存储故障码。** 当前 `status_dual.v` 仅在 A52 PC 输出中加入存储故障码高半字节和编码器引脚诊断高位；手机与 PC 的命令回显各自独立。手机仍能读取字节 16 bit3 的存储故障标志，此时显示“存储故障：设备未提供故障码（手机串口）”，不会编造故障原因。

解析器同时支持最新 host 的故障高半字节字段：若未来或测试帧提供该码，则显示 1 芯片识别失败、2 写入读回校验失败、3 录制索引提交失败、4 录制缓存溢出、5 SPI操作超时、6 录制区未准备、7 没有可重演记录、8 重演数据校验失败。故障码与存储状态分别解码，状态 6 始终表示“停止收尾中”。编码器引脚诊断也仅在诊断标记存在时读取，手机默认显示“未提供”。

命令仍为 `43 4D SEQ OP ARG_LO ARG_HI CHECK 0D`。竹笛示例：`43 4D 01 01 04 00 06 0D`。功能切换使用 PC 同款 `OP=03` 掩码更新，避免覆盖同时来自 PC 的其他功能位。多点弹奏使用 `OP=20` 的七键掩码；GATT 写入串行处理并合并尚未发送的门控更新。

## 本地曲谱

保留“小星星”“欢乐颂”，也可载入 JSON。键号为 0–6；一拍可包含多键，空数组表示休止：

```json
{"title":"和弦练习","bpm":100,"notes":[[0,2,4],[1,3,5],[],[6]]}
```

也支持 `{"events":[{"keys":[0,2,4]},{"keys":[]}]}`。曲谱仅在页面内显示指引，不上传、不发送 BLE 命令；自定义曲谱刷新后需重新载入。BPM 40–240；文件最大 1 MB，最多 10000 拍。

## 复现测试

本机运行程序：Node **`E:/node.exe`**（v24.18.0）；协议对照使用 Python **`C:/Users/asus/AppData/Local/Programs/Python/Python313/python.exe`**；浏览器为 **`C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe`**。不需要 npm 安装依赖。Python 用 `-B` 只读导入最新 host，防止在 `mobile/` 外写入字节码。

在 PowerShell 执行：

```powershell
Set-Location E:/qiansai/three_20k_flute_v21
& E:/node.exe --check mobile/protocol.js
& E:/node.exe --check mobile/app.js
& E:/node.exe --test mobile/tests/protocol.test.cjs
& E:/node.exe mobile/tests/browser-smoke.cjs
```

协议测试从 PATH 调用 `python`；请确保其指向以上 Python 或可用的 Python 3。浏览器测试允许用环境变量 `EDGE_PATH` 指定其他 Edge 路径。浏览器测试只开本机临时 HTTP 服务与无窗口 Edge，临时用户目录创建在 `mobile/tests/` 并在完成后清理，不连接物理 BLE，也不发布网站。

实测结果和限制见 `TEST_RESULTS.md`。在手机和硬件上仍需验收真实 BLE MTU／通知吞吐、持续多指演奏、后台行为、断连松键、压力／编码器输入和录制重演。
