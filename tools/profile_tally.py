#!/usr/bin/env python3
"""Tally [PROF] samples from stderr.txt (written by src/thread_dump.c).

    python3 tools/profile_tally.py build/ssx3_recomp.map stderr.txt

Prints the most frequent innermost function per thread and overall, using the
linker map to name each rebased RIP (generated code is sub_<guest VA>).
"""
import bisect, collections, re, sys

def load_map(path):
    syms = []
    pat = re.compile(r"\s+[0-9a-fA-F]{4}:[0-9a-fA-F]{8}\s+(\S+)\s+([0-9a-fA-F]{16})\s")
    for line in open(path, encoding="utf-8", errors="replace"):
        m = pat.match(line)
        if m:
            syms.append((int(m.group(2), 16), m.group(1)))
    syms.sort()
    return [a for a, _ in syms], [n for _, n in syms]

def main():
    addrs, names = load_map(sys.argv[1])
    def name(rip):
        i = bisect.bisect_right(addrs, rip) - 1
        return names[i] if i >= 0 else hex(rip)
    leaf = collections.Counter(); incl = collections.Counter()
    per_thread = collections.defaultdict(collections.Counter)
    total = 0
    for line in open(sys.argv[2], encoding="utf-8", errors="replace"):
        if not line.startswith("[PROF] "):
            continue
        parts = line.split()
        tid = parts[1]
        rips = []
        for x in parts[2:]:
            if not x.startswith("0x"):
                break
            rips.append(int(x, 16))
        if not rips:
            continue
        total += 1
        frames = [name(r) for r in rips if 0x140000000 <= r < 0x150000000]
        if not frames:
            continue
        blocked = not (0x140000000 <= rips[0] < 0x150000000)
        key = ("[wait] " if blocked else "") + frames[0]
        leaf[key] += 1
        per_thread[tid][key] += 1
        for f in set(frames):
            incl[f] += 1
    print(f"{total} thread-samples")
    print("\nTop innermost (first exe frame; [wait] = thread blocked in the OS):")
    for f, c in leaf.most_common(20):
        print(f"  {c:5d}  {100*c/total:5.1f}%  {f}")
    print("\nTop inclusive (anywhere in the top 8 frames):")
    for f, c in incl.most_common(20):
        print(f"  {c:5d}  {100*c/total:5.1f}%  {f}")
    print("\nBusiest threads:")
    for tid, cnt in sorted(per_thread.items(), key=lambda kv: -sum(kv[1].values()))[:6]:
        top = ", ".join(f"{f} {c}" for f, c in cnt.most_common(3))
        print(f"  tid {tid}: {sum(cnt.values())} samples; {top}")

if __name__ == "__main__":
    main()
