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
| 0x10 | Kurt goes through it and can't stand on it (opcode 63; doors set it while open) |
| 0x40 | rolling (opcode 85) |
| 0x80 | no automatic banking/pitch (opcode 97) |
| 0x100 | a platform Kurt can stand on (`damp_platform_floor`) |
| 0x200 | set by `follow_path` flags1 bit 0 |
| 0x400 | the path is played once (`follow_path` flags2 bit 0) |
| 0x800 | Kurt walks through it (pickups, projectiles), but stands on it with 0x100 |
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
  Only the object's own arena counts: LEVEL5's key falls through the overlapping CMUSE_4 onto
  MUSE_5's floor. The sweep never pushes a box out of an overlap: a pose growing into a wall
  doesn't move the object (LEVEL7's `SW_H150`). The port uses `body_test_motion` with the other
  arenas' bodies excluded (`MDKLevel.get_other_bodies`) and keeps only the vertical part of its
  overlap recovery (`tests/own_arena_test.gd`, `tests/runner_pickup_test.gd`).
  Like any BSP sweep it is stopped by faces' fronts only: LEVEL6's boulders `XBO` pop out of their
  pit through the back of OLYM_6's hidden walls (group 3, y = 2772 and a diagonal). The port gives
  each triangle group a one-sided copy on `Level.OBJECT_LAYER` for the probe, and ignores an
  overlap the motion leaves sideways (`tests/rolling_ball_test.gd`).
- Objects with flag 0x80000 (the ridden board, set when Kurt gets on; thrown items) go into the
  arena whose connection their move crosses (0x45e810, 0x43ca00). LEVEL4's first board run
  (MEAT_1 → CMEAT_1 → MEAT_3) ends by the board's script, which waits for Kurt in a box of MEAT_3:
  a board left in MEAT_1 stops updating and Kurt never gets off (`tests/board_run_test.gd`).
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
0x46e170). The boulders of levels 4, 6 and 8 (`XCBOMB`, `XBO`). A rolling object is drawn at z +
the height offset (`obj+0x5c`, 0x43b65c) and its world bounds follow: LEVEL6's `XBO` rests on its
centred origin and is lifted by 5 of its 5.15 radius (`MDKObject.get_lift`).

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

### Kurt's arena

Kurt starts in the DTI's start arena (block 0, `level_load`) and changes arena only by crossing a
connection (DTI record type 6, 0x41c550 every frame; the arena he left stays as `0x573a68` during
the transition) or by a teleport (`teleport_player`, 112). Only Kurt's arena and the other arena
of a transition are drawn and solid. Arenas that no connection leads to and that aren't the start
arena can only be reached by a teleport; some are never used, and level 7's `DANT_8` (flat colours
and `GLASS3`) lies over the start of `DANT_1`. The port keeps every arena loaded, but hides these
and makes them not solid until a teleport takes Kurt there, and changes Kurt's arena as the
original does (below; the start arena is the smallest arena box around him); it draws only
Kurt's arena and the second one (see
[The second arena](#the-second-arena)). The 1996 demo's connections have no direction, so there
the port still picks the smallest arena box around Kurt among the arenas connected to his. ❓ how
the demo does it.

#### Crossing a connection (0x41c550) ✅

`0x41c550(arena, prev, cur)` returns the arena entered when the move `prev → cur` leaves `arena`
through one of its connections (first match in record order), else 0.

- Records: `arena+0x38` count, `+0x3c` the 36-byte DTI records; type 6 only. At level load
  `0x41c22c` pairs each record (id ≥ 1000) with the one of the same id in another arena (same box,
  opposite direction, else a fatal "Mismatched connect" error) and **replaces both ids with the
  other arena's index**.
- Fields: `+8` direction (an **integer** in the `angle` field), `+0xc..+0x14` corner 1 `(x0, y0,
  z0)`, `+0x18..+0x20` corner 2 `(x1, y1, z1)` (the name bytes).
- Direction = the way the move goes to **leave** this arena (the paired record has the opposite):

| Dir | Crossing (`prev` → `cur`) | Other axes (cur inside, or the move crosses a bound) |
| --- | --- | --- |
| 0 / 1 | `cur.x < x0 ≤ prev.x` / `prev.x ≤ x0 < cur.x` | y in [y0, y1), z in [z0 − 5, z1] |
| 2 / 3 | `cur.y < y0 ≤ prev.y` / `prev.y ≤ y0 < cur.y` | x in [x0, x1), z in [z0 − 5, z1] |
| 6 / 7 | `cur.z < z0 − 0.5 ≤ prev.z` / `prev.z ≤ z0 − 0.5 < cur.z` | x in [x0, x1], y in [y0, y1) |
| 4 / 5 | none: `cur` on the left (4) / right (5) of the XY line corner 1 → corner 2 | x, y, z as above |

  (−5 at 0x4945c8, −0.5 at 0x4945d0.) Levels use 0–3 (doorways, 140 records) and 6/7 (hatches,
  28); 4/5 never.
- Callers: `game_frame` 0x41d4d8 with Kurt's arena, `prev` = 0x5739cc (Kurt's feet of the last
  frame: `camera_update` 0x4174d0 copies 0x5739c0 there every frame; a teleport 0x41bce4 sets
  both), `cur` = 0x5739c0, after the scripts and the pending teleport. On a hit: `0x573be8` (sliding)
  = −15 if > 0, 0x573a68 = the arena left, 0x573a6c = 1, 0x573a0c = new, `BSPShow(new)` (loads it,
  switches the music to it, first-time aliens). Corridors (`C…`) and arenas are treated alike.
