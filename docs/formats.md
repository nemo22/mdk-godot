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

`u32 count`, then 16-byte entries: `char[8] name, u32 records offset, f32 ?`.
Names are `HMO_1`… (arenas) and `CHMO_1`… (corridors) in level 3; other levels use other prefixes
(`MEAT_n`, `OLYM_n`, `DANT_n`, …). Names not starting with `C` get flags `|= 3` in the game.

Each records list is `u32 count`, then 36-byte records:
`u32 type, s32 id, f32 angle, f32 x, f32 y, f32 z, char[12] name`. Types seen: 1, 3 (in corridors),
2 (alien, `name` refers to a CMI script), 6 (connection, id 1000+), 7, 8. ❓

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

### Models section 🟡

`u32 size`, then `u32 animation count, u32 model count, u32 sound count` and directories of
`char[8] name, u32 offset` (offsets relative to the counts). At most 16 sounds.

Model: `u32 flags, u32 material count`, `char[16]` material names, `u32 vertex count`,
vertices (`f32 x, y, z`), `u32 triangle count`, 36-byte triangles (same layout as world triangles,
but UVs are normalized 0–1). Followed by a bounding box and more data ❓.

### World section ✅ (`arena_parse_world`)

1. `u32 count`, then `char[10]` material names, padded to a multiple of 4 bytes.
2. `u32 count`, then 44-byte BSP nodes: `f32 plane[4]`, child indices, … 🟡
   Node fields 7 and 8 are offsets relative to the end of the vertex list (+4) ❓
3. `u32 count`, then 36-byte triangles:
   `s16 v0, v1, v2, s16 material, f32 u0, v0, u1, v1, u2, v2, u32 flags`.
   - `material` ≥ 0: index into the material names. `material` < 0: palette color `-material`, or a
     special material (see below) if `-material` ≥ 256.
   - UVs are in texels (textures repeat, e.g. floors).
   - `flags`: bits 20–22 look like a light level ❓, bit 0 ❓.
4. `u32 count`, then vertices `f32 x, y, z` in world coordinates.
5. `u32` ❓, then BSP leaf data ❓.

## Texture archive (MAT/MTI) ✅

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

- `kind` = 0x10000 or 0x10001: animated sprite; the first `u16` is the frame count ❓
- Otherwise (0, or 2 for some floors): texture `u16 width, u16 height`, then `width × height`
  palette indices, row by row.

## BNI (sprite archive) ✅

`u32 size, u32 count`, then per entry `char[12] name, u32 offset` (relative to file offset 4).
Sizes are the difference between consecutive offsets. Plain images are `u16 width, u16 height`
followed by palette indices. `SNIPERS1` is probably a headerless 640 × 480 image (judging by its size). Kurt's animations
(`K_*`) and other entries use an unknown format ❓.

## SNI (sound archive) ✅

Common header, `u32 count`, then per entry `char[12] name, u16 ?, u16 ?, u32 offset, u32 length`
(offset relative to file offset 4). Each entry is a RIFF WAV file (PCM, mono, 8 or 16 bits).
`GATTFIRE`'s RIFF header doesn't count its final pad byte.

## CMI (scripts) 🟡

`LEVELn.CMI`, internal name `LEVELn.CMD`. Bytecode scripts for aliens and objects
(`HMO_1$XG_0` = alien `XG` #0 in arena `HMO_1`) and definitions of effects, bullets and pickups
(`EXPLODE`, `BULLET`, `SW_HOME`, …). Directories are `u32 count`, then per entry
`u8 length, char name[length], u32 offset`.
