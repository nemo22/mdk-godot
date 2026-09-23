"""Decoder and previewer for the between-level screens (game state 6, see docs/gameplay.md).

Reads MISC/STATS.BNI and MISC/MDKFONT.FTI and renders 600 x 360 PNG previews of the intermission
image, the debriefing and briefing pages (texts typed in full, laid out with the game's text
codes and FONTBIG) and a static Score-O-matic (labels and bars at their final positions).

Colours 0-63 come from the FTI's SYS_PAL (the game uses its current global palette there, whose
first 64 colours are the same system colours); colours 64-255 from the image's own palette
(the image entries: 768-byte palette, u16 width, u16 height, pixels) or from the PAL entry.

Usage:
    python mdk_stats.py list                       entries of STATS.BNI
    python mdk_stats.py texts                      the ST_*, DEB*, BRIEF* texts of MDKFONT.FTI
    python mdk_stats.py intermission OUT.png       L1_INTRM
    python mdk_stats.py debrief N FLAGS OUT.png    level N (1-4), FLAGS = S, F, SS, SF, FS
    python mdk_stats.py brief N OUT.png            BRIEFN on LN_MAP (1-5)
    python mdk_stats.py score OUT.png [fired hits sniper sniper_hits kills total heads]

The MDK directory defaults to C:/games/MDK (override with the MDK environment variable).
"""
import os
import struct
import sys

from PIL import Image

MDK = os.environ.get("MDK", "C:/games/MDK")
W, H = 600, 360


def archive(path, name_len):
    """BNI (name_len 12) or FTI (name_len 8) directory: {name: bytes}, offsets relative to +4."""
    data = open(path, "rb").read()
    count = struct.unpack_from("<I", data, 4)[0]
    stride = name_len + 4
    entries = []
    for i in range(count):
        base = 8 + stride * i
        name = data[base:base + name_len].split(b"\0")[0].decode("latin-1")
        entries.append((name, struct.unpack_from("<I", data, base + name_len)[0] + 4))
    out = {}
    for i, (name, off) in enumerate(entries):
        end = entries[i + 1][1] if i + 1 < len(entries) else len(data)
        out[name] = data[off:end]
    return out


BNI = archive(os.path.join(MDK, "MISC/STATS.BNI"), 12)
FTI = archive(os.path.join(MDK, "MISC/MDKFONT.FTI"), 8)


def text(name):
    return FTI[name].split(b"\0")[0]


def palette(entry):
    """256 RGB triplets: 0-63 from SYS_PAL, 64-255 from the entry's palette."""
    sys_pal = FTI["SYS_PAL"][:192]
    return list(sys_pal + entry[192:768])


class Font:
    """FONTBIG / FONTSML: 256 u32 glyph offsets, glyph = s8 ascent, s8 descent, u8 width, pixels."""

    def __init__(self, name, space):
        self.data = FTI[name]
        self.space = space

    def glyph(self, c):
        off = struct.unpack_from("<I", self.data, c * 4)[0]
        if off == 0:
            return None
        asc, desc, width = struct.unpack_from("<bbB", self.data, off)
        return asc, desc, width, self.data[off + 3:off + 3 + (asc + desc + 1) * width]

    def width(self, s):
        return sum(g[2] if g else self.space for g in map(self.glyph, s))

    def draw(self, img, x, y, s, scale=1.0):
        """Draws at baseline y (0x415a20 / 0x415bd8; scaled: 0x415d8c, nearest-neighbour)."""
        for c in s:
            g = self.glyph(c)
            if g is None:
                x += self.space * scale
                continue
            asc, desc, width, pix = g
            rows = asc + desc + 1
            for j in range(int(rows * scale)):
                for i in range(int(width * scale)):
                    v = pix[int(j / scale) * width + int(i / scale)]
                    px, py = int(x) + i, int(y - asc * scale) + j
                    if v and 0 <= px < W and 0 <= py < H:
                        img.putpixel((px, py), v)
            x += width * scale


BIG = Font("FONTBIG", 6)
SML = Font("FONTSML", 4)


