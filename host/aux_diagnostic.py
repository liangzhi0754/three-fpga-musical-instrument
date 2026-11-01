"""Explain auxiliary-bus telemetry without inferring ACK from a voltage average."""


def format_aux_diagnostic(data):
    if "encoder_status" in data:
        online = bool(data.get("aux_online", 0) & 2)
        gesture = "在线，正在读取动作" if online else "离线或初始化中"
        text = (f"辅助总线：手势模块 {gesture}；"
                "PAJ7620 SCL→A54 / SDA→A55；VL53L0X 已停用")
        d = data.get('encoder_diagnostic')
        if d:
            text += (f"\n编码器诊断 v11.3：A25={int(d['raw_a'])} B56={int(d['raw_b'])}；"
                     f"A变化={'有' if d['seen_a'] else '无'} B变化={'有' if d['seen_b'] else '无'}；"
                     f"动作计数={d['count']}（到63保持）；"
                     f"合法相序={'有' if d['legal_seen'] else '无'} "
                     f"双位跳变={'有' if d['illegal_seen'] else '无'}")
        return text
    d = data.get("aux_diagnostic")
    if not d:
        return "辅助诊断：当前为旧版 A 板程序；请烧录 A_DISTANCE_PROBE_V7.fs"
    distance_online = bool(data.get("aux_online", 0) & 1)
    if distance_online:
        text = "测距初始化完成；" + ("距离有效" if d["valid"] else "等待有效距离")
    elif d["error"] and not d["chip"]:
        if d["error"] == 1:
            reason = {1: "地址写入无应答", 2: "寄存器地址无应答", 3: "数据写入无应答",
                      4: "地址读取无应答", 5: "通信超时（检查 SCL 是否被拉低）"}
            text = "测距通信失败：" + reason.get(d["bus_fault"], "事务失败")
        elif d["error"] == 2:
            text = "测距等待寄存器就绪超时"
        else:
            text = f"测距寄存器校验失败：读到 0x{d['fail_read']:02X}"
        text += f"；失败步骤 {d['fail_pc']} / 寄存器 0x{d['fail_reg']:02X}"
    elif d["error"] and d["chip"]:
        if d["error"] == 1:
            reason = {1: "地址写入无应答", 2: "寄存器地址无应答", 3: "数据写入无应答",
                      4: "地址读取无应答", 5: "通信超时"}
            text = "手势通信失败：" + reason.get(d["bus_fault"], "事务失败")
        elif d["error"] == 3:
            text = f"手势寄存器校验失败：读到 0x{d['fail_read']:02X}"
        else:
            text = "手势初始化未完成"
        text += f"；失败步骤 {d['fail_pc']} / 寄存器 0x{d['fail_reg']:02X}"
    else:
        text = "测距初始化中" if not d["chip"] else "测距尚未在线"
    text_out = (f"辅助诊断 v8：{text}；测距芯片ID 0x{d['model_id']:02X}\n"
            f"当前步骤 {d['pc']} / 状态 {d['state']}；重试轮次 {d['attempts']}；"
            f"完成事务 {d['transactions']} / 距离更新 {d['ranges']}（计数每256次归零）；"
            f"电平瞬时值 SCL={int(d['scl'])} SDA={int(d['sda'])}")

    p = data.get("aux_probe")
    if not p:
        return text_out + "\n当前尚无 v7 引脚/地址扫描结果；请确认烧录的是 A_DISTANCE_PROBE_V7.fs"
    f = p['flags']
    if p['phase'] not in (254, 255):
        summary = f"正在检查引脚并扫描地址（阶段{p['phase']}）"
    elif (f & 3) != 3:
        low = "、".join(n for b,n in ((0,"SCL"),(1,"SDA")) if not f & (1<<b))
        summary = f"空闲时{low}未拉高；后续电平测试和扫描未执行"
    elif (f & 127) != 127:
        checks = ((0,"SCL空闲未拉高"),(1,"SDA空闲未拉高"),
                  (2,"SCL未能拉低"),(3,"拉低SCL时SDA也变低"),
                  (4,"SDA未能拉低"),(5,"拉低SDA时SCL也变低"),
                  (6,"释放后未恢复高电平"))
        summary = "电平测试异常：" + "、".join(t for n,t in checks if not f & (1<<n))
    elif f & 128:
        summary = "扫描超时，SCL没有及时拉高"
    else:
        found = "、".join(f"0x{a:02X}" for a in p['addresses']) or "无"
        summary = f"引脚电平测试通过；应答地址：{found}"
    gesture_online = bool(data.get('aux_online', 0) & 2)
    gesture_state = "初始化完成，正在读取动作" if gesture_online else (
        "地址0x73有回应，但初始化未完成" if 0x73 in p['addresses'] else
        "扫描尚无0x73回应；检查供电/连线，或等待唤醒后再重试")
    return (text_out + f"\n总线排查（轮次{p['rounds']}）：{summary}"
            + f"\n手势：{gesture_state}。v8接线 SCL→A54 / SDA→A55；扫描结果为扫描时刻状态。")
