#!/usr/bin/env python3
"""
Traktor Audio 6 control, native (no Rosetta).
Protocol decoded from the original control panel (USB vendor control requests on endpoint 0):

  write: bmRequestType=0x40  bRequest=REQ  wValue=VALUE  wIndex=CHANNEL  wLength=0
  read:  bmRequestType=0xC0  bRequest=REQ  wValue=0      wIndex=CHANNEL  wLength=1

  REQ 1 = thru mode                    REQ 2 = input source (phono/line)
  CHANNEL (wIndex) = 3 (A) or 5 (B)    VALUE = 0 or 1

  Startup config: same requests, with 0x100 added to wIndex (0x103 / 0x105).
  After editing, the control panel sends bRequest 0x10 (wValue 0, wIndex 0),
  most likely "store startup config".

Setup:  brew install libusb && pip3 install pyusb
Usage:  ./ta6.py status [--startup]
        ./ta6.py input A 1
        ./ta6.py thru B 0 --startup
"""
import argparse
import sys

import usb.core
import usb.backend.libusb1

NI_VID = 0x17CC
REQUESTS = {"input": 2, "thru": 1}
CHANNELS = {"A": 3, "B": 5}  # name -> wIndex
STARTUP_OFFSET = 0x100       # wIndex high byte 1 = startup config
REQ_STORE_STARTUP = 0x10
TIMEOUT_MS = 5000


def backend():
    # Homebrew's libusb is not always on the default search path
    for path in (None, "/opt/homebrew/lib/libusb-1.0.dylib", "/usr/local/lib/libusb-1.0.dylib"):
        be = usb.backend.libusb1.get_backend(find_library=(lambda _: path) if path else None)
        if be:
            return be
    sys.exit("libusb not found - run: brew install libusb")


def find_device(pid):
    kw = {"idVendor": NI_VID, "backend": backend()}
    if pid is not None:
        kw["idProduct"] = pid
    devs = list(usb.core.find(find_all=True, **kw))
    if not devs:
        sys.exit("No Native Instruments device found")
    if len(devs) > 1:
        sys.exit("Several NI devices found, pick one with --pid: "
                 + ", ".join(hex(d.idProduct) for d in devs))
    return devs[0]


def read(dev, req, index):
    return dev.ctrl_transfer(0xC0, req, 0, index, 1, timeout=TIMEOUT_MS)[0]


def write(dev, req, index, value):
    dev.ctrl_transfer(0x40, req, value, index, None, timeout=TIMEOUT_MS)


def main():
    p = argparse.ArgumentParser(description="Traktor Audio 6 settings")
    p.add_argument("--pid", type=lambda s: int(s, 0), help="USB product ID, if needed")
    sub = p.add_subparsers(dest="cmd", required=True)
    st = sub.add_parser("status")
    st.add_argument("--startup", action="store_true", help="show the startup config")
    for name in REQUESTS:
        s = sub.add_parser(name)
        s.add_argument("channel", type=str.upper, choices=CHANNELS)
        s.add_argument("value", type=int, choices=(0, 1))
        s.add_argument("--startup", action="store_true",
                       help="save to the startup config instead of the live setting")
    a = p.parse_args()

    dev = find_device(a.pid)
    offset = STARTUP_OFFSET if a.startup else 0
    label = "startup" if a.startup else "live"

    if a.cmd == "status":
        for name, ch in CHANNELS.items():
            vals = ", ".join(f"{n}={read(dev, r, ch + offset)}" for n, r in REQUESTS.items())
            print(f"{label} channel {name}: {vals}")
    else:
        index = CHANNELS[a.channel] + offset
        write(dev, REQUESTS[a.cmd], index, a.value)
        if a.startup:
            write(dev, REQ_STORE_STARTUP, 0, 0)
        print(f"{label} {a.cmd} channel {a.channel} -> {a.value} "
              f"(read back: {read(dev, REQUESTS[a.cmd], index)})")


if __name__ == "__main__":
    main()
