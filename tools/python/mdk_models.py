"""Reference decoder for MDK models and animations.

Models live in an arena's models section (LEVELnO.MTO) or in the level's CMI
"enemy table" (LEVELn.CMI, global models: weapons, aliens); animations only
in arena models sections.

Usage:
    python mdk_models.py LEVEL3O.MTO HMO_1                     # list + boundary check
    python mdk_models.py LEVEL3O.MTO HMO_1 XU XU_LAND          # per-frame bbox
    python mdk_models.py LEVEL3O.MTO HMO_2 XG XG_WAVE LEVEL3.CMI

Game code: model parse 0x430cf0, frame step 0x43ab70, matrix track 0x43af28.
"""
import struct
import sys

import numpy as np


def cstr(b):
    return b.split(b"\0", 1)[0].decode("ascii", "replace")


# ---------------------------------------------------------------- MTO / arena

def mto_arenas(data):
    """Returns {name: file offset of the arena's u32 size}."""
    (count,) = struct.unpack_from("<I", data, 0x10 + 4)
    out = {}
    off = 0x18
    for _ in range(count):
        name, o = struct.unpack_from("<8sI", data, off)
        out[cstr(name)] = o
        off += 12
    return out


class ModelsSection:
    """The arena's models section: animations, models and sounds."""

    def __init__(self, data, arena_off):
        buf = arena_off + 4                      # arena buffer (after u32 size)
        (models_rel,) = struct.unpack_from("<I", data, buf)
        sec = buf + models_rel                   # u32 size
        (self.size,) = struct.unpack_from("<I", data, sec)
        self.base = base = sec + 4               # offsets below are relative to this
        na, nm, ns = struct.unpack_from("<3I", data, base)
        off = base + 12
        dirs = []
        for n in (na, nm):
            d = []
            for _ in range(n):
                name, o = struct.unpack_from("<8sI", data, off)
                d.append((cstr(name), o))
                off += 12
            dirs.append(d)
        self.anim_dir, self.model_dir = dirs
        # sounds: 24-byte entries like SNI: char[12] name, u16 a, u16 b, u32 offset
        # (relative to base, a RIFF WAV), u32 length  (func 0x4310cc)
        self.sound_dir = []
        for _ in range(ns):
            name, a, b, o, ln = struct.unpack_from("<12sHHII", data, off)
            self.sound_dir.append((cstr(name), a, b, o, ln))
            off += 24
        self.data = data

    def model(self, name, cmi=None):
        for n, o in self.model_dir:
            if n.upper() == name.upper():
                return Model(self.data, self.base + o, n)
        if cmi is not None:                      # global model from LEVELn.CMI
            m = cmi_models(cmi).get(name.upper())
            if m is not None:
                return m
        raise KeyError(name)

    def anim(self, name):
        for n, o in self.anim_dir:
            if n.upper() == name.upper():
                return Animation(self.data, self.base + o, n)
        raise KeyError(name)


def cmi_models(data):
    """LEVELn.CMI "enemy table" (2nd directory, read by func 0x430fc8):
    {name: Model, or None for an arena ("overlay") model looked up by name in
    the current arena's models section}. Offsets are relative to file offset 4."""
    b = 4

    def rdir(p):
        (n,) = struct.unpack_from("<I", data, p)
        p += 4
        out = []
        for _ in range(n):
            ln = data[p]
            name = cstr(data[p + 1:p + 1 + ln])
            (o,) = struct.unpack_from("<I", data, p + 1 + ln)
            p += 5 + ln
            out.append((name, o))
        return out, p

    _, p = rdir(b + 0x10)        # 1st directory: scripts (HMO_1$XG_0, ...)
    d2, _ = rdir(p)
    return {n: (Model(data, b + o, n) if o else None) for n, o in d2}


# ---------------------------------------------------------------- model

TRI = struct.Struct("<3hh6fI")  # v0 v1 v2 material u0 v0 u1 v1 u2 v2 flags (36 bytes)


class Part:
    pass


