"""Run xboxrecomp's tools.split with the names applied to functions.json.

tools.split re-runs the disassembler in memory and takes each function's name
from that fresh run, so names written into tools/disasm/output/functions.json
by merge_names.py --apply (Ghidra FidDb, RTTI, ...) never reach the .s files,
despite docs/DECOMP.md saying they do. This does the same split, but copies
those names onto the detected functions first.

    xboxrecomp/.venv/bin/python ssx3-recomp/tools/split_named.py \
        --xboxrecomp xboxrecomp SSX3/default.xbe --out ssx3-recomp/decomp \
        --text-only --extra-sections D3D,D3DX,XGRPH,DSOUND,XPP
"""

import argparse
import json
import os
import sys


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("xbe_path")
    p.add_argument("--xboxrecomp", required=True, help="toolkit clone")
    p.add_argument("--out", required=True)
    p.add_argument("--text-only", action="store_true")
    p.add_argument("--extra-sections", default="")
    p.add_argument("--seed-functions", action="append", default=[],
                   help="seed JSON for tools.disasm (repeatable); must match "
                        "what tools.disasm was run with")
    p.add_argument("--functions-json",
                   help="named functions.json (default: the toolkit's "
                        "tools/disasm/output/functions.json)")
    args = p.parse_args()

    root = os.path.abspath(args.xboxrecomp)
    sys.path.insert(0, root)
    from tools.disasm.disasm import Disassembler
    from tools.disasm.__main__ import _load_seed_functions
    from tools.split.splitter import load_abi, split

    funcs_json = args.functions_json or os.path.join(
        root, "tools", "disasm", "output", "functions.json")
    with open(funcs_json) as f:
        named = {int(e["start"], 16): e["name"] for e in json.load(f)
                 if not e["name"].startswith("sub_")}

    extra = [s.strip() for s in args.extra_sections.split(",") if s.strip()]
    seeds, observed = [], set()
    for path in args.seed_functions:
        seeds.extend(_load_seed_functions(path, observed))
    d = Disassembler(xbe_path=args.xbe_path, text_only=args.text_only,
                     stats_only=True, force=True, extra_sections=extra,
                     seed_functions=sorted(set(seeds)), observed_seeds=observed)
    if not d.run():
        return 1

    applied = 0
    for fn in d.func_detector.functions.values():
        if fn.start in named:
            fn.name = named[fn.start]
            applied += 1
    print("Names applied: %d of %d from %s" % (applied, len(named), funcs_json))
    if applied != len(named):
        print("WARNING: %d named addresses are not function starts in this "
              "analysis; were the disasm flags different?"
              % (len(named) - applied), file=sys.stderr)

    abi = load_abi(os.path.join(root, "tools", "abi_analysis", "output",
                                "abi_functions.json"))
    manifest = split(d.engine, d.func_detector, args.out, abi_by_addr=abi)
    print("Split %d functions into %s (with ABI: %d)"
          % (manifest["functions"], os.path.join(args.out, "asm"),
             manifest["with_abi"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
