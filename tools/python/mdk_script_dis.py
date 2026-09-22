"""Reference disassembler for MDK script bytecode (LEVELn.CMI).

Operand layouts are in `script_opcodes.json` (next to this file); instructions whose operands depend
on earlier operands are handled in `complex_operand()`. See `docs/scripts.md`.

Usage:
    python mdk_script_dis.py C:/GOG Games/MDK                   # check every script of levels 3-8
    python mdk_script_dis.py C:/GOG Games/MDK 3 HMO_1           # disassemble a script of level 3
    python mdk_script_dis.py C:/GOG Games/MDK 3 'HMO_1$XH1_DOOR'
"""
import collections
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = {o["opcode"]: (o["part"], o) for o in json.load(open(os.path.join(HERE, "script_opcodes.json"), encoding="utf-8"))}


def load_cmi(data_dir, level):
    """Returns (bytes, [4 directories of (name, offset)], end of the directories)."""
    d = open(os.path.join(data_dir, "TRAVERSE", "LEVEL%d" % level, "LEVEL%d.CMI" % level), "rb").read()
    p = 0x14
    dirs = []
    for _ in range(4):
        (count,) = struct.unpack_from("<I", d, p)
        p += 4
        entries = []
        for _ in range(count):
            length = d[p]
            name = d[p + 1:p + 1 + length].rstrip(b"\0").decode("latin1")
            (offset,) = struct.unpack_from("<I", d, p + 1 + length)
            p += 1 + length + 4
            entries.append((name, offset))
        dirs.append(entries)
    return d, dirs, p


def entry_points(d, dirs):
    """Script entry points: alien and object scripts, and arena scripts (from the arena records)."""
    entries = [(name, off + 4) for name, off in dirs[0]] + [(name, off + 4) for name, off in dirs[2] if off]
    for name, off in dirs[3]:
        rec = off + 4
        p = rec + 1 + d[rec]
        p += 1 + d[p]
        (script,) = struct.unpack_from("<I", d, p)
        if script:
            entries.append((name, script + 4))
    return entries


class Stop(Exception):
    pass


class Bad(Exception):
    pass


class R:
    def __init__(self, d, p):
        self.d, self.p = d, p
        self.targets = []
        self.data = []
        self.warn = []

    def u8(self):
        v = self.d[self.p]; self.p += 1; return v

    def s8(self):
        v = struct.unpack_from('<b', self.d, self.p)[0]; self.p += 1; return v

    def u16(self):
        v = struct.unpack_from('<H', self.d, self.p)[0]; self.p += 2; return v

    def s16(self):
        v = struct.unpack_from('<h', self.d, self.p)[0]; self.p += 2; return v

    def u32(self):
        v = struct.unpack_from('<I', self.d, self.p)[0]; self.p += 4; return v

    def f32(self):
        v = struct.unpack_from('<f', self.d, self.p)[0]; self.p += 4
        if v != v or (v != 0 and not (1e-6 < abs(v) < 1e7)):
            self.warn.append(f'odd f32 {v!r}')
        return v

    def off(self, code=True):
        v = struct.unpack_from('<I', self.d, self.p)[0]; self.p += 4
        if v and v + 4 >= len(self.d):
            raise Bad(f'target out of file {v:#x}')
        if v and code:
            self.targets.append(v + 4)
        if v and not code:
            self.data.append(v + 4)
        return v

    def pstr(self):
        L = self.d[self.p]
        s = self.d[self.p + 1:self.p + 1 + L]
        self.p += 1 + L
        if L and s[-1] != 0:
            self.warn.append(f'pstr not NUL terminated {s!r}')
        if any(c < 32 or c > 126 for c in s[:-1]):
            self.warn.append(f'pstr odd chars {s!r}')
        return s.rstrip(b'\0').decode('latin1')

    def action(self):
        a = self.u8()
        if a == 0xFE:
            return ('ifelse-gosub', self.off(), self.off())
        if a in (0xFC, 0x0C):
            return ({0xFC: 'gosub', 0x0C: 'goto'}[a], self.off())
        if a == 0xFD:
            return ('return',)
        self.warn.append(f'action byte {a:#x}')
        return ('A=%#x' % a,)

    def value(self):
        k = self.u8()
        if k == 3:
            return self.f32()
        i = self.u8()
        if i > 3:
            self.warn.append(f'var index {i}')
        if k > 3:
            self.warn.append(f'var kind {k}')
        return f'var{k}[{i}]'