class Model:
    """flags=0: one unnamed part; flags!=0: named parts."""

    def __init__(self, data, off, name=""):
        self.name = name
        self.offset = off
        p = off
        self.flags, nmat = struct.unpack_from("<II", data, p)
        p += 8
        self.materials = [cstr(data[p + 16 * i:p + 16 * i + 16]) for i in range(nmat)]
        p += 16 * nmat
        if self.flags:
            (nparts,) = struct.unpack_from("<I", data, p)
            p += 4
        else:
            nparts = 1
        self.parts = []
        for _ in range(nparts):
            part = Part()
            part.name = ""
            part.pivot = None
            part.bbox = None
            if self.flags:
                part.name = cstr(data[p:p + 12])
                part.pivot = np.frombuffer(data, "<f4", 3, p + 12).copy()
                p += 24
            (nv,) = struct.unpack_from("<I", data, p)
            p += 4
            part.verts = np.frombuffer(data, "<f4", nv * 3, p).reshape(nv, 3).astype(np.float64)
            p += nv * 12
            (nt,) = struct.unpack_from("<I", data, p)
            p += 4
            part.tris = [TRI.unpack_from(data, p + 36 * i) for i in range(nt)]
            p += nt * 36
            if self.flags:
                part.bbox = np.frombuffer(data, "<f4", 6, p).copy()  # xmin xmax ymin ymax zmin zmax
                p += 24
            self.parts.append(part)
        self.bbox = np.frombuffer(data, "<f4", 6, p).copy()        # xmin xmax ymin ymax zmin zmax
        p += 24
        (nref,) = struct.unpack_from("<I", data, p)
        p += 4
        self.refpoints = np.frombuffer(data, "<f4", nref * 3, p).reshape(nref, 3).copy()
        p += nref * 12
        self.end = p


# ---------------------------------------------------------------- animation

class Track:
    pass


