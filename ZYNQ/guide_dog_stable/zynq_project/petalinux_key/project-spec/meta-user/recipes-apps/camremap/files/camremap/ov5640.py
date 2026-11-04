"""OV5640 camera configuration over SCCB (bit-banged on PS EMIO GPIO).

Register table: board-verified guide_dog_main led_src/ov5640/ov5640_init.c,
800x480 RGB565 (the PL expands it to RGB888).  SDA is used open-drain style
(drive low / release to pull-up), SCL is push-pull, like the bare-metal code.
"""
import json
import time


class Sccb:
    def __init__(self, scl, sda, half_period_s=0.0):
        self.scl = scl
        self.sda = sda
        self.t = half_period_s
        self.scl.drive(1)
        self.sda.release()

    def _d(self):
        if self.t:
            time.sleep(self.t)

    def _sda(self, bit):
        if bit:
            self.sda.release()
        else:
            self.sda.drive(0)

    def start(self):
        self.sda.release(); self.scl.set(1); self._d()
        self.sda.drive(0); self._d()
        self.scl.set(0); self._d()

    def stop(self):
        self.scl.set(0); self._d()
        self.sda.drive(0); self._d()
        self.scl.set(1); self._d()
        self.sda.release(); self._d()

    def write_byte(self, value):
        for i in range(7, -1, -1):
            self.scl.set(0); self._d()
            self._sda((value >> i) & 1); self._d()
            self.scl.set(1); self._d()
        self.scl.set(0)
        self.sda.release(); self._d()
        self.scl.set(1); self._d()
        ack = self.sda.read() == 0
        self.scl.set(0); self._d()
        return ack

    def read_byte(self):
        self.sda.release()
        value = 0
        for _ in range(8):
            self.scl.set(0); self._d()
            self.scl.set(1); self._d()
            value = (value << 1) | self.sda.read()
        self.scl.set(0); self._d()
        self.sda.release(); self._d()      # NACK
        self.scl.set(1); self._d()
        self.scl.set(0); self._d()
        return value


class OV5640:
    WADDR = 0x78
    RADDR = 0x79

    def __init__(self, sccb):
        self.b = sccb

    def write_reg(self, reg, val):
        self.b.start()
        ok = self.b.write_byte(self.WADDR)
        ok = self.b.write_byte((reg >> 8) & 0xFF) and ok
        ok = self.b.write_byte(reg & 0xFF) and ok
        ok = self.b.write_byte(val & 0xFF) and ok
        self.b.stop()
        return ok

    def read_reg(self, reg):
        self.b.start()
        self.b.write_byte(self.WADDR)
        self.b.write_byte((reg >> 8) & 0xFF)
        self.b.write_byte(reg & 0xFF)
        self.b.stop()
        self.b.start()
        self.b.write_byte(self.RADDR)
        value = self.b.read_byte()
        self.b.stop()
        return value

    def chip_id(self):
        return (self.read_reg(0x300A) << 8) | self.read_reg(0x300B)

    def configure(self, table_path, log=print):
        with open(table_path, "r", encoding="utf-8-sig") as f:
            cfg = json.load(f)
        time.sleep(int(cfg.get("boot_delay_us", 30000)) / 1e6)
        cid = self.chip_id()
        log("OV5640 chip id 0x%04X%s" % (cid, "" if cid == 0x5640 else " (expected 0x5640)"))
        nacks = 0
        regs = cfg["initialization_registers"]
        for item in regs:
            reg = int(item["address"], 0)
            val = int(item["value"], 0)
            if not self.write_reg(reg, val):
                nacks += 1
            delay = int(item.get("delay_after_us", 0))
            if delay:
                time.sleep(delay / 1e6)
        log("OV5640 configured: %d registers, %d NACK" % (len(regs), nacks))
        return {"chip_id": cid, "registers": len(regs), "nacks": nacks}
