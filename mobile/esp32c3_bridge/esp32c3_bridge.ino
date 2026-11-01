/*
 * ESP32-C3 BLE <-> UART bridge for the three-board FPGA instrument.
 *
 * FPGA side : A76 = FPGA TX -> ESP32-C3 GPIO5 (UART1 RX)
 *             A80 = FPGA RX <- ESP32-C3 GPIO4 (UART1 TX)
 *             common GND, 3.3 V logic, 115200 8N1
 *
 * Phone side: BLE GATT, project UUIDs from bridge_contract.json
 *             6E400001-... service
 *             6E400002-... phone writes 8-byte CM commands
 *             6E400003-... ESP32 notifies AA57/AA58/AA59 frames
 *
 * Board: ESP32-C3 Super Mini (Arduino-ESP32 core, "ESP32C3 Dev Module")
 * Tools: USB CDC On Boot = Enabled, Flash Size = 4MB (verify actual)
 *
 * This sketch does NOT modify the FPGA protocol and does NOT put logs on UART1.
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ---------------------------------------------------------------------------
// Project contract
// ---------------------------------------------------------------------------
static const char* DEVICE_NAME = "FPGA-Instrument-C3";

static const char* SERVICE_UUID =
    "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
static const char* RX_CHAR_UUID =
    "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";  // phone -> ESP32 (write)
static const char* TX_CHAR_UUID =
    "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";  // ESP32 -> phone (notify)

// ESP32-C3 UART1 -> FPGA A board
static const int UART_TX_PIN = 4;   // ESP32 TX -> A80
static const int UART_RX_PIN = 5;   // A76 -> ESP32 RX
static const uint32_t UART_BAUD = 115200;

// ---------------------------------------------------------------------------
// Buffers
// ---------------------------------------------------------------------------
static const size_t MAX_FRAME = 108;
static const size_t FRAME_QUEUE_DEPTH = 12;
static const size_t CMD_QUEUE_DEPTH = 8;

struct Frame {
  uint8_t data[MAX_FRAME];
  uint16_t len;
};

static Frame frameQ[FRAME_QUEUE_DEPTH];
static volatile uint8_t frameHead = 0;
static volatile uint8_t frameTail = 0;
static volatile uint8_t frameCount = 0;

static uint8_t cmdQ[CMD_QUEUE_DEPTH][8];
static volatile uint8_t cmdHead = 0;
static volatile uint8_t cmdTail = 0;
static volatile uint8_t cmdCount = 0;
static portMUX_TYPE cmdMux = portMUX_INITIALIZER_UNLOCKED;

static uint8_t uartBuf[256];
static size_t uartLen = 0;

static uint8_t cmdBuf[32];
static size_t cmdLen = 0;

static BLEServer* bleServer = nullptr;
static BLECharacteristic* txChar = nullptr;
static BLECharacteristic* rxChar = nullptr;
static volatile bool deviceConnected = false;

static Frame txFrame;
static bool txActive = false;
static uint16_t txPos = 0;
static uint32_t lastNotifyMs = 0;

// Statistics (USB log only)
static uint32_t statUartBytes = 0;
static uint32_t statFramesOk = 0;
static uint32_t statFramesBad = 0;
static uint32_t statFramesDropped = 0;
static uint32_t statCmdOk = 0;
static uint32_t statCmdBad = 0;
static uint32_t lastStatsMs = 0;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
static uint16_t frameLengthFor(uint8_t secondByte) {
  switch (secondByte) {
    case 0x55: return 12;
    case 0x56: return 38;
    case 0x57: return 74;
    case 0x58: return 88;
    case 0x59: return 108;
    default:   return 0;
  }
}

static bool frameChecksumOk(const uint8_t* p, uint16_t len) {
  if (len < 4) return false;
  if (p[len - 1] != 0x0D) return false;
  uint8_t sum = 0;
  for (uint16_t i = 2; i + 2 < len; ++i) sum += p[i];
  return sum == p[len - 2];
}

static void pushFrame(const uint8_t* p, uint16_t len) {
  if (frameCount >= FRAME_QUEUE_DEPTH) {
    // Keep the newest state; drop the oldest queued frame.
    frameTail = (frameTail + 1) % FRAME_QUEUE_DEPTH;
    --frameCount;
    ++statFramesDropped;
  }
  Frame& f = frameQ[frameHead];
  memcpy(f.data, p, len);
  f.len = len;
  frameHead = (frameHead + 1) % FRAME_QUEUE_DEPTH;
  ++frameCount;
  ++statFramesOk;
}

static bool popFrame(Frame& out) {
  if (!frameCount) return false;
  out = frameQ[frameTail];
  frameTail = (frameTail + 1) % FRAME_QUEUE_DEPTH;
  --frameCount;
  return true;
}

static void pushCommand(const uint8_t* p) {
  portENTER_CRITICAL(&cmdMux);
  if (cmdCount >= CMD_QUEUE_DEPTH) {
    // Bounded queue: drop oldest command rather than growing RAM forever.
    cmdTail = (cmdTail + 1) % CMD_QUEUE_DEPTH;
    --cmdCount;
  }
  memcpy(cmdQ[cmdHead], p, 8);
  cmdHead = (cmdHead + 1) % CMD_QUEUE_DEPTH;
  ++cmdCount;
  portEXIT_CRITICAL(&cmdMux);
}

static bool popCommand(uint8_t out[8]) {
  bool ok = false;
  portENTER_CRITICAL(&cmdMux);
  if (cmdCount) {
    memcpy(out, cmdQ[cmdTail], 8);
    cmdTail = (cmdTail + 1) % CMD_QUEUE_DEPTH;
    --cmdCount;
    ok = true;
  }
  portEXIT_CRITICAL(&cmdMux);
  return ok;
}

static void drainCommands() {
  uint8_t out[8];
  while (deviceConnected && popCommand(out)) {
    Serial1.write(out, 8);
    Serial1.flush();
    ++statCmdOk;
  }
}

// ---------------------------------------------------------------------------
// UART frame parser (byte stream, never newline-based)
// ---------------------------------------------------------------------------
static void consumeUart(size_t n) {
  if (n >= uartLen) {
    uartLen = 0;
    return;
  }
  memmove(uartBuf, uartBuf + n, uartLen - n);
  uartLen -= n;
}

static void feedUartByte(uint8_t b) {
  if (uartLen >= sizeof(uartBuf)) {
    consumeUart(1);  // drop oldest byte, keep bounded
  }
  uartBuf[uartLen++] = b;

  while (uartLen >= 2) {
    if (uartBuf[0] != 0xAA) {
      consumeUart(1);
      continue;
    }
    uint16_t need = frameLengthFor(uartBuf[1]);
    if (need == 0) {
      consumeUart(1);
      continue;
    }
    if (uartLen < need) break;
    if (!frameChecksumOk(uartBuf, need)) {
      ++statFramesBad;
      consumeUart(1);
      continue;
    }
    pushFrame(uartBuf, need);
    consumeUart(need);
  }
}

// ---------------------------------------------------------------------------
// BLE command parser: 43 4D SEQ OP ARG_LO ARG_HI CHECK 0D
// ---------------------------------------------------------------------------
static void feedCmdByte(uint8_t b) {
  if (cmdLen >= sizeof(cmdBuf)) {
    memmove(cmdBuf, cmdBuf + 1, sizeof(cmdBuf) - 1);
    cmdLen = sizeof(cmdBuf) - 1;
  }
  cmdBuf[cmdLen++] = b;

  while (cmdLen >= 8) {
    size_t i = 0;
    while (i + 1 < cmdLen && !(cmdBuf[i] == 0x43 && cmdBuf[i + 1] == 0x4D)) ++i;
    if (i > 0) {
      memmove(cmdBuf, cmdBuf + i, cmdLen - i);
      cmdLen -= i;
      if (cmdLen < 8) break;
    }
    if (cmdBuf[7] != 0x0D ||
        ((uint8_t)(cmdBuf[2] + cmdBuf[3] + cmdBuf[4] + cmdBuf[5]) != cmdBuf[6])) {
      ++statCmdBad;
      memmove(cmdBuf, cmdBuf + 1, cmdLen - 1);
      --cmdLen;
      continue;
    }
    pushCommand(cmdBuf);
    memmove(cmdBuf, cmdBuf + 8, cmdLen - 8);
    cmdLen -= 8;
  }
}

// ---------------------------------------------------------------------------
// BLE callbacks
// ---------------------------------------------------------------------------
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    deviceConnected = true;
    Serial.println("[BLE] connected");
  }

  void onDisconnect(BLEServer* server) override {
    deviceConnected = false;
    txActive = false;
    txPos = 0;
    // Drop stale commands; keep draining UART so it does not backlog.
    portENTER_CRITICAL(&cmdMux);
    cmdCount = 0;
    cmdHead = cmdTail = 0;
    portEXIT_CRITICAL(&cmdMux);

    // Fail-safe: release any phone-held remote notes immediately.
    // The FPGA also has its own 500 ms timeout.
    uint8_t release[8] = {0x43, 0x4D, 0xFE, 0x20, 0x00, 0x00, 0x00, 0x0D};
    release[6] = (uint8_t)(release[2] + release[3] + release[4] + release[5]);
    Serial1.write(release, 8);
    Serial1.flush();

    Serial.println("[BLE] disconnected");
    BLEDevice::startAdvertising();
  }
};

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
   String raw = characteristic->getValue();
for (size_t i = 0; i < raw.length(); ++i) {
  feedCmdByte((uint8_t)raw[i]);
}
  }
};

// ---------------------------------------------------------------------------
// Setup / loop
// ---------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(200);

  // UART1 is the FPGA link. Logs must NOT go here.
  Serial1.begin(UART_BAUD, SERIAL_8N1, UART_RX_PIN, UART_TX_PIN);

  BLEDevice::init(DEVICE_NAME);
  BLEDevice::setMTU(247);  // request a large MTU; iOS usually grants 185

  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new ServerCallbacks());

  BLEService* service = bleServer->createService(SERVICE_UUID);

  txChar = service->createCharacteristic(
      TX_CHAR_UUID,
      BLECharacteristic::PROPERTY_NOTIFY);
  txChar->addDescriptor(new BLE2902());

  rxChar = service->createCharacteristic(
      RX_CHAR_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  rxChar->setCallbacks(new RxCallbacks());

  service->start();

  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  adv->setMinPreferred(0x06);
  adv->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("[BOOT] FPGA-Instrument-C3 BLE bridge");
  Serial.println("[BOOT] UART1 115200 8N1  TX=GPIO4 RX=GPIO5");
  Serial.println("[BOOT] advertising...");
}

void loop() {
  // 1) Drain UART -> frame parser
  while (Serial1.available()) {
    int v = Serial1.read();
    if (v >= 0) {
      ++statUartBytes;
      feedUartByte((uint8_t)v);
    }
  }

  // 2) Forward queued commands to FPGA
  drainCommands();

  // 3) Forward complete frames to phone (chunked by negotiated MTU)
  uint32_t now = millis();
  if (deviceConnected && (now - lastNotifyMs) >= 2) {
    if (!txActive) {
      if (popFrame(txFrame)) {
        txActive = true;
        txPos = 0;
      }
    }
    if (txActive) {
      uint16_t mtu = BLEDevice::getMTU();
      uint16_t chunk = (mtu > 3) ? (mtu - 3) : 20;
      if (chunk > 180) chunk = 180;
      uint16_t remain = txFrame.len - txPos;
      if (chunk > remain) chunk = remain;

      txChar->setValue(txFrame.data + txPos, chunk);
      txChar->notify();
      txPos += chunk;
      lastNotifyMs = now;
      if (txPos >= txFrame.len) txActive = false;
    }
  }

  // 4) USB statistics (never on UART1)
  if (now - lastStatsMs >= 5000) {
    lastStatsMs = now;
    Serial.printf(
        "[STAT] uart=%lu ok=%lu bad=%lu drop=%lu q=%u cmd=%lu cmdbad=%lu conn=%d mtu=%u\n",
        (unsigned long)statUartBytes, (unsigned long)statFramesOk,
        (unsigned long)statFramesBad, (unsigned long)statFramesDropped,
        (unsigned)frameCount, (unsigned long)statCmdOk,
        (unsigned long)statCmdBad, deviceConnected ? 1 : 0,
        (unsigned)BLEDevice::getMTU());
  }
}
