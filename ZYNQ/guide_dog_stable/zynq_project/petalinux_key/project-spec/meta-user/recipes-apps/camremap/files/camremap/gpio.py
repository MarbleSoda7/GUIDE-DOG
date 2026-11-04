"""PS GPIO access through the Linux sysfs interface.

Using the kernel GPIO driver (instead of poking 0xE000A000 through /dev/mem)
keeps the Zynq GPIO controller clock enabled while the lines are requested.
"""
import os
import time

SYSFS = "/sys/class/gpio"


def find_chip_base(label="zynq_gpio", root=SYSFS):
    for name in sorted(os.listdir(root)):
        if not name.startswith("gpiochip"):
            continue
        d = os.path.join(root, name)
        try:
            with open(os.path.join(d, "label")) as f:
                if f.read().strip() == label:
                    with open(os.path.join(d, "base")) as g:
                        return int(g.read().strip())
        except OSError:
            continue
    raise RuntimeError("GPIO chip '%s' not found under %s" % (label, root))


class SysfsLine:
    """One GPIO line. drive(v) = push-pull, release() = high-Z (pull-up)."""

    def __init__(self, number, root=SYSFS):
        self.number = int(number)
        d = os.path.join(root, "gpio%d" % self.number)
        if not os.path.isdir(d):
            with open(os.path.join(root, "export"), "w") as f:
                f.write(str(self.number))
            for _ in range(100):
                if os.path.exists(os.path.join(d, "direction")):
                    break
                time.sleep(0.01)
        self._dir = os.open(os.path.join(d, "direction"), os.O_WRONLY)
        self._val = os.open(os.path.join(d, "value"), os.O_RDWR)

    def drive(self, value):
        os.write(self._dir, b"high" if value else b"low")

    def set(self, value):
        os.write(self._val, b"1" if value else b"0")

    def release(self):
        os.write(self._dir, b"in")

    def read(self):
        os.lseek(self._val, 0, os.SEEK_SET)
        return 1 if os.read(self._val, 1) == b"1" else 0

    def close(self):
        os.close(self._dir)
        os.close(self._val)


def open_sccb_lines(camera=1):
    """Return O_SCL/O_SDA for camera 1 or I_SCL/I_SDA for camera 2.

    The Wildfire adapter has separate SCCB buses but shared physical RST/PWDN
    and a module-local 24 MHz XCLK oscillator.
    """
    offsets = {1: (54, 55), 2: (56, 57)}
    try:
        scl_emio, sda_emio = offsets[int(camera)]
    except (KeyError, ValueError):
        raise ValueError("camera must be 1 or 2")
    base = find_chip_base()
    return SysfsLine(base + scl_emio), SysfsLine(base + sda_emio)
