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

### Object update (0x43c7dc)

Every frame `game_frame` updates the objects of Kurt's arena (`0x573a0c`), and of the second arena
seen through an open door (`0x573a68`, when `0x573a6c` is set); objects of the other arenas are
frozen. Then the arena's own script runs (the arena's embedded object at `arena+0x118`). For each
active object (`obj+6`):

1. `obj+7 == 1`: it becomes the aliens' target (`0x491e48`, opcode 251).
2. Built-in behaviours by flag: doors (0x100000, 0x43cc68) and swinging objects (0x400000, 0x43cfe8).
3. Flag 0x40000000: 0x440074 (not identified); objects that died there, or that move to another
   arena (`obj+0x2bc`, 0x43ca00), are skipped.
4. Run the script if it has one (`script_run` 0x440bc8, see [scripts.md](scripts.md)).
5. Follow the spline path, if any (0x43c258), then carry out the movement command (0x45b6c8).
6. Gravity (0x45e74c), then friction and the move by the velocity with collisions (0x45e810).
7. Built-in behaviours: Kurt's projectiles and effects (0x1000, 0x43deac), pickups (0x200000,
   0x43daf4).
8. Animation (`object_anim_update` 0x43a89c), with root motion.
9. The measured velocity per tick (`obj+0x18c`), rolling objects (0x40, 0x4602c8), and if Kurt stands
   on the object (`0x573b84`) he moves and turns with it. Then the position and yaw are saved as
   the previous ones (`obj+0x180`, `obj+0x50`).

A reduced update (0x478704 → 0x47868c: script, path, movement, velocity, animation) runs a few
object types (`XM5_FLAP`, `BIGBOLT`, `SW_SBONE`, `SW_SEAL`…) in a special game state (`0x573c60`).

### Flags

`obj+0x148`…`obj+0x14b` are flag bytes (the port keeps them as one 32-bit integer, `obj+0x148` being
the low byte). Identified bits:

| Bit | Meaning |
| --- | --- |
| 0x1 | no automatic banking from turning (opcode 23) |
| 0x2 | gravity; friction is then horizontal only (opcode 36) |
| 0x4 | collides with the arena geometry (opcode 35) |
| 0x8 | the animation loops (opcodes 3/59) |
| 0x10 | Kurt goes through it (opcode 63; doors set it while open) |
| 0x40 | rolling (opcode 85) |
| 0x80 | no automatic banking/pitch (opcode 97) |
| 0x100 | a platform Kurt can stand on (`damp_platform_floor`) |
| 0x200 | set by `follow_path` flags1 bit 0 |
| 0x400 | the path is played once (`follow_path` flags2 bit 0) |
| 0x800 | Kurt goes through it (pickups, projectiles) |
| 0x1000 | Kurt's projectiles and effects (0x43deac) |
| 0x10000 | doesn't turn to face its movement (paths, flying) |
| 0x20000 | a pickup that has landed |
| 0x40000 | tested by opcode 176 |
| 0x80000 (0x14a bit 3) | also collides with the other arena during transitions |
| 0x100000 | door (connector between two arenas, see below) |
| 0x200000 | pickup (see below) |
| 0x400000 | swinging object (0x43cfe8) |
| 0x8000000 | the path drives the horizontal velocity instead of the position (`follow_path` flags1 bit 1) |
| 0x10000000 | path speed depends on Kurt's distance (opcode 164) |
| 0x20000000 | bounces off walls (velocity reflected with factor 0.8) instead of stopping |
| 0x40000000 | 0x440074 runs before the script (not identified) |

Objects created by `spawn_flagged` (pickups) start with `0x2008A6`, projectiles get `|= 0x80820`,
doors `0x1108000`.

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

### Doors (0x43cc68)

Doors are **connectors** between an arena and a corridor, created by `spawn_connector` (opcode 149)
in the scripts of both: the second call finds the existing door and moves it into its arena. The
door's state (`obj+0x312`: 1 open, 2 opening, 4 closing, 8 closed; higher bits set by opcode 152:
0x10 not solid while open, 0x20 stays open, 0x40 locked, 0x100 lock hidden) changes every frame:

- Kurt closer than `obj+0x30e` (opcode 153, 20 units by default): unless open, opening or locked,
  play the opening animation (opcode 150, first) and show the arena behind the door (`BSPShow`).
- Farther: unless closing, closed or staying open, play the closing animation (second).
- When the animation ends the door becomes open or closed. A sound is played at each of the four
  events (opcode 151: opening, closing, open, closed).
- Model parts named `LOCK` are shown only on a closed locked door; parts whose name starts with
  `HC` are hidden while the door is closed. Kurt doesn't collide with the `LOCK` parts.

Door models can be flat: the level 6 iris door is 9 one-sided quads (`P1`…`P9`) around a `HUB`, so
models are drawn without back face culling.

### Pickups (0x43daf4)

Pickups (flag 0x200000, spawned by arena scripts with `spawn_flagged`, often high in the air) fall
with gravity; below −15 units/s their fall speed is held at −15 and a `SW_CHUTE` model is attached
(movement command 74). On the floor they rise by 1.5 and get flag 0x20000; the chute then shrinks
(scale −1/s) and is removed at 0.2. Landed pickups spin at 180°/s, except `SW_H150`, `SW_SEAL` and
`SW_SBONE` (`SW_H150` plays its own animations near Kurt).

### Kurt and objects (`damp_collide_move` 0x465e34, `damp_platform_floor` 0x41d2c4)

