"""
Does the Python port reproduce the device exactly?

Every OCR dump contains both the word observations AND the lines the device's
`LineAssembler` actually produced. That makes each dump a self-checking oracle: run
the port on the observations at Swift's own constants and the output must match the
recorded lines exactly. Until this reports 8/8, no threshold experiment run in
Python means anything about what the phone will do.

    python3 verify.py console.txt
    python3 verify.py console.txt --menu 3     # first mismatch in detail
"""

import argparse
import re
import sys

import faithful


DIMS = re.compile(r"^# image (\d+)x(\d+) px")
OBS = re.compile(r'^"(.*)" @ ([-\d.]+),([-\d.]+)\s+([-\d.]+)[x\u00d7]([-\d.]+)\s*$')


def parse(path: str) -> list:
    raw = open(path, "r", encoding="utf-8", errors="replace").read()
    blocks = re.findall(
        r"===== BANGFORBUCK OCR EXPORT \(start\) =====(.*?)"
        r"===== BANGFORBUCK OCR EXPORT \(end\) =====", raw, re.S)
    if not blocks:
        sys.exit("no OCR export blocks found")

    menus = []
    for block in blocks:
        obs, device, dims, section = [], [], (0, 0), None
        for line in block.splitlines():
            if (m := DIMS.match(line)):
                dims = (int(m.group(1)), int(m.group(2)))
                continue
            if line.startswith("# Vision line candidates"):
                section = "conf"; continue
            if line.startswith("#") and "observations" in line:
                section = "obs"; continue
            if line.startswith("# LineAssembler.lines output"):
                section = "lines"; continue
            if line.startswith("# MenuParser trace"):
                section = "trace"; continue

            if section == "obs" and (m := OBS.match(line.rstrip())):
                text = m.group(1).replace('\\"', '"').replace("\\\\", "\\")
                midx, midy = float(m.group(2)), float(m.group(3))
                w, h = float(m.group(4)), float(m.group(5))
                # The dump prints mid/w/h at 4dp; reconstruct the corners.
                obs.append(faithful.Obs(text, faithful.Box(
                    midx - w / 2, midy - h / 2, midx + w / 2, midy + h / 2)))
            elif section == "lines" and line.startswith("  ") and line.strip():
                device.append(line.strip())
        if obs:
            menus.append({"dims": dims, "obs": obs, "device": device})
    return menus


def diff(mine: list, theirs: list, limit: int = 12) -> list:
    """First differing positions, aligned naively (enough to localise a bug)."""
    out = []
    for i in range(max(len(mine), len(theirs))):
        a = mine[i] if i < len(mine) else "<none>"
        b = theirs[i] if i < len(theirs) else "<none>"
        if a != b:
            out.append((i, b, a))
            if len(out) >= limit:
                break
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--menu", type=int)
    args = ap.parse_args()

    menus = parse(args.log)
    exact = 0
    for i, m in enumerate(menus, 1):
        mine = faithful.lines(m["obs"])
        ok = mine == m["device"]
        exact += ok
        w, h = m["dims"]
        print(f"menu {i}  {w}x{h}  device {len(m['device']):3d}  port {len(mine):3d}  "
              f"{'MATCH' if ok else 'differs'}")
        if args.menu == i and not ok:
            print()
            for pos, dev, got in diff(mine, m["device"]):
                print(f"  [{pos}] device: {dev!r}")
                print(f"       port:   {got!r}")
    print(f"\n{exact}/{len(menus)} exact")
    if exact != len(menus):
        print("Port is NOT faithful. Do not draw conclusions from experiments yet.")


if __name__ == "__main__":
    main()
