"""Lists every use of the given script opcodes in the levels' CMI scripts.

Usage: python find_opcode.py <data dir> <opcode> [<opcode> ...]
Prints the level, the entry point (script name), the address and the decoded operands.
"""
import sys

from mdk_script_dis import SPEC, entry_points, load_cmi, walk


def main():
    data_dir = sys.argv[1]
    opcodes = {int(a) for a in sys.argv[2:]}
    for level in range(3, 9):
        d, dirs, _ = load_cmi(data_dir, level)
        seen = set()
        for name, start in entry_points(d, dirs):
            for p, (opc, vals, _) in sorted(walk(d, start).items()):
                if opc in opcodes and p not in seen:
                    seen.add(p)
                    print("level %d %-24s %06x %3d %s %s" % (level, name, p, opc, (SPEC[opc][1]["mnemonic"] if opc in SPEC else "?"), vals))


if __name__ == "__main__":
    main()