Kurt collides with the objects of his arena that are active, alive (health ≠ 0) and have neither
flag 0x10 nor 0x800: first their whole bounds (`obj+0x198`), then each visible model part's box
(the part's bounds in the current animation frame, `part+0x44`), skipping the hidden parts
(`obj+0x2c8`) and the `LOCK` parts of doors. Objects with flag 0x100 are platforms: Kurt can stand
on them (`0x573b84`) and they carry him when they move or turn.

### Hits

When something hits an object it sets the object's hit event (`obj+0x21e`: part index + 1, −1 for
the chain gun, −2 for other hits, −3 for blasts), what hit it (`obj+0x21d`: −1 chain gun, −2 super
chain gun, 1–4 Kurt's projectile types) and the direction of the hit (`obj+0x224`, used by
`push_hit_dir`). Scripts test it with `if_hit` (any hit but blasts), `if_hit_part` (by part name,
`ANY` for any part) and `if_hit_fd` (blasts); a true test clears the event, and the end of each
script frame (`0xFF`) clears it too.

**Weak parts** (`set_weak_parts`, flag 0x2000): parts whose name is the given prefix followed by a
digit at the given length take hits separately, with their own hit points (`obj+0x30e[part]`, max
`obj+0x31e[part]`). When a weak part's hit points reach 0 the hit event is that part (index + 1).
Parts with at most 900 hit points drive the boss health bar.

### Death

`object_kill` (0x43d6d4 → 0x43d670): the object switches to its death script (`obj+0x110`, set by
opcode 76) if it has one (movement stopped, health 0, flag 0x20 so the chain gun ignores it),
otherwise it explodes (0x43d224):

- The object's explosion sound (`obj+0x154`, opcode 25) or `EXPLODE`, and a screen shake by
  distance.
- Debris: the model's break-up parts (model record `+0x84`) fly off as particles, and gore when
  the option `0x5742dc` is on.
- An explosion object using the global model 0 (`EXPLODE`: 21 triangles with a 26-frame animated
  texture): its texture shows one frame per tick and the object vanishes after the last one. It's
  scaled to 1.5 × the object's height over the explosion model's, faces the shooter (yaw + 180°)
  and is pitched towards the camera.

## Kurt's chain gun (0x41a304)

Holding fire (`damp_move`) sets `0x573a38`: the chain gun sound loops (`GATTFIRE`, or `MULTIFIRE`
with the super chain gun) and Kurt's animation becomes `K_SHOT` (standing) or `K_RUNFIR`
(running); in the other states a random frame of `K_MUZZF` is drawn behind Kurt every other tick
([gameplay.md](gameplay.md#firing)). Every frame, after Kurt moves and before the objects run, the
chain gun **hits instantly** (no bullets):

1. Every object of Kurt's arena that is active, alive, without flags 0x10 and 0x20, is a candidate:
   its bounds in the current pose (`obj+0x198`), or for objects with weak parts each visible weak
   part's box (then the whole object if no part qualifies).
2. The aim test (0x41ab2c) takes a box's size (its diagonal, at least 10) and its centre seen from
   Kurt's position + 5 in height: the box qualifies when it's closer than size + 140, within a cone
   of `(size − 2) × 90 / (size − 2 + distance)` degrees on either side of Kurt's yaw, and visible
   (a ray to its centre doesn't hit the arena). Its score is `dx² + dy² + 4·dz²` (dz from Kurt's
   feet); the lowest score wins. So the gun aims automatically, favouring close, big targets.
3. The target loses 1 hit point per tick (6 with the super chain gun, whose timer `0x5743ef` counts
   down while firing), unless it's indestructible (≥ 65000); a hit weak part loses them too. The
   hit event is set (−1). Sparks fly on the side of the box facing Kurt, with the object's
   ricochet sound (`obj+0x150`, opcode 26) or `RICO1`–`RICO3`, every 4 frames. At 0 hit points the
   object is killed (with the super chain gun it's also pushed away at 20 units/s).
4. Without a target, a ray is cast 150 units along Kurt's yaw: sparks where it hits the arena, and
   the hit triangle's group reacts (0x40d560, hit type 2).

Kurt's other weapons are projectiles in 3 slots (`0x573c98`, 0xfc bytes each, updated after the
objects by 0x462708): a per-frame move function, a lifetime, types 1–4 (type 4 bounces off the
arena); hitting an object sets its hit event, hitting the arena runs the group hit code, and types
2–4 explode (0x4638cc, 150 damage within 25 or 50 units).

## Arena triangle groups

The top byte of an arena triangle's flags is its **group** (1–21, 0 = none; masks and counters
exist for groups 1–16). Scripts change groups at run time:

- `group_set_state` (98) sets or clears triangle flags **0x10** (not drawn: skipped by the draw list
  0x40acc8) and **0x20** (not solid: skipped by the BSP collision `bsp_leaf_tri_test`). No triangle
  has them set in the data. Arena scripts use this to hide rooms Kurt isn't in (level 5
  `MUSE_1`), for destructible parts, bridges…
- `group_set_texture` (140) gives every triangle of a group another material.
- `group_set_hit_flags` (168) and `group_on_hit` (99) make groups react to hits: flag 0x80 makes a
  group destructible (it's hidden until hit, then shown: its damaged version), hits increase the
  group's counter (`arena+0xcc`, opcodes 162/163) and can run a script (0x40d560).
- `group_state_near_player` (194) applies a state to the groups around the one under Kurt.

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