NOFALL = {9, 12, 94, 253, 255, 110, 184, 182}  # 182 switch_goto


def cond(r):
    c = r.u8(); a = [c, r.f32()]
    if c in (7, 8):
        a.append(r.f32())
    return a


def complex_operand(r, opc, a, prev):
    """prev = list of previously decoded operand values of this instruction"""
    L = a['layout']
    kind = a.get('kind')
    # ---------- part 1 (by opcode) ----------
    if opc in (4,):
        if a['name'] == 'command_args':
            cmd = prev[0]
            if cmd == 7:
                return r.action()
            if cmd == 43:
                return [r.f32(), r.f32()]
            return None
        if a['name'] == 'selector_args':
            sel = prev[2]; out = []
            if sel in (6, 10): out.append(r.f32())
            if sel in (2, 4, 5, 6, 7, 10): out.append(r.pstr())
            if sel == 5: out.append(r.u32())
            return out
    if opc == 2 and a['name'] == 'origin':
        return [r.f32(), r.f32(), r.f32()] if prev[4] == 0 else None
    if opc == 164:
        return [r.f32() for _ in range(4)] if prev[0] else None
    if opc == 42 and a['name'] == 'part':
        s = r.pstr()
        return ('', r.pstr()) if s == '' else s
    if opc == 249 and a['name'] == 'sound':
        return r.pstr() if prev[0] == 1 else None
    if opc == 250:
        if a['name'] == 'type_name':
            return r.pstr() if prev[0] == 0xFF else None
        if a['name'] == 'box':
            return [r.f32() for _ in range(4 if prev[2] == 2 else 6)]
    if opc in (174, 175) and a['name'] == 'b':
        return r.f32() if prev[1] in (7, 8) else None
    if opc == 129:
        if prev[0] in (0, 1, 2):
            n = r.u8(); return [r.pstr() for _ in range(n)]
        return None
    if opc == 132:
        return [r.f32(), r.f32(), r.f32()] if prev[1] == 0xFF else None
    if opc == 89:
        f = prev[0]
        if f & 0x10: return [r.f32(), r.f32(), r.f32()]
        if f & 0x20: return r.u8()
        if f & 0x40: return [r.f32(), r.f32(), r.f32()]
        return None
    # ---------- generic kinds ----------
    if kind in ('action', 'cond_action') or L.startswith('branch action') or L.startswith('u8 act;') or L.startswith('u8 kind; kind 0xFE'):
        return r.action()
    if kind == 'value' or L.startswith('value:') or L.startswith('u8 src; if src==3') or L.startswith('u8 kind; if kind==3'):
        return r.value()
    if kind == 'cond' or (L.startswith('u8 op; f32')):
        return cond(r)
    # ---------- parts 2/3 by opcode ----------
    if opc == 61:
        m = r.u8(); return [m, r.u8() if m == 0 else r.pstr()]
    if opc == 83:
        if r.d[r.p] == 0xFF:
            r.u8(); return [r.f32(), r.f32()]
        return r.value()
    if opc == 159:
        m = r.u8(); return [m] + ([r.f32(), r.f32(), r.f32()] if m in (1, 2) else [])
    if opc == 189:
        m = r.u8()
        if m == 0: return [m, r.f32(), r.f32()]
        if m == 1: return [m, r.f32()]
        return [m]
    if opc == 193:
        m = r.u8(); return [m] + ([r.pstr()] if m == 3 else [])
    if opc == 245:
        if r.d[r.p] == 0:
            r.u8(); return [r.u8(), r.pstr()]
        return [r.pstr()]
    if opc == 248:
        m = r.u8(); x = r.f32()
        return [m, x, r.f32(), r.f32()] if m == 0 else [m, x, r.f32()]
    if opc in (172, 178):
        m = r.u8(); return [m, r.u8()] if m == 3 else [m, r.f32(), r.f32(), r.f32()]
    if opc == 173:
        s = r.pstr()
        return [s] if s != '' else ['', r.pstr(), r.f32(), r.f32(), r.f32(), r.f32()]
    if opc == 180:
        m = r.u8(); return [m] + ([r.f32(), r.f32(), r.f32()] if m else [])
    if opc == 181:
        m = r.u8()
        if m == 0: return [m, r.u8(), r.u32()]
        if m == 1: return [m, r.u8(), r.f32(), r.f32(), r.u32()]
        return [m]
    if opc == 203:
        m = r.u8(); return [m] + ([r.f32()] if m == 1 else [])
    if opc == 224:
        m = r.u8(); return [m] + ([r.f32(), r.f32()] if m else [])
    if opc == 228:
        Ln = r.d[r.p]
        if Ln == 0:
            r.u8(); return ['', r.u8()]
        return r.pstr()
    if opc == 242:
        m = r.u8(); return [m] + ([r.f32() for _ in range(12)] if m else [])
    if opc == 158:
        return r.off() if prev[2] & 2 else None
    raise KeyError(f'complex not handled: op {opc} {a["name"]}: {L[:80]}')


