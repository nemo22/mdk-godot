"""Flat-shaded contact sheets of decoded animation frames (validation only).

python render_model.py MTO ARENA MODEL ANIM OUT.png [frames per row] [yaw deg] [pitch deg] [step]
"""
import colorsys
import math
import sys

import numpy as np
from PIL import Image, ImageDraw

from mdk_models import ModelsSection, mto_arenas


def view_matrix(yaw, pitch):
    y, p = math.radians(yaw), math.radians(pitch)
    # MDK is Z up. Camera looks along -forward; screen x = right, screen y = up.
    rz = np.array([[math.cos(y), -math.sin(y), 0], [math.sin(y), math.cos(y), 0], [0, 0, 1]])
    rx = np.array([[1, 0, 0], [0, math.cos(p), -math.sin(p)], [0, math.sin(p), math.cos(p)]])
    # map world (x, y, z) -> view (right, up, depth) with z up -> up
    swap = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]])
    return rx @ swap @ rz


def render_frame(model, parts_verts, R, center, scale, size, colors):
    img = Image.new("RGB", (size, size), (24, 24, 32))
    dr = ImageDraw.Draw(img)
    polys = []
    light = np.array([0.4, 0.8, 0.45])
    light /= np.linalg.norm(light)
    for pi, (part, verts) in enumerate(zip(model.parts, parts_verts)):
        v = (verts - center) @ R.T
        for tri in part.tris:
            a, b, c = v[tri[0]], v[tri[1]], v[tri[2]]
            n = np.cross(b - a, c - a)
            ln = np.linalg.norm(n)
            if ln == 0:
                continue
            n /= ln
            shade = 0.35 + 0.65 * abs(float(n @ light))
            depth = (a[2] + b[2] + c[2]) / 3
            col = tuple(int(255 * ch * shade) for ch in colors[pi])
            pts = [(size / 2 + p[0] * scale, size / 2 - p[1] * scale) for p in (a, b, c)]
            polys.append((depth, pts, col))
    polys.sort(key=lambda t: t[0])  # far (low depth) first: view depth axis points towards camera
    for _, pts, col in polys:
        dr.polygon(pts, fill=col, outline=(0, 0, 0))
    return img


def main():
    mto, arena, mname, aname, out = sys.argv[1:6]
    cols = int(sys.argv[6]) if len(sys.argv) > 6 else 6
    yaw = float(sys.argv[7]) if len(sys.argv) > 7 else 35
    pitch = float(sys.argv[8]) if len(sys.argv) > 8 else 20
    step = int(sys.argv[9]) if len(sys.argv) > 9 else 1
    data = open(mto, "rb").read()
    sec = ModelsSection(data, mto_arenas(data)[arena])
    import os
    cmi = open(os.environ["CMI"], "rb").read() if os.environ.get("CMI") else None
    model = sec.model(mname, cmi)
    anim = sec.anim(aname)
    frames = [(f, pv) for f, pv in anim.frames(model) if f % step == 0 or f == anim.nframes - 1]
    allv = np.concatenate([np.concatenate(pv) for _, pv in frames])
    center = (allv.min(0) + allv.max(0)) / 2
    R = view_matrix(yaw, pitch)
    radius = np.linalg.norm(allv - center, axis=1).max()
    size = 220
    scale = size * 0.46 / radius
    colors = [colorsys.hsv_to_rgb(i / max(1, len(model.parts)), 0.55, 1.0) for i in range(len(model.parts))]
    rows = (len(frames) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * size, rows * size), (0, 0, 0))
    for i, (f, pv) in enumerate(frames):
        img = render_frame(model, pv, R, center, scale, size, colors)
        ImageDraw.Draw(img).text((4, 4), "%s f%d" % (aname, f), fill=(255, 255, 255))
        sheet.paste(img, ((i % cols) * size, (i // cols) * size))
    sheet.save(out)
    print("wrote", out, len(frames), "frames")


if __name__ == "__main__":
    main()
