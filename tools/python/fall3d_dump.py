"""Lists and decodes the files of MDK's fall minigame (`FALL3D/`), for docs/gameplay.md "The fall".

Usage:
    python fall3d_dump.py <FALL3D dir> [--png <out dir>]

Prints the entries of FALL3D.BNI (name, offset, size, what the size means), FALL3D_n.MTI
(name, kind, size) and FALL3D.SNI, and decodes the fall-specific records:

- `FALLPU_n`: the pickup list, 12-byte records `char[12]` pickup name (NUL-padded), ended by
  an empty name; the game spawns them from the last one backwards (fall_3d.c 0x4114a4).
- `ZOOM0000`..`ZOOM0015`: the 16 frames of the haze overlay on the ground, one record per
  pair of screen rows (180 records): `u32 nL, u8[4*nL] table, u32 nM, u32 nR, u8[4*nR] table`,
  nL + nM + nR = 150 groups of 4 pixels (600 px). The table bytes 0..8 select a white-blend
  table (see gameplay.md); the middle nM groups are drawn without blending.
- `SPACEPAL`, `FALLPn`: 768-byte VGA palettes (0..255 per component).
- `SPACE`, `MOON`, `EARTH`, `PICK`, `SKULL`, `FLARE1`-`4`, ...: plain images `u16 w, u16 h, pixels`.

With --png, writes the plain images (with SPACEPAL / FALLP1 palettes), the ground `LEVELn`,
the minecrawler track `PODn`, the crawler sprites `Ln_C000m` and the ZOOM masks as PNGs (needs
Pillow).
"""
import os
import struct
import sys


def read_bni(path):
    data = open(path, "rb").read()
    size, count = struct.unpack_from("<II", data, 0)
    entries = []
    for i in range(count):
        name, offset = struct.unpack_from("<12sI", data, 8 + i * 16)
        entries.append([name.split(b"\0")[0].decode("latin1"), offset + 4])
    ends = sorted(o for _, o in entries) + [len(data)]
    out = {}
    for name, offset in entries:
        end = min(e for e in ends if e > offset)
        out[name] = data[offset:end]
    return [n for n, _ in entries], out


def read_mti(path):
    data = open(path, "rb").read()
    count = struct.unpack_from("<I", data, 20)[0]
    out = []
    for i in range(count):
        name, kind, value, f, offset = struct.unpack_from("<8sIIfI", data, 24 + i * 24)
        offset += 4
        name = name.split(b"\0")[0].decode("latin1")
        entry = {"name": name, "kind": kind, "value": value, "f": f, "offset": offset}
        if kind != 0xFFFFFFFF:
            if kind >> 16:
                frames, w, h = struct.unpack_from("<IHH", data, offset)
                entry.update(frames=frames, w=w, h=h, pixels=data[offset + 8:offset + 8 + frames * w * h])
            else:
                w, h = struct.unpack_from("<HH", data, offset)
                entry.update(w=w, h=h, pixels=data[offset + 4:offset + 4 + w * h])
        out.append(entry)
    return out


def read_sni(path):
    data = open(path, "rb").read()
    count = struct.unpack_from("<I", data, 20)[0]
    out = []
    for i in range(count):
        name, flags, unk, offset, length = struct.unpack_from("<12sHHII", data, 24 + i * 24)
        out.append((name.split(b"\0")[0].decode("latin1"), flags, unk, offset, length))
    return out


def parse_zoom(blob):
    """Returns 180 rows of (left bytes, middle group count, right bytes)."""
    rows, p = [], 0
    for _ in range(180):
        nl = struct.unpack_from("<I", blob, p)[0]; p += 4
        left = blob[p:p + 4 * nl]; p += 4 * nl
        nm, nr = struct.unpack_from("<II", blob, p); p += 8
        right = blob[p:p + 4 * nr]; p += 4 * nr
        rows.append((left, nm, right))
    return rows, p


def main():
    root = sys.argv[1]
    png = sys.argv[sys.argv.index("--png") + 1] if "--png" in sys.argv else None
    order, bni = read_bni(os.path.join(root, "FALL3D.BNI"))
    print("FALL3D.BNI")
    for name in order:
        blob = bni[name]
        note = ""
        if len(blob) >= 4:
            w, h = struct.unpack_from("<HH", blob, 0)
            if w * h + 4 in (len(blob), len(blob) - 1, len(blob) - 2, len(blob) - 3):
                note = f"image {w}x{h}"
        if len(blob) == 768:
            note = "palette"
        if name.startswith("FALLPU_"):
            names = []
            for i in range(0, len(blob) - 11, 12):
                s = blob[i:i + 12].split(b"\0")[0].decode("latin1")
                if not s:
                    break
                names.append(s)
            note = "pickups: " + ", ".join(names)
        if name.startswith("ZOOM"):
            rows, used = parse_zoom(blob[4:])
            groups = {sum((len(l) // 4, m, len(r) // 4)) for l, m, r in rows}
            values = sorted({b for l, m, r in rows for b in l + r})
            note = f"zoom mask, u32 {struct.unpack_from('<I', blob)[0]} + {used} bytes, groups/row {groups}, values {values}"
        print(f"  {name:12s} {len(blob):8d}  {note}")
    for n in range(1, 6):
        path = os.path.join(root, f"FALL3D_{n}.MTI")
        if os.path.exists(path):
            print(f"FALL3D_{n}.MTI")
            for e in read_mti(path):
                dims = f"{e.get('frames', 1)}x{e['w']}x{e['h']}" if "w" in e else f"colour {e['value']}"
                print(f"  {e['name']:8s} kind {e['kind']:#x} {dims}")
    print("FALL3D.SNI")
    for name, flags, unk, offset, length in read_sni(os.path.join(root, "FALL3D.SNI")):
        print(f"  {name:12s} flags {flags} {unk:#x} {length}")
    if png:
        from PIL import Image
        os.makedirs(png, exist_ok=True)

        def save(name, w, h, pixels, pal):
            img = Image.frombytes("P", (w, h), bytes(pixels[:w * h]))
            img.putpalette(pal)
            img.save(os.path.join(png, name + ".png"))

        space = bni["SPACEPAL"]
        for name in order:
            blob = bni[name]
            if len(blob) >= 4 and not name.startswith(("ZOOM", "FALLPU", "FALLP", "SPACEPAL")):
                w, h = struct.unpack_from("<HH", blob, 0)
                if 0 < w * h <= len(blob) - 4:
                    pal = space if name in ("SPACE", "MOON", "EARTH") else bni["FALLP1"]
                    save(name, w, h, blob[4:], pal)
            if name.startswith("ZOOM"):
                rows, _ = parse_zoom(blob[4:])
                img = bytearray()
                for l, m, r in rows:
                    img += bytes(b * 28 for b in l) + bytes(4 * m) + bytes(b * 28 for b in r)
                Image.frombytes("L", (600, 180), bytes(img)).save(os.path.join(png, name + ".png"))
        for n in range(1, 6):
            path = os.path.join(root, f"FALL3D_{n}.MTI")
            if os.path.exists(path):
                for e in read_mti(path):
                    if "w" in e:
                        save(f"MTI{n}_{e['name']}", e["w"], e["h"] * e.get("frames", 1), e["pixels"], bni[f"FALLP{n}"])


if __name__ == "__main__":
    main()
