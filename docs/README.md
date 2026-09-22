# MDK knowledge base

Everything learned about MDK (Shiny Entertainment, 1997) while porting it: file formats, how the
original engine works, its script language and virtual machine. The findings come from the game
data and from reverse engineering `MDKD3D.EXE` with Ghidra; each document says where its
information comes from (function addresses, constants) so it can be checked again.

Legend used in the documents: ✅ fully understood and implemented, 🟡 partly understood, ❓ guess.

## Documents

| Document | Contents |
| --- | --- |
| [formats.md](formats.md) | File formats: common header, palettes, DTI (level data), MTO (arenas: models, animations, world geometry), MTI/MAT (textures), BNI (sprites), SNI (sounds, corridor geometry), CMI (scripts, global models), FTI (UI texts and fonts), menu files |
| [engine.md](engine.md) | Engine internals: the executables and their source files, objects and their update, flags, velocity/gravity/friction, collisions, movement commands, spline paths, animation, commands between objects, globals, constants |
| [gameplay.md](gameplay.md) | Kurt: timing, movement (acceleration, turbo, turning, jumping, falling, chute), collision, camera, sprite drawing |
| [scripts.md](scripts.md) | The script language and its virtual machine: which scripts run, the interpreter loop, restart points, gosub stack, operand encodings, bugs in the data |
| [script_opcodes.md](script_opcodes.md) | Reference of the 251 opcodes (generated from [`script_opcodes.json`](../tools/python/script_opcodes.json)) |
| [scripts/notes_part1.md](scripts/notes_part1.md), [part 2](scripts/notes_part2.md), [part 3](scripts/notes_part3.md) | Raw reverse engineering notes on the interpreter: object fields, arena fields, helpers, globals, per-opcode details |
| [roadmap.md](roadmap.md) | What the port does and what's next |

## Tools

- [`tools/ghidra/`](../tools/ghidra/README.md): Ghidra setup (Watcom register calling convention),
  export and naming scripts, [`names.txt`](../tools/ghidra/names.txt) (names of the reverse
  engineered functions), `fn.py` (prints functions of the export), `const.py` (reads constants from
  the executable).
- [`tools/python/`](../tools/python/README.md): reference decoders used to validate the formats:
  models and animations (`mdk_models.py`, `render_model.py`), the script disassembler
  (`mdk_script_dis.py`), and `gen_script_table.py` (generates the GDScript opcode table and
  [script_opcodes.md](script_opcodes.md)).

## Interesting findings

- The game is built from two kinds of spaces: **arenas** (big levels in `LEVELnO.MTO`) and
  **corridors** between them, whose geometry hides in the sound archive `LEVELnO.SNI` next to the
  music ([formats.md](formats.md#sni-sound-archive-)).
- Kurt is a **2D sprite** drawn at screen scale (1 pixel = 1/360 of the view height), not a model
  ([gameplay.md](gameplay.md#kurts-sprite-damp_sprite_draw-rle_draw_hotspot)).
- Aliens, doors and pickups are run by a **bytecode language** of 251 opcodes. Scripts restart
  every frame at a saved *restart point* instead of keeping a program counter, which makes them
  behave like small state machines ([scripts.md](scripts.md#interpreter)).
- Objects move with a velocity plus a one-frame *push*, gravity and friction; flying enemies
  follow **Hermite spline** paths stored in the script file ([engine.md](engine.md#spline-paths-0x43c0f8-0x43c258)).
- Script data has a few bugs that the original silently survives: an invalid opcode at the start
  of an arena script of level 3, boxes with an empty Z range, and jump tables that always take the
  first entry ([scripts.md](scripts.md#data-bugs-in-the-original)).
- Two script opcodes were misnamed during the analysis until the scripts themselves showed the
  opposite: opcode 3 plays an animation once and 59 loops it (3 is followed by `if_anim_done` 1064
  times, 59 never).
