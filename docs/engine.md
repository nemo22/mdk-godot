# MDK engine internals

What the original engine does at runtime, from the reverse engineering of `MDKD3D.EXE` (see
[README.md](README.md) for the other documents). Addresses are those of `MDKD3D.EXE`; names in
backticks are the names given in the Ghidra project ([`tools/ghidra/names.txt`](../tools/ghidra/names.txt)).
Constants were read from the executable with [`tools/ghidra/const.py`](../tools/ghidra/const.py).

## The executables

- `MDK95.EXE` (software rendering), `MDK3DFX.EXE` (Glide) and `MDKD3D.EXE` (Direct3D) share the game
  code; the port follows `MDKD3D.EXE`.
- Compiled with **Watcom C** (register calling convention: arguments in EAX, EDX, EBX, ECX, then
  the stack; the callee preserves the other registers). Ghidra needs a custom calling convention for
  it: [`tools/ghidra/x86watcomreg.cspec`](../tools/ghidra/x86watcomreg.cspec).
- Assertion and allocation strings keep the source file names (`..\mdksrc\main\...`): `traverse.c`
  (the "traverse" game mode: walking through the arenas), `tr_alcmd.c` (alien commands: the script
  interpreter, over 6000 lines), `fall_3d.c` (the falling sequence at the start of each level),
  `endlev.c`, `finish.c`, `savegame.c`, `options.c`/`optmenu.c`/`optdispl.c`/`optload.c`/`optperf.c`,
  `soundset.c`, `intro.c`, `demo.c`, `chunks.c`, `memblock.c`, `mdkfopen.c`, `perfchec.c`,
  `abortcon.c`; shared code in `..\mdksrc\share\` (`loadmats.c`, `setupob.c`, `readbin.c`,
  `gifread.c`, `allocenm.c`) and the renderer's options in `..\mdksrc\d3d\optd3d.c`.
- Units: 1 world unit = 1 Godot unit. Angles are degrees (yaw 0 = +X, 90 = +Y), Z is up.

## Frame timing

The game runs at a variable frame rate; the simulation uses `g_frame_dt` (seconds) and
`g_frame_dt_ticks` (the same in 1/30 s ticks), see [gameplay.md](gameplay.md#timing-timer_update-timer_compute).
Some code counts integer ticks (`g_frame_ticks`). The port runs scripts and objects at a fixed
30 Hz.

## Objects

Aliens, doors, pickups, bullets and effects are **objects** (0x32e bytes, allocated by 0x45fd4c) in
a linked list per arena (`arena+0x68`). The field layout is in
[scripts/notes_part1.md](scripts/notes_part1.md#object-fields-obj--alienobject-0x32e-bytes-allocated-by-0x45fd4c).
Each arena also has an embedded object that runs the arena's script.

### Object update (0x47868c)

Every frame, for each object of the arenas being simulated:

1. Run the script if it has one (`script_run` 0x440bc8, see [scripts.md](scripts.md)).
2. If active: follow the spline path, if any (0x43c258).
3. Carry out the movement command (0x45b6c8).
4. Gravity (0x45e74c).
5. Friction, then move by the velocity with collisions (0x45e810).
6. Animation (`object_anim_update` 0x43a89c), with root motion.
7. Save the position as the previous position (`obj+0x180`).

### Flags

`obj+0x148`…`obj+0x14b` are flag bytes (the port keeps them as one 32-bit integer, `obj+0x148` being
the low byte). Identified bits:

| Bit | Meaning |
| --- | --- |
| 0x1 | no automatic banking from turning (opcode 23) |
| 0x2 | gravity; friction is then horizontal only (opcode 36) |
| 0x4 | collides with the arena geometry (opcode 35) |
| 0x8 | the animation loops (opcodes 3/59) |
| 0x80 | no automatic banking/pitch (opcode 97) |
| 0x200 | set by `follow_path` flags1 bit 0 |
| 0x400 | the path is played once (`follow_path` flags2 bit 0) |
| 0x10000 | doesn't turn to face its movement (paths, flying) |
| 0x80000 (0x14a bit 3) | also collides with the other arena during transitions |
| 0x8000000 | the path drives the horizontal velocity instead of the position (`follow_path` flags1 bit 1) |
| 0x10000000 | path speed depends on Kurt's distance (opcode 164) |
| 0x20000000 | bounces off walls (velocity reflected with factor 0.8) instead of stopping |
| 0x200000 | runs even when Kurt is in another arena |

Objects created by `spawn_flagged` start with `0x2008A6`, projectiles get `|= 0x80820`.

`obj+0x14c` holds contact flags set by the movement code: 0x1 collided this frame, 0x2 on the floor
(collided while moving down), 0x4 a projectile touched Kurt, 0x8 stuck (the stuck detection of
walkers). 0x1, 0x2 and 0x10 are cleared at the start of each velocity step.

### Velocity, gravity and friction (0x45e74c, 0x45e810)

- **Gravity** (flag 0x2): `vz -= obj+0x48 × dt` (default 32 units/s², set by opcode 55), limited to
  −220 units/s. Updrafts (`updraft_query`) can slow objects down.
- **Friction**: the speed is reduced by `obj+0x44 × dt` (default 64 units/s², opcode 82), in 3D, or
  horizontally only when the object has gravity.
- **Motion** for this frame: `(velocity + push) × dt` plus conveyor belts. `push` (`obj+0x294`…
  `obj+0x29c`) is a velocity for this frame only: walking, `push_forward`, paths in velocity mode
  add to it; it's cleared after the move.
- **Collisions** only for objects with flag 0x4 (0x45fec4): a box swept through the arena's BSP
  (`bsp_sweep_box`, the same as Kurt's, see [gameplay.md](gameplay.md#collision-damp_collide_move-bsp_sweep_box)).
  The box is half as wide as the object's world bounds (`obj+0x198`: half extents = size × 0.25) and
  as high as half the distance from the origin to the top of the bounds, starting 0.05 above the
  origin when moving vertically (0.5 otherwise). On a hit: `vz = 0` (or the velocity is reflected
  with factor −1.8 along the normal when bouncing), the hit triangle is kept (`obj+0x2b0`, used by
  conveyors), and triangle-group hit scripts may run (0x40d560). Without flag 0x4 objects move
  freely, only clamped to an optional box (`obj+0x27c`…`obj+0x290`).
- Objects more than 200 units below their arena's lowest point (`arena+0x44e`) die (0x43d884): the
  death script runs (and the object is put back 150 units below the floor, without gravity), or the
  object is removed.

### Movement commands (0x45b6c8)

`obj+0x11e` holds the movement command, usually the number of the opcode that started it, with a
parameter in `obj+0x11f`:

| Command | Started by | Behaviour |
| ---: | --- | --- |
| 0 | | idle |
| 1 | `command_objects` command 1 | keeps a formation place around the leader `obj+0x138` (below) |
| 6 | `move_to_target` | chases the target, flying (below) |
| 15 | `alarm` | plays an alarm sound every 32 frames while in Kurt's arena and sets `0x573aec = 10` |
| 30 | `spawn_chain` | chain of objects following each other (snake-like aliens) |
| 43 | `move_near_target`, commands | goes to the destination (walking or flying) |
| 61 | `fire` | projectile |
| 74 | `attach_to` | stays attached to another object: its reference point `obj+0x276` is kept on the other's point `obj+0x277`, same yaw and pitch |
| 78 | `move_to` | goes to the destination |
| 88 | `set_move_x` | moves along its yaw (and pitch when flying) at up to the max speed (`obj+0x11f` ≠ 0), or slows down to a stop |
| 197 | | like 78, stopped when stuck |
| 229 | `turn_and_jump_to_dest` | ballistic jump; ends after half the flight time (`obj+0x302`) once on the floor |

Walking and flying (43, 78, 197) go through a **waypoint** (`obj+0x12c`): `move_to` and
`move_near_target` plan a detour around walls (`plan_move` 0x45a1dc) and the object heads for the
waypoint, then the destination (`obj+0x120`).

- **Speed**: `obj+0x34` accelerates by `obj+0x3c × dt` (default 10) or slows down by `obj+0x40 × dt`
  (default 15) towards the max speed `obj+0x38` (default 50 units/s), halved while the waypoint is
  more than 80° away.
- **Turning**: always 180°/s towards the waypoint (`obj+0x48`, once thought to be a turn rate, is
  the gravity).
- **Walking** (flag 0x2, 0x45a7d4): `push += speed × (cos yaw, sin yaw)`; the waypoint is reached
  within 5 units (Manhattan distance, horizontal).
- **Flying** (0x45ae74): the speed is split between horizontal (along the yaw) and vertical in
  proportion to the horizontal and vertical distances; the waypoint is reached within 4 units
  horizontally and 3 vertically. With flag 0x10000 the object doesn't turn and moves straight
  (reached within 1 unit, Manhattan).
- **Stuck detection**: the distance moved is summed over 16 ticks (9 for command 197); if it's less
  than `speed × 0.5`, the object is stuck (`obj+0x14c` bit 3). When a stuck object also didn't turn
  (less than 3°), it replans a detour (0x45a434, up to 3 times), then gives up: command 78 moves
  straight by `speed × dt` per axis, the others stop.
- **Chasing** (command 6, 0x45e448): speed in units per *tick*: while facing the target within
  22.5° it grows by `(22.5 − angle) × ticks / 6 × 0.0444` up to 2.333, otherwise it drops by
  `0.05 × ticks` down to 0.333; turning at 180°/s (not when the target is behind and within 30
  units); the height follows the target (+8) at a quarter of the speed. The position is moved
  directly, without collisions.
- **Formation** (command 1, set by `command_objects` 0x4405d0): places alternate on each side,
  `offset = (±(n/2 + 1) × 5 × s, −4 × b, 8)` with `s, b = 4, 2.5` for `XE` aliens and 1 otherwise,
  turned by the leader's yaw; followers fly there at their max speed, then snap to the place and turn
  like the leader.
- **Projectiles** (command 61): move `speed × dt` along the yaw and pitch; the lifetime `obj+0x302`
  (set by opcode 106) counts down and kills them at 0; they die where the segment they moved hits
  the arena, and set `obj+0x14c` bit 2 when it crosses Kurt's box (grown by 1 unit horizontally).
  `fire` gives them flags `0x80820`, the shooter's yaw and pitch, and the script to run (bullet
  scripts set their speed, lifetime, scale, aim, and test `if_touching_kurt` → `hurt_kurt`).

### Spline paths (0x43c0f8, 0x43c258)

Path records (in the CMI, referenced by `follow_path`): `u32 key count`, then 40-byte keys:
`s32 frame, f32 position[3], f32 in_tangent[3], f32 out_tangent[3]`. Each segment is a cubic
Hermite curve: with `u = (t − frame_i) / (frame_{i+1} − frame_i)`, `d = p1 − p0`,
`p(u) = ((a·u + b)·u + m0)·u + p0` where `m0` is key i's out tangent, `m1` key i+1's in tangent,
`a = m0 + m1 − 2d`, `b = 3d − 2m0 − m1`.

- The path time `obj+0xf0` (frames) advances by `speed × ticks` (`obj+0xe8`, 1 or −1 for
  backwards, or controlled by Kurt's distance with opcode 164), stopping on the stop frame `obj+0xe6`
  if set (opcode 21).
- Looping paths wrap at `last key frame − 1`; paths played once end (`obj+0xec = 0`) at
  `last key frame − 2` (or below 0 backwards).
- Position = `p(t) + origin` (`obj+0xf4`; relative paths use the object's position minus the
  path's start point). The object faces its movement (plus the yaw offset `obj+0x100`) when it moved
  more than `0.5 × dt`, unless flag 0x10000. In velocity mode (flag 0x8000000) the horizontal motion
  is converted into `push` and the height is left alone.

### Animation (`object_anim_update` 0x43a89c)

- Time `obj+0xdc` (frames) advances by `animation speed × obj+0xe0 (30) × dt`. Looping animations
  (flag 0x8, opcode 59) wrap at the frame count; the others stop on the last frame, and
  `obj+0x118` becomes 0xFF00 (ended, tested by `if_anim_done`).
- `obj+0x118` ≥ 0 is a hold frame (opcode 118): the animation stops there.
- Frames are stepped one by one (`anim_step_frames`) and each frame's root motion moves the object.
- A sound can be attached to a frame (opcode 24: name `obj+0x140`, frame `obj+0x144`).

### Commands between objects (`command_objects` 0x440384)

Scripts send commands to other objects of their arena (opcode 4). Receivers must be active, not
the sender, of the right type (except selectors 3 and 8), alive, obey the sender's priority
(`receiver.obey_level (obj+0x11b) >= sender.priority (obj+0x11a)`), and not have another leader of a
higher or equal priority. Commands: 1 join a formation, 7 goto a script target (also resets the
receiver's gosub stack; skipped when it's already running that target, `obj+0x10c`), 0xFC gosub a
script target (the receiver's return point is its restart point), 43 go near the target. The sender
becomes the receiver's leader (`obj+0x138`). Selectors are listed in
[script_opcodes.md](script_opcodes.md) (opcode 4).

### Death

`object_kill` (0x43d6d4 → 0x43d670): the object switches to its death script (`obj+0x110`, set by
opcode 76) if it has one, otherwise it explodes (0x43d224).

## Globals

Globals used by the scripts and objects are listed in [scripts/notes_part2.md](scripts/notes_part2.md)
and [scripts/notes_part3.md](scripts/notes_part3.md). The main ones:

| Address | Meaning |
| --- | --- |
| 0x5739c0 (`g_damp_position`) | Kurt's position; 0x5739f0 his yaw; 0x5739f4 his bounding box (min x, y, z, max x, y, z) |
| 0x573a0c | Kurt's arena; 0x573a68 the other arena during a transition |
| 0x57fc34, 0x57fc30 | the target of the aliens (Kurt or a decoy) and its yaw |
| 0x574324 | Kurt's health; 0x573bd4 invulnerability time; 0x573b20 hurt flash |
| 0x573c24 | the World's Most Interesting Bomb (a decoy), if active |
| 0x5742dc | option toggled by cheat codes (1 by default; opcode 232, BHOLE/BHOLE2) |
| 0x573b4c | the 4 global script variables |
| 0x520a84 | table of loaded global models (80 entries of 0x88 bytes) |

## Constants

Values read from the executable, in the units of the code (`dt` = frame time in seconds, `ticks` =
frame time in 1/30 s):

| Where | Value | Use |
| --- | --- | --- |
| 0x45e74c | −220 | terminal vertical velocity of objects |
| 0x45e810 | −1.8 | bounce: velocity += normal × (velocity · normal) × −1.8 |
| 0x45fec4 | 0.25, 0.5, 0.05 | collision box: half extents, height factor, height above the origin |
| 0x45e2bc | 180°/s | turning towards waypoints |
| 0x45a7d4 | 5, 80°, 0.5 | walking: waypoint reached, angle for half speed, half speed |
| 0x45ae74 | 3, 80°, 4, 3 | flying: no turning closer than 3, half speed, waypoint reached (horizontal, vertical) |
| 0x45e448 | 30°, 22.5°, 1/6 × 0.0444, 2.333, 0.05, 0.333, 0.25 | chasing |
| 0x43d884 | −200, −150 | falling out of the arena |