def typeset(img, s, y):
    """Lays out a whole text like 0x4335c0 with every character shown (budget 2000).

    Codes (an optional decimal number N may precede the letter): \\c centre the next line on
    x 300 (or N); \\n new line (y += 36, + N); \\y like \\n (y += N if given, else 36);
    \\x left-align at x N (or 0), same y; \\p pause N characters; \\d / \\i typed / instant.
    """
    x, centred, line, i = 0, False, b"", 0

    def flush():
        if line:
            BIG.draw(img, x - (BIG.width(line) >> 1) if centred else x, y, line)

    while i < len(s):
        c = s[i]
        i += 1
        if c != 0x5C:
            line += bytes([c])
            continue
        n = None
        j = i
        while j < len(s) and (0x30 <= s[j] <= 0x39 or s[j] == 0x2D):
            j += 1
        if j > i:
            n = int(s[i:j])
        code = chr(s[j])
        i = j + 1
        if code in "cnxy":
            flush()
            line = b""
            if code == "c":
                x, centred = (n if n is not None else 300), True
            elif code == "x":
                x, centred = (n if n is not None else 0), False
            elif code == "n":
                x, centred = 0, False
                y += (n or 0) + 36
            else:
                x, centred = 0, False
                y += n if n is not None else 36
    flush()


def page(background):
    entry = BNI[background]
    w, h = struct.unpack_from("<HH", entry, 768)
    img = Image.frombytes("P", (w, h), entry[772:772 + w * h])
    img.putpalette(palette(entry))
    return img


DEB = {"S": 0x00, "F": 0x40, "SS": 0x80, "SF": 0xA0, "FS": 0xC0}  # top byte of 0x57440f & 0xE0


def score(counts):
    fired, hits, sniper, sniper_hits, kills, total, heads = counts
    img = Image.new("P", (W, H), 0)
    img.putpalette(palette(BNI["PAL"]))
    BIG.draw(img, (600 - BIG.width(text("ST_SCR"))) // 2, 28, text("ST_SCR"))
    SML.draw(img, (600 - SML.width(text("ST_DAMP"))) // 2, 48, text("ST_DAMP"))
    rows = [
        ("ST_SHF", fired, fired, b"%d" % fired),
        ("ST_ACC", hits * 100 // fired if fired else 0, 100, None),
        ("ST_SNF", sniper, sniper, b"%d" % sniper),
        ("ST_ACC", sniper_hits * 100 // sniper if sniper else 0, 100, None),
        ("ST_KILL", kills, total, b"%d/%d" % (kills, total)),
    ]
    final = [(180, 75, 120, 128), (420, 75, 120, 128), (180, 125, 120, 128), (420, 125, 120, 128),
             (300, 175, 120, 128)]
    for (label, value, maximum, shown), (x, y, w, s) in zip(rows, final):
        scale = s / 256
        lbl = text(label)
        BIG.draw(img, x - round(BIG.width(lbl) * scale * 0.5), y, lbl, scale)
        by, bx = round(y + 18 * scale), x - w // 2
        shown = shown if shown is not None else b"%d%%" % value
        SML.draw(img, bx - (SML.width(shown) + 8), by + 8 + 6, shown)
        if maximum and w * value // maximum:
            for py in range(by, by + 16):
                for px in range(bx, bx + w * value // maximum):
                    img.putpixel((px, py), 0x3F)
    lbl = text("ST_HEAD")
    BIG.draw(img, 300 - BIG.width(lbl) // 2, 255, lbl)
    return img


def main():
    cmd = sys.argv[1]
    if cmd == "list":
        for name, data in BNI.items():
            print("%-12s %7d" % (name, len(data)))
    elif cmd == "texts":
        for name in FTI:
            if name.startswith(("ST_", "DEB", "BRIEF")):
                print("%-8s %r" % (name, text(name).decode("latin-1")))
    elif cmd == "intermission":
        page("L1_INTRM").save(sys.argv[2])
    elif cmd == "debrief":
        n, flags = int(sys.argv[2]), sys.argv[3]
        img = page("L%d_MAP" % n)
        typeset(img, text("DEBTOP"), 64)
        typeset(img, text("DEB%d%s" % (n, flags)), 120)
        typeset(img, text("DEBBOT"), 300)
        img.save(sys.argv[4])
    elif cmd == "brief":
        n = int(sys.argv[2])
        img = page("L%d_MAP" % n)
        typeset(img, text("BRIEF%d" % n), 32)
        img.save(sys.argv[3])
    elif cmd == "score":
        counts = [int(v) for v in sys.argv[3:10]] or [250, 150, 12, 9, 40, 60, 6]
        score(counts).save(sys.argv[2])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
