"""Prints which of the opcodes the levels use are implemented in the port's VM.

Usage: python opcode_coverage.py <data dir> [<script_vm.gd>]
The VM's implemented opcodes are the numbers of its `match` cases (`\t\t12, 94:`).
"""
import re
import sys

from mdk_script_dis import SPEC, entry_points, load_cmi, walk


def main():
    data_dir = sys.argv[1]
    vm_path = sys.argv[2] if len(sys.argv) > 2 else "../../game/scripts/script_vm.gd"
    implemented = set()
    for line in open(vm_path, encoding="utf-8"):
        match = re.match(r"^\t\t([0-9, ]+):", line)
        if match:
            implemented |= {int(n) for n in match.group(1).replace(" ", "").split(",") if n}
    used = set()
    for level in range(3, 9):
        d, dirs, _ = load_cmi(data_dir, level)
        for _, start in entry_points(d, dirs):
            for opc, _, _ in walk(d, start).values():
                if opc != 0xFF:
                    used.add(opc)
    missing = sorted(used - implemented)
    print("%d of the %d opcodes the levels use are implemented" % (len(used & implemented), len(used)))
    for opc in missing:
        print("  %3d %s" % (opc, SPEC[opc][1]["mnemonic"] if opc in SPEC else "?"))


if __name__ == "__main__":
    main()
