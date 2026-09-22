# MDK in Godot

A port of [MDK](https://en.wikipedia.org/wiki/MDK_(video_game)) (Shiny Entertainment, 1997) to
[Godot 4.7](https://godotengine.org/), based on reverse engineering the original game's data files
and executable (`MDKD3D.EXE`, the Direct3D version).

**Status:** early. The level viewer loads all 6 levels (all arenas, textures, palettes and skies)
and lets you fly through them. There is no gameplay yet.

## Running

The original game data is required (it isn't included). Place this project folder within the MDK
installation folder (for example `C:\GOG Games\MDK\godot-mdk`), install MDK in the default GOG
location, or set the `MDK_DATA_DIR` environment variable.

Open the project in Godot 4.7 and run it. Command line options (after `--`):

- `--level=N`: level to load (3–8).
- `--camera=x,y,z`, `--look-at=x,y,z`: initial camera placement.
- `--screenshot=file.png`: save a screenshot and quit.

Controls: WASD to move, Q/E to go down/up, click to look around with the mouse, Shift to go faster.

## Layout

- `mdk/`: MDK data formats (file parsers, palette, mesh building, shaders).
- `game/`: the game itself (currently the level viewer).
- `docs/formats.md`: file format documentation.
- `tools/ghidra/`: Ghidra setup and scripts used for reverse engineering, and the names of
  reverse engineered functions.
