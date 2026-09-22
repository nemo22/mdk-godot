"""Prints constants stored in an executable at virtual addresses (as float, double, int).

Usage: python const.py <exe> <address> [...]
"""
import struct
import sys


def sections(data):
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    count = struct.unpack_from("<H", data, pe + 6)[0]
    optional_size = struct.unpack_from("<H", data, pe + 20)[0]
    image_base = struct.unpack_from("<I", data, pe + 24 + 28)[0]
    table = pe + 24 + optional_size
    out = []
    for i in range(count):
        entry = table + i * 40
        virtual_size, virtual_address, raw_size, raw_pointer = struct.unpack_from("<IIII", data, entry + 8)
        out.append((image_base + virtual_address, max(virtual_size, raw_size), raw_pointer, raw_size))
    return out


def read(data, table, address, size):
    for start, length, raw, raw_size in table:
        if start <= address < start + length:
            offset = address - start
            if offset + size > raw_size:
                return None
            return data[raw + offset:raw + offset + size]
    return None


def main():
    data = open(sys.argv[1], "rb").read()
    table = sections(data)
    for arg in sys.argv[2:]:
        address = int(arg.removeprefix("_DAT_").removeprefix("DAT_"), 16)
        raw = read(data, table, address, 8)
        if raw is None:
            print("%08x: (uninitialized)" % address)
            continue
        f32 = struct.unpack_from("<f", raw)[0]
        f64 = struct.unpack_from("<d", raw)[0]
        i32 = struct.unpack_from("<i", raw)[0]
        print("%08x: f32 %-14g f64 %-14g i32 %d" % (address, f32, f64, i32))


if __name__ == "__main__":
    main()
