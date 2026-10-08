# MDK file formats

Reverse engineered from the game data and `MDKD3D.EXE` (Watcom C/C++, June 1997).
Function names refer to [`tools/ghidra/names.txt`](../tools/ghidra/names.txt).

All values are little-endian. `u8/u16/u32/s16/s32` are integers, `f32` is an IEEE float.
Names are ASCII, NUL-padded to a fixed length unless noted otherwise.
MDK coordinates are Z up (the port converts them to Godot's Y up as `(x, z, -y)`).

Status: ✅ verified (data loads and renders correctly), 🟡 partially understood, ❓ unknown.

## Files loaded for a level

`level_load` loads, in this order (`n` is the level number, 3–8):

| File | Contents |
| --- | --- |
| `TRAVERSE/LEVELn/LEVELnS.MTI` | Level texture archive: shared textures, alien textures, palette color materials, animated sprites. |
| `TRAVERSE/TRAVSPRT.BNI` | Shared HUD and sniper-mode sprites, Kurt's animations. |
| `TRAVERSE/LEVELn/LEVELn.CMI` | Scripts (bytecode) for aliens and objects, weapon/effect definitions. |
| `TRAVERSE/LEVELn/LEVELn.DTI` | Level settings, arena list, base palette, sky. |
| `TRAVERSE/LEVELn/LEVELnO.MTO` | Arenas: textures, models, animations, sounds, palette colors, world geometry. |
| `TRAVERSE/LEVELn/LEVELnO.SNI`, `LEVELnS.SNI`, `TRAVERSE/TRAVERSE.SNI` | Sounds. |

## Common header

Most files start with:

| Offset | Type | Description |
| --- | --- | --- |
| 0x00 | u32 | Size of the rest of the file (file size − 4). |
| 0x04 | char[12] | Internal file name (e.g. `LEVEL3O.MAT`, `LEVEL3.DAT`, `LEVEL3.CMD`). |
| 0x10 | u32 | Size again (file size − 16). |

The game loads files without their first 4 bytes, so most offsets stored in files are relative to
file offset 4 (the internal name).

## Palette ✅

An arena's 256-color palette (8-bit RGB triplets) is the DTI palette with indices 64–175 replaced
by the arena's 112 colors (`arena_load_step`). The DTI palette has magenta placeholders there.
Index 0 is forced to black and is transparent in sprites. Sprites (`BNI`) only use indices 0–63.

## DTI (level data) 🟡

`LEVELn.DTI`, internal name `LEVELn.DAT`. After the common header, 5 `u32` block offsets
(relative to file offset 4).

### Block 0: settings 🟡

| Offset | Type | Description |
| --- | --- | --- |
| 0x00 | u32 | Index of the arena Kurt starts in (block 2 order; 0 in every level) ✅ |
| 0x04 | f32[3] | Player start position ✅ |
| 0x10 | f32 | Player start angle in degrees (90 faces +Y) ✅ |
| 0x14 | u32 | Sky: palette index filling the screen above the panorama ✅ |
| 0x18 | u32 | Sky: palette index filling the screen below the panorama ✅ |
| 0x1C | u32 | Sky: panorama row at eye level (horizon) ✅ |
| 0x20 | u32 | Sky: horizontal offset in pixels ✅ |
| 0x24 | u32 | Sky: panorama width for 360° (1800 or 900) ✅ |
| 0x28 | u32 | Sky: panorama height (360) ✅ |
| 0x2C | s32[2] | If positive, there's a second panorama and these are its fill colors (levels 5, 6). The sky is the first panorama; the second is only shown by mirrors (0x474694, 0x475860) ✅. |
| 0x34 | 4 × u32[4] | `GLASS1`–`GLASS4`: R, G, B, alpha (0–255) ✅ |

### Block 1 🟡

`u32 count`, then per entry `u32 id, u32 ?, f32 x, f32 y, f32 z, f32 angle` ❓

### Block 2: arenas and corridors 🟡

`u32 count`, then 16-byte entries: `char[8] name, u32 records offset, f32 camera pitch` ✅ (degrees,
positive looks down; usually 4, see [gameplay.md](gameplay.md#camera-camera_update)).
Names are `HMO_1`… (arenas) and `CHMO_1`… (corridors, whose geometry is in `LEVELnO.SNI`) in
level 3; other levels use other prefixes (`MEAT_n`, `OLYM_n`, `DANT_n`, …). Names not starting with `C` get flags `|= 3` in the game.

Each records list is `u32 count`, then 36-byte records:
`u32 type, s32 id, f32 angle, f32 x, f32 y, f32 z, char[12] name`. Types seen: 1, 3 (in corridors),
2 (alien, `name` refers to a CMI script), 5 (cover spots for `find_cover_spot`, the game keeps the
list at `arena+0x38`/`+0x3c`), 6 (connection, see below), 7, 8. ❓

**Connections** (type 6) come in pairs with the same id (1000+), one in an arena and one in its
corridor. The `angle` field holds an integer, the direction Kurt crosses in to leave the arena (0 −x,
1 +x, 2 −y, 3 +y, 6 −z, 7 +z), `x, y, z` and the 12 name bytes (3 × f32) are the corners of the doorway. Every frame 0x41c550
checks whether Kurt's move crossed a connection of his arena inside the doorway; if so he's in the
other arena (see [engine.md](engine.md#kurts-arena)). ✅

### Block 3: palette ✅

`u32` (112, the number of arena colors), then 256 × RGB.

### Block 4: sky ✅

8-bit panorama, `height` rows of `width + 4` pixels (the 4 extra pixels repeat the start of the
row). For levels with two panoramas, the second one follows the first. The file ends with the
12-byte internal name.

The original draws the sky as a 2D backdrop (`sky_draw`): it scrolls horizontally with the yaw
(`width` pixels for 360°) and vertically with the pitch, with the horizon row at eye level.

## MTO (level arenas) ✅

`LEVELnO.MTO`, internal name `LEVELnO.MAT`. After the common header: `u32 count`, then per arena
`char[8] name, u32 offset` (absolute file offset).

Arenas are streamed in 32 KiB chunks when the player gets close (`mto_begin_arena`,
`mto_load_arena_chunk`). At `offset`: `u32 size`, then `size` bytes loaded into a buffer.
Offsets below are relative to that buffer:

| Offset | Type | Description |
| --- | --- | --- |
| 0x00 | u32 | Offset of the models section |
| 0x04 | u32 | Offset of the palette section (112 × RGB) ✅ |
| 0x08 | u32 | Offset of the world section |
| 0x0C | u32 | Size of the texture archive |
| 0x10 | | Texture archive `HMO_n.MAT` (see below) ✅ |

### Models section ✅

Offsets are relative to `base`, right after the section's `u32 size`:
`u32 animation count, u32 model count, u32 sound count`, then animation and model entries
(`char[8] name, u32 offset`, 12 bytes each), then 24-byte sound entries (`char[12] name, u16 ?,
u16 ?, u32 offset, u32 length`, like SNI entries, pointing to RIFF WAV files; at most 16).
A reference decoder is in [`tools/python/mdk_models.py`](../tools/python/mdk_models.py).

The level's CMI file has more models (aliens, weapons) in its second directory
(`u8 length, name, u32 offset`, offset relative to file offset 4; offset 0 means "look it up in
the arena"), in the same format (`cmi_load_model_table`).

#### Model (`model_parse`)

```
u32 flags                        0: one unnamed part; 1: named parts
u32 material count, char[16] × count (the game keeps the first 10 characters)
[flags] u32 part count           (otherwise 1)
per part:
  [flags] char[12] name, f32 pivot[3] (unused by the game)
  u32 vertex count, f32[3] × count        model space
  u32 triangle count, 36-byte triangles    same layout as world triangles, UVs in texels
  [flags] f32 bbox[6]            xmin, xmax, ymin, ymax, zmin, zmax (rest pose)
f32 bbox[6]                      whole model (object collision boxes, see engine.md)
u32 reference point count (≤ 8), f32[3] × count
```

All parts are drawn with the object's transform: part vertices are absolute model coordinates.

#### Animation (`arena_find_animation`, `anim_step_frames`)

```
+0   f32 speed (1.0: 30 frames per second)
+4   u32 track count T
+8   u32 frame count F
+12  u32 track offset[T]         relative to animation + 4
     f32 root motion[F][3]
     u32 reference point count R, f32[R][F][3] (the reference points in each frame: the
     animation moves them, e.g. the camera points of `X_STRIKB`)
track:
+0   char[12] part name
+12  u32 vertex count (the game uses the model part's count instead)
+16  f32 scale; if its bits & 0x7FFFFFFF are 0, the track uses matrices
```

- **Delta tracks** (scale ≠ 0): `f32 base[n][3]` at +20, then records `s16 frame, s8 delta[n][3]`,
  ending with frame −1. Frame 0 sets the vertices to `base`; each record adds `delta × scale`
  (frames without a record hold the previous vertices, so frames must be applied in order).
- **Matrix tracks** (rigid parts): `u8 rotation shift` at +20, `u8 position shift` at +21,
  `f32 base[n][3]` at +22, then `s16 m[F][3][4]`: R = m / (0x8000 >> rotation shift),
  t = m[·][3] / (0x8000 >> position shift), vertices = R·base + t.
- Tracks are matched to model parts by name (case-insensitive). Parts without a track keep their
  current vertices, so each object instance needs its own copy of the vertices.
- Root motion: stepping to frame f moves the object by `motion[f]` (model space); `motion[0]` is the
  opposite of the sum of the others, so looping returns to the start.

### World section ✅ (`arena_parse_world`)

1. `u32 count`, then `char[10]` material names, padded to a multiple of 4 bytes.
2. `u32 count`, then 44-byte BSP nodes: `f32 plane[4]`, child indices, … 🟡
   Node fields 7 and 8 are offsets relative to the end of the vertex list (+4) ❓
3. `u32 count`, then 36-byte triangles:
   `s16 v0, v1, v2, s16 material, f32 u0, v0, u1, v1, u2, v2, u32 flags`.
   - `material` ≥ 0: index into the material names. `material` < 0: palette color `-material`, or a
     special material (see below) if `-material` ≥ 256.
   - UVs are in texels (textures repeat, e.g. floors).
   - `flags`: top byte = triangle group (see [engine.md](engine.md#arena-triangle-groups));
     0x10 not drawn and 0x20 not solid (set only by scripts); bit 23 outlines the triangle in its
     colour along the edges bits 20 (v0–v1), 21 (v1–v2) and 22 (v2–v0) pick (see "Special
     materials"); bit 0 ❓.
4. `u32 count`, then vertices `f32 x, y, z` in world coordinates.
5. `u32` ❓, then BSP leaf data ❓.

## Special materials ✅

How the original draws palette "colours" ≥ 256 (`MDKD3D.EXE`, and `MDK95.EXE` for the software
renderer).

### Where the value is tested

No special case in the scene code: arena triangles (BSP walk 0x40b9fc → 0x40b7f0) and model
triangles (`model_draw_parts` 0x40dca0, depth-sorted; also 0x406e24) all call `model_draw_triangle` (0x40e770) with the
raw s16 material. The value is only interpreted by the rasterizer back end ✅:

- D3D: `d3d_set_material` (0x471290, unnamed in Ghidra) called by every submit function
  (`d3d_submit_triangle` 0x471954, polygon 0x471ea4, gouraud 0x471c20/0x4721b0, line 0x472420).
- Software (`MDK95.EXE`): dispatch at 0x40c93f.

```
m = triangle material (s16, negative = palette colour / special)
software 0x40c93f                       D3D 0x471290 / submit functions
m >= 0          texture                 texture (material table 0x57ec10[m]+0x34)
-255..-1        flat palette[-m]        flat palette[-m & 0xff]
-1010..-990     mirror 0x47a770(m+1000) mirror: sky texture, screen-space UV
-1027..-1024    glass LUT fill 0x412970 glass: untextured, vertex ARGB from DTI, alpha blend
-1028 RIPPLE    0x46e940 (row shift)    NOT DRAWN (every submit fn: if m == -0x404 return)
m < -1028       LUT (-1029-m) (effects) colour table entry (-1029-m) (effects, not level data)
other (-256, -257, -989..-257, -1023..-1011): flat palette[(-m) & 0xff]
```

### NONE (256) and PEN_ENV (257) ✅

- No special code in either renderer. As a negative value they fall through to the palette path:
  `NONE` → palette 0 (forced black by the DTI loader), `PEN_ENV` → palette 1 (white).
- Data: no triangle anywhere stores −256 or −257. `NONE` only appears **by name** (index into the
  name list) on a few arena/corridor triangles (HMO_1/2/3/9, OLYM_5/6, GUNT_2/3/7, CGUNT_3/6), all
  with triangle flags = 3. `PEN_ENV` is only listed in XBSHARK's material names (OLYM_10) and in
  the level 5/6 MTI, never referenced by a triangle.
- A named palette material has no texture: D3D draws it with palette[1] (0x471290 `m >= 0`,
  texture null), software fills colour 0xFF after a debug print (0x40c8e2). So `NONE` triangles
  are not "invisible" in the engine ❓; they're probably never seen (flags 3 ❓). Port: keep skipping.

### Mirrors (990–1010) ✅

Names: `MIRRLOW` 990, `MIRRMED` 1000, `MIRRHIGH` 1010 (levels 3/4/7); `PEN_990/995/1000/1005/1010`
(levels 5/6/8). Any value in 990–1010 is a mirror (XBSHARK uses 995–1009).

Not a real reflection: the triangle is filled with the **sky panorama**, mapped in screen space
(same columns as the sky behind it), shifted vertically by the material value. Opaque, no blend.

Mirror sky image: the second panorama of the DTI if present (levels 5, 6: DTI block 0 field 11 > 0,
pixels at `sky + (wrap+4)*height`), else the normal one. D3D: `sky_setup` 0x474694 uploads it as
texture 0x583bf8 (handle at 0x583c2c); the visible sky is blitted from the **first** panorama
(0x475860 builds the blit surfaces from `g_sky_pixels`). Software: 0x47a770 picks the same
second-image offset (0x54ec98/0x54ec94).

```
k        = value - 1000                     // -10..10  (software arg m+1000, negated sign)
K        = 360 + 8*(1000 - value)           // 990 → 440, 1000 → 360, 1010 → 280
sky_x    = (yaw*5 + sky_offset) % wrap - view_w/2     // 0x5991f8, sky_draw 0x475b4c
sky_y    = round(f * cam_fwd_z)                       // 0x599208 = [0x5991e4]*[0x5739a8] ❓ meaning
column   = sky_x + screen_x                            // both renderers
row D3D  = K - sky_y + screen_y      (0x471908: v = (m*8+0x20a8 - sky_y + trunc(y)) * tex.vscale)
row SW   = K - sky_y - screen_y      (0x47a770: row decremented per scanline → flipped image)
SW only: rows outside 0..height-1 are filled with the (second) sky's top/bottom colour.
D3D: UV wraps (no clamp state set).
```

- D3D state: texture on, TEXTUREMAPBLEND MODULATE, vertex colour 0xFFFFFFFF, no alpha (unless the
  texture is colour-keyed), flat shade. `rhw` = 1 (no perspective; UVs are already screen space).
- LOW/MED/HIGH only change `K`, i.e. which band of the sky is reflected (40 px per 5 units).
  No reflectivity/alpha difference.
- The software image is vertically flipped (a mirror), the D3D one isn't ❓ (unless the texture
  upload flips it; 0x474978 not read).

Port: screen-space shader on the sky texture:
`uv = vec2((sky_x + FRAGCOORD.x) / wrap, (K - sky_y ∓ FRAGCOORD.y) / height)` (in 640×480-ish
original pixels; scale by viewport / original view size).

### Glass (1024–1027) ✅

Names `GLASS1`–`GLASS4` or `PEN_111`–`PEN_114` (= 1024–1027).

- Colour + alpha per level from the DTI, block 0 after the sky fields (int[13..28]):
  4 × `{R, G, B, A}` (A 0–255). `level_load` (0x41b0c0) copies them to table 0x5744d8
  (bytes B, G, R, A). Values:

  | Level | GLASS1 | GLASS2 | GLASS3 | GLASS4 |
  | --- | --- | --- | --- | --- |
  | 3 | 96,255,255 a64 | 48,255,255 a48 | 48,255,192 a32 | 0,128,32 a240 |
  | 4 | 96,255,255 a64 | 48,255,255 a48 | 48,255,192 a32 | 255,255,0 a160 |
  | 5 | 180,80,40 a128 | 230,180,140 a128 | 0,0,5 a128 | 80,40,20 a128 |
  | 6 | 220,220,160 a80 | 180,180,140 a80 | 120,50,10 a110 | 180,240,240 a70 |
  | 7 | 255,0,0 a32 | 255,0,0 a48 | 0,0,0 a128 | 255,255,128 a72 |
  | 8 | 100,250,255 a110 | 255,200,150 a64 | 250,150,250 a128 | 255,255,255 a128 |

- D3D (0x471290): no texture, vertex colour `A<<24 | RGB` (RGB + flash `0x574242*16`, clamped,
  0x470694), flags `2 | (0x49230c)`: ALPHABLENDENABLE = 1 with global SRCBLEND = SRCALPHA,
  DESTBLEND = INVSRCALPHA (set once in 0x470dc0). So `out = A/255 * rgb + (1 - A/255) * dst`.
  Cards without alpha blending (0x492304 & 0x10): STIPPLEDALPHA + STIPPLEENABLE and RGB halved.
- Software: per glass a 256-byte LUT (0x4081a4: `pal[i]*(256-A) + rgb*A >> 8`, nearest palette
  entry), rebuilt on arena change (`arena_activate` 0x4194e4, 0x5738e4 + i*0x100 in D3D exe; 0x540b20 in MDK95);
  fill = `dst = LUT[dst]`. Same result.
- Same alpha for both faces; global CULLMODE = NONE (every triangle double-sided in D3D) ✅.
- `FUN_00433b50` rewrites the table (alphas 0x5a/0x55/0x50/0x3c/0x28/0x0f over 6 tables) for some
  special scene ❓.

#### Edge outlines (triangle flags bits 20–23) ✅

0x40b7f0, per arena triangle: if flag bit 23 is set, draw lines (0x40f698 → D3D line 0x472420)
along edges selected by bit 20 (v0–v1), bit 21 (v1–v2), bit 22 (v0–v2). Line colour = the
triangle's material: palette colour if −255..−1, else the material itself (glass → the glass
ARGB, alpha blended, gouraud). Bit 23 is set on ~all glass triangles, so glass panes get
translucent coloured frames. (formats.md currently calls bits 20–22 a light level ❓ — wrong.)
Some panes also flag their inner diagonals (LEVEL7's DANT_7 columns: fan triangles with a quad
half's edge flags), so thin lines cross them. The port's enhanced look skips flagged edges two
coplanar triangles share (`MDKMeshBuilder._inner_edges`, `tests/glass_outline_test.gd`); the
original look draws them all, as the original.

#### Coplanar details (port)

The original draws without a depth buffer, back to front, so a detail lying in a bigger triangle's
plane (a poster, LEVEL6 OLYM_7's mirror tiles on the floor, OLYM_5's hub rims on the glass) simply
covers it. With a depth buffer they fight. The port gives each triangle a depth layer: one above
the highest bigger triangle of its plane it overlaps by area (Sutherland-Hodgman clip; of equal
ones the later in the data), at most 3 (`MDKMeshBuilder.arena_layers`, `tests/layer_test.gd`), and
lifts it by 0.03 a layer towards its front. A centre test missed partial overlaps.
Outlines lie on their triangles' layers and are drawn pulled towards the eye by 1/128 of their
distance (`mdk/shaders/outline.gdshader`: the same place on screen, nearer in depth), as the
original draws them after the triangles; on the edge's depth they came out dotted. ❓ Checked only
by reasoning: the tests run headless, without a renderer.

### RIPPLE (1028)

- D3D: never drawn ✅ (`if (m == -0x404) return;` in all submit functions).
- Software 0x46e940 ✅: screen-space refraction of what's already drawn behind (no z-buffer,
  back-to-front order). For each scanline `y` of the triangle span `[xl, xr)`:

  ```
  off = table[(frame + y) & 1023]               // signed byte, pixels
  for x in xl..xr: fb[y][x] = fb[y][min(x + off, 599)]   // in place, 600-byte rows
  table[i] = round(4 * sin(i*360/256 °) * sin(i*360/64 °))   // built at 0x46da0a, i < 1384
  frame = 0x5414d8, +1 per rendered frame (frame-rate dependent)
  ```

  No tint, no texture: invisible water surface that wobbles the background horizontally (±4 px).
- Used only by the corridor `CHMO_8` (level 3, 8 triangles). Listed in MTIs of levels 3, 4, 7.

### Per-frame state and ordering ✅

- D3D init (0x470dc0): ZENABLE = 0, ZWRITEENABLE = 0, CULLMODE = NONE, SRCBLEND = SRCALPHA,
  DESTBLEND = INVSRCALPHA, SHADEMODE = FLAT, TEXTUREPERSPECTIVE = 1, FOG off.
  State bits cached in 0x4922d4: 1 texture, 2 alpha blend, 8 gouraud, 0x10 MODULATEALPHA.
- No z-buffer: arena triangles come out back-to-front from the BSP walk, objects are spliced into
  BSP leaves, model triangles are depth-sorted (qsort 0x479e26). So glass needs no extra sorting.
- No reflection pass, no stencil. Only per-frame inputs: sky scroll `sky_x`/`sky_y` (sky_draw),
  frame counter for the ripple.

### Usage (triangle scan of LEVELnO.MTO arenas, models and LEVELnO.SNI corridors) ✅

- Glass: everywhere. Arenas: HMO_2,3,5,7,8,9,10; MEAT_1,3,5,6; MUSE_1–5; OLYM_1–5,7–10;
  DANT_1–3,5–10; GUNT_1–8. Corridors: CHMO_4,8,9; CMEAT_3; COLYM_4,8; CGUNT_1,3–7,9.
  Models: XTGUN/XTGUND, XW3/XW3D, XCBOSS, X_STRIKD, XT/XTD, X_BOTTLE, X_GLASS, X3_LDOOR, XBSHARK,
  XGDR, BEAMS, XBSHIP, XCARGO/XCARGOD, XFORK, XMINCAR.
- Mirrors: arenas HMO_9 (990), MUSE_3 (990/1000/1005), OLYM_5 (995), OLYM_6 (990/1000),
  OLYM_7 (990–1010), GUNT_5 (995), GUNT_8 (995); corridor CHMO_9 (1000); model XBSHARK (995–1009).
- RIPPLE: CHMO_8 only. NONE: by name only (see above). PEN_ENV: unused.

### In the port

`MDKSpecialMaterials` (from the DTI, given to the level's `MaterialResolver`s): glass is unshaded,
the DTI colour with its alpha, double-sided; mirrors use `mirror.gdshader`, the sky's mapping by
view direction on the mirror panorama (`MDKDti.mirror_sky`) with the rows shifted by
`8 × (1000 − value)` (`MIRRMED` taken to show the sky as behind it ❓, the original's `sky_y` and
row base not matched exactly); `RIPPLE`, `NONE` and `PEN_ENV` aren't drawn. Outlined edges are line
surfaces in the triangle's material (`MDKMeshBuilder._add_outlines`, untextured triangles only).
The sky is now the first panorama on levels 5 and 6 (it was the second ❓ to check against the
game). Elsewhere (the fall, the stream, the statistics, the model viewer) placeholders remain.

## Texture archive (MAT/MTI) ✅

Palette index 0 is transparent only in textures whose `kind` has bit 0 (`EXPLODE`, `TRAIL`, `BUBB`,
`SB_*`, `SL_*`): D3D uploads those with alpha (0x474c9c: `texture+0xc` & 1, if the device has an
alpha format), the others opaque, index 0 then palette black. LEVEL8's arena textures paint black
with it (13–40 % of `I2_WALL1`, `I2_FSHAF`, `I2_ENT`…; no other level's still textures use it but
`BULLET`). Port: `MDKTextureArchive.Zero.BY_KIND` turns index 0 into `BLACK` (16) in still textures
without bit 0 (arena and level archives); animated ones (`FIRE`, `PULSE`, `SW_EWJ`) keep it ❓.

An arena's `HMO_n.MAT` or a level's `LEVELnS.MTI` (offsets relative to the internal name):
`char[12] name, u32 size, u32 count`, then 24-byte entries:
`char[8] name, u32 kind, u32 value, f32 ?, u32 offset`.

- `kind` = 0xFFFFFFFF: palette color material, `value` is the palette index (e.g. `BLACK` = 16,
  `WHITE` = 244, `PEN_1` = 1) or a special material:

  | Value | Names | Meaning |
  | --- | --- | --- |
  | 256 | `NONE` | Not drawn (only by name, on hidden triangles) |
  | 257 | `PEN_ENV` | Unused |
  | 990–1010 | `MIRRLOW`, `MIRRMED`, `MIRRHIGH` | Mirror: the sky panorama, shifted |
  | 1024–1027 | `GLASS1`–`GLASS4` | Glass: the level's colour and alpha |
  | 1028 | `RIPPLE` | Water: rows of the background shifted (software only) |

  See "Special materials" below.

- High 16 bits of `kind` set (0x10000, 0x10001, 0x20000): animated texture ✅:
  `u32 frame count, u16 width, u16 height`, then the frames (`width × height` indices each).
  Used for effects (`EXPLODE`, `FIRE`) and animated walls (`M_COMM`). The meaning of the low bits
  is unknown ❓.
- Otherwise (0, or 2 for some floors): texture `u16 width, u16 height`, then `width × height`
  palette indices, row by row.

## BNI (sprite archive) ✅

`u32 size, u32 count`, then per entry `char[12] name, u32 offset` (relative to file offset 4).
Sizes are the difference between consecutive offsets. Plain images are `u16 width, u16 height`
followed by palette indices. `SNIPERS1` is probably a headerless 640 × 480 image (judging by its size).

Kurt's animations (`K_*`) are RLE sprite animations ✅: `u32 size`, `u32 frame count`,
`u32 frame offsets[count]` (relative to the frame count), then frames: `u16 width, u16 height,
s16 hotspot x, s16 hotspot y`, then rows of commands: `0x00–0x7F` = n + 1 literal palette indices,
`0x80–0xFD` = the next index repeated n − 0x7C times, `0xFE` = end of row, `0xFF` = end of frame.
Index 0 is transparent. See [gameplay.md](gameplay.md#kurts-sprite-damp_sprite_draw-rle_draw_hotspot)
for how the hotspot is used.

## SNI (sound archive) ✅

Common header, `u32 count`, then per entry `char[12] name, u16 flags, u16 volume, u32 offset, u32 length`
(offset relative to file offset 4). Most entries are RIFF WAV files (PCM, mono, 8 or 16 bits);
flags 3 marks music (the arena music of `LEVELnO.SNI`, `CORRIDOR`), 1 looping sounds; the u16
after the flags is the sound's default volume (0–0x7FFF, see [sound.md](sound.md)).
Some headers are sloppy (`GATTFIRE` doesn't count its final pad byte, some `LIST` chunks are
truncated), so the port only keeps the `fmt ` and `data` chunks.

**Corridors** ✅: in `LEVELnO.SNI`, the entries named after arenas with a `C` prefix (`CHMO_1`,
`CMEAT_3`, `CGUNT_2`…) aren't sounds but the geometry of the corridor that follows the arena, in the
same layout as an arena's world section. Empty corridors are two triangles with the material `NONE`.
Corridors use the level texture archive (`C_FLR1`…).

Kurt's extra sprite animations for a level are kept in its `LEVELnS.SNI` instead of
`TRAVSPRT.BNI`, in the same format as a BNI animation (`u32 size`, then the animation):
`K_SURF`/`K_SURFJ` in level 4, `K_SLIP`/`K_SLIDE`/`K_BSLIDE`/`K_FSLIDE` in level 6 ✅.

## CMI (scripts) 🟡

`LEVELn.CMI`, internal name `LEVELn.CMD`. Bytecode scripts for aliens and objects
(`HMO_1$XG_0` = alien `XG` #0 in arena `HMO_1`) and definitions of effects, bullets and pickups
(`EXPLODE`, `BULLET`, `SW_HOME`, …). Directories are `u32 count`, then per entry
`u8 length, char name[length], u32 offset`.

## Menu files 🟡

- `MISC/OPTIONS.BNI` (BNI archive): `MDKOPT` is the main menu background (a 768-byte palette, then a
  600 × 360 image with the plain image header) ✅; `MAINSONG` is the menu music (RIFF WAV) ✅;
  `INTRO1A` is the splash before the menu: two 768-byte palettes, then 600 × 360 run-length pixels
  (see [gameplay.md](gameplay.md#videos)) ✅.
- `MISC/MDKFONT.FTI`: `u32 size, u32 count`, then per entry `char[8] name, u32 offset` (relative to
  file offset 4) ✅. Entries:
  - texts (NUL-terminated, `\n` escapes for line breaks) ✅: `OPT0`–`OPT4` (main menu), `OM_*` (options),
    `KM_*` (key names), `PAUSED`, …; the between-level texts `ST_*`, `DEBTOP`, `DEBBOT`,
    `DEB1`–`DEB4` + `S`/`F`/`FS`/`SS`/`SF`, `BRIEF1`–`BRIEF5` use more codes (`\c`, `\20n`, …; see
    [gameplay.md](gameplay.md#statistics-and-briefing-state-6)). The backslash codes are literal
    characters in the file, interpreted when drawn.
  - `SYS_PAL`: 64 colors, the same as the first 64 of `MDKOPT`'s palette ✅
  - `FONTBIG`, `FONTSML`: 256 `u32` glyph offsets (relative to the font, 0 = no glyph: a space of 6
    or 4 pixels), then per glyph `s8 ascent, s8 descent, u8 width` and
    `(ascent + descent + 1) × width` palette indices row by row (0 transparent), drawn from `ascent`
    rows above the baseline (0x415a20) ✅. The colours are in the first 64 of the palette. `FONTBIG`
    (152 glyphs, about 30 pixels high, gold) has ASCII 33–126 and Latin-1/Polish letters; `FONTSML`
    (204 glyphs, orange) also has key names (`Esc`, `F1`, `Home`, arrows, …) at codes 1–31 and
    128–159 for the key settings.
  - `F8`: 8 × 8 bitmap font (128 characters) ✅
  - `SND_PUSH`: menu sound (RIFF WAV) ✅

## Videos and images ✅

- `MISC/FLIC/*.FLC`: Autodesk FLC (magic 0xAF12), 600 × 360, 8 bits: a 128-byte header (`u32
  size, u16 magic, u16 frames, u16 width, u16 height, u16 depth, u16 flags, u32 speed`, `oframe1`
  at 80), then frame chunks (0xF1FA: `u32 size, u16 type, u16 chunks`, 16 bytes) with sub-chunks
  `COLOR_256` (4), `BYTE_RUN` (15), `DELTA_FLC` (7), `BLACK` (13, only in ring frames); `MDKEND.FLC`
  starts with a prefix chunk (0xF100) and has a postage stamp (18). Each file has one more frame,
  the ring frame back to the first, which isn't shown. `MDKFlc`.
- `MISC/MDKS_001.GIF`…`008`: GIF87a/89a stills, 600 × 360, one image each with its own palette.
  `MDKGif`.
- `MISC/FLIC/MDKBZK.MVE`: Interplay MVE, 432 × 320, 14.99 fps (timer 8341 µs × 8), 3126 shown
  frames, stereo 16-bit 22050 Hz Interplay DPCM sound (see [gameplay.md](gameplay.md#videos)).
  `MDKMve`:
  - A 26-byte signature, then chunks `u16 size, u16 type` of opcodes `u16 size, u8 type, u8
    version, data`: 0x02 timer (`u32 µs, u16 count`), 0x03 sound (`u16, u16 flags` 1 stereo, 2 16
    bits, 4 compressed, `u16 rate`), 0x05 screen (`u16 width / 8, u16 height / 8`), 0x0C palette
    (`u16 first, u16 count`, 6-bit RGB), 0x0F decoding map, 0x11 video data, 0x07 show (the buffers
    swap), 0x08 sound and 0x09 silence (`u16 sequence, u16 stream mask, u16 size`), 0x01 end of
    chunk, 0x00 end.
  - Video 0x11 (8 bits): after a 14-byte header, one opcode per 8 × 8 block from the decoding map
    (4 bits, low nibble first, blocks row by row): 0 copy from the shown frame, 1 unchanged (the back
    buffer still holds the frame before), 2/3 copy from the back buffer with a motion vector from one
    byte, 4/5 copy from the shown frame (one byte as two nibbles, or two signed bytes), 7/8 two
    colours per pixel, 2 × 2, quadrant or half, 9/A four colours the same way, B 64 raw bytes, C 16
    2 × 2 colours, D 4 quadrant colours, E one colour, F a checkerboard of two.
  - Sound: per channel an `s16` start value, then each byte adds a step from a 256-entry table to
    the channels in turn (Interplay DPCM).

## Statistics files ✅

Used by the between-level screens (see [gameplay.md](gameplay.md#statistics-and-briefing-state-6));
[`tools/python/mdk_stats.py`](../tools/python/mdk_stats.py) decodes and previews them.

- `MISC/STATS.BNI` (BNI archive, 17 entries):
  - `CGUN`, `SNIPER`, `RICO1`–`RICO3`, `ALDIE`, `XGHEAD1`, `XGHEAD2`, `TELETYPE`: RIFF WAV sounds.
  - `PAL`: a bare 768-byte palette (the Score-O-matic's colours 64–255).
  - `XGHEAD`: a model in the `model_parse` layout **without** the leading `u32 flags` (parsed as
    flags 0: one unnamed part): 3 materials (`XG_BOD`, `PEN_255`, `XG_BACK`), 8 vertices,
    12 triangles, box about ±1.
  - `L1_INTRM`, `L1_MAP`–`L5_MAP`: 216772 bytes = a 768-byte palette, `u16 width, u16 height`
    (600 × 360), then the pixels (like `MDKOPT`). Their colours 1–63 are the system colours of
    `SYS_PAL`; index 0 is magenta in `L1_INTRM` and `PAL`, black in the maps.
- `MISC/STATS.MTI`: a texture archive like `LEVELnS.MTI` (internal name `STATS.MAT`, 40 entries):
  `XG_BACK` (128 × 128), `XG_BOD` (256 × 283), `NONE` and palette colours `PEN_n` (some map to
  another index, e.g. `PEN_186` = 194, `PEN_211` = 37).

## Fall files (`FALL3D/`) ✅

The fall minigame (see [gameplay.md](gameplay.md#the-fall-state-2-fall_3dc)) has its own files;
`tools/python/fall3d_dump.py` lists them and exports PNGs.

- **`FALL3D.BNI`** (BNI archive):
  - Models without the leading `u32 flags` of the arena model format (`model_parse`): the game passes
    "named parts" from a table instead (bit 7 of 0x490ca4): `KURT` (2 materials `CB3`, `CF3`,
    18 named parts), `MISSILE`, `CHUTE`, `BONES`, `SW_DUMMY`, `SW_H150`, `SW_THUMP`, `SW_TWIST`,
    `SW_INTER` have named parts; `EXPLODE`, `SW_BONES`, `SW_GATT`, `SW_HGREN`, `SW_HBOMB`, `SW_HOME`,
    `SW_LGREN`, `SW_SGREN`, `SW_SHOT`, `SW_H01`, `SW_H25`, `SW_H50`, `SW_H100`, `SW_KEY` have one.
  - Model animations in the arena animation format: `KURTANIM` (18 tracks, 199 frames), `KURT_HIT`
    (18, 30), `BONESANM` (27, 31).
  - Palettes (768 bytes, 8-bit RGB): `SPACEPAL` (the intro), `FALLP1`–`FALLP5` (one per fall; the
    game forces colour 0 to black). The first 64 colours are the same in all six.
  - Plain images (`u16 w, h`, pixels): `SPACE` 600 × 360, `MOON` 128², `EARTH` 512² (these three
    use `SPACEPAL`), `FLARE1` 32², `FLARE2` 48², `FLARE3` 16², `FLARE4` 64², `PICK` 64²,
    `SKULL` 256², and HUD copies `SC_STAT`/`SC_BSTAT` 84 × 63, `SNIP_TXT` 80 × 12.
  - RLE sprite animations (like `K_*`): `PICKUPS` (9 frames, the inventory icons), `BANG` (26 frames,
    unused ❓).
  - `ZOOM0000`–`ZOOM0015`: the haze overlay frames. `u32 size`, then 180 records (one per pair of
    screen rows): `u32 nL, u8 left[4 nL], u32 nM, u32 nR, u8 right[4 nR]`, with
    nL + nM + nR = 150 groups of 4 pixels. `left`/`right` hold one byte per pixel (1–8, the blend
    table offset); the nM middle groups are plain. They draw a clear ellipse in the middle and
    radial streaks around it.
  - `FALLPU_1`–`FALLPU_5`: the pickups dropped during the fall, 12-byte records `char[12]` (a
    pickup model name, NUL-padded) ended by a record starting with 0. `FALLPU_1`: `SW_HOME`,
    `SW_GATT`, `SW_HOME`; the others: `SW_GATT`, `SW_HBOMB`, `SW_SGREN`, `SW_HOME` (dropped from the
    last one).
- **`FALL3D_n.MTI`** (texture archive, internal name `FALL3D_n.MAT`, n = level index + 1):
  - `LEVELn` 1024 × 1024: the ground, seen from above.
  - `PODn` 64 × 1024: the minecrawler's track, copied into `LEVELn` row by row under the crawler
    (the same rows; the top ≈ 130 rows are plain ground).
  - `Ln_C0001`–`Ln_C0008` 64 × 108: the minecrawler's animation frames (drawn as sprites).
  - The model textures: `CB3`, `CF3` (Kurt), `CHUTE`, `MISSILE`, `EXPLODE` (animated, 26 frames of
    128², kind 0x10001), `BONEHEAD`, `BONEBOD`, `SW_*` (pickups), and palette colours `GREY1`…`GREY31`
    (indices 17–47), `BLACK` (0).
- **`FALL3D.SNI`** (SNI archive, 23 sounds): `WINDLOOP` and `C_GRIND` (flags 1, looped), `EXPLODE1`,
  `EXPLODE2`, `R_START`, `R_MOVE`, `M_PASS`, `M_LNCH`, `P_CHUTE`, `P_COLL`, `P_FALL`, `BONES`,
  `K_HIT1`–`K_HIT7`, `K_FINISH`, `K_COLL1`, `K_COLL2`, `K_SEEN`.
- **`RADAR`** isn't in the files: the game builds it (0x412f94) from 46 triangles
  `u8 v0, v1, v2, colour` at 0x40fec0 (in the code section) over 25 vertices it recomputes each
  frame.
