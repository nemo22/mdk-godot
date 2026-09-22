# MDK in Godot

A port of [MDK](https://en.wikipedia.org/wiki/MDK_(video_game)) (Shiny Entertainment, 1997) to
[Godot 4.7](https://godotengine.org/), based on reverse engineering the original game's data files
and executable (`MDKD3D.EXE`, the Direct3D version).

**Status:** early. All 6 levels load (arenas, textures, palettes, skies), and Kurt can run, jump and
use his chute through them with the original movement and camera. The original scripts run: aliens,
pickups and doors are placed, walk, fly along their paths and shoot, doors open, and Kurt's chain
gun shoots and blows aliens up. See [the roadmap](docs/roadmap.md).

## Running

The original game data is required (it isn't included). Place this project folder within the MDK
installation folder (for example `C:\GOG Games\MDK\godot-mdk`), install MDK in the default GOG
location, or set the `MDK_DATA_DIR` environment variable.

Open the project in Godot 4.7 and run it. Command line options (after `--`):

- `--level=N`: start level N (3–8) directly, skipping the menu.
- `--viewer`: free-camera level viewer (`--camera=x,y,z`, `--look-at=x,y,z`).
- `--models`: model viewer (`--arena=NAME`).
- `--screenshot=file.png`: save a screenshot and quit.
- `--profile=seconds`: print performance and script statistics, then quit. `--no-scripts` disables
  the scripts.

Controls: W/S or Up/Down to run, A/D to strafe, the mouse or Left/Right to turn, Space to jump (hold
it while falling to open the chute), Shift for turbo, the left mouse button or Ctrl to fire, Escape
to go back to the menu. In the level
viewer: WASD to move, Q/E to go down/up, click to look around, Shift to go faster.

## Layout

- `mdk/`: MDK data formats (file parsers, palette, mesh building, shaders).
- `game/`: the game itself (menu, level, Kurt, camera) and the level and model viewers.
- `docs/`: the knowledge base about MDK ([index](docs/README.md)): file formats, engine internals,
  Kurt's movement and camera, the script language and its VM, and the roadmap.
- `tools/ghidra/`: Ghidra setup and scripts used for reverse engineering, and the names of
  reverse engineered functions.
- `tools/python/`: reference decoders used to validate formats.
