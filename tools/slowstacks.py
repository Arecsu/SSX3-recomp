"""Name the stacks in [HOLDSTACK] lines (RECOMP_SLOW_STACKS / RECOMP_GUESTCPU_STATS).

    python tools/slowstacks.py play_stderr.txt [build/ssx3_recomp.map] [depth]

Each line: why (slowNNNms-main/-exec/-flip, heldNNms), thread id, then the
native call chain innermost first, with runs of the same frame and of system
DLL frames ("sys") collapsed. Generated functions are named sub_<guest VA>.
"""
import bisect
import re
import sys

_SYM = re.compile(r"\s+[0-9a-fA-F]{4}:[0-9a-fA-F]{8}\s+(\S+)\s+([0-9a-fA-F]{16})\s")


def main(argv):
    if len(argv) < 2:
        raise SystemExit(__doc__)
    log = argv[1]
    mapfile = argv[2] if len(argv) > 2 else "build/ssx3_recomp.map"
    depth = int(argv[3]) if len(argv) > 3 else 16
    syms = []
    with open(mapfile, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = _SYM.match(line)
            if m:
                syms.append((int(m.group(2), 16), m.group(1)))
    syms.sort()
    addrs = [a for a, _ in syms]
    with open(log, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            i = line.find("[HOLDSTACK]")
            if i < 0:
                continue
            head, _, rest = line[i + 12:].partition(":")
            chain = []
            for a in re.findall(r"0x([0-9A-Fa-f]+)", rest):
                v = int(a, 16)
                if 0x140000000 <= v < 0x150000000 and addrs:
                    name = syms[bisect.bisect_right(addrs, v) - 1][1]
                else:
                    name = "sys"
                if not chain or chain[-1] != name:
                    chain.append(name)
            print(head.strip(), " < ".join(chain[:depth]))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
