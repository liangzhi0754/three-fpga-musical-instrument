# ESP32-C3 桥接源码副本

`esp32c3_bridge.ino` 原样复制自 `E:/qiansai/bluetooth_work_v1/bluetooth_work_v1/esp32c3_bridge/esp32c3_bridge.ino`，未修改，未在本次工作中编译／上传。

桥接器已经支持 AA59 的 108 字节帧、校验和、BLE MTU 分片及 8 字节 CM 命令原样转发；音色 ID 4 以及最新字段含义由 FPGA 和网页解释，无需更改此固件协议。已刷入这份基线固件时，本次 UI 更新通常无需重刷。

## 接线

- FPGA A76 TX → ESP32-C3 GPIO5 RX。
- ESP32-C3 GPIO4 TX → FPGA A80 RX。
- FPGA／ESP32 GND 共地；115200、8N1、3.3 V 逻辑。
- PC 单独接 FPGA A52 TX → USB-TTL RXD，USB-TTL TXD → FPGA A86 RX，GND 共地。
- 不要并接两个 TX 输出；USB-TTL TXD 不接 A80。C3 自己 USB 供电，电源脚不接 FPGA 电源轨。

## 首次编译／刷入参考

1. 在 Arduino IDE 2.x 安装 Espressif Arduino-ESP32 核心，打开本目录 `.ino`。
2. 选择实际对应的板型，基线配置为 `ESP32C3 Dev Module`、`USB CDC On Boot: Enabled`，Flash 大小按实物确认。
3. 使用该核心自带的 `BLEDevice`／`BLEServer` 等 API。基线曾建议 3.0.x／3.1.x，但本次没有验证任何核心版本的编译兼容性；如核心 API 有差异须现场验证，不能把源码复制视为编译成功。
4. 选择 C3 USB 串口编译并上传；USB 串口监视器设 115200，确认广播名 `FPGA-Instrument-C3` 和 `[STAT]` 计数。
5. 通过兼容 Web Bluetooth 的 iOS BLE 浏览器打开 HTTPS 网页连接；Safari 不支持。实际手机连接和通知稳定性须上板验收。

完整部署路径、UUID、字段与测试限制见上级 `README.md`。