class Animation:
    def __init__(self, data, off, name=""):
        self.name = name
        self.offset = off
        self.speed, np_, nf = struct.unpack_from("<fII", data, off)
        self.nparts, self.nframes = np_, nf
        track_offs = struct.unpack_from("<%dI" % np_, data, off + 12)
        p = off + 12 + 4 * np_
        # per-frame root motion (model space, applied to the object position)
        self.motion = np.frombuffer(data, "<f4", nf * 3, p).reshape(nf, 3).copy()
        p += nf * 12
        (nref,) = struct.unpack_from("<I", data, p)
        p += 4
        # reference points: [ref][frame] -> xyz (replace the model's reference points)
        self.refpoints = np.frombuffer(data, "<f4", nref * nf * 3, p).reshape(nref, nf, 3).copy()
        p += nref * nf * 12
        self.tracks = []
        for to in track_offs:
            t = Track()
            q = off + 4 + to
            t.offset = q
            t.name = cstr(data[q:q + 12])
            t.nverts, = struct.unpack_from("<I", data, q + 12)
            (raw,) = struct.unpack_from("<I", data, q + 16)
            t.scale = struct.unpack_from("<f", data, q + 16)[0]
            nv = t.nverts
            if raw & 0x7FFFFFFF == 0:
                # rigid: per-frame 3x4 fixed-point matrix
                t.mode = "matrix"
                t.rot_shift, t.pos_shift = data[q + 20], data[q + 21]
                vb = q + 22
                t.base = np.frombuffer(data, "<f4", nv * 3, vb).reshape(nv, 3).astype(np.float64)
                mp = vb + nv * 12
                m = np.frombuffer(data, "<i2", nf * 12, mp).reshape(nf, 3, 4).astype(np.float64)
                m[:, :, :3] /= float(0x8000 >> t.rot_shift)
                m[:, :, 3] /= float(0x8000 >> t.pos_shift)
                t.matrices = m
                t.end = mp + nf * 24
            else:
                # vertex deltas: s16 frame, then nv * s8[3], until frame < 0 (or >= nframes)
                t.mode = "delta"
                vb = q + 20
                t.base = np.frombuffer(data, "<f4", nv * 3, vb).reshape(nv, 3).astype(np.float64)
                r = vb + nv * 12
                t.deltas = {}
                while True:
                    (fr,) = struct.unpack_from("<h", data, r)
                    r += 2
                    if fr < 0 or fr >= nf:
                        break
                    t.deltas[fr] = np.frombuffer(data, "<i1", nv * 3, r).reshape(nv, 3).astype(np.float64)
                    r += nv * 3
                t.end = r
            self.tracks.append(t)

    def track(self, name):
        for t in self.tracks:
            if t.name.upper() == name.upper():
                return t
        return None

    def check(self, model):
        """The game indexes tracks with the MODEL part's vertex count, so the
        counts must match; returns a list of mismatches."""
        bad = []
        for p in model.parts:
            t = self.track(p.name)
            if t is not None and t.nverts != len(p.verts):
                bad.append((p.name, len(p.verts), t.nverts))
        return bad

    def decode(self, model):
        """-> verts [frames, total model verts, 3] (parts concatenated in model
        order), refpoints [frames, n, 3] (or the model's static ones)."""
        verts = np.stack([np.concatenate(pv) for _, pv in self.frames(model)])
        if self.refpoints.shape[0]:
            refs = self.refpoints.transpose(1, 0, 2)
        else:
            refs = np.repeat(model.refpoints[None], self.nframes, 0)
        return verts, refs

    def frames(self, model):
        """Yields (frame, [verts per model part]) for frames 0..n-1, mirroring
        the game's sequential playback (func 0x43ab70): delta tracks accumulate
        from the base pose (reset at frame 0), matrix tracks are absolute.
        Parts without a track keep their current (model) vertices."""
        cur = [p.verts.copy() for p in model.parts]
        for f in range(self.nframes):
            for i, part in enumerate(model.parts):
                t = self.track(part.name)
                if t is None:
                    continue
                if t.mode == "matrix":
                    m = t.matrices[f]
                    cur[i] = t.base @ m[:, :3].T + m[:, 3]
                elif f == 0:
                    cur[i] = t.base.copy()
                elif f in t.deltas:
                    cur[i] = cur[i] + t.deltas[f] * t.scale
            yield f, [c.copy() for c in cur]


# ---------------------------------------------------------------- CLI

def main():
    data = open(sys.argv[1], "rb").read()
    arenas = mto_arenas(data)
    sec = ModelsSection(data, arenas[sys.argv[2]])
    if len(sys.argv) == 3:
        ends = sorted([o for _, o in sec.anim_dir + sec.model_dir] + [sec.size])
        for n, o in sec.model_dir:
            m = sec.model(n)
            nxt = min(e for e in ends if e > o)
            print("model %-8s flags=%d mats=%d parts=%s ref=%d end=%d next=%d" % (
                n, m.flags, len(m.materials),
                [(p.name, len(p.verts), len(p.tris)) for p in m.parts],
                len(m.refpoints), m.end - sec.base, nxt))
        for n, o in sec.anim_dir:
            a = sec.anim(n)
            nxt = min(e for e in ends if e > o)
            print("anim %-8s speed=%g parts=%d frames=%d ref=%d tracks=%s end=%d next=%d" % (
                n, a.speed, a.nparts, a.nframes, a.refpoints.shape[0],
                [(t.name, t.nverts, t.mode, len(getattr(t, 'deltas', {}))) for t in a.tracks],
                max(t.end for t in a.tracks) - sec.base, nxt))
        return
    cmi = open(sys.argv[5], "rb").read() if len(sys.argv) > 5 else None
    model = sec.model(sys.argv[3], cmi)
    anim = sec.anim(sys.argv[4])
    print("vertex count mismatches:", anim.check(model))
    for f, parts in anim.frames(model):
        allv = np.concatenate(parts)
        print(f, allv.min(0).round(2), allv.max(0).round(2))


if __name__ == "__main__":
    main()
