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
| 0x00 | u32 | ❓ (0) |
| 0x04 | f32[3] | Player start position ✅ |
| 0x10 | f32 | Player start angle in degrees (90 faces +Y) ✅ |
| 0x14 | u32 | Sky: palette index filling the screen above the panorama ✅ |
| 0x18 | u32 | Sky: palette index filling the screen below the panorama ✅ |
| 0x1C | u32 | Sky: panorama row at eye level (horizon) ✅ |
| 0x20 | u32 | Sky: horizontal offset in pixels ✅ |
| 0x24 | u32 | Sky: panorama width for 360° (1800 or 900) ✅ |
| 0x28 | u32 | Sky: panorama height (360) ✅ |
| 0x2C | s32[2] | If positive, there's a second panorama and these are its fill colors (levels 5, 6). The Direct3D renderer draws the second panorama. 🟡 |
| 0x34 | 4 × u32[4] | Colors ❓ |

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
list at `arena+0x38`/`+0x3c`), 6 (connection, id 1000+), 7, 8. ❓

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
     u32 reference point count R, f32[R][F][3]
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
     0x10 not drawn and 0x20 not solid (set only by scripts); bits 20–22 look like a light level ❓,
     bit 0 ❓.
4. `u32 count`, then vertices `f32 x, y, z` in world coordinates.
5. `u32` ❓, then BSP leaf data ❓.

## Texture archive (MAT/MTI) ✅

Palette index 0 is transparent: only effect textures use it (`EXPLODE`, `FIRE`, `TRAIL`, `BUBB`,
`SB_*`, `SL_*`, `PULSE`…), like sprites.

An arena's `HMO_n.MAT` or a level's `LEVELnS.MTI` (offsets relative to the internal name):
`char[12] name, u32 size, u32 count`, then 24-byte entries:
`char[8] name, u32 kind, u32 value, f32 ?, u32 offset`.

- `kind` = 0xFFFFFFFF: palette color material, `value` is the palette index (e.g. `BLACK` = 16,
  `WHITE` = 244, `PEN_1` = 1) or a special material:

  | Value | Names | Meaning |
  | --- | --- | --- |
  | 256 | `NONE` | Invisible |
  | 257 | `PEN_ENV` | ❓ |
  | 990–1010 | `MIRRLOW`, `MIRRMED`, `MIRRHIGH` | Mirror |
  | 1024–1027 | `GLASS1`–`GLASS4` | Glass |
  | 1028 | `RIPPLE` | Water |

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

Common header, `u32 count`, then per entry `char[12] name, u16 flags, u16 ?, u32 offset, u32 length`
(offset relative to file offset 4). Most entries are RIFF WAV files (PCM, mono, 8 or 16 bits);
flags 3 marks music (the arena music of `LEVELnO.SNI`, `CORRIDOR`), 1 some looping sounds ❓.
Some headers are sloppy (`GATTFIRE` doesn't count its final pad byte, some `LIST` chunks are
truncated), so the port only keeps the `fmt ` and `data` chunks.

**Corridors** ✅: in `LEVELnO.SNI`, the entries named after arenas with a `C` prefix (`CHMO_1`,
`CMEAT_3`, `CGUNT_2`…) aren't sounds but the geometry of the corridor that follows the arena, in the
same layout as an arena's world section. Empty corridors are two triangles with the material `NONE`.
Corridors use the level texture archive (`C_FLR1`…).

## CMI (scripts) 🟡

`LEVELn.CMI`, internal name `LEVELn.CMD`. Bytecode scripts for aliens and objects
(`HMO_1$XG_0` = alien `XG` #0 in arena `HMO_1`) and definitions of effects, bullets and pickups
(`EXPLODE`, `BULLET`, `SW_HOME`, …). Directories are `u32 count`, then per entry
`u8 length, char name[length], u32 offset`.

## Menu files 🟡

- `MISC/OPTIONS.BNI` (BNI archive): `MDKOPT` is the main menu background (a 768-byte palette, then a
  600 × 360 image with the plain image header) ✅; `MAINSONG` is the menu music (RIFF WAV) ✅;
  `INTRO1A` ❓.
- `MISC/MDKFONT.FTI`: `u32 size, u32 count`, then per entry `char[8] name, u32 offset` (relative to
  file offset 4) ✅. Entries:
  - texts (NUL-terminated, `\n` escapes for line breaks) ✅: `OPT0`–`OPT4` (main menu), `OM_*` (options),
    `KM_*` (key names), `PAUSED`, …
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