- Follows Kurt's arena (0x573a0c), not his position: the camera pitch (`camera_update` eases
  0x573918 to `arena+0x462`, the DTI pitch), the music (`arena_load` of Kurt's arena), triggers
  0x41bf1c (records of Kurt's arena), Kurt vs objects.
- `camera_update` also runs it on (Kurt's feet + 3 z → the camera position): when that reaches the
  second arena, the draw order is swapped (`0x490db4` = 1).
- Also called by the effects' segment test 0x407e2c (result in `effect+0x1a6`) and by the object
  move 0x45e810 (objects with `obj+0x14a` bit 3, result in `obj+0x2bc`). 🟡 their effect not checked.

### The second arena

#### Globals ✅

| Address | Meaning |
| --- | --- |
| 0x573a0c | Kurt's arena |
| 0x573a68 | second arena ("neighbour"): the one behind an open door, the one Kurt just left, or one being preloaded |
| 0x573a6c | second arena **active** (drawn, updated, solid for Kurt). 0 = only loaded/preloaded |
| 0x573b00 | an MTO arena is being streamed (`arena_switch` sets it, `arena_load_step` 0x41983c clears it when the last 32 KiB chunk is in). Not a "disable" flag: while set the second arena's BSP may not be there |
| 0x573b04 / 0x573b2c | arena sounds / arena music still loading (0x419ac0 / 0x4193a4 one step per frame) |
| 0x573b24 / 0x573b28 | Kurt's / second arena of the previous frame (for deactivation) |
| `_g_current_arena` | the one MTO arena whose geometry is resident (arenas, flag `arena+0x44` bit 1). Corridors (bit 1 clear) live in `LEVELnS.SNI` and are loaded separately (0x431914 / freed 0x431ad8) |
| `arena+0x44` bit 4 | DTI objects already spawned (0x43bd38) |

Only one MTO arena is resident at a time (`arena_switch` 0x41970c frees the previous one's `+0x24`/`+0x40`), so the
pair Kurt/second is in practice arena + corridor. ❓ (two MTO arenas as a pair would evict one).

#### Primitives ✅

- **`arena_load` 0x419d00(a)**: loads `a` (not active by itself): corridor → `arena_activate` 0x4194e4; MTO
  arena → `arena_switch` (starts streaming, 0x573b00 = 1). Starts loading its music if it has any (`+0x44` bit 2,
  0x4192c4); if `a` is Kurt's arena switches the music (0x419158). Registers textures (0x42325c). Then for each
  type-6 connection of `a` to an arena that is neither Kurt's nor the **active** second: every live door
  (flag 0x100000) of that arena whose `obj+0x60` or `obj+0x302` is `a` is moved into `a` (`obj+0x2bc = a`, 0x43ca00;
  the door's `+0x302` becomes its old arena, yaw += 180).
- **`BSPShow` 0x41a11c(a)** (opcode 100 `arena_show` via 0x41a1ac; `NONE` → a = 0):
  - a = 0: `arena_clear` 0x419f78: 0x573a68 = 0, 0x573a6c = 0 (and `_g_current_arena` = 0 if it was the second
    one still streaming).
  - a = Kurt's arena: `arena_load(a)`; 0x573a68 unchanged.
  - a ≠ second: 0x573a68 = a, `arena_load(a)`.
  - then **blocks** until streaming, sounds and music are loaded (loops on 0x573b00/b04/b2c), sets
    **0x573a6c = 1** (always, also when a is Kurt's arena: whatever second arena is set becomes active), and the
    first time (`+0x44` bit 4 clear) spawns the DTI objects of `a` (0x43bd38, see below).
- **`arena_set_neighbour` 0x41a2d0** (opcode 223): if the arena ≠ 0x573a68: 0x573a68 = it, `arena_load` (streams in
  the background, one chunk per frame from `game_frame`), **0x573a6c = 0**. `NONE`/not found → nothing.

#### 1. When it is set / cleared ✅

| Event | Code | 0x573a68 | 0x573a6c |
| --- | --- | --- | --- |
| Door starts **opening** (Kurt closer than `obj+0x30e`, state not open/opening/locked) | 0x43cc68 | `BSPShow(side)`: `obj+0x302` if it is neither Kurt's nor the active second; else `obj+0x60` if that is neither; else nothing | 1 |
| Door **closing ends** (state 4 → 8, animation done) | 0x43cc68 | `BSPShow(NONE)` → 0 | 0 |
| Door opening ends / closing starts | 0x43cc68 | unchanged | unchanged |
| Kurt **crosses a connection** (type 6, 0x41c550 on Kurt's previous/current position) | `game_frame` 0x41d4d8 | = arena he left; Kurt's = new one; `BSPShow(new)` | 1 |
| Kurt's XY inside (or crossing) a **type 1** record box of his arena (every frame) | 0x41bf1c | id = −1 → cleared; else `BSPShow(arenas[id])` | 0 / 1 |
| Same, **type 3** record | 0x41bf1c | id = −1 → cleared; else if different: = arenas[id], `arena_load` (async) | 0 if changed, else unchanged |
| Opcode 100 `arena_show` | 0x41a1ac | `BSPShow` | 1 (0 for NONE) |
| Opcode 223 `arena_set_neighbour` | 0x41a2d0 | = arena (async load) | 0 |
| **Teleport** into an MTO arena (`+0x44` bit 1) | 0x41bce4 | cleared, then `BSPShow(Kurt's)` | 0 |
| **Teleport** into a corridor not loaded | 0x41bce4 | = the last arena (highest index) with a type-6 connection to it (`arena_load`); other loaded corridors not connected to `_g_current_arena` are freed; then `BSPShow(Kurt's)` | 1 |
| Teleport into a loaded corridor | 0x41bce4 | unchanged; `BSPShow(Kurt's)` | 1 (if set) |
| Level start (0x41ba68, flag 2 clear) | 0x41ba68 | `BSPShow(Kurt's)`, then `arena_load(second)` if set | 1 |
| Load game | 0x42fb18 | restored from the save (index, −1 = none, 0x42ebc8); `BSPShow(Kurt's)`, `BSPShow(second)` if set | 1 |

- Type 1/3 records (corridors) are trigger rectangles: `x, y` (`+0xc`, `+0x10`) to `x2, y2` (`+0x18`, `+0x1c`), no
  z test; `id` = arena index. Crossing condition = inside on both axes or the segment previous → current position
  crosses an edge. ✅
- ❓ Nothing found that resets 0x573a68 on level load (`level_load` reallocates `_g_arenas`); presumably the level's
  start state or a script sets it.
- ❓ Whether 0x573a6c itself is saved: irrelevant, loading forces 1 through `BSPShow`.

Typical sequence: door opens → `BSPShow(other side)` (sync load, active, first-time spawn) → Kurt walks through
→ connection crossing swaps the pair (left arena stays active second) → a type 1/3 trigger in the corridor or the
next door closing (`BSPShow(NONE)`) clears it.

#### 2. What an active second arena changes ✅

Frame order in `game_frame` 0x41d4d8: objects of Kurt's arena (0x43c7dc) → free dead ones (0x45fc68) →
**if 0x573a6c && 0x573a68: objects of the second arena**, free its dead ones → Kurt's arena script (`arena+0x118`)
→ **if 0x573a6c && 0x573a68: second arena's script** → pending teleport (0x41bce4) → connection crossing →
triggers 0x41bf1c → camera → draw → triangle-group update 0x40d46c (Kurt's, second if 0x573a6c) → … →
deactivation (end of frame).
The port keeps this order: Kurt's crossing is checked first, but the arena scripts run after the
objects, else MEAT_5's `arena_show NONE` (LEVEL4) dropped CMEAT_4 before the ridden board there
crossed into MEAT_5, and its script never let Kurt off (`tests/board_run2_test.gd`).

| System | Kurt's | Second when 0x573a6c = 1 | Second when 0x573a6c = 0 (preloaded) | Other arenas |
| --- | --- | --- | --- | --- |
| Objects updated (0x43c7dc) incl. doors | yes | yes | no | no |
| Arena script | yes | yes | no | no |
| Drawn (`arena_build_drawlist` 0x4185f0, geometry + its objects) via 0x41e344 | yes | yes | no | no |
| Effects (`arena+0x5c`, 0x405ea0), texture scrolling (0x414230) | yes | yes (not while 0x573b00) | yes (not while 0x573b00) | no |
| Triangle groups (0x40d46c) | yes | yes | no | no |
| Kurt's BSP collision (`damp_collide_move` 0x465e34) | yes | yes (not while 0x573b00, not on the snowboard 0x573c30) | no | no |
| Kurt vs objects | Kurt's arena objects only | no | no | no |
| Updrafts (`damp_gravity`, 0x46360c), ledge grab, camera clearance | yes | yes if 0x573b00 = 0 | same | no |
| Segment/ray tests (0x421680): `if_sees_kurt` 0x4605d0, 0x460518, `if_bomb_visible`, chain gun 0x41a304 / 0x41ab2c, Kurt's projectiles 0x462708, blasts 0x463a94, air strike, effects 0x407e2c | yes | yes if 0x573b00 = 0 | same (**not** gated by 0x573a6c) | no |
| Objects hit by chain gun / projectiles / blasts (0x41a304, 0x462708, 0x463a94, 0x46428c) | yes | yes | no | no |
| Object BSP moves (0x45fec4) | own arena; objects with flag 0x80000 also test Kurt's (or the second if they are in Kurt's) and switch arena on hit | | | |
| End-level break-up (0x40a9e0) | yes | yes | no | no |
| Loop sounds / models | loaded | loaded | **loaded** (activation covers both slots) | unloaded |

- Draw order: second first, then Kurt's; swapped (`0x490db4` = 1) when the camera is behind a connection into the
  second arena (`camera_update` 0x4174d0 runs 0x41c550 on the camera position). No portal or door clipping found: the whole arena is
  submitted (per-triangle projection/culling in `arena_build_drawlist`). ❓ finer culling not checked.
- While 0x573b00 = 1 (streaming) the second arena is not drawn and has no effects (`game_frame` passes 0).
- Music: `arena_load` of either slot preloads that arena's music; it is only started if the arena is Kurt's
  (see sound.md "Arena music").

#### 3. Activation / deactivation ✅

- **Activation** `arena_activate` 0x4194e4 (after a corridor load, or when streaming + sounds of an MTO arena
  finish, via 0x419ac0): parses the streamed world if needed, inits its groups (0x40d46c(a,1)), registers textures
  of Kurt's and second, palette 64–175, then **0x43f8e0 on every live object of Kurt's arena and of 0x573a68
  (whatever 0x573a6c)**: re-creates its model instance (and replays its current animation frame), restarts its
  loop sound (`obj+0x15c` → `obj+0x158`).
- **First show** 0x43bd38 (only from `BSPShow`, arena bit 4 clear): DTI type 2 records → aliens (model
  `+0x4` hi word, instance lo word, script `"%s$%s_%d"`), type 4 → static objects (flags |= 0x2008a0, `obj+8` = 1,
  script `"%s$%s"`, `SW_DUMMY` part hidden); skipped when a live object of that type/instance already sits at that
  position. So aliens behind a door exist from the moment the door starts opening, before Kurt enters.
- **Deactivation** at the end of `game_frame`: an arena that was Kurt's or the second last frame (0x573b24/b28)
  and is neither now → 0x419cb0: frees its effects, and 0x43f800 on each live object: clears the aliens' target
  if it was it; projectiles/effects (flags 0x1000/0x4000) are destroyed (the Interesting/other bomb pointers
  0x573c20/0x573c24 cleared); others: loop sound stopped, model instance freed (state kept, re-created on
  activation). Setting 0x573a6c = 0 alone does **not** deactivate (objects stay loaded, just frozen and undrawn).
- Objects moving into an arena (0x43ca00) are loaded if it is Kurt's or the second (any 0x573a6c), else unloaded.
- Object pool full (0x45fd4c): recycles objects from arenas that are neither Kurt's nor the second.

#### In the port

`MDKScriptRuntime` keeps `second_arena` / `second_active`: `show_arena()` (`BSPShow`: opcode 100,
doors starting to open, crossing into another arena, trigger records of type 1, the start and
teleports) and `preload_arena()` (opcode 223, type 3); a door that ends closing clears it. A
teleport clears it only into an arena; into a corridor not loaded it loads the last arena (DTI
order) connected to it, as in the table above (`_teleport_second`, `tests/door_arena_test.gd`). The
objects and the script of the active second arena run, and its DTI aliens appear when it's first
shown (so behind a door as it opens). Only Kurt's arena and the active second one are drawn, with
their objects; an arena in neither slot any more stops its objects' loop sounds, which start again
when it comes back, and Kurt's thrown items there go. Rays (`raycast`) stop only on Kurt's arena
and the second one; Kurt collides only with his arena and the active second one
(`Level.set_solid_arenas`). His arena changes by crossing the connections (`_crossed_arena`),
and the camera pitch and the music follow it. A door that already links the two arenas is moved into the arena whose
script asks for it, unless it's in Kurt's or the second arena (`spawn_connector`). Type 4 records (static objects: only the pickups of level 8's `GUNT_9`) are spawned
with the aliens, with flags 0x2008a0 and 1 health.

### Doors (0x43cc68)

Doors are **connectors** between an arena and a corridor, created by `spawn_connector` (opcode 149)
in the scripts of both: the second call finds the existing door and moves it into its arena. A new
door starts closed (state 8) with an opening distance of 20 (`object_spawn` 0x45cdec, spawn flag 1).
A door whose other side (`obj+0x302`) is Kurt's arena moves into it each frame, turned around
(0x43ca00), and `arena_load` pulls doors in the same way: so a door lives in an arena that is drawn.
Otherwise, once Kurt left its arena and it shut, that arena is put away and the door freezes (LEVEL7:
back from DANT_2, the doorway to CDANT_1 showed the sky and Kurt walked through the door). Crossing
a doorway makes the arena left the active second one before the new one loads (`game_frame`). The
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

### The running `SW_H150` (0x43daf4)

Runs for every object with flag 0x200000 (pickup) after its velocity/friction step (0x45e74c,
0x45e810) and before `object_anim_update`.

**Only `SW_H150`** ("I Feel Top!!!") runs away. `SW_SEAL` and `SW_SBONE` only skip the 180°/s spin;
no other pickup moves. Animations `H150_I` (idle, `0x574b14`) and `H150_R` (run, `0x574b20`),
loaded at level load (0x404618) from `TRAVSPRT.BNI`. Sound `RUNNER` (`0x5744b4`).

Before landing it falls under its chute like any pickup (engine.md "Pickups"). Once landed
(flag 0x20000 set, or gravity flag 0x2 clear) each frame:

1. `obj+0x5c` (target height offset) = 0 (other pickups keep 1.5).
2. While its chute exists (`obj+0x312`), nothing else (the chute shrinks 1/s, removed at 0.2).
3. **Idle restart**: if no animation (`obj+0x114` = 0) or it ended (`obj+0x118` = 0xFF00) and
   `rand() < ticks × 72` (≈ 0.22 % per tick, mean ≈ 15 s): animation `H150_I`, fps `obj+0xe0` = 30,
   time `obj+0xdc` = 0, frame `obj+0xe4` = −1, hold `obj+0x118` = −1, clear flag 0x8 (plays once).
   Return.
4. **Not running** (animation ≠ `H150_R`): if Kurt is within 20 units (3D squared distance
   `0x417480` < 400): animation `H150_R` with the same resets, flag |= 0x8 (loops), play `RUNNER`
   (`0x402fd8(snd, 0)`: 2D, only if not already playing). Return.
5. **Running** (animation = `H150_R`):
   - push (`obj+0x294/0x298`, a velocity for the next move only) += 40 × (cos yaw, sin yaw) with the
     yaw of *before* this frame's turn → 40 u/s forward, with gravity and collisions (flags 0x2, 0x4).
   - away angle = atan2(Kurt.y − y, Kurt.x − x) + 180, minus 360 if > 360.
   - yaw turns towards it by at most 270 × dt (shortest arc, 0x460968).
   - flag |= 0x2 (gravity).
   - stop when Kurt is more than √1000 ≈ 31.6 units away **horizontally** (2D, squared > 1000):
     animation `H150_I` (time 0, frame −1; fps and hold left as they are), clear flag 0x8.
     `RUNNER` is not stopped.
   - Root motion of `H150_R` may add movement ❓.

No time limit and no jumping: it keeps running while Kurt stays within 31.6 units, and restarts
each time he comes within 20. Taking it is the normal pickup collection.

Placed by `spawn_flagged` (opcode 161): level 3 `HMO_5`, level 4 `MEAT_10`, level 6 `OLYM_5`,
`OLYM_8`, level 7 `DANT_1`, `DANT_6`.

```
          dist3D < 20               dist2D > 31.6
  IDLE ─────────────────▶ RUN ────────────────────▶ IDLE
  (H150_I once,           (H150_R loop, 40 u/s,
   replayed at random)     turn 270°/s away)
```

### `SW_EWJ` and the holy cow `SW_HCOW` (0x46d718)

`SW_EWJ` (text "Groovy!") is an instant pickup (case 10 of 0x46d478): sound `COLLECT` (2D restart,
game state 3 only), then 0x46d718.

**Target choice** (Kurt's arena `0x573a0c`, list `arena+0x68`): among objects that are active
(`+6`), have neither flag 0x10 nor 0x20 and health < 65000, and are within 600 units (3D,
0x417450):

- `a` = |Kurt's yaw (`0x5739f0`) − atan2(obj.y − Kurt.y, obj.x − Kurt.x)|, folded into 0–180.
- score = distance (a < 30°), distance + 400 (a < 50°), distance + 1000 (otherwise).
- skipped if a segment from obj + (0,0,5) to obj + (0,0,105) hits the arena BSP (0x421680, needs
  open sky), or if a cow already targets it (an active object with flag 0x40000000 whose
  `+0x302` points at this object's position).
- lowest score wins (start 999999, ties go to the later object).

No target → the target is Kurt himself.

**Spawn**: `COW` (`0x5744ac`, 2D restart) plays; model index of `SW_HCOW` (0x45ca88; the game
stops with "ENEMY name %s not found" if the level lacks it); object spawned in Kurt's arena at
target position + (0, 0, 100), spawn flag 0 (0x45cdec):

| Field | Value |
| --- | --- |
| flags `+0x148` | 0x40000806: gravity 0x2, collides 0x4, Kurt passes through 0x800, cow logic 0x40000000 |
| health `+0x8` | 65000 (indestructible) |
| vz `+0x30` | −gravity (`−obj+0x48`, default −32 u/s) |
| `+0x302` | pointer to the target's position (live: follows a moving target), or Kurt's `0x5739c0` |
| `+0x306` | 0.5 (s, landing timer) |

No script. Gravity 32 u/s² (default) → from 100 up it lands after ≈ 1.8 s ❓ (unless the model's
own gravity differs).

**Each frame, before the script** (0x440074, flag 0x40000000):

- While flag 0x20 is clear:
  - box hits (0x45cf60, cow bounds `obj+0x198`): mode 2 → every other active object of its arena
    without flags 0x820 whose bounds overlap: hit event −3 (blast, `+0x21e` = 0xFD),
    `+0x21d` = 0xFC, hit direction = cow yaw/pitch (`+0x224/0x228`), health −1000 unless ≥ 65000,
    `object_kill` at ≤ 0. Mode 1 → Kurt's box (`0x5739f4`) and his visible parts: `hurt_kurt(10)`
    (0x46a498). Any hit sets flag 0x20: it hits once.
  - while in the air (`obj+0x14c` bit 2 clear): x and y each move towards the target's x/y at
    50 u/s (per axis, clamped: diagonal up to 70.7 u/s).
- On the floor (`obj+0x14c` bit 2): flag |= 0x20, timer `+0x306` −= dt; below 0 →
  `object_kill` → no death script → default explosion (`EXPLODE`, no `SW_HCOWD` model → 16 fire
  sparks, flash).

So: a cow drops from 100 up onto the enemy Kurt faces (1000 damage), or onto Kurt (10 damage),
and explodes 0.5 s after landing.

**Levels**: `SW_EWJ` is spawned in level 4 (`MEAT_4` ×3, `MEAT_8` ×4, `CMEAT_3`, `CMEAT_7` ×3)
and level 5 (`MUSE_4`, script 26930). `SW_HCOW` is in the model tables of levels 3–8
(`LEVELnS.MTI`, `LEVELn.CMI`).

- The port does both (`MDKObjectBehaviors`, `MDKScriptRuntime._drop_cow()`); test `--cow`.

### Kurt and objects (`damp_collide_move` 0x465e34, `damp_platform_floor` 0x41d2c4)

Kurt walks into the objects of his arena that are active, alive (health ≠ 0) and have neither
flag 0x10 nor 0x800 (`flags & 0x810`): first their whole bounds (`obj+0x198`), then each visible
model part's box (the part's bounds in the current animation frame, `part+0x44`), skipping the
hidden parts (`obj+0x2c8`) and the `LOCK` parts of doors. This only clips his XY move; his Z comes
from the BSP alone. The box of the platform he stands on starts 1 above his feet.

`damp_platform_floor` stands him on objects with flag 0x100 and without 0x10 (byte `obj+0x148`
bit 4 clear, `obj+0x149` bit 0 set), whatever 0x800: a ray from 3 above his feet to 3 below
(0x4945d8/0x4945e0) against the visible parts; the last hit is the platform (`0x573b84`), which
carries him when it moves or turns. 0x800000 decides neither: landed on such a platform
(`damp_gravity` 0x469efc), `0x573b8c` = 1 and the scan is skipped, he keeps it (getting on the
snowboard, below).

| Flags | Walls | Floor | E.g. (level) |
| --- | --- | --- | --- |
| none | yes | no | grunts, doors, turrets |
| 0x100 (+0x800000) | yes | yes | `XPGUN` (3), `XBGUN`, `XTR` (6), `XTANK` (7), `X10_CAP` (8) |
| 0x800 + 0x100 | no | yes | `XWINCH` (3), `XSNOWB` 0x800900 before it's ridden (4) |
| 0x10, or 0x800 without 0x100 | no | no | pickups, bolts, `X4_TOWER` (5), `X3_BALC` (6), `XFORK` 0x810 (8) |

- The port (`MDKObject.update_body`, `Kurt._one_way_bodies`): floor-only bodies get layer
  `FLOOR_ONLY_LAYER`, wall-only ones `WALL_ONLY_LAYER`; Kurt passes through the first while his
  feet are under their top, the second while above it. Bodies he's inside of, but floor-only
  ones, count as touched (`Kurt.passed_objects`, as `0x573c2c`): he mounts the `XE` by falling
  through it. Test `tests/object_flags_test.gd`.

- The port (`MDKScriptRuntime._kurt_carrier`, `_carry_kurt`): each tick, the platform under Kurt
  (a ray from 3 above his feet to 3 below) carries him by its move and turn, Godot's own platform
  velocity off. Touching a body doesn't count as inside it (`Kurt._update_inside_bodies`), else he
  fell through the lift. Test `tests/platform_carry_test.gd` (LEVEL6's lift, 25 units a tick).

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
Example: level 8's start ship `XBSHIP` (`GUNT_1`, health 65000) has 7 blue turrets `T1`–`T7` (60
hit points). Its script blows a turret off on any hit event of it, so one sniper round does (the
chain gun only at 0 hit points, and from the floor the turrets are beyond its reach); with all 7
gone the ship falls, rolling, and explodes. Sniper rounds test the parts' faces, so the hull's box
doesn't hide the turrets ✅.

Example: level 8's forklift puzzle (`GUNT_2`). The first `XFORK` (script 0x4b0c) drives a path; any
hit sends it into the turret garage `XPER` (-383, 525, 18), which rises and fires. The `XPER`'s death
script (0x52b3) deletes it and spawns a new `XFORK` with a driver (0x4bc6, health 1110) that drives at
Kurt. Below 1000 hit points the driver `XFK_HEAD` and the canopy blow off; from then on each hit
gives it 1000 back and pushes it along the shot (`push_hit_dir`: 50 units/s for a part hit, 80 × dt
for the chain gun), so it can't be killed but can be pushed. While it (or Kurt) is on the yellow pad
(-435..-414, 547..568, z 7..9) the glass (group 1) over the way down is hidden; Kurt alone hides it
only once a forklift runs that check. While the garage is closed it hovers 4 units over the blue
floor; its box (the hull's pose box turned by its yaw, 0x43f370) stops Kurt there and on the pad's
east edge ✅. Test `tests/forklift_test.gd`.

### Death

`object_kill` (0x43d6d4 → 0x43d670): the object switches to its death script (`obj+0x110`, set by
opcode 76) if it has one (movement stopped, health 0, flag 0x20 so the chain gun ignores it),
otherwise it explodes (0x43d224):

- The object's explosion sound (`obj+0x154`, opcode 25) or `EXPLODE`, and a screen shake by
  distance.
- Debris: the parts of the break-up model `<model>D` (model record `+0x84`) fly off, or 16 fire
  sparks without one, and gore when the option `0x5742dc` is on; a white flash by distance (see
  [Sparks and explosion debris](#sparks-and-explosion-debris)).
- An explosion object using the global model 0 (`EXPLODE`: 21 triangles with a 26-frame animated
  texture): its texture shows one frame per tick and the object vanishes after the last one. It's
  scaled to 1.5 × the object's height over the explosion model's, faces the shooter (yaw + 180°)
  and is pitched towards the camera.

## Kurt's chain gun (0x41a304)

Holding fire (`damp_move`) sets `0x573a38`: the chain gun sound loops (`MULTIFIRE`, or `GATTFIRE`
with the super chain gun, 0x46c3e4) and Kurt's animation becomes `K_SHOT` (standing) or `K_RUNFIR`
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
  has them set in the data, but the arena's activation (`0x40d46c(a, 1)`, after
  `arena_parse_world`) sets both on every triangle with flag **0x2** ✅: all in group 0, so they
  stay hidden and passable (the `NONE` walls, a few `BLACK`/`PEN_255`/floor triangles; LEVEL8
  GUNT_2's `NONE` triangle cuts the floor diagonally). Arena scripts use this to hide rooms Kurt
  isn't in (level 5
  `MUSE_1`), for destructible parts, bridges…
- `group_set_texture` (140) gives every triangle of a group another material.
- `group_set_hit_flags` (168) and `group_on_hit` (99) make groups react to hits: flag 0x80 makes a
  group destructible (it's hidden until hit, then shown: its damaged version), hits increase the
  group's counter (`arena+0xcc`, opcodes 162/163) and can run a script (0x40d560).
- `group_state_near_player` (194) gives the groups around the one under Kurt the opposite of its
  op, the others the op (0x453a1e; LEVEL4's boards: op 2, the slope near Kurt shown, the rest hidden).

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
  [gameplay.md](gameplay.md#sliding-damp_buttslide-0x468db8). No level creates a conveyor (opcodes
  146–148 appear in no script), so the port has none.

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
| 51 (0x4779e0) | `MUSE_5` `XBN` | Kurt strikes: 0x4398f0(1) first plays `X_STRIKD` full screen (see [below](#the-full-screen-strike-0x4398f0); 0x43fa0c plays `X_STRIKB` the same way before Bones' air strike). Kurt is put at the object with its yaw, the object moves 4 along y, Kurt's state becomes 100 ❓; state 0x47, camera at (Kurt x − 10, y, z + 8) with yaw `90° − Kurt yaw`, pitch 0, distance 10 (shot unchanged, probably 11) |
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
- The port runs the cutscenes (state, which objects run and show, the camera), the full-screen
  strike (`MDKStrikeScene`), and event 81 plays the end movie (`EndMovie`, see gameplay.md "Videos").

### The full-screen strike (0x4398f0)

A loop of its own, the game stopped: 0x4398f0(0) before Bones' air strike (0x43fa0c), (1) for
Kurt's strike at the end of the game (event 51). Effects are paused (0x40319c), the music goes on.

- An object of the model `X_STRIKB` (with the animation `X_STRIKB` of `TRAVSPRT.BNI`, `0x574b10`)
  or `X_STRIKD` (the arena's animation), animation played once at 30 frames per second.
- When the one strike of the last two levels is used (`0x57440b`, Bones dives himself) only the
  parts `AWING`, `CANOPY`, `LEVER`, `LEVER01`–`LEVER03`, `OBJECT` show (table 0x491ddc; the hidden
  mask `obj+0x2c8`): the plane without Bones.
- Each frame: yaw += 45°/s, animation step, which also moves the model's reference points
  (`anim_step_frames` 0x43ab70 copies the animation's `f32[R][F][3]` points to the model's
  `+0x24`); the camera (0x439d70) sits at reference point 1 and looks at reference point 0 (both
  through the object's matrix), up = +z, zoom 0.35265 (focal length 600 / 0.35265 ≈ 1701 pixels on
  the 600×360 view: a long lens); only the sky and the model are drawn.
- It ends with the animation or on Esc; the camera is restored (and, for the air strike, the
  palette and `0x573a64 = 2`), the effects resume.
- The port (`MDKStrikeScene`) pauses the game and draws the level's sky and the model in a
  `SubViewport` over everything. Test: `--strike` (`--strike=dive` for the plane alone).

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
  them (`updraft_query` with mask 8), after a bounce too. At life ≤ 0 they're deleted. A segment
  starting on a plane crosses nothing (0x421470), so a piece resting on a surface leaves through
  it: the fans' sparks, born 0.25 below the grate, rise through it (`tests/fan_spark_test.gd`).
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

## Sparks and explosion debris

### Sparks (`effect_spark` 0x4052d4) ✅

`0x4052d4(effect, point, pool, index, size, colour, range)`; `index` is unused.

- **Size**: `s = (1 + R(2⁻¹⁵)) × size` → `[0.5, 1.5) × size`.
- **Geometry**: a tetrahedron, 4 vertices (+0x156) and 4 triangles (`+0x8c = 4`, `+0x90 = 4`):
  vertex `i = (T[i] + (R(2e-5), R(2e-5), R(2e-5))) × s` (jitter ±0.33 per axis) with the table
  0x404b00:

  | i | T[i] |
  | --- | --- |
  | 0 | (0, 0, 0.5) |
  | 1 | (0.5, 0, −0.5) |
  | 2 | (−0.5, 0.5, −0.5) |
  | 3 | (−0.5, −0.5, −0.5) |

  Triangles (0,2,1), (0,3,2), (0,1,3), (1,2,3), normals precomputed (0x405db0, +0x126). Collision
  box ±0.5·s (+0x74..+0x88).
- **Position**: `point + (R(2⁻¹⁴), R(2⁻¹⁴), R(2⁻¹⁵))` → ±1, ±1, ±0.5. Matrix rotation starts as
  identity.
- **Velocity** (units/tick): `vx, vy = R(2⁻¹⁴)` (±1), `vz = (rand() − 0x800) × 2⁻¹⁴` (−0.125…+1.875):
  mostly upwards.
- **Spin** (+0x44, applied once per update, `M = M × S`): `0x46de70(a, b, c, scale 1, t 0)` with
  three angles `(rand() − 0x41c2) × 28/32768` → −14.4°…+13.6° each (slightly biased negative).
- **Life**: `(rand() >> 9) + 60` → 60–123 ticks.
- **Update**: `0x4061d8` (movement of drops/debris: `pos += v·ticks` with sweep 0x407e2c; else
  `vz −= ticks × 0.284444 × 0.25`; a hit puts it at the contact, `v −= 1.4 (v·n) n`, life −20; fans
  push it (mask 8); deleted at life ≤ 0). If `s ≥ 1` and `rand() & 3 == 0` the update is 0x406004
  instead: it also leaves a **smoke trail** (below) every 1 or 2 ticks (`(rand() & 1) + 1`, fixed per
  effect). Only size-1.0 sparks can reach `s ≥ 1` (half of them), so 1/8 of those trail.
- **Draw** (0x406e24): each front-facing triangle (screen winding) is a **flat, opaque, untextured**
  triangle (negative material = palette colour, see [formats.md](formats.md#world-section--arena_parse_world)):

  ```
  d      = min(0, n · camrow2)      n = face normal, camrow2 = 3rd row of camera × effect matrix
  colour = round(base + range × |d|)   base = +0x94 (u8), range = +0x95 (signed s8)
  ```

  So the face turned to the camera gets `base + range`, edge-on faces `base`. Not lit otherwise.
  Palette indices < 64 are the DTI's shared colours (same in every level).

#### Colour sets

| Caller | size | base, range | Indices | Colours |
| --- | --- | --- | --- | --- |
| kind 0, gore on (`0x5742dc` ≠ 0) | 0.5 | 3, 3 | 3–6 | green 00ff00 → 009700 → 006300 (6 = cyan, face-on only) |
| kind 0, gore off | 0.5 | 13, 3 | 13–16 | blue 0000ff → 0000c3 → 000087 → black |
| kind 1 | 0.5, v × 0.5 | 0x25, 0xf0 (−16) | 37 → 21 | dark grey 130b0b (edge-on) → light beige b7bb93 (face-on) |
| kind ≥ 2 | 0.5 | 10, 3 | 10–13 | orange ff6400 → red → dark red 8c0000 (13 = blue, face-on only) |
| fire (explosions, fans, nuke) | 1.0 or 0.5 | 0x30, 0x10 | 48–64 | fire ramp 0f0000 → a34700 → ffff4f → white (64 = the arena's first colour ❓) |

### Smoke trail (0x406070) ✅

Priority 10. A `TRAIL` sprite (0x407048) at the moving effect's position: scale +0xa0 = 4
(`width × 4 / 256` units), speed 1 frame/tick, life 11 ticks, velocity 0 but moved by 0x4061d8 (so it
falls under gravity), box ±0.5.

### Spark bursts (`spark_burst` 0x41e8f4) ✅

`0x41e8f4(arena, point, sound, count, kind)`:

1. `kind` picks the colour set above (kind 1 also multiplies the velocity by 0.5).
2. **Sound**: when the arena's effect list is empty, or `count > 1`, or `frame_counter & 3 == 0`
   (0x573aa4, counted in frames, not ticks): the named sound (`obj+0x150`, opcode 26) or
   `RICO1`/`RICO2`/`RICO3` (`rand_below(3)`), 3D, flags 0x10106, volume 0x7fff, pitch 1, range 50.
   The sparks themselves are spawned **every call** (every frame the chain gun hits).
3. `count` sparks `0x4052d4(…, 0.5, base, range)` at **priority 0** (they never steal a pool slot;
   dropped when the pool is full).

Callers:

| Caller | Point | count | kind |
| --- | --- | --- | --- |
| Chain gun on an object (0x41a304) | box centre − ½ box size × aim dir (x, y) | 1 | `obj+0x21f` (indestructible flag: 0 normal → green, 1 → kind 1); weak-part hit → 0 |
| Chain gun on the arena | ray hit − 1 unit along the aim | 1 | 2 if the group reacted (0x40d560 bit 0), else 1 |
| Kurt's rounds on an object, not killed (0x462708) | hit point (`obj+0x210`) | 3 | `obj+0x21f` |
| Kurt's rounds on the arena (0x462eb4) | hit point | 1 / 3 | 2 if the group reacted (1 spark), else 1 (3 sparks) |
| Chasing aliens' hitscan (0x45ec18, from command 6 0x45e448) | on Kurt / arena hit | 1 | 0 on Kurt (+ `hurt_kurt 1` 0x46a498) / 1 on the arena |

**Chasing aliens' hitscan** (unused: command 6 is only set by opcode 6 `move_to_target`, which no
level's script uses; not in the port): every frame the chaser faces its target within 30°,
it casts a ray 150 units along `(0.866 cos yaw, 0.866 sin yaw, −0.5)` (30° down). If Kurt's position
projects on it at `0 < t < 150`, horizontally within √3 of the ray and `Kurt z − 0.5 < z < Kurt z + 5`,
Kurt is hit; otherwise the ray is tested against the arena (then the neighbour arena).

Other `0x4052d4` callers (fire colours):

- Fans (0x414230): one spark in 8 frames at a random point of the box (`z0 + 0.25`), size 0.5,
  velocity 0; the updraft lifts it (already in engine.md).
- The nuke (0x43efcc): 16 sparks, size 1.0, priority 20, plus 2 blasts and `EXPLODE`.
- Explosion fallback (0x43d224) and body-part bounces (0x406ccc), below.

### Object explosion (`object_explode` 0x43d224) ✅

Called by `object_kill` when there is no death script, with the hit point and a yaw.

1. The object's 8 attached effects (`obj+0x160`) and tracked sound (`obj+0x158`) are freed. Movement
   command 15 (alarm) sets 0x573af0 = 10.
2. Sound `obj+0x154` (opcode 25) or `EXPLODE`, 3D, flags 0x10006, range 200.
3. **White flash** (0x573b68, not the shake): `flash += round(1000 / distance(Kurt, point))`, clamped to
   0…150 (skipped at distance 0).
4. **Debris**, from the break-up model `M = model record + 0x84`:
   - M exists: if it's an arena ("overlay") model not yet loaded (`+0xa ≠ 0`, `+0x20 = 0`),
     `model_instance_create` resolves it in the arena (a copy linked in 0x573c6c); failing that
     (not found) it counts as absent.
   - **No break-up model**: 16 sparks at the object's position (`obj+0x10`), size 1.0, fire colours,
     priority 20. No gore.
   - **Break-up model**: for each part of M, the part with the same name (case-insensitive) in the
     object's model is looked up; if it exists and is hidden (`obj+0x2c8` bit) the piece is skipped.
     Otherwise one piece `0x405900(effect, obj, part, M+0x10 materials)` at priority 30.
     Then, with gore on (`0x5742dc`), up to 32 drops (0x406b3c, stops when the pool refuses one):
     at the object's position (matrix `obj+0xac`), velocity `obj+0x18c + (R(2⁻¹⁴), R(2⁻¹⁴),
     (rand() − 0x800) × 2⁻¹⁴)`, sprite scale `5 + rand() × 5e-5` (5…6.64), `SL_MED`/`SL_SMA`.
5. The object is removed (0x43d7bc).
6. **Explosion object**: a new object with the global model 0 (`EXPLODE`) at the point, yaw = the given
   yaw (also previous yaw), health 0, animation frame −1 / time −1, flags `+0x148 |= 0x20`, scale
   `+0x58 = 1.5 × (obj+0x1ac − obj+0x1a0) / (model0 z max − z min)` (the pose-bounds height over the
   explosion model's). Pitch `+0x13c = atan2(dz, h)` (0x440220) with `h` = horizontal distance from
   the camera (0x5738ec) and `dz = camera z + 5 − point z`, only when `h > 5` or `|dz| > 8`, else 0.

#### Break-up pieces (0x405900) ✅

- Draw: `+0x8c = 1` part, `+0x94` = the break-up part, `+0x90` = M's material table; drawn textured
  with `model_draw_parts` (0x407394). Part vertices are model-space absolute, so the piece starts
  exactly where that part of the model sits.
- Matrix: `0x46df5c(bank obj+0x54, yaw obj+0x4c, obj position)` = `Rz(yaw) · Rx(bank)` + position,
  then **z + 2**. No object scale, no animation pose (the break-up model is static) ❓.
- Velocity: `obj+0x18c` (the object's measured velocity per tick) `+ (R(2⁻¹⁴), R(2⁻¹⁴),
  (rand() − 0x800) × 2⁻¹⁴)`, i.e. like a spark: ±1, ±1, −0.125…+1.875 units/tick.
- Spin: three angles `(rand() − 0x41c2) × 28/32768` (±14°) per update, `M = M × S`: the piece
  rotates about the **model origin**, not its own centre, so outlying parts swing wide.
- Life `(rand() >> 9) + 60` (60–123 ticks); box ±0.5 (+0x74..+0x88).
- Update 0x4061d8 (as sparks); `rand() & 3 == 0` (1/4) → 0x406004: a smoke trail every 1–2 ticks.
- **"body" parts** (dead code ✅): a part whose name contains lowercase `"body"` (case-sensitive
  `strstr`, 0x479802, string 0x4932ec) would get the object's velocity exactly, a spin of ±4°
  (`× 8/32768`), always a trail, and on its first bounce (0x406ccc) life −300, a 64×64 `TRAIL` puff
  (scale 16, 12 frames, life 11) and 8 fire sparks. All part names are uppercase (`XG1_BODY`…), so
  this never happens.
- Flag `+0x186 & 8` (explosion 0x43cb2c when the effect dies) is never set.

#### Which models break up ✅

The loader (`level_load` 0x41b0c0, after `cmi_load_model_table`) links every CMI global model
record `X` (80 × 0x88 at 0x520a84) to the record named `X + "D"` (`"%sD"`, 0x49447c) via `+0x84`.
Arena-only models have none ❓. Dump (CMI second directory + `mdk_models.py`, overlays resolved in
the level's arenas):

| Model → break-up | Levels | Pieces |
| --- | --- | --- |
| XG → XGD | 3–8 | 9: `XGD_GUN, SHDR, TOER, TGHR, TGHL, HND, SHDL, HEAD, BODY` (names differ from `XG1_*`: never skipped) |
| XF → XFD | 3–8 | 6 (`XF1_H01, XF1_BODY`, 4 missiles); levels 5–6: 9 (+ `OBJECT01–03`) |
| XD → XDD | 3–8 | 6 (`XDD_FACE, LEGL, LEGR, BODLFT, HEAD`, `X_ENEMA`) |
| XS → XSD | 3–8 | 15, same names as XS (hidden parts skipped) |
| XC → XCD | 3–8 | 20, same names as XC |
| XGEN → XGEND | 3–8 | 8–9 (`CAP1–3`, `XGENT`, `XGENBASE`, extra `XGEN0x`/`CAP0x`) |
| XE → XED | 3, 4, 7, 8 | 7–8 (`XB`, `XB_UNDER`, thrusters…) |
| XT → XTD | 3, 6, 8 | 19, same names as XT |
| XTGUN → XTGUND | 3, 4, 5 | 13 |
| XTANK → XTANKD, XTANKT → XTANKTD | 4, 7 | 6 and 4 |
| XW3 → XW3D | 3 | 25 (wheel + 24 single-triangle shards `XWD_Gnn`) |
| XCARGO → XCARGOD | 8 | 14 (huge: parts up to 185 units) |
| XU → XUD, XPER → XPERD, XMART → XMARTD | 3, 8 | not found in any arena → fallback sparks |

### Other explosions ✅

- `explosion_spawn` 0x43cb2c(arena, point, scale): only the `EXPLODE` object (yaw and pitch towards the
  camera; pitch uses `dz = camera z + 3 − point z` (0x4969ac) with the same 5/8 thresholds, where
  0x43d224 uses +5) and the `EXPLODE` sound; **no sparks, debris or flash**. Scale 2.0 for Kurt's rounds types 2–4
  (0x4638cc) and item bombs (0x43deac), 3.0 for the World's Most Interesting Bomb (0x43f18c).
- The nuke (0x43efcc) adds 16 fire sparks (above).

### In the port

`MDKDebris` moves the sparks and the break-up pieces with the shattered triangles (one mesh rebuilt
every tick; sparks as flat vertex-coloured triangles, `colour = base + range × |facing|`); smoke
trails are `MDKEffects` `TRAIL` sprites. `MDKScriptRuntime.spark()` makes the bursts (kinds
`FLESH`, `HARD`, `GROUP`, `FIRE`; flesh sparks are green with gore, blue without: `Settings.gore`, see gameplay.md "Menus"), and
`explode()` the break-up, gore drops, white flash and pitch thresholds; the nuke adds its 16 fire
sparks. Test: `--sparks`. The fans let out their fire sparks (`MDKFans.update`, still at their
point, lifted by the updraft with mask 8 like every piece).

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
| 0x574268 | level index (0–5) in the order of play `0x490030` = LEVEL7, 6, 3, 4, 8, 5; 0x57423e difficulty (0–2) |
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