CODE_OFF = set()


def decode(r, opc):
    part, o = SPEC[opc]
    vals = []
    for a in o['operands']:
        t = a['type']
        if t == 'u8': v = r.u8()
        elif t == 's8': v = r.s8()
        elif t == 'u16': v = r.u16()
        elif t == 's16': v = r.s16()
        elif t == 'u32': v = r.u32()
        elif t == 's32': v = struct.unpack('<i', struct.pack('<I', r.u32()))[0]
        elif t == 'f32': v = r.f32()
        elif t == 'pstr': v = r.pstr()
        elif t == 'off32':
            code = not (a.get('role') == 'data' or (opc, a['name']) in {(2, 'path'), (28, 'path'), (3, 'anim'), (59, 'anim')})
            v = r.off(code)
        elif t == 'repeat':
            n = r.u8(); v = []
            for _ in range(n):
                item = []
                for it in a['items']:
                    if it['type'] == 'off32': item.append(r.off())
                    elif it['type'] == 'u8': item.append(r.u8())
                    elif it['type'] == 'pstr': item.append(r.pstr())
                    else: raise KeyError(it)
                v.append(item)
        elif t == 'complex':
            v = complex_operand(r, opc, a, vals)
        else:
            raise KeyError(t)
        vals.append(v)
    return vals, ('end' if opc in NOFALL else 'next')



def walk(d, start):
    """Disassembles everything reachable from file offset `start`. Returns {offset: (opcode, values, end)}."""
    out = {}
    work = [start]
    while work:
        p = work.pop()
        while p not in out:
            opc = d[p]
            if opc == 0xFF:
                out[p] = (opc, [], p + 1)
                break
            if opc not in SPEC:
                out[p] = (opc, ["invalid opcode"], p + 1)
                break
            r = R(d, p + 1)
            vals, flow = decode(r, opc)
            out[p] = (opc, vals, r.p)
            work.extend(r.targets)
            if flow == "end":
                break
            p = r.p
    return out


def check(data_dir):
    stats = collections.Counter()
    for level in range(3, 9):
        d, dirs, _ = load_cmi(data_dir, level)
        for name, start in entry_points(d, dirs):
            try:
                for opc, vals, _ in walk(d, start).values():
                    stats["invalid" if vals == ["invalid opcode"] else "decoded"] += 1
            except (Bad, IndexError, struct.error, KeyError) as e:
                stats["errors"] += 1
                print("level %d %s: %s" % (level, name, e))
    print(dict(stats))


def main():
    data_dir = sys.argv[1]
    if len(sys.argv) < 4:
        check(data_dir)
        return
    level, name = int(sys.argv[2]), sys.argv[3]
    d, dirs, _ = load_cmi(data_dir, level)
    start = dict(entry_points(d, dirs))[name]
    for p, (opc, vals, _) in sorted(walk(d, start).items()):
        mnemonic = "end" if opc == 0xFF else SPEC[opc][1]["mnemonic"] if opc in SPEC else "?"
        print("%06x  %3d %-22s %s" % (p, opc, mnemonic, vals))


if __name__ == "__main__":
    main()
