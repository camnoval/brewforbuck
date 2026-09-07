"""
Extract the device-produced `LineAssembler.lines output` block from each OCR dump.

`faithful.py` proves the Python port reproduces those lines exactly (verify.py, 8/8),
so for any experiment that lives DOWNSTREAM of the assembler -- i.e. anything in
`MenuParser` -- the recorded lines are the real parser input and can be used directly.
No geometry needed.

    from dumplines import menus
    for name, lines in menus("Fixtures/console.txt"):
        ...
"""

import re
import sys

START = "===== BANGFORBUCK OCR EXPORT (start) ====="
END = "===== BANGFORBUCK OCR EXPORT (end) ====="
OUT = re.compile(r"^# LineAssembler\.lines output \((\d+)\):")
DIMS = re.compile(r"^# image (\d+)x(\d+) px")


def menus(path):
    """[(label, [line, ...]), ...] in dump order."""
    raw = open(path, "r", encoding="utf-8", errors="replace").read()
    blocks = re.findall(re.escape(START) + r"(.*?)" + re.escape(END), raw, re.S)
    if not blocks:
        sys.exit("no OCR export blocks found")

    out = []
    for n, block in enumerate(blocks, 1):
        lines, dims, collecting, declared = [], "", False, None
        for line in block.splitlines():
            line = line.rstrip("\r")
            if (m := DIMS.match(line)):
                dims = f"{m.group(1)}x{m.group(2)}"
                continue
            if (m := OUT.match(line)):
                collecting, declared = True, int(m.group(1))
                continue
            if not collecting:
                continue
            if line.startswith("#") or line.startswith("====="):
                continue
            # The block prints one assembled line per row, quoted.
            s = line.strip()
            if not s:
                continue
            if s.startswith('"') and s.endswith('"') and len(s) >= 2:
                s = s[1:-1]
            lines.append(s)
        if declared is not None and len(lines) != declared:
            sys.exit(f"menu {n}: declared {declared} lines, scraped {len(lines)}")
        out.append((f"menu {n} ({dims})", lines))
    return out


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "Fixtures/console.txt"
    for label, lines in menus(path):
        print(f"\n===== {label} — {len(lines)} lines =====")
        for line in lines:
            print(f"  {line}")
