"""Prints decompiled functions from a Ghidra `decomp.c` export (see ExportAll.java).

Usage:
    python fn.py <decomp.c> <address or name> [...]     print functions
    python fn.py <decomp.c> --callers <address or name>  list functions calling it
"""
import re
import sys

HEADER = re.compile(r"^// ==== FUNCTION (\S+) @ ([0-9a-fA-F]+) ")


def load(path):
    functions = {}
    order = []
    current = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = HEADER.match(line)
            if m:
                current = (m.group(1), int(m.group(2), 16))
                functions[current] = [line]
                order.append(current)
            elif current:
                functions[current].append(line)
    return functions, order


def find(functions, key):
    key = key.lower().removeprefix("0x")
    for name, addr in functions:
        if name.lower() == key or f"{addr:08x}" == key.zfill(8) or name.lower() == f"fun_{key.zfill(8)}":
            return (name, addr)
    return None


def main():
    functions, _ = load(sys.argv[1])
    args = sys.argv[2:]
    if args and args[0] == "--callers":
        target = find(functions, args[1])
        if not target:
            sys.exit(f"not found: {args[1]}")
        pattern = re.compile(r"\b" + re.escape(target[0]) + r"\s*\(")
        for key, lines in functions.items():
            if key != target and any(pattern.search(l) for l in lines[1:]):
                print(f"{key[1]:08x} {key[0]}")
        return
    for arg in args:
        key = find(functions, arg)
        if not key:
            print(f"// not found: {arg}")
            continue
        sys.stdout.write("".join(functions[key]))


if __name__ == "__main__":
    main()
