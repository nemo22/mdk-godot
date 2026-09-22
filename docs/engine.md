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
object types (`XM5_FLAP`, `BIGBOLT`, `SW_SBONE`, `SW_SEAL`…) during cutscenes (`0x573c60`, see
[Cutscenes](#cutscenes-special_event-131)).

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
| 30 | `spawn_chain` | a link of a chain, placed from the head's transform (below) |
| 43 | `move_near_target`, commands | goes to the destination (walking or flying) |
| 61 | `fire` | projectile |
| 74 | `attach_to` | stays attached to another object: its reference point `obj+0x276` is kept on the other's point `obj+0x277`, same yaw and pitch |
| 78 | `move_to` | goes to the destination |
| 88 | `set_move_x` | moves along its yaw (and pitch when flying) at up to the max speed (`obj+0x11f` ≠ 0), or slows down to a stop |
| 197 | | like 78, stopped when stuck |
| 229 | `turn_and_jump_to_dest` | ballistic jump; ends after half the flight time (`obj+0x302`) once on the floor |

`turn_and_jump_to_dest rate, action` (229, 0x460d24) turns the object towards its destination
(`obj+0x120`) by at most `rate` degrees per second; once it faces it, the jump starts (command 229):
the top is `max(z + 10, goal z + 30)` when jumping down, else `max(goal z + 10, z + 30)`;
`vz = √(2 g (top − z))`, the flight time `t = (vz + √(vz² + 2 g (z − goal z))) / g` (`obj+0x302`, g =
`obj+0x48`) and the horizontal speed `(friction × t² / 2 + distance) / t`, so the friction brings it
down exactly. The action runs while command 229 is on. Grunts use it to leap to the waypoints of
`pick_waypoint8`.

**Rolling** (flag 0x40, `set_rolling` 85, `set_roll_radius` 169): when rolling starts, the rotation
part of the object's matrix is saved (`obj+0x302`); from then on the object's matrix is that saved
one times its scale, and every frame (0x4602c8) it's turned by `distance moved / (2π × radius)`
turns (`obj+0x326`, 1 if ≤ 0) about the horizontal axis across the motion (built from two angles,
0x46e170). The boulders of levels 4, 6 and 8 (`XCBOMB`, `XBO`).

Walking and flying (43, 78, 197) go through a **waypoint** (`obj+0x12c`): the object heads for the
waypoint, then the destination (`obj+0x120`).

- **`plan_move`** (0x45a1dc) runs only when `move_to` (78), `move_near_target` (43), `move_to_bomb`
  (167), `partner_flank` (227) or `command_objects` 43 (only in Kurt's arena) start a move; the
  find/pick opcodes (46, 197, 221) and formations go straight. There's no waypoint graph: if the
  line from the object to the destination, both 8 units up, hits the arena (a ray against the own
  arena's BSP, 0x421680; no objects), it tries `C = middle + t × s × length × (sin a, cos a)` for
  `t` = 0.1…1.1 and `s` = −1, +1 (a = the heading to the destination) and takes the first `C` seen
  from both ends (else the destination). The offset `(sin a, cos a)` is a bug: it's only sideways
  when the line runs along an axis (along the line at 45°).
- **Replanning when stuck** (0x45a434): an object heading for a detour drops it; one heading for the
  destination tries the same kind of points around `0.75 B + 0.25 A` then around itself, with
  `t` = 0.1, 0.4 … 1.9.

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
- **Stuck detection**: walking with command 43, any collision makes the object stuck (`obj+0x14c`
  bit 3). Otherwise, while it collides and is faster than 2, the distance moved is summed over 16
  ticks (9 walking with command 197, `obj+0x2a1`, `obj+0x2a4`); if it's less than `speed × 0.5`,
  it's stuck; without a collision the counters reset. When a stuck object also didn't turn (less
  than 3° this frame), `obj+0x2a0` goes up: command 197 stops, the first time it replans (0x45a434,
  and the counter goes up again, so only once), then command 78 moves straight at the waypoint by
  `speed × dt` per axis through everything and the others stop (`if_move_idle_flag` 231 sees
  `obj+0x2a0`). The stuck bit is only cleared by a new move, so after a sidestep the object goes back
  to the destination as soon as it stops turning.
- **Banking** (0x43b65c): without flags 0x80 (`set_banking` 0) and 0x1, `roll = (roll − r) × 0.95`
  within ±10° with `r` the turn per tick (at most ±2°). With flag 0x1 the roll rocks between −10°
  and +10° by 2° a call ❓ (not in the port). While a spline path runs with flag 0x200 the pitch
  follows the climb: `0.2 × atan2(dz, horizontal) + 0.8 × pitch`.
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

## Kurt's items (0x46ce78, 0x43deac)

Pressing "use" (`damp_move`) with an item selected (not the super chain gun) makes Kurt throw it:
on the floor with `K_SPWEP` (state 805; the item leaves on frame 8), in the air at once. Only one
thrown item at a time, except decoys (types 1, 8, 9); while the World's Most Interesting Bomb is out,
"use" sets it off instead (0x43f258).

- **Throw** (0x46ce78): an object with the item's pickup model at Kurt's position + 4 in height,
  flags `|= 0x818a6`, kind `obj+0x30a` = item type, 150 ticks of flight (`obj+0x30e`; 750 for types
  8 and 9), no friction, scale 0.1 growing to 1 (3/s), Kurt's yaw, velocity 25 units/s forward (75
  for grenades) and 15 up (0 with the chute). The slot's count goes down.
- **Flight** (0x43deac, 0x43eb48): the item moves with gravity and collisions, and stops on the
  part boxes of objects (grenades: any object without flags 0x810; the others only objects with
  flag 0x1000000). It activates (flag 0x4000, no more gravity or collisions) when it hits something
  or its time runs out (the mortar only on the floor):
  - 5 grenade: blast of 150 on objects and triangle groups, 75 on Kurt, radius 40; explosion ×2.
  - 1 decoy: walks forward at 5 units/s for 450 ticks (`SW_DUM_M` animation); aliens aim at it
    (`0x573c20`) instead of Kurt.
  - 2 the World's Most Interesting Bomb (`0x573c24`): holds the first frame of its `SW_INTER`
    animation and spins at 235°/s for 600 ticks (or until Kurt presses "use"), then plays it and
    blows up: blast of 450 (67 on Kurt) within 80 units, explosion ×3. Alien scripts react to it
    (`if_no_bomb`, `if_bomb_visible`, `move_to_bomb`).
  - 3 tornado (0x43ee98, sound `TORNADO`): spins at 360°/s for 60 ticks, letting out a twister
    (0x40741c) at once and at 45, 30 and 15 ticks left, then blows up (`object_kill`). See below.
  - 4 mortar (0x43e690; it activates only on a floor): plays its `SW_THUMP` animation (121
    frames) and pounds the ground on frames 28, 54, 64, 71, 77, 82 … 127 (table `0x491e4c`): each
    thump shakes the screen (5) and hits every object of its arena without flags 0x1030 that isn't
    an `XE` or `XF` (flyers): −4 health, hit event −1, hit type −3, the direction from Kurt, and +5
    upwards velocity if it stands on a floor. From the 4th thump on, Kurt is knocked down
    (`0x573b20` = 5) if he stands on a floor. At the end it blows up (`object_kill`).
  - 7 the nuke (0x43efcc): the `SW_KEY` item turns into the `SW_NUKE` model and animation (from
    frame 1, 900 ticks), with a full white flash (`0x573b68` = 255) and the looping sound `NUKE`.
    While it plays the screen shakes (at least 3), and from frame 70 the screen turns white
    (flash = (frame − 70) × 255 / (frames − 70)). Then doors within 50 units get door state bit
    0x80, a blast of 200 on objects and groups and 19 on Kurt within 60 units (hit type −8), 16
    debris particles and the `EXPLODE` sound.
  - 8 seal and 9 super bone (0x43e980, 0x43ea84): they fly for 750 ticks (the seal rolls at
    30°/s) and just stop. Once still they fall and play the arena's `XMT_LAND` animation. Unless
    their script flag 1 is set (something got hold of them: level 5's `XGUNTAM` eats them), they
    become pickups again (flag 0x200000) after 150 ticks, and a seal shrinks away (×0.9 per tick,
    then `object_kill`) when its time is up; a bone stays.
- The item animations (`SW_INTER`, `SW_DUM_I`, `SW_DUM_M`, `SW_THUMP`, `SW_NUKE`, `H150_I`,
  `H150_R`, `X_STRIKB`) are model animations stored in `TRAVSPRT.BNI`.
- Types 0x80/0x81 are Bones' air strike (sniper mode; 0x81 drops `X_TOOTH` bombs of kind 5).

### Twisters (0x40741c, 0x407774, 0x407974)

Twisters are effects (the arena's effect list `arena+0x5c`, not objects), drawn as a textured
ribbon along their last positions (0x439690).

- For 2 seconds a twister spirals out of the tornado: its angle grows at 720°/s, and at angle a it
  is at the tornado + (cos, sin)(a) × 15 × a/1440 and 15 × a/1440 higher, stopping 0.1 off walls,
  moving at 200 units/s along the spiral.
- At 1440° it splits: one twister for each object of the tornado's arena (and the other visible
  arena) without flags 0x30, each chasing its object for 150 ticks: each tick its velocity keeps 90%
  and gains 20 units/s towards the object's box centre; it bounces off walls (the velocity is
  mirrored) and wind zones push it.
- An object (alive, flags without 0x30) whose box contains a twister loses 2 health per tick, hit
  event −1, direction from Kurt; it's killed at 0. The twister then loses an extra tick of life.

### Blasts (0x463a94)

`blast(center, damage, …, radius, count kills, source, targets, hit type)`, targets being 1 Kurt,
2 objects, 4 arena triangle groups:

- **Objects** (alive, without flags 0x10/0x20): the damage on a box (0x463958) is 0 beyond the
  radius or behind a wall, and falls off with the distance from the centre to the box centre minus
  half the box's diagonal. Weak parts take it separately. The source object takes the full damage.
  Objects farther than their `obj+0x2c4` (opcode 177, 1000 by default) are spared. The hit event
  is −2 (or a destroyed weak part), with the blast's hit type.
- **Kurt**: his distance (to his feet + 1) is doubled, or beyond the radius behind a wall; within
  the radius he's hurt by at most 15.
- **Kurt**'s knock-down counter (`0x573b20`) is doubled after the hit: a blast knocks him down
  from 3 damage.
- **Triangle groups** with hit flags or a hit script, in Kurt's arena and the other visible one:
  the first solid triangle of the group within the radius whose centre the blast reaches (or
  whose ray hits another triangle of the same group: that point is used) gets a hit (0x40d560) of
  kind 3 (4 when the blast doesn't count kills), `damage × (radius − distance) / radius`, with
  the blast's hit type. One hit per group.

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

### Group hits (0x40d560)

`hit(arena, triangle, amount, kind, hit type, point, from, to)`. The kind is a bit mask of what
hit: 1 Kurt's projectiles (0x462708), 2 the chain gun (amount = damage, hit type −1, −2 with the
super chain gun), 3 Kurt's blasts, 4 other blasts, 8 Kurt himself (0x46634e, hit type −11), 0x10
effects (0x45fec4, hit type −10). For a triangle of group g (1–16):

- If the group's hit flags (`arena+0x6c`, opcode 168) share a bit with the kind: flag 0x80 shows
  the group (group state op 3) and sets its bit in `arena+0x114`; 0x40 makes the hit count (an
  amount of at least 1) whatever the mask; 0x20 makes the function return 2 (the chain gun then
  shows other sparks).
- If the group has a hit script (`arena+0x8c`, opcode 99) and its hit mask (`arena+0x7c`) shares a
  bit with the kind (or flag 0x40): the counter `arena+0xcc` grows by the amount, the hit point and
  direction go to globals `0x4d5374`/`0x4d5358`, and the script runs at once from its start in the
  scratch object `0x57fc40` (0x45c9a0: cleared, arena set, `obj+0x21d` = the hit type, which
  `if_hit_weapon` tests). Returns 1.

Level 5 uses this for its fans: `if_hit_weapon -8` means only the nuke destroys them.
## Fans and conveyors 🟡

Each arena has a list of fans and conveyors (`arena+0x45e`, taken from a free list `0x573f8c`,
fatal "No spare fans"). An entry: `+0 next, +4 arena, +8 name, +0xc id (hotspot id or triangle
group), +0x10 param, +0x14 type (−1 = conveyor), +0x18 strength, +0x1c enable mask (−1 = all),
+0x20 box x0, y0, z0, x1, y1, z1, +0x38/+0x3c texture scroll, +0x40 target strength, +0x44 ramp
rate`.

- `fan_create` (142, 0x413a94) builds a fan on the arena's hotspot of type 7 with that id (the
  DTI arena records: `type, id, angle`, then the box `x0, y0, z0, x1, y1, z1`, the last 12 bytes
  being the "name" field of other records). z0 is lowered by 0.5. With type 6 the strength
  operand is a time: strength = `(z1 − z0) / (time − 0.5)`. All levels use type 6.
  `fan_enable` (190) sets or clears bit 0 of the mask, `fan_remove` (143) removes it.
- **Updrafts** (`updraft_query` 0x413c24 → 0x413d14): for a point inside a fan's box (up to z1 + 5)
  whose caller mask matches (1 Kurt, 2 objects, 4 and 8 not identified yet), the fan gives a
  target vertical speed `strength × f`: `f` = 1 for type 6 except in the top 5 units, where it's
  `1 − (z − (z1 − 5)) × 0.2`; types 1–5 fade with the relative height `h` (1 − h², (1 − h)²,
  1 − h, 1 − h³, (1 − h)³); param ≠ 0 means `h` = 1. Near the top (type 6) a small wobble
  (`0x490d7c`, ±0.1 per frame) is added and a faster upward speed is halved towards it. The
  vertical speed then rises by `(target + 64) × dt` up to the target. Kurt tests his arena, then
  the neighbour one (`0x573a68`), with mask 1; objects test theirs with mask 2 (position `obj+0x10`,
  velocity `obj+0x28`).
- Every frame (0x414230) the strength ramps towards `+0x40`; a conveyor scrolls the UVs of its
  triangle group (wrapping at ±512) and pushes what stands on the group (`conveyor_push` 0x413c80:
  box fields `+0x20..+0x28` as a direction × strength × dt); a fan spawns a rising particle at a
  random point of its box (z0 + 0.25) one frame in 8 (0x4052d4, pool `arena+0x5c`).
- `wind_zone` (224) uses the type-9 hotspots to slide Kurt, see
  [gameplay.md](gameplay.md#sliding-damp_buttslide-0x468db8). Conveyors aren't in the port yet.

## Chains (`spawn_chain` 29, movement command 30)

Snake-like aliens: a head object with links hanging off it (level 3's flying bombers, level 7's
`XBANG` and `XTANK`, level 8's `XBSHIP`; the levels always create 1–3 links at a time).

- `spawn_chain count, model, script` (0x447c9a) creates `count` objects of that model at the head's
  position, each with kind 7, movement command 30, leader `obj+0x138` = the head and id
  `obj+0x146` = (links left) + (highest id of the head's links so far) + 1, so calling it again
  extends the same chain and id 0 is the link nearest the head. The head knows nothing about them.
- Each frame the link with id 0 places the whole chain (0x45bb3f): link `i` takes the yaw
  `head yaw + 90° × i` and is moved so that its first reference point sits on the previous link's
  second one (the head is the first "previous"). Nothing else moves them: no velocity, speed,
  waypoint or frame time, so a chain is rigid and frame rate independent.
- Before that, every link checks that its leader is alive and that the links with the ids below it
  exist; the first link that finds a gap (or a dead head) detaches (`obj+0x138` = 0, movement
  command 0) and is left to its own script.

## Swinging objects and ropes

- `jump_to x, y, z, speed, gain` (226, 0x4578ba) hangs the object on a rope: pivot `obj+0x1c` =
  (x, y, z), angular speed `obj+0x302` = speed, gain `obj+0x30a`, rope length `obj+0x306` =
  pivot z − object z, the yaw to turn to `obj+0x30e` = its yaw, and flag 0x400000. Only level 6's
  `XSWINGB` (`OLYM_6`, a 1985-unit pendulum with `touch_damage` and the sounds `PENDULUM` and
  `PENDHIT`) uses it.
- Every frame (0x43cfe8, after the script) with θ = pitch (`obj+0x13c`) and t = ticks:
  `ω −= sin θ · gain · t`, then `θ += ω · gain · t`, and the object is put at
  `pivot + (cos yaw · sin θ · L, sin yaw · sin θ · L, −cos θ · L)`: it swings in the vertical plane
  of its yaw, tilting with the swing.
- At each turning point (ω changes sign) the plane turns towards the target: the angle to it less
  the yaw, wrapped to ±180°, folded to ±90° (either side of the plane will do) and clamped to
  ±15°, is added to the yaw as the new goal, which the yaw reaches at 10° per second.
- **Ropes** (the block `obj+0x2d0`): `+0x2d0` is a palette colour, `+0x2d1` a mode and 4 points
  follow at `+0x2d2`. `arena_build_drawlist` (0x4185f0) draws them as lines (0x40e6c4):
  - mode 0xFF: a line from each of the model's reference points 1–4 (`obj+0x1bc + i × 12`) to
    each non-zero point i;
  - other modes: bits 0 and 1 are the lines point 0 → point 1 and point 2 → point 3 (the first
    end 5 units higher).
- `set_2d0_block` (242) sets colour 1 and mode 0xFF with 4 points, or clears the mode with a
  count of 0: level 5's cage of Bones (`MUSE_5`, whose cables vanish one at a time before it
  falls) and a platform in level 8 (`GUNT_10`). The pendulum writes colour 1, mode 1 and the
  line from itself to the pivot every frame.

## Cutscenes (`special_event` 131)

`special_event e` (0x4456d2) calls 0x477cf4 for events above 50; the others end the level.

- **Cutscene state `0x573c60`**: while it's non-zero, `game_frame` (0x41d4d8) runs 0x478704
  instead of the normal frame: Kurt isn't updated and the controls do nothing.
  - Below 0x3d only `XM5_FLAP`, `XBN`, `BOLT`, `BIGBOLT`, `SW_SBONE` and `SW_SEAL` run (the
    reduced update 0x47868c) and are drawn, except the bolts.
  - From 0x3d on, every active object without the flags 0x201000 (pickups, Kurt's items) runs and
    is drawn; at 0x5b the flagged ones also run, but still aren't drawn.
  - Kurt is drawn only at 0x47 (and 0x51); at 0x51 nothing else runs or is drawn.
- "Stop" (0x4779b0): leaves sniper mode (0x4645c8) and stops Kurt firing (`0x573a38`, 0x46c3e4).
- **The camera** (0x477d94): shot `0x599938`, target `0x599940`; it keeps the yaw `0x599920`
  (`90° − heading`), pitch `0x599924`, distance `0x599928`, position `0x59992c` and a blend timer
  `0x59993c` in ticks. All shots but 11 look at the target's z + 3: pitch = −atan2(dz, distance),
  yaw = 90° − the heading to the target.
  - 0: from (423, 85, max(target z − 25, −2260)); timer 1800; switches to 1 once the target is 12
    or more units away (at once in practice: it starts the orbit from far away).
  - 1 and 2: orbit behind the target at `(cos, sin)(target yaw + 150°) × d`, with
    `d = 0.9 d + 0.1 × (12 or 25)`, at z −2258 (1) or rising by a tick per tick up to −2246 (2);
    yaw = 120° − target yaw. While the timer runs (it drops by the ticks) the position, pitch and
    yaw are `0.2 new + 0.8 old`, then the pitch is `0.7 new + 0.3 old` and the yaw
    `0.3 new + 0.7 old`.
  - 11: fixed position, yaw and pitch. 12: fixed position looking at the target (in state 0x5d
    the stored position is never overwritten).
- **Events** (all in the last levels' scripts):

| Event | Where | What |
| --- | --- | --- |
| 51 (0x4779e0) | `MUSE_5` `XBN` | Bones strikes: 0x4398f0(1) first plays Kurt's model with `X_STRIKD` full screen (❓ how it looks; 0x43fa0c plays `X_STRIKB` the same way). Kurt is put at the object with its yaw, the object moves 4 along y, Kurt's state becomes 100 ❓; state 0x47, camera at (Kurt x − 10, y, z + 8) with yaw `90° − Kurt yaw`, pitch 0, distance 10 (shot unchanged, probably 11) |
| 52 (0x477ac4) | `MUSE_5` `XBN` | stop; the first `XBN` is the target; state 0x34, shot 0 (follows the dog) |
| 53, 92 | `MUSE_5`, `DANT_10`, `GUNT_10` | state 0: the cutscene ends |
| 54 | `MUSE_5` | nothing |
| 55 | `MUSE_5` `XBN` jumps | shot 2 |
| 61 (0x477b44) | `MUSE_5` `XGUNTAM` dies | stop; state 0x3d, shot 11 at Gunter's position + 45 units ahead, z + 3, pitch −20°, yaw `270° − his yaw` |
| 81 | `MUSE_5`, end of the `X_STRIKE` path | the end of the game: state 0x51, 0x477248(1): game state `0x574262` = 8 plays `MISC/FLIC/MDKEND.FLC` (0x47727c, with timed extras 0x477604) and `MISC/FLIC/MDKBZK.MVE` (0x477870), then state 0 (the menu ❓) |
| 91 (0x477c84) | `GUNT_10`, the second `XGUNTAM` | stop; state 0x5b, shot 12 from (−121, 3347, −350) |
| 93 (0x477c34) | `DANT_10`, `XB1` after `XB_HEAD` is blown off | the same, state 0x5d, from (1158, 5006, 315) |

- **The end of the level** (events 0–50, always 0: `HMO_10`, `MEAT_10`, `OLYM_10`, `DANT_10`,
  `GUNT_10`, 1–3 s after the boss dies): the pending teleport arena `0x573c80` = −1. At the end of
  `game_frame` that stops Kurt firing and calls 0x40a9e0 (`endlev.c`): the level is over
  (`0x573b60` = 1), Kurt's health is at least 1, the sounds `NUKE` and `TORNADO` play and the arena
  breaks up around Kurt (`END_LEVEL`: 100000, 500, 0.15, 0.025 at 0x490654 ❓ how it looks).
- The port runs the cutscenes (state, which objects run and show, the camera) and goes on to the
  next level 5 s after the end; the full-screen strike, the videos, the break-up and the
  statistics aren't done yet.

## Effects (the pool at `arena+0x5c`)

A pool of 96 records (0x1aa bytes) shared by the arenas: sprites, particles and debris. When it's
full, 0x405138 steals the effect of lowest priority in the arena (only below the requested one:
wounds 50, trails 10, drops and bubbles 5, sparks 0). An effect has an update (returns 1 to be
deleted) and a draw function, a 3×4 matrix (position at +0x20/+0x30/+0x40), a spin matrix applied
every update (+0x44), velocity in units per tick (+0x18a), life in ticks (+0x196).

- **Sprites** (0x407048): a screen-aligned quad of an animated texture, `width × scale / 256` units
  wide (scale +0xa0), frame `F − 1 − (trunc(life × speed) mod F)` (speed +0xa4 in frames per tick),
  so the animation plays forwards as the life runs out; index 0 is transparent. Textures (the same in
  every level): `SL_BIG` (30 frames, 64×64, a green slime blob), `SL_MED`/`SL_SMA` (30 frames, 32/16
  pixels, drops), `SB_MED`/`SB_SMA` (unused here), `BUBB` (6 frames), `BUBB_POP` (4), `TRAIL` (11,
  smoke).
- **Movement** (0x4061d8, drops and debris): `pos += v × ticks` with a collision sweep (0x407e2c);
  without a hit `vz −= ticks × 0.284444 × 0.25` (about 64 units/s²); a hit puts the effect at the
  contact, `v −= 1.4 (v·n) n` (bounce with restitution 0.4) and takes 20 ticks of life. Fans push
  them (`updraft_query` with mask 8). At life ≤ 0 they're deleted.
- **Wounds** (`attach_effect name, slot, towards`, 128, 0x4067b8, only with the effects detail
  `0x5742dc` on): an `SL_BIG` sprite (scale 10: 2.5 units, speed 0.5: 15 fps, life `2F − 1`) kept in
  `obj+0x160[slot]` at the object's reference point `slot`. Every frame (0x40690c) it loops; each
  loop its intensity (from 0x7fff) drops by 128–255, and when no burst runs and `rand() <
  intensity` a burst of 30 ticks starts with a jitter of ±0.25 per axis; during a burst every
  update squirts a drop towards the reference point `towards` at `(direction + jitter) × 0.5` units
  per tick, scale 4. `"OFF"` with `slot == towards` removes it (0x405250); the other names (the
  wounded part) aren't used. The 8 slots are freed when the object dies or is removed. Used 184
  times on aliens (`XG1_BODY 2→3`, `XG1_FOTL 1→7`…); `OFF 1,1` stops the leg wound.
- **Drops** (0x406b3c): `SL_MED` or `SL_SMA` at random, speed 0.25, life `4F − 1` = 119 ticks, moved
  as above. `spawn_debris count, v, spread, absolute, x, y, z, size` (136, 0x4484e3) spawns `count`
  of them (only 1 with the detail off, none if `count ≤ 1`) at the point (+ the object's position
  when `absolute` = 0) with `v` plus `±spread/2` in x and y and `−spread/16…+0.94 spread` in z, scale
  `size + rand × 0.0005`: slime fountains and pipes in level 3's `HMO_2`/`HMO_3`, a gush in level 5.
- **Bubbles** (`spawn_effect chance, slot, point`, 132, 0x406434): with probability `chance`% a
  `BUBB` at the reference point `slot` (or the point when `slot` = 255), scale `10 ± 3.3`, speed 0.5,
  life 64; every update `vz += 0.5 dt`, a random wobble of `±1.6 dt` in x and y and `scale += 4 dt`
  (dt in seconds); it stops on a hit and then pops (`BUBB_POP`, life 7). `chance ≥ 150` would make
  sparks (0x4052d4: small tetrahedra in the fire colours 0x30 + 0x10 × light), which no level uses.
- The port draws the sprites as billboards (`MDKEffects`) and moves them every tick. A wound's blob
  sits at the reference point of the model's rest pose ❓ (the original's hot points follow the
  object's matrix, perhaps the animation too).

## Shattered triangle groups (`shatter_group` 137–139, 0x40c828)

Once taken for lighting (`light_group*`), these break a triangle group into flying pieces. 138 sets
the point (`0x4d5374`) and a direction (`0x4d5358`), 139 the point with no direction, 137 reuses
what the last one left; then `0x40c828(group, life, size, arena, speed)` (groups 1–255):

- The direction is normalised; a zero one means a radial burst and is replaced by (0, 0, 1), so a
  137 after a 139 blows the pieces straight up.
- Each triangle is split at the middle of an edge until `|AB × CB|² ≤ size² / 4` (area ≤ size / 4),
  with the UVs interpolated (0x40cbe0 flat, 0x40d014 textured).
- Each piece becomes a double-sided effect (0x40564c, priority 25) with the original material:
  `f = 1 − |centre − point|² / d²` (d = distance to the farthest corner of the group's box, axis by
  axis), velocity `speed × f` along the direction or away from the point (up when at the point),
  a spin of up to ±14° × f per update about each axis (0x46de70), life `round(life × 30)` ticks. They
  move like the drops above and aren't lit.
- When the pool runs out, the rest of the group makes no pieces.
- The scripts hide the group themselves right after (`group_set_state g, 0`) and play sounds: ice
  and walls blowing out in level 4 (`ICEXP1`, `EXPLODE`, then `hurt_kurt 10`), panels bursting in
  level 3's `HMO_3`/`HMO_4`, big long-lived shatters in level 7.
- The port builds the pieces into one mesh rebuilt every tick (`MDKDebris`, at most 600 pieces).

## Shooting galleries (level 6)

`OLYM_2` and `OLYM_4` have six `XBGUN` cannons firing along −y at a row of pop-up targets.

- `if_gun_aim y, z, action` (219, 0x461024): the aim leads Kurt's sideways movement
  (`(x − previous x) / dt`) by 1.67333 s, the flight time of the `XBG_B1` shot (300 units/s) in
  `OLYM_2`, plus a jitter of ±0.25°; the gun can only aim within 270° ± 3°. It fires at Kurt when
  aimed and `rand(70) < |vx| + 10`, else at one of up to 4 objects within 2 of `y` and 3 of `z`
  (the raised targets) in its cone, else at Kurt when aimed; otherwise it faces 270° and fires 29% of
  the time.
- `place_x_near_player x_min, x_max, y_limit` (220, 0x460f00): a target rises at Kurt's x (25%),
  at his x 2.67333 s later (50%) or at random (25%, and always when Kurt is outside the range or
  beyond `y_limit`), at least 12 units from the other objects on exactly the same y. The target then
  follows a path up (`TARGET` sound), waits 15 s and goes down again.

## Camera tracking (`camera_track` 203, 0x4612e0)

The camera pitch (`0x573918`, positive looks down) normally eases to the arena's rest pitch
(`arena+0x462`) by `0.85 old + 0.15 new` per frame; `0x5739b0` = 1 makes `camera_update` skip that
for a frame. `camera_track` (not in sniper mode) sets it and eases the pitch towards the object:
the angle off Kurt's yaw `d` (folded to 0–180°), the height (mode 0: 70% of the way up the object's
box, mode 1: `z + f × scale`); past 90° or below Kurt the goal is the rest pitch, otherwise
`−atan2(height − Kurt z, distance) × (120 − d) / 120`, clamped to −30…rest. Level 7's `XU` boss and
level 5's Gunter.

## Guided mortar rounds (`bomb_follow_path` 28, 0x4635b0)

`0x491ef0` is the sniper mode's mortar round (`SW_LGREN`, type 4) that just hit a triangle group
(set in 0x462708 before the group hit script runs, never cleared). The opcode makes it follow a
spline path (update 0x4634ac: absolute positions, life 99 until the last key, then 0 so it goes
off, no collisions; the round's camera stays on Kurt's side). Level 7's `DANT_6` guides rounds that
hit four wall groups down chutes onto four grunts. The port guides its mortar rounds the same way (`MDKSniperRounds`).

## Bullet holes (`special_130` 130, 0x45d140)

Stamps a bullet hole onto the texture of the object's last hit face, in the `if_hit_part ANY`
handlers of Gunter (`MUSE_2`, `GUNT_10`) and level 6's boss (`OLYM_10` `XB2`, where eyes and nose
get a hole instead of being hidden when `if_option 0`).

- Only direct projectile hits (0x462708) write the hit part + 1 (`obj+0x21c`, never cleared ❓),
  the face (`obj+0x220`) and the point (`obj+0x210`); explosions only set `+0x21e`.
- The point is taken into model space (less the translation `obj+0xb8/c8/d8`, times the matrix
  `obj+0xac`, divided by the scale `obj+0x58` squared). Faces with no texture, or texture flag
  `+0xc & 2`, are skipped. 0x45d594 intersects the line v0 → point with the edge v1–v2 (in the 2
  dominant axes) to interpolate the UVs.
- `BHOLE` (`BHOLE2` when `0x5742dc` = 0) is blitted 1:1 centred there (0x4048f8, only non-zero
  pixels), wrapping at the texture size, and the texture is uploaded again (0x4749c4, 0x474978).
  The texture is shared, so every object using it gets the hole. The port (`stamp_bullet_hole`)
  keeps the part and point of the last sniper round's hit and takes the part's face nearest to the
  point in the current pose.

## Globals

Globals used by the scripts and objects are listed in [scripts/notes_part2.md](scripts/notes_part2.md)
and [scripts/notes_part3.md](scripts/notes_part3.md). The main ones:

| Address | Meaning |
| --- | --- |
| 0x5739c0 (`g_damp_position`) | Kurt's position; 0x5739f0 his yaw; 0x5739f4 his bounding box (min x, y, z, max x, y, z) |
| 0x573a0c | Kurt's arena; 0x573a68 the other arena during a transition |
| 0x57fc34, 0x57fc30 | the target of the aliens (Kurt or a decoy) and its yaw |
| 0x574324 | Kurt's health; 0x573bd4 invulnerability time; 0x573b20 knock-down counter |
| 0x573aa8 | screen shake; 0x573b68 white flash; 0x573b70 red flash |
| 0x573c24 | the World's Most Interesting Bomb (a decoy), if active |
| 0x5742dc | option toggled by cheat codes (1 by default; opcode 232, BHOLE/BHOLE2) |
| 0x573b4c | the 4 global script variables; 0x573b5c the global flags (bits 29–31: towns, see [gameplay.md](gameplay.md#the-minecrawlers-timer-0x4240c4)) |
| 0x520a84 | table of loaded global models (80 entries of 0x88 bytes) |
| 0x573a38 | Kurt fires (the fire key is held) |
| 0x573c74, 0x573c78 | health bar: seconds left, object shown (or the arena's own object at `arena+0x118`) |
| 0x57ecf0 | message queue (4 × `time, flags, text`); read/write indices 0x57ece8/0x57ecec; current message 0x57ec90 (2 lines), time 0x57ece0, zoom 0x57ece4, flags 0x57ecd8 |
| 0x574270 | ticks before the minecrawler flattens the town |
| 0x574268 | level index (0–5 for levels 3–8); 0x57423e difficulty (0–2) |
| 0x5742a4 | the HUD is drawn (0 in cutscenes) |
| 0x573c60 | cutscene state (0 = none), see [Cutscenes](#cutscenes-special_event-131); camera 0x599920…0x599940 |
| 0x573c80 | arena Kurt is teleported to at the end of the frame; −1 ends the level |
| 0x573b60 | the level is over |

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
