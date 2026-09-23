# MDK gameplay internals

Reverse engineered from `MDKD3D.EXE`. Function names refer to
[`tools/ghidra/names.txt`](../tools/ghidra/names.txt). World units are called "u"; Z is up in MDK
coordinates. Items marked *(inferred)* weren't verified line by line.

## Timing (`timer_update`, `timer_compute`)

- The game logic is tick-based at **30 ticks per second**, measured with 120 Hz sub-ticks.
- `0x491e20` is the frame time in ticks (smoothed: 0.75·previous + 0.25·raw), `0x491e24` the frame
  time in seconds, `0x491e18` the number of whole ticks (≥ 1, clamped to 4).
- A frame limiter waits until 34 ms have passed (≈ 29.4 fps). There is one physics step per frame,
  scaled by the frame time.
- Animations advance one frame per tick, except Kurt's run animation (see below).

## Kurt ("Damp") movement

Kurt's state is the animation state at `0x573a70`:

| State | Animation | Meaning |
| --- | --- | --- |
| 100 | `K_STILL` | Standing (plays once, holds the last frame) |
| 101 | `K_IDLE` | Idle animation |
| 200 | `K_LAND` | Landing |
| 201 | `K_SURF` | Surfing |
| 300 | `K_SHOT` | Shooting while standing |
| 400 | `K_TRN45` | Turning in place (frame from the rotation angle) |
| 500 | `K_SIDE` | Strafing |
| 600 / 601 | `K_RUN` / `K_RUNFIR` | Running (firing); footstep sounds on frames 0 and 13 |
| 700 / 701 | `K_FALL` / `K_CHUTE` | Falling / chute |
| 702 / 703 | `K_JUMP` / `K_RJMP` | Jumping standing / running |
| ≥ 800 | | Hanging from a ledge, special modes |

### Horizontal (`damp_move`, `input_read_axes`, `vel_accel`, `vel_friction`)

Speeds per tick (× 30 for per second):

| | Normal | Turbo (Shift) |
| --- | --- | --- |
| Acceleration (forward, backward, strafe) | 0.04444 u/tick² | 0.08889 u/tick² |
| Maximum speed | 0.6667 u/tick (20 u/s) | 1.3333 u/tick (40 u/s) |
| Keyboard turn acceleration | 0.9 °/tick per frame | 1.3 °/tick per frame |
| Keyboard turn maximum | 4 °/tick (120 °/s) | 6 °/tick (180 °/s) |

- Pressing the opposite direction resets the speed to one acceleration step (`vel_accel_dt`).
- Without input, speed decreases by 0.17778 u/tick² above 0.6667 u/tick, and by 0.08889 u/tick²
  below, times 1.0 on a floor, 0.75 in the air, 0.1 on slippery floors (floor triangle flag 0x04).
  The strafe acceleration uses the same factors (0.5 on slippery floors).
- Turning slows down by 1.6 °/tick² above 4 °/tick, 0.55 °/tick² below.
- Mouse turning sets the turn speed to 3 × clamp(mouse dx / sensitivity / dt, ±4) °/tick.
- Movement: yaw −= turn × dt; dx = (vf·cos yaw + vs·sin yaw)·dt; dy = (vf·sin yaw − vs·cos yaw)·dt.
- The camera rolls by up to ±10° while running and turning (±0.25 °/tick), decaying by
  clamp(0.35·|roll|, 0.05, 2.5) °/tick.

### Vertical (`damp_vertical`, `damp_gravity`)

- Gravity 64 u/s², falling speed capped at 250 u/s.
- Jump: vertical speed 40 u/s (peak ≈ 12 u), when on the ground and the key was released since the
  last jump. During the first 6 ticks, releasing the key subtracts the remaining ticks × 3.333 u/s.
- Falling faster than 16 u/s starts the fall (700), or the chute (701) if the jump key is held.
- Chute: gravity 21.33 u/s², falling speed braked (256 u/s²) to 8 u/s.
- Landing faster than 100 u/s is a hard landing (probably damage *(inferred)*).
- The floor is found by the downward collision sweep (no separate height query). Moving platforms
  are found by a ray from z + 3 to z − 3 (`damp_platform_floor`).
- Ledge grab (`damp_ledge_grab` 0x469868, after `damp_gravity`) ✅: while falling (vertical speed
  ≤ −0.25), moving forward, not already hanging and with a state priority below 9, the path of the
  point 4.604 above the feet and 1, 2 then 3 units ahead (last frame's position → this frame's) is
  tested against Kurt's arena, then the neighbour one. The first triangle hit must be flat
  (|nz| ≥ 0.85); its edge crossed by the line from the hit point back towards Kurt is the ledge.
  Kurt must face it within 30° (his yaw becomes the edge's angle − 90°), and a box of half size
  (0.5, 0.5, 2) swept from 1 unit before the edge to half a unit past it, 2.5 above it, must be
  free. Kurt is then put 1 unit before the edge and 4.604 below it, his speeds cleared, state 800.
- Climbing (state 800, `damp_animate`): `K_HANG` at 2 ticks per frame, with gravity off
  (`0x573a40` = 2); for tick `t` (from 1) and `k = (t + 1) >> 1` below 15, the height grows by
  `(H[k] − H[k−1]) × 0.708333 × 0.5` and the position moves back by `(B[k] − B[k−1])` × the same
  along the facing, with the tables `H` (`0x491f34`: 0.374 … 6.417) and `B` (`0x491f74`: 0.685 …
  −1.305): about 4.27 up and 0.7 forward in all. After `2 × frames − 1` ticks he's free again. The
  port looks for the edge by stepping back from the hit point with short downward rays and gets the
  wall's direction from a ray under the edge.

### Kurt's run animation (`damp_run_anim_frame`)

The frame advances by `rate` frames per tick, with u = forward speed (u/tick) × 1.5:
rate = 0.75u + 0.25 up to u = 1, then 0.25u + 0.75. It plays backwards when backing up.

## Collision (`damp_collide_move`, `bsp_sweep_box`)

- Kurt is an axis-aligned box swept through the arena BSP.
  - Horizontal sweeps: half extents (0.6, 0.6, 2.5) centered at z + 3 (so obstacles lower than
    0.5 u are stepped over); 4 slide iterations; slides only if (m·n)² ≤ 0.75·|m|², so walls within
    30° of head-on stop him.
  - Vertical sweeps: half extents (0.4, 0.4, 2.5) centered at z + 2.51.
- Planes with |nz| < 0.75 are walls: the steepest walkable slope is about 41°.
- Near arena borders, the neighboring arena is also tested. Objects are tested with segment versus
  bounding box.
- Conveyor belts (`conveyor_push`) add their velocity, depending on the floor triangle's material.

## Firing

The fire key (held) sets `0x573a38` in `damp_move` (unless Kurt is in a state class ≥ 8), which
starts the looping chain gun sound and asks for the firing animation: `K_SHOT` (state 300) when
standing, `K_RUNFIR` (state 601, footsteps on frames 4 and 17) when running. `damp_animate` clears
the muzzle flash every frame and, while firing, every other frame picks the next of the 4 `K_MUZZF`
frames at random (`(previous + rand(3) + 1) & 3`) with a random 0–4 pixel offset added to a
per-state base: turning and strafing (0, 0), falling (40, 6), jumping (0, 0), running jump
(0, −10), chute (20, 0), surfing (−42, 12). `damp_sprite_draw` draws the flash's hotspot at Kurt's
hotspot plus that offset, before (behind) Kurt. The hits are described in
[engine.md](engine.md#kurts-chain-gun-0x41a304).

## Pickups (`damp_collect_pickups` 0x46c448)

Every frame Kurt takes the pickups of his arena (flag 0x200000, not already taken: 0x40000) that
the segment from his previous to his current position crosses; a pickup's box is its bounds grown
by 1 unit, and 5 downwards. Taken pickups get flags 0x41000 and vanish in 30 ticks.

- **Used at once** (table 0x4920e0, 0x46d478): sniper ammo `SW_HOME`, `SW_SGREN`, `SW_HGREN`,
  `SW_LGREN`, `SW_BONES` (+8, 3, 3, 8, 1 of ammo type 1–5 at `0x5743f3`, halved on hard when above
  1, and that type is selected); health `SW_H25` (+10, up to 100), `SW_H50` (+50, up to 100),
  `SW_H100` (at least 100), `SW_H150` (at least 150), `SW_H01` (+1, up to 100); `SW_EWJ` and
  `BONEFLC` are easter eggs. Sounds: `APPLE` for health, `BONES`, otherwise `COLLECT`.
- **Inventory** (table 0x4921ac: 5 slots of 0x24 bytes at `0x57432c`, count `0x5743e0`, selection
  `0x5743e4`): 1 `SW_DUMMY` (decoy), 2 `SW_INTER` (the World's Most Interesting Bomb, sound
  `WMIB`), 3 `SW_TWIST` (tornado), 4 `SW_THUMP` (mortar), 5 `SW_HBOMB` (grenades: 5/3/1 per pickup on
  easy/normal/hard, 1 in `DANT_2`), 6 `SW_GATT` (super chain gun: 400/200/100 ticks of 6× damage,
  `0x5743ef`), 7 `SW_KEY`, 8 `SW_SEAL`, 9 `SW_SBONE`. Grenades and the super chain gun stack in their
  slot; other pickups need a free slot (at most 5), else Kurt leaves them. The new item is selected
  (except the super chain gun).
- Scripts see a taken pickup through its flag 0x40000 (`if_flag_40000`).
- Every pickup shows its name as a message for 2 seconds (the text of `MDKFONT.FTI` with the pickup's
  name, e.g. `SW_HBOMB` "Hand Grenade", `SW_H150` "I Feel Top!!!", `SW_EWJ` "Groovy!"), except
  `SW_H01` and `BONEFLC`.

## Damage and death (`hurt_kurt` 0x46a604, `damp_control`)

- Damage is ignored while Kurt is invulnerable (`0x573bd4`), dead or in some states; it's 2/3 on easy
  (at least 1) and doubled on hard. Each hit adds `damage × 25` to the red flash `0x573b70`
  (kept within 75–180, −4 per tick).
- **Knocked down**: each hit also adds its damage to `0x573b20` (blasts then double it; the mortar
  and `set_hurt_flash` set it), which drains by 2 per second and is capped at 5. At 5, Kurt is
  knocked down (state 901, priority 9): `K_BANG` then `K_BFLIP`, one frame per tick, the push of
  `push_kurt` (`0x573c08`, slowing by 0.1 u/tick per tick) stopping when the flip starts. He can't
  move, fire or use items, and he is invulnerable for 3 seconds (`0x573bd4`). In the air it only
  happens within 13 units above a floor (a ray down), and his vertical speed becomes at most
  −64 u/s.
- At 0 health, once on the floor, Kurt plays `K_BANG` (state 1002) and holds its last frame; the
  `SKULL` image fades in at the centre of the view (`0x573b70` going up to 255), then the game loads
  the last saved game (`LASTGAME`).

## Sliding (`damp_buttslide` 0x468db8)

Kurt slides down the wind tunnels of level 6 on his back. The script opcode `wind_zone` (224) starts
it (0x468b64) while Kurt is inside a type-9 hotspot box of the arena and he stands on a floor or is
already sliding: `0x573be8` = 1, speed cap `0x573bf8` = 50, slide velocity `0x573bf0`/`0x573bf4` = 0,
floor normal `0x573bfc`… = (0, 0, 1), state 807. The chain gun stops.

- **States** (`K_SLIP`, `K_SLIDE`, `K_FSLIDE`, `K_BSLIDE`, in `LEVEL6S.SNI`): 807 `K_SLIP` plays
  once, then 808 `K_SLIDE` loops; 809 while accelerating and 810 while braking.
- **Every frame**: the floor normal is smoothed (`0.8 × old + 0.2 × new` horizontally, half and half
  in z) and the slope pushes by `10 × normal`; with no floor the push stays and the air timer
  `0x573a48` counts ticks. The push and the wind go through `slide_accel(ax, ay)` (0x468be0), which
  per axis adds `a² × dt` above 0.1, subtracts it below −0.1, and otherwise brakes by 2 u/s²
  towards 0.
- The heading is `atan2(vy, vx)` and becomes Kurt's yaw while `|vx| + |vy| > 0.5`; turning left or
  right turns him by 45°/s. Moving forward accelerates by 35 u/s² (above 15 u/s) and raises the cap
  by 10/s up to 80; braking slows by 15 u/s² down to 15 u/s and lowers the cap by 25/s down to 15;
  with no input the cap goes back to 50 at 20/s. There is no other friction.
- Kurt moves at `(cos yaw, sin yaw) × min(speed, cap)`, and falls at twice the normal gravity
  (128 u/s²). When a wall stops him (less than half of a move of over 0.5 units), the slide is
  aimed half way towards what he actually moved and the speed averaged with it.
- The camera rolls with the slope (`0x573910`, a tenth per frame towards
  `90° − atan2(n.z, n.x × ûy − n.y × ûx)`).
- `BUTSLIDE` loops (at 15000 Hz instead of 11025 while accelerating), `BUTBRAKE` plays while braking.
- **Out of it**: sliding blocks jumping, the chute, the fall states and the landing (no hard
  landing, no damage from it). It ends when the air timer passes 20 ticks (state 700, falling), when
  the arena changes (`0x573be8` = −15 counts up to 0), or when Kurt comes to a stop on the floor:
  then he gets up like from a knock-down, starting at the `K_BFLIP` half (state 901).
- Level 4's snow chase has a similar board mode (0x46ac4c, `K_SURF`/`K_SURFJ` in `LEVEL4S.SNI`,
  sounds `SKILAND`/`SKITURN`, the board object `0x573c30`) ❓ not analysed yet.

## Sniper mode (`0x573a60`)

- **Entering** (`damp_move` 0x46883c, key `KM_SNIPE`, once per press): only with Kurt's state
  priority below 8, standing on a floor (vertical speed 0) that isn't an active fan or conveyor.
  The chain gun stops, speeds are cleared and Kurt goes to state 803 (`SNIPERON`, `K_STILL` held,
  camera distance 0, eye 4 above the feet); a phase counter `0x573a64` then copies the `SNIPERS1`
  frame, selects the sniper projection (`0x57428c`), resets the pitch and starts `BREATH`.
- **Leaving** (0x4645c8): the key again (state 900, `SNIPEROFF`), falling (off the floor with a
  vertical speed below −30 or above 0), knock-downs and death, leaving a moving platform, the end of
  the level, cutscenes ("stop" 0x4779b0) and `push_kurt`. Hits don't end it. The pitch goes back to
  the arena's, the zoom to 2.4.
- **Controls** (0x467384 instead of `damp_move`): Kurt only sidesteps (a quarter of the running
  speed: 5 units/s, 10 with turbo) and still falls. The turn and forward/back keys turn and tilt the
  view through speeds that accelerate by 0.4°/tick² (0.6 with turbo) up to 4°/tick (6), with the
  friction 1.0667 (1.6 above 4); each frame `yaw −= v × ticks × zoom × 0.416667` and the same for the
  pitch, which stays within ±50° (forward looks up). The mouse turns by `0.12 × zoom × 0.4167` per
  unit. There's no sway.
- **Zoom** (`0x57391c`, the inverse of the magnification): the focal length is `384 / zoom` pixels
  (it's `600 / 2.4` = 250 in the normal view); 1 on entering (53° wide), at least 0.25 (4×), or
  `min(0.25, 0.375 × height / distance)` of the locked target (height at least 10, 0x4678b0). The
  zoom keys (`KM_ZOOMI`/`KM_ZOOMO`) accelerate a speed by 0.01 per tick up to 0.15, which decays by
  0.015; zooming out multiplies the zoom by `1 + v` each frame, zooming in divides it (0x4687a4).
  `ZOOM` loops while zooming.
- **The view**: the scope is a 384×280 viewport at (107, 79) of the 600×360 view (centre
  (299, 219)); the eye is 4 above the feet and moves forward by `5 (1 − cos pitch)` when looking
  down; Kurt isn't drawn.
- **Target lock** (0x43b65c, during projection): the nearest object (by depth) whose screen box
  overlaps a 64-pixel square around the crosshair, not flagged 0x30 (`0x573a8c`): homing rounds chase
  it and it sets the zoom limit.
- **Screen** (`TRAVSPRT.BNI`): `SNIPERS1` (640×480 palette indices, no header) is the frame around
  the view; `SNIPERS2` is a mask over the view (`u32 size`, then u16 words over 600-pixel rows:
  below 0x8000, n × 4 literal bytes; 0x8nnn skips nnn transparent pixels; 0xFFnn, nn literal bytes;
  0xFF00 ends), with holes for the scope and three 140×70 round cameras at (72, 10), (228, 0),
  (384, 10) (each follows a round from behind, 90° wide, then shows colour 0x3c after a hit, 0xf4
  after a kill, or the `SNIPERGA` animation after a miss); `CROSS` on the scope's centre; the zoom in
  percent `round(100 × (1 − zoom)² × 1.05194)` in `SNIP_TXT` digits at (564, 155) with the
  `SNIP_RNG` gauge (its bottom rows, following by 3 pixels a tick) at (552, 176); `SNIP_WEP` at
  (112, 304), the icons `SNIP_W1`–`W6` of the types with ammo and the selected type's `SNIP_Ln` and
  count (0x490fd8, 0x490fa8); the loaded rounds as 3D models along keyframes (0x41eb10, 0x490e58).
- **Ammo** (`0x5743e8` selected type, counts at `0x5743ef + 4 × type`; zeroed on each level): 0 the
  bullet (always), 1 `SW_HOME` homing bullets, 2 `SW_SGREN` grenades, 3 `SW_HGREN` homing grenades,
  4 `SW_LGREN` mortar rounds, 5 `SW_BONES` Bones' air strike (pickups give 8, 3, 3, 8, 1, halved on
  hard above 1). Keys pick a type directly or step through the ones with ammo.
- **Clip** (0x41eb10): up to 3 rounds (`0x5743ea`) and a timer (`0x5743eb`) dropping by 4 per second;
  while it runs, rounds load one per frame (`SNIPRELD`), only as many as there's ammo for (except
  bullets). Firing (0x461e88) needs the fire key, 5 frames since the last shot, the timer at 0 and a
  free round slot: a round is used, the timer goes up by 1 (a shot every 0.25 s), or to 3 when the
  clip is empty. Changing type raises the timer to 3 before the new rounds load. `SNIPERSHOT`.
- **Rounds** (3 slots of 0xfc bytes at `0x573c98`, 0x462708 after the objects): from the eye along
  the view, tested every frame along the segment moved against the objects (box, then the parts'
  faces), then the arena's BSP.

  | Type | Life (ticks) | Speed (units/s) | Movement |
  | --- | --- | --- | --- |
  | 0 bullet, 2 grenade | 75 | 1100 | straight (0x462f24), spinning 720°/s |
  | 1, 3 homing | 240 | 400 → 100/250 | steers at the lock after 7 ticks (0x463174) |
  | 4 mortar | 450 | 150 × cos pitch, vertical −150 × sin pitch | drag, gravity 32, bounces (0x46360c) |

  - Homing: the yaw rate accelerates by 540°/s² towards the error (up to 270°/s, back to 0 when it
    has the wrong sign, never overshooting), the pitch turns by 120°/s, the speed aims for 250 when
    within 35° of the target (else 100), rising by 200/s, falling by 500/s. The aim is the target's
    `HEAD` part if it has one, else its box.
  - Mortar: `f = h / (|vz| + h)`, `h −= f × 60 dt`, while rising `vz −= (1 − f) × 60 dt`, then
    gravity 32 (−220 at most); fans lift it. On the arena: `0x491ef0` = the round, the triangle
    group's hit script (kind 1, hit type 4; `bomb_follow_path` can guide it), then
    `v −= 1.75 (v·n) n`, and it settles after 15 ticks once stopped.
  - Hits: bullets take 8 hit points (not from objects with 65000 or more), set the hit event to the
    part + 1 (`if_hit_part`) and the hit point, face and direction (`obj+0x210`…, for
    `special_130`); at 0 the object dies. Grenades and the mortar explode (0x4638cc): 150 damage to
    objects and triangle groups and 75 to Kurt within 25 (50 for the mortar), hit type −7. A bullet
    hitting the arena does 8 to its triangle group (kind 1). The slot stays busy while its camera
    watches: 45 ticks after a hit, 30 after a miss or an explosion.
- **Bones' air strike** (type 5, 0x4641ac, 0x43fa0c): needs a point hit within 5000 units with open
  sky 1000 units above it and no strike out; it spawns `X_STRIKE`, which flies a 5-key spline over
  the target at 150 units/s, 30 units above the arena, dropping 9 `X_TOOTH` bombs (grenades) around
  it; in the last two levels (index > 3: LEVEL8 and LEVEL5) there's only one strike and it dives
  into the target (a 450-damage blast).
- **Sounds**: `SNIPERON`, `SNIPEROFF`, `BREATH`, `ZOOM`, `SNIPERSHOT`, `SNIPRELD`, `RASPBER`.
- The round models (`SW_SHOT`…) stand upright, their length along +Z: in flight the nose (+Z) is
  turned to the direction and the spin is around the length.
- The port also zooms with the mouse wheel (a notch holds the zoom key for 6 ticks); in sniper
  mode the wheel doesn't step through the ammo types, the item keys still do.
- The port has all of it but the 3D clip on the screen and the iris around the air strike's target
  (`MDKSniperRounds`, `MDKAirStrike`, `SniperOverlay`; the round cameras are `SubViewport`s). The
  air strike's curve goes through the same 5 points with Godot's `Curve3D`, not the original's
  spline parameters (0.5, 1.0, 0.5 ❓).

## Level flow (game state `0x574262`, main loop 0x401cb8)

| State | Frame (init) | What |
| --- | --- | --- |
| 0 | 0x4265c0 (0x42618c) | menu |
| 2 | 0x4114a4 (0x410018) | the fall (`FALL3D`) |
| 3 | `game_frame` (0x41ba68) | the level |
| 5 | 0x4352ac (0x433b50) | the stream between levels (`STREAM`) |
| 6 | 0x43200c (0x431b00) | statistics, debriefing, briefing |
| 7 | — | load the last level directly |
| 8 | 0x47727c | the end videos |

- **Order of play** (`0x490030`): the level index `0x574268` (0–5) picks LEVEL7, 6, 3, 4, 8, 5.
  `LOAD_n.LBB` and `TRAVERSE/LEVELn` use the LEVEL number; `FALL3D_n`, `FALLPn`, `FALLPU_n`,
  `Ln_MAP`, `BRIEFn`, `DEBn…`, `OOT_Ln` use the index + 1. The index decides some rules: no town
  timer in the last level (index 5), a single diving air strike from index 4, the fans don't lift
  rolling objects in LEVEL6 (index 1), Bones falls with Kurt only at index 4.
- **New game**: the level files are copied (a bar), the briefing (state 6), the fall, then the
  level. **End of a level**: the tornado (below), the stream; below index 4 the statistics, the
  save prompt, the next briefing, the fall; from index 4 the index becomes 5 and LEVEL5 loads
  directly (state 7), without statistics or fall. Health at 0 after the fall or the stream is game
  over.
- **Loading screen** (`level_load` 0x41b0c0, drawn by 0x422a10): `MISC/LOAD_n.LBB` (768-byte
  palette, `u16 w, h` = 200×200, pixels) centred at (200, 25) of the 600×360 screen, `LOAD_MSG`
  "Loading" centred at y 260, a progress bar 10…590 × 290…310 (13 steps, outline colour 4) and a
  second one at 330…350 for sub-steps.
- **The end of a level** (`endlev.c`, 0x40a9e0 and 0x40ad9c each frame): the visible triangles of
  Kurt's arena (and the one through an open door) are listed from the highest down; each frame
  0–7 of the highest are hidden (flags 0x30) and fly off (0x40b280): `vz += 0.025` per tick, a spin
  growing by 0.15° per tick² up to 2.5° per tick around Kurt; a piece goes when its centre passes
  the limit (500 above, rising with Kurt). The screen shakes (5). Kurt takes off (state 1000
  `K_TAKEOF`, then 1001 `K_FLOATC`) and rises with the debris (0x40b558 instead of `damp_control`):
  he turns clockwise ever faster (`0x573b0c` += 0.15° per tick up to 2.5° per tick), his rise
  speed `0x573b14` grows by 0.025 per tick (three times as fast once above 3 units per tick). Above
  3, the camera pitch offset `0x573b1c` (added to the arena's pitch) drops by 22.5°/s to
  `(−60 − the arena's pitch) × 0.5` (the view tilts up); once there a sound plays and the white
  flash climbs by 8 per tick; past 300 the stream starts. The city outcome flags are kept
  (`0x57440f` = `0x573b5c`).
- **The fall** (state 2, `fall_3d.c`): a minigame in its own files, played after each briefing;
  see [The fall](#the-fall-state-2-fall_3dc) below.
- **The stream** (state 5, `STREAM/STREAM.BNI`, `STREAM.MTI`): Kurt steers down a generated tunnel
  (0x434838, not decoded yet), hitting the walls hurts; Bones rescues him (`RESCUE`) after segment
  177 or at 1 health (the Gunta variant ends at 186).
- **Statistics** (state 6, `MISC/STATS.BNI`, `STATS.MTI`): `L1_INTRM` until a key; the debriefing
  typed at 15 characters per second on `L<n>_MAP`; the Score-O-matic; then the briefing `BRIEFn`
  on the next map (health raised to 100, the inventory emptied). See
  [below](#statistics-and-briefing-state-6).
- **In the port**: the order of play, the loading screen (`LoadingScreen`), the end of level
  (`MDKEndLevel`), the statistics, debriefing and briefing (`StatsScreen`: after a level below
  index 4, and the briefing alone for a new game), then the next level. The fall, the stream and the
  save prompt after the Score-O-matic aren't done. The Score-O-matic's counts
  (`GameState.stats`) are cleared when a level starts.

### Statistics and briefing (state 6)

✅ = read in the code (`MDKD3D.EXE`) or the data, ❓ = unverified. A preview renderer of every page
is [`tools/python/mdk_stats.py`](../tools/python/mdk_stats.py).

**Screen.** Everything is drawn on the 600 × 360 screen (the images are blitted 1:1 at (0, 0) by
0x46fa3c, the texts are centred on x 300) ✅. Colours: 0–63 are the global palette `0x5735e4`
(the system colours, identical to `SYS_PAL` of `MDKFONT.FTI` after every level that reaches state
6 ✅), 64–255 come from the page's image (the first 192 bytes of each image's palette are the
same system colours, index 0 aside) ✅. Fonts: `FONTBIG` (0x415a20, baseline y) and `FONTSML`
(0x415bd8); their widths count 6 / 4 pixels for a missing glyph ✅.

**Entry** (`0x431b00(new_game)`) ✅: loads `STATS.MTI` (the head's textures) and `STATS.BNI`, the
sounds `CGUN` (loaded with flag 1, probably looping ❓), `SNIPER`, `RICO1`–`3`, `ALDIE`,
`XGHEAD1`/`2`, `TELETYPE`, parses the model `XGHEAD`, copies the global palette into the working
palette `0x57f464` with colours 64–255 from `PAL`, and looks up the `ST_*` texts. Callers: after the
stream while the index is below 4 (0x401cb8, `new_game` = 0, starts at the intermission); a new
game (0x4240a0) and loading a kind-6 save (0x40a51c, 0x430930) pass 1 and start at the briefing.
The menu has a debug key (`D`, `0x57ea60`, under a condition not checked ❓) that fills the counters
with random numbers and enters with 0. No music is started ❓ (the BNI has none).

**Phases** (`0x57f428`, run by 0x43200c; each phase initialises itself on its first frame,
`0x57f424`) ✅:

| # | Function | Shows | Palette 64–255 | Next |
| --- | --- | --- | --- | --- |
| 2 | 0x432818 | `L1_INTRM` (the same image after every level) | `L1_INTRM` | 4 |
| 4 | 0x4322a0 | the debriefing on `L<i+1>_MAP` | `L<i+1>_MAP` | 1 |
| 1 | 0x4328a4 | the Score-O-matic on a cleared screen (black ❓) | `PAL` | index + 1, save prompt (0x42b520(1)), 3 |
| 3 | 0x4325b0 | the briefing `BRIEF<i+1>` on `L<i+1>_MAP` (after the increment: the next level) | `L<i+1>_MAP` | state ends (the fall) |

(`i` = the level index `0x574268`, so `L1_MAP`–`L5_MAP` and `BRIEF1`–`5` follow the order of play.)

**Fades and keys** ✅:

- Each phase fades in over 0.5 s (`0x57f414 += 2 × dt`; `dt` = the frame time in seconds): the
  working palette (all 256 colours) is blended `(colour·k + c·(256 − k)) >> 8` with
  `k = round(fade × 256)` (0x416f80), `c` = white for the intermission, black for the others. At 1
  the palette is set exactly. Nothing but the image (and the Score-O-matic's title and heads) is
  drawn until the fade-in is complete.
- Keys, read every frame: **Esc** (edge, `0x57ea50`) = skip (`0x57f78c`) and fast; **Fire or Jump
  held** (`0x57eb48`, `0x57eb40`) = fast (`0x57f790`): every fade, typing and counting runs twice as
  fast (typing 4×).
- A phase ends (0x431f1c) only when it has finished showing everything and then any bound control
  is held or pressed (`0x57eb30`…`0x57eba8`) or Esc is pressed; there's no timeout (the values 10/5
  written to `0x57f434` are only a "waiting" marker ✅). It then fades out to black over 0.5 s
  (`0x57f418`, `k = round((1 − fade) × 256)`) and the next phase starts. Holding Fire therefore
  runs through the whole sequence. The text stays drawn during the fade-out.

**Typing** (0x4335c0, used by the debriefing and the briefing) ✅: a character budget
`n = round(count)`; `count` starts at 1 and grows by 15 per second (60 when fast); Esc sets it to
2000 in the briefing. Every frame the text is laid out from the start and drawn with `FONTBIG`
until the budget runs out; a cursor is appended to the last partial line: `_` while
`(ticks & 31) ≤ 15`, a space otherwise (`ticks` accumulates `0x491e18`, 30 per second: it blinks
every 16 ticks). A centred line being typed is placed by the width of the complete line, so it
doesn't move. Each frame where `n` changed plays `TELETYPE` (restarted). Text codes (a decimal
number `N`, possibly negative, may precede the letter):

| Code | Effect |
| --- | --- |
| `\c`, `\Nc` | end the line; the next one is centred on x 300 (or N); y unchanged |
| `\n`, `\Nn` | end the line; x 0, left-aligned; y += 36 (+ N) |
| `\y`, `\Ny` | end the line; x 0, left-aligned; y += 36 (or y += N) |
| `\x`, `\Nx` | end the line; left-aligned at x N (or 0); y unchanged |
| `\Np` | pause: the budget loses N characters (only while counting) |
| `\d`, `\i` | characters count against the budget (default) / appear instantly |

Characters and spaces cost 1, codes cost nothing. The texts only use `\c`, `\n` and `\20n`.

**Intermission** (phase 2) ✅: `L1_INTRM` (Kurt, Dr. Hawkins and Bones in the ship), fading in from
white, until a key.

**Debriefing** (phase 4) ✅: three texts typed one after the other at y (baseline of the first line)
64, 120 and 300: `DEBTOP` ("Debriefing"), the result `DEB<i+1><r>`, `DEBBOT` ("More..."). The first
starts with `count` = 1, the next ones with 0; finished texts are redrawn in full. Each Esc press
finishes the current text and starts the next (the third press ends the page). `r` comes from the
town flags kept at the end of the level (`0x57440f` = the global flags `0x573b5c`, bits 31 = a
second town is threatened, 30 = the level's town was flattened, 29 = the second town was
flattened):

| bits 31–29 | 000 | 001 | 010 | 011 | 100 | 101 | 110 | 111 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| text | `S` | `S` | `F` | `S` | `SS` | `SF` | `FS` | `FF` |

`DEB1`–`DEB4` exist with `S`, `F`, `FS`, `SS`, `SF`; there is no `FF` text (the lookup would fail ❓).
`DEB1SF` has six lines, so its last one (y 300) overlaps "More..." ✅ (layout).

**Score-O-matic** (phase 1) ✅. Always drawn: the spinning heads, `ST_SCR` "Score-O-matic" (`FONTBIG`
centred, baseline 28) and `ST_DAMP` "NAME: Kurt Hectic" (`FONTSML` centred, baseline 48). Then six
rows appear one at a time (`0x57f410` = the current row):

| Row | Label | Value (`0x57f3e0[row]` counts up to) | Bar full at | Text | Start (x, y, w, s) | End |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | `ST_SHF` "Shots fired" | `0x573c3c` | the value | `%d` | 300, 85, 240, 256 | 180, 75, 120, 128 |
| 1 | `ST_ACC` "Accuracy" | `0x573c40 × 100 / 0x573c3c` (0 if none) | 100 | `%d%%` | 300, 155, 240, 256 | 420, 75, 120, 128 |
| 2 | `ST_SNF` "Sniper rounds fired" | `0x573c44` | the value | `%d` | 300, 155, 240, 256 | 180, 125, 120, 128 |
| 3 | `ST_ACC` "Accuracy" | `0x573c48 × 100 / 0x573c44` | 100 | `%d%%` | 300, 225, 240, 256 | 420, 125, 120, 128 |
| 4 | `ST_KILL` "Kills" | `0x573c54` | `0x573c50` | `%d/%d` (count/total) | 300, 225, 240, 256 | 300, 175, 120, 128 |
| 5 | `ST_HEAD` "Head shots" | `0x573c4c` | — | heads | 300, 255, 240, 256 | same |

(tables at 0x491b78 and 0x491bd8; integer percentages, truncated.)

- **Drawing a row** (0x432de0) with its slide `t` (`0x57f3f8[row]`, 0…1): `x, y, w, s` are lerped
  from start to end and rounded; the label is `FONTBIG` scaled by `s / 256` (nearest-neighbour,
  0x415d8c), centred on `x` with baseline `y`. The bar is at `bx = x − w/2`, `by = round(y + 18·s/256)`,
  16 pixels high, filled with colour 63 for `w × value / full` pixels (nothing else: no frame).
  The value text is `FONTSML`, right-aligned 8 pixels left of the bar (`bx − width − 8`), baseline
  `by + 14`.
- **Sequence of a row** (rows 0–4): wait 0.5 s (`0x57f42c`, the row is hidden), play `SNIPER` and
  show the row big (t = 0); wait 0.5 s (`0x57f430`); count: each frame the value grows by
  `max(1, round(target × dt × 0.5))` (so about 2 s whatever the target; × 2 when fast, the whole
  target on Esc) and plays `CGUN` (rows 0–3) or `ALDIE` (row 4) unless already playing; the
  accuracy rows also play a random `RICO1`–`3` one frame in 8. When the value reaches the target
  the slide starts (`t += 2 × dt`, 0.5 s; Esc snaps it to 1), `CGUN` is stopped and the next row
  begins its 0.5 s wait. Rows keep sliding while the next ones appear.
- **Head shots** (0x433268, row 5, skipped entirely when the option `0x5742dc` is 0): the label
  stays at (300, 255) at full size. After the `SNIPER` wait and the 0.5 s wait, one head per second
  (0.5 s when fast; all at once and silently on Esc; nothing if the count is 0): the counter goes up, `XGHEAD1` or `XGHEAD2` plays at random, and
  while the counter is below `2 × perrow` a head appears. `perrow` = the count if below 5 (one row),
  `(count + 1) / 2` up to 16, else 8 (16 heads at most). Head `k` of a row of `m` heads is placed at
  `x = 20 (k + 1) / (m + 1) − 10`, `y = 8` (depth), `z = −3` (first row) or `−4.5` (second row),
  scale 0.8, and spins about z at 157°/s (`obj+0x4c`). The view (0x432b74): camera at the origin
  looking along +y, focal length 250 px (zoom 2.4), centre (300, 180), so on screen the heads are
  at `300 + 31.25 x` and y ≈ 274 / 321 (❓ sign: below the label, as it must be). Once all are
  counted, the page waits for a key.
- `XGHEAD` is a simple textured box (8 vertices, 12 triangles; `XG_BOD` 256 × 283, `XG_BACK`
  128 × 128 and colour 255 from `STATS.MTI`), drawn with the level renderer (0x46dba0,
  `model_draw_parts`) and the `PAL` colours.

**Briefing** (phase 3) ✅: on entry the inventory is emptied (`0x5743ef`, `0x57432c`…), health
raised to 100 (`0x574324`), then `BRIEF<i+1>` is typed at y 32 on `L<i+1>_MAP` ("!!!Newsflash!!!",
20 pixels of extra space, then four or five centred lines 36 apart). Esc shows all of it and ends
the page at once. After the fade-out state 6 returns and the fall starts.

**Sounds** ✅: `SNIPER` (a Score-O-matic row appears), `CGUN` (counting, rows 0–3), `RICO1`–`3`
(accuracy rows, random), `ALDIE` (counting kills), `XGHEAD1`/`XGHEAD2` (each head shot),
`TELETYPE` (each typed character); all from `STATS.BNI`.

## The fall (state 2, `fall_3d.c`)

Kurt falls from orbit onto the minecrawler before each level (not before LEVEL5, which loads
directly). Init 0x410018, each frame 0x4114a4 (intro 0x41106c), cleanup 0x410b80. `n` below is the
level index + 1 (1–5). Times are in seconds (`t`, `0x5209c4`, counted from the end of the intro) or
ticks (1/30 s); `dt` is the frame time in seconds (`0x491e24`). World units "u", Z up. The files are
described in [formats.md](formats.md#fall-files-fall3d); `tools/python/fall3d_dump.py` lists and
exports them.

### Loading (0x410018) ✅

- `FALL3D/FALL3D_n.MTI` (textures, see formats.md), `FALL3D/FALL3D.BNI` (models, palettes,
  images), `FALL3D/FALL3D.SNI` (sounds). The level's `TRAVSPRT.BNI` isn't loaded: the fall BNI has
  its own copies of the HUD images (`SC_STAT`, `SC_BSTAT`, `SNIP_TXT`, `PICKUPS`).
- Models (table 0x490ca4/0x490cbc, slot = byte & 0x7F, bit 7 = the model has named parts):
  `KURT` 1, `MISSILE` 3, `CHUTE` 4, `BONES` 5, `SW_BONES`…`SW_KEY` 6–23 (the pickups), `EXPLODE` 24.
  Slot 2 is `RADAR`, a model built in code (0x412f94, see below). Model animations: `KURTANIM`,
  `KURT_HIT`, `BONESANM`.
- The palettes `FALLPn` (the fall) and `SPACEPAL` (the intro) get colour 0 forced to black. The
  intro starts on `SPACEPAL`.
- Difficulty (`0x57423e`: 0 easy, 1 normal, 2 hard) and level index `i` (0–4) set ✅:

  | Variable | Easy | Normal | Hard | Meaning |
  | --- | --- | --- | --- | --- |
  | `0x5209d4` | 117.65 × (1 + 0.1 i) | 117.65 × (1 + 0.2 i) | 117.65 × (1 + i / 3) | radar beam speed (u/s) |
  | `0x5209dc` | 2 + i / 5 | 2 + i / 3 | 2 + i / 2 | missiles per detection (integer division, + 0 or 1 at random) |
  | `0x5209d8` | 7.5 − i | 6.5 − i | 5.5 − i | missile aim spread (u) |
  | `0x5209e0` | 32 − i | 32 − 3 i | 32 − 5 i | ticks between missiles (+ 0–31) |
  | `0x5209e4` | 63 − 3 i | 63 − 7 i | 63 − 9 i | ticks before the next radar (+ 0–63) |

- In the first level's fall (index 0) the message `FALL_T1` ("Avoid the RADAR!") is queued
  (0x425400, flag 1, 3 s).
- Bones falls with Kurt when the index is above 3 (`0x5208b8`), i.e. only at index 4 (LEVEL8).
- `WINDLOOP` starts at volume 0.

### Intro in space (0x41106c, 150 ticks = 5 s) ✅

A countdown `0x520a7c` from 150 ticks; `f = 1 − ticks left / 150` (0 → 1). Camera at (0, 0, 0)
looking down (same projection as the fall). Each frame, in this order:

1. `SPACE` (600 × 360) copied to the screen as the background.
2. `MOON` (128²) centred at (300, 270 − 90 f), scaled (64 + 256 f) / 256 (32 → 160 px).
3. `EARTH` (512²) centred at (300, 488 − 224 f), scaled (300 + 128 f) / 256 horizontally and
   (100 + 42 f) / 256 vertically (600 × 200 → 856 × 284 px: a flattened disc rising from below).
4. From 90 ticks left (after 2 s): Kurt (`KURT`, `KURTANIM` looping, angles +0x4c = 90°,
   +0x13c = −90°) flies in: `e = 1 − (1 − min((90 − left) / 60, 1))²` (ease out), position
   (30 e − 30, 10 e − 10, −10 e), i.e. from the camera's position (lower left on screen) to 10 u
   below the camera in 2 s.

Palette: fade in from black over the first 2 s (palette × `1 − (left − 90) / 60`, 0x410c28), plain
`SPACEPAL` from 91 to 60 ticks left, then fade to white over the last 2 s (0x410cc0 with
`1 − (60 − left) / 60`, see [Palette effects](#palette-effects-0x5209c8)). The wind (`0x5209b8`)
rises from 0 to 0xC00 between 120 and 60 ticks left (`((120 − left) × 12 / 60) << 8`); its sound
volume is `0x5209b8 × 0x5000 / 0xC00` every frame of the whole fall.

At 0 ticks: blend tables rebuilt for `FALLPn` (0x410874), the first radar in 7–22 ticks, the first
pickup in 31–62 ticks (if the level has any), Kurt placed at z = 5270 (x, y stay 0), Bones (if any)
at (0, 0, 5290) with `BONESANM`.

### Kurt (0x413158) ✅

- Falls at a constant 66.67 u/s (z −= 66.67 dt); after 30 s he's at z ≈ 3270. `KURTANIM` loops;
  when hit, `KURT_HIT` plays once, then `KURTANIM` again (it loops forever once he's dead).
- Steering (until t = 30 s), per axis like Kurt's walk (`vel_accel_dt`, 0x409270): a key sets the
  acceleration to 11.765 u/s per tick (352.9 u/s²) up to 117.65 u/s, pressing the opposite
  direction first resets the speed to one step; without a key the speed drops by 11.765 u/s per
  tick to 0. `0x57eb30`/`0x57eb34` give −x/+x, `0x57eb38`/`0x57eb3c` +y/−y (which physical keys
  these are ❓: left, right, up, down); analog axes `0x57ea18` (x) and −`0x57ea1c` (y) scale both
  values.
- Limits: |x| ≤ 58.82 (1000/17), |y| ≤ 35.29 (600/17); hitting a limit zeroes that speed.
- After 30 s: `K_FINISH` plays once, and each frame `v = (v − 2 p) × 0.5` per axis: he's pulled
  back to the centre.
- Collision box: x ± 4, y ± 4, z ± 5 around him (+0x198…+0x1ac); missiles and pickups test the
  segment of their last move against it (0x45ef80).

### Camera and projection ✅

- Position (0x413440): (0.85 x, 0.85 y, z + 10) of Kurt until t = 30 s; then x, y still follow and z
  moves by `vz × dt` with `vz` from −66.67 u/s rising by 33.33 u/s² to 0: the camera stops in 2 s,
  66.7 u lower, while Kurt keeps falling away from it. The wind level (`0x5209b8`) follows
  `−vz × 0.015 × 3072` (0xC00 → 0).
- It looks straight down; world +x is right and +y is up on screen:
  `sx = 300 + 250 (x − cx) / (cz − z)`, `sy = 180 − 250 (y − cy) / (cz − z)` (focal 250 px on the
  600 × 360 view; horizontal FOV 100.4°, vertical 71.5°). Kurt, 10 u below, is drawn at
  (300 + 3.75 x, 180 − 3.75 y): at most ±220 × ±132 px from the centre.
- Models are sorted by depth (a key per object, ascending z, 0x411aa4) and drawn in that order:
  the model at its z, the chute at z + 2, the missile's smoke trail (0x439454) at 0, an explosion at
  camera z + 5 (always on top); an entry at z + 10 for missiles (+0x108, 0–8) has no drawing code,
  and a `PICK` sprite for objects with +0x10c set is never used ❓.

### Ground (0x41357c) ✅

Not 3D: the texture `LEVELn` (1024², `FALLPn` palette) is mapped affinely onto the whole 600 × 360
view, before the models. With `S = cz / 5280` texels per pixel:

- `u = 512 + 0.36 cx + S (sx − 300)`, `v = A − 0.36 cy + S (sy − 180)`,
  `A = 824 − 624 t / 33` (a pixel at the view centre is the texel (512 + 0.36 cx, A − 0.36 cy)).
- So the ground zooms in as the camera drops (S from ≈ 1 to 0.62 at 30 s), slides 0.36 texels
  per unit of camera movement (parallax, faster than a plane at z = 0 would), and scrolls down the
  screen at 18.9 texels/s. The texture isn't wrapped.
- **The minecrawler** sits at texel (512, A): its sprite `Ln_C0001`–`Ln_C0008` (64 × 108, 8 frames
  at 15 fps: `0x520920 += ticks × 0.5`, modulo 8, palette index 0 transparent) is drawn centred at
  `(300 − 0.36 cx / S, 180 + 0.36 cy / S)` scaled by `0.75 / S` (sprite scale `192 / S`, 256 = 1:1).
  Its sound `C_GRIND` loops at volume `(min(t / 30, 1) + 2) / 3` (2/3 → full).
- **Its track** is written into `LEVELn` itself each frame (0x41357c): with
  `R = round(A − h × 80 / 256)` (h = 108, so ≈ A − 34, near the front of the sprite) and `n` = the
  previous `R` (initially 1024) − R, at least 24, rows R … R + n − 1 of `PODn` (64 × 1024) replace
  the ground's columns `512 − w … 512 + w − 1` of the same rows, `w = round(16 + 2 j / 3)` for the
  j-th row (j < 24), 32 after: a groove 32 texels wide under the crawler widening to 64 behind it.
  The first frame writes the track from ≈ row 790 to the bottom.
- **Haze** (`ZOOMnnnn`, 16 frames, the next one each frame): each record covers two screen rows
  and gives a byte `b` (1–8) per pixel of the left and right parts of the row (in groups of 4
  pixels; the middle part is plain); those pixels use blend table `k + b` instead of the palette, `k = 0x5209b8 >> 8` (the wind level, 12
  during the fall). Table `j` (1–24) blends toward white by `a[j − 1] / 256`,
  `a` = 0 ×8, 3, 6, 12, 18, 24, 48, 72, 96, 120, 144, 168, 192, 215, 230, 245, 255 (0x490d1c); at
  k = 12 that's 24/256 (b = 1) to 192/256 (b = 8): white radial speed streaks around a clear centre,
  fading out with the wind at the start and the end (k = 0 would pick the 50 % green table, an
  unintended edge case).

### Radars (0x4130ac create, 0x412af8 update) ✅

One at a time. The first appears 7–22 ticks after the intro, the next `0x5209e4` + 0–63 ticks after
one disappears (`R_START` plays).

- **Model** `RADAR` (0x412f94): 25 vertices recomputed every frame, 46 triangles (0x40fec0,
  `u8 v0, v1, v2, colour`): a fan of 6 from vertex 0 to ring 1 (colour 0), rings 1–2, 2–3, 3–4 (12
  each, colours 1–3) and a cap on ring 4 (4 triangles, colour 4). Colour c is material
  −(0x405 + c) (special materials 1029–1033), presumably the translucent green tables built at
  `0x5738e4` (palette blended toward (0, 255, 0) by 48, 64, 80, 96, 128 / 256) ❓.
- Placed at (−4 cx, −4 cy, 0). Ring k (1–4) is a hexagon (0°, 60°, … from (0.5, 0.866)) centred at
  the fraction `1 − 2^−k` of the way from the base to the beam spot, radius `r × (1 − 2^−k)`: a
  horn-shaped beam ending in a disc of radius r around the spot.
- **Extending**: the spot rises at 3000 u/s towards the target height `z_t` = Kurt z − 3, its xy
  following the line from (0, 0) to the target, r = 10 × z / z_t. When it arrives it takes a new
  random target (x ± 58.82, y ± 35.29).
- **Tracking** (spot at `z_t`): velocity `v = 0.75 v + 0.25 × speed × unit(target − spot)` in xy
  (speed = `0x5209d4`), r = 10; after 30 ticks or when within 2.94 u (on each axis) of the target
  (`R_MOVE`), it picks a new target (0x412a38): one of Kurt, the falling pickups, and random points
  (± 58.82, ± 35.29) to make 12 choices at most (up to 3 random ones), chosen uniformly.
- **Detection**: Kurt's xy within 15 u of the spot (`K_SEEN`): the radar retracts (the spot drops
  at 1500 u/s and the radar goes when it reaches 0), `0x5209dc` + 0/1 missiles are added to the
  launch queue with the first one next tick, and the screen flashes (target 0.75 or lower by 0.5,
  at 3/s).

### Missiles (0x412568 launch, 0x411ee8 update) ✅

- Launched from the queue every `0x5209e0` + 0–31 ticks (`M_LNCH`), each one also whitening the
  screen by 0.2 (to 0.5 at most).
- Start at (0, 0, 0) with velocity (250 sin a, 250 cos a, 250), `a` random, a random aim offset
  (±spread, ±spread, 0) with spread `0x5209d8`, and a smoke trail (0x439088).
- Each frame: move; while below 0.75 × Kurt's z, z moves 3 × more (4 × its vertical speed); the
  `MISSILE` model is oriented along its velocity (0x4123e8).
- For 60 ticks it just flies; then it homes: with `dz` = Kurt z − its z, it aims at Kurt +
  (offset x, offset y, −min(dz / 225, 10) × 66.67) and steers `v = 0.8 v + 0.2 × 250 × unit`. Once
  it's more than 5 u above Kurt it has passed (`M_PASS`) and is removed 60 ticks later.
- **Hit** (segment vs Kurt's box, until t = 30 s): `EXPLODE1`/`EXPLODE2` and one of `K_HIT1`–`K_HIT7`;
  damage 4 (easy), 4 + rand(8) (normal), twice 4 + rand(8) (hard), health clamped at 0. The missile
  becomes an explosion: model `EXPLODE` with the animated `EXPLODE` texture (26 frames), following
  Kurt's z, frame = ticks since the hit, scale = 2 × frame / 26, a random yaw, removed after 26 ticks.

### Pickups (0x4128fc spawn, 0x41275c update) ✅

- `FALLPU_n` lists names of `CMI`-style pickups (`SW_HOME`, `SW_GATT`, `SW_HBOMB`, `SW_SGREN`);
  they're dropped from the last one to the first, the first 31–62 ticks after the intro, then every
  31–158 ticks. Level 1: `SW_HOME`, `SW_GATT`, `SW_HOME`; levels 2–5: `SW_HOME`, `SW_SGREN`,
  `SW_HBOMB`, `SW_GATT` (in drop order).
- Spawn (`P_FALL`): its model, at (±55.88, ±33.53, Kurt z + 15) (0.95 × Kurt's range, uniform),
  falling at 133.3 u/s (twice Kurt's speed), for 30–93 ticks.
- Then its chute opens (`CHUTE` model at z + 2, `P_CHUTE`): it brakes by 66.67 u/s² to 50 u/s and
  spins at 30°/s. Kurt catches up with it.
- Taken when its last move crosses Kurt's box (`P_COLL`, `K_COLL1`/`K_COLL2`), added to the
  inventory as in the level (0x46d6b0: `SW_HOME` etc.); removed once it's above the camera.

### Bones (0x4133b8, index 4 only) ✅

Starts 20 u above Kurt at (0, 0) and falls at 74.07 u/s, overtaking him; `BONES` plays once when he
passes below Kurt.

### Palette effects (`0x5209c8`) ✅

The fall palette `FALLPn` is shown through a "brightness" `b` (0x410cc0: each component
`(c × k + (256 − k) × 255) >> 8`, `k = round(256 × clamp(b, 0, 1))`, colour 0 kept except in the
first second): b < 1 is whiter.

- First second: b = t (from white).
- Normal: b moves towards a target (`0x5209d0`) at a rate (`0x5209cc`); once reached, a target
  below 1 is replaced by 1 at 0.5/s, and at 1 there's a 1/32 chance per frame of a flicker to 0.9
  at 0.5/s. Detection sets the rate to 3 and lowers the target by 0.5 (≥ 0.75), a launch by 0.2
  (≥ 0.5). A hit sets b to 3 (no visible effect, delays the flicker).
- t > 31 s: palette × (1 − (t − 31) / 2) (0x410c28), black at 33 s.

### Death ✅

Health at 0 (hit): b goes from 3 down by dt. While b ≥ 1, the red component of colours 1–254
rises by 5 per tick (only every third byte from offset 3: the screen turns red) and `SKULL` (256²)
is drawn centred at (300, 180) scaled by the smallest of those red values / 256 (256 = 1:1); below
1 the palette fades to black (skull at full size); at 0 the fall ends and, the health being 0, the
game returns to the menu (game over).

### HUD and end ✅

- Each frame after the scene: messages (0x425474), the health box (`SC_STAT`, 0x420830) and the
  inventory (`PICKUPS`, 0x46cce4), as in the level.
- At t > 33 s the fall ends (0x4114a4 returns 1): the fall files are freed (0x410b80) and the level
  loads (0x41ba68) with the health (`0x574324`) and inventory (with the pickups) as they are; the
  main loop also sets `0x574270`–`0x574278` to 1000 ❓.
- Stereo mode (`0x574318`, 3D glasses ❓) draws everything twice with eye offsets (`0x491cc8`).
- Sounds (`FALL3D.SNI`): `WINDLOOP`, `C_GRIND` (loops), `EXPLODE1`/`2`, `R_START`, `R_MOVE`,
  `M_PASS`, `M_LNCH`, `P_CHUTE`, `P_COLL`, `P_FALL`, `BONES`, `K_HIT1`–`7`, `K_FINISH`,
  `K_COLL1`/`2`, `K_SEEN`. No music.
- Loaded but unused by the fall code ❓: `FLARE1`–`FLARE4`, `BANG` (a 26-frame RLE animation),
  `PICK`.

## Saving and loading (`savegame.c`, `optload.c`)

- **Kinds** (`GAME` type): 3 = the start of a level (at its entry point, no fall), 6 = before a
  level (the statistics and briefing, then the fall), 1003 = a full snapshot.
- **F2** (`0x42b520(0)`, only while playing a level: game state 3, no menu, no cutscene, the level
  not over, no `X_STRIKE` out) writes a full snapshot after asking for a name (`SV_TITLE` "Name for
  Saved Game", up to 8 letters, digits, `_`, `$`); F3 opens the list. After each level the
  statistics screen asks `SV_ASK` "Save Game?" and writes a type 6 (type 3 before the last level)
  named after the level number.
- **Death** (`damp_control` ≈ 0x466b40, once the red flash passes 255): the death counter
  `0x574407` goes up, a light save is written to `LASTGAME.SAV` and the game goes back to the main
  menu, where `OPT0` "Continue" loads it: the level starts again from its beginning with 100 health
  and nothing in the inventory. `LASTGAME.SAV` is deleted when the game quits. There are no
  checkpoints between arenas. The difficulty isn't saved (`Skill` in `MDK.CFG`).
- **Files** `SAVES/<name>.SAV`: `u32 size, u32 checksum` (byte sum from offset 8, as stored), then
  packets `char tag[4], u32 size, data`. The first, `SAVE` (2 bytes, plain), is an XOR key and
  increment: every later byte is `b ^ key`, then `key += inc`. Packets (table 0x4919fc; sizes must
  match): `THMB` (768-byte palette + a 64×45 thumbnail), `GAME` (24: type, level index 0–5,
  unused, health 1–150 (100 in light saves), deaths, `0x57440b`), then for full snapshots `MORE`
  (52: the size of `LEVELn.CMI` as a version, the minecrawler timers, …), `PLAY` (239: raw
  `0x574324…`: health, inventory, ammo, clip), `DAMP` (724: Kurt's block `0x5739c0…`, with the
  script variables and global flags), `CAME` (200, the camera), per arena `AREN` (0x466, the arena)
  with its `ALIE` objects (0x32e each) and `FAND` fans (72), `BULL` ×3 (the sniper rounds), `SEND`.
  Pointers are stored as offsets into the arenas or the CMI, objects as sequential ids.
- **Loading** (0x430930) checks the size and checksum and resets the game (health 100, empty
  inventory and ammo). A full snapshot reloads the level without entering an arena, restores
  Kurt, the camera, each arena and its objects and fans, and re-enters Kurt's arena: he's back
  exactly where he was.
- **The list** (0x428cfc): `SAVES/*.SAV` by name, 13 rows, `SVOPT1` "Select Saved Game", `SVOPT3`
  "No Saved Games Found", `SVBAD` "Invalid/Corrupt File"; the preview is `MISC/LOAD_n.LBB` (n from
  {7, 6, 3, 4, 8, 5} by level) for light saves or the thumbnail.
- The inventory and ammo never carry over to the next level (0x4325b0 clears them).
- **In the port** (`GameState`): light saves as JSON in `user://saves/<NAME>.sav`, `LASTGAME` on
  death with "Continue" in the menu, and the "Saved Game" list. The F2 snapshot and the save prompt
  after a level aren't done yet.

## The minecrawler's timer (0x4240c4)

Each level but the last gives Kurt 45, 30 or 20 minutes (by difficulty: 81000, 54000, 36000 ticks
at `0x574270`) before the minecrawler flattens the town it's heading for. Then the screen shakes
(5), the message `OOT_L1`–`OOT_L5` ("There goes Laguna Beach!", "Bye Bye Lindfield!", …, flags 3,
5 s) shows and the global flag 30 (`0x573b5f` & 0x40) is set, which the debriefing reads
(`DEB1F`…). If the global flag 31 is set (the minecrawler heading for a second town: Sydney,
Hamburg, Moscow, Tokyo, Paris), the message is `OOT_L1A`… and the flag 29 is set instead. The timer
stops at the end of the level (`0x573b60`).

## Screen effects

- **Shake** (`0x573aa8`, raised by `raise_573aa8`/0x467f7c, the mortar, the nuke): each frame above
  1 the 3D view is drawn shifted by random offsets of ±1.64 × shake pixels (rand − 0x4000 ×
  shake × 0.0001, at most ±19 horizontally and ±59 vertically); it drains by 0.25 per tick.
- **White flash** (`0x573b68`, `screen_flash`, the nuke) and **red flash** (`0x573b70`, hits):
  they tint the palette (0x470a88); the white one fades by 4 per tick.

## HUD (0x41e128)

Drawn on the 600×360 view after the 3D scene:

- **Health** (0x420830): the `SC_STAT` image at the bottom right (`600 − (w + 16)`, `360 − (h + 10)`)
  with the health in its middle, in the digits of `SNIP_TXT` (8 pixels wide, 0x420bd0); the number
  blinks (16 ticks out of 32) at 20 or less, and every other frame while invulnerable.
- **Inventory** (0x46cce4): for 60 ticks after a change (`0x574328`), or always in sniper mode, the
  items' `PICKUPS` icons (frame = item type − 1) at `(32 + 48 × slot, 328)` with their count above
  when above 1 (the super chain gun shows its ticks); new items fly there from the pickup's place on
  screen. The selected slot is framed (`48 × slot + 8…+0x37`, 304–351).
- **Health bar** (0x41e3c8) at the top left while `0x573c74` > 0 seconds: a bar of colour 3 (green)
  from x 0 to `health × 500 / 900`, framed in colour 4 up to `max × 500 / 900`, y 4–10. It shows
  for a second the object the chain gun hits if its maximum (`obj+0x2a2`, the last `set_health`)
  is at most 900, or the hit points of the weak part it hits (at most 900); `boss_bar` (opcode 181)
  shows the arena's values while Kurt fires. It goes away early when the object dies or its health
  or maximum are out of 1–900, and in sniper mode.
- **Messages** (0x425400 queues, 0x425474 draws): 4 entries of `time, flags, text` at `0x57ecf0`;
  flag 2 puts the text at the front. The current message (`0x57ec90`, two lines of 36 bytes split at
  the `\n` escape) is drawn in `FONTBIG`, centred on the view with its baseline at y 120 (two
  lines: 105 and 135); a line of 600 pixels or more is drawn in `FONTSML`. With flag 1 it grows
  from nothing to full size in 0.5 s (scaled about the baseline, the lines at 120 ∓ 15 × scale)
  and shrinks back after its time; its time runs twice as fast while others wait. Sources: pickups
  (flag 1, 2 s), `hud_message` (opcode 247: the practice room's hints, the bones' countdown, …),
  the level timer (flags 3, 5 s), `FALL_T1` "Avoid the RADAR!" (the first level's fall, flag 1,
  3 s) and `NODIE` (a cheat, flags 3, 2 s).
- In sniper mode: zoom level, ammo types (`SNIP_L1`–`SNIP_L6`, `SNIP_W1`–`SNIP_W6`) and counts,
  range (`SNIP_RNG`).

## Camera (`camera_update`)

- Distance D = 8 u behind Kurt's feet, pivot height H = 4.5 u (4.0 in sniper mode).
- Pitch p (positive looks down) = the arena's pitch (DTI block 2, eased as 0.85·old + 0.15·new per
  tick) + the look offset (look up/down keys, 90 °/s, total −60…+90°, returns at 200 °/s)
  − 40 × smoothed vertical speed + min(air ticks × 0.667, 40) while airborne (decays at 40 °/s).
- Position: feet + facing·(5(1 − cos p) − D·cos p) + up·(H + D·sin p) when p > 0; without the
  5(1 − cos p) term otherwise, and with D·(p + 100)/80 below −20°.
- The camera never gets closer: if a wall is between Kurt's head (z + 5.5) and the camera, Kurt is
  pushed away from it (`camera_clearance`).
- Projection: the 3D view is 600 × 360 with a focal length of 250 px: horizontal FOV 100.4°,
  vertical FOV 71.5°.

## Kurt's sprite (`damp_sprite_draw`, `rle_draw_hotspot`)

Kurt is a 2D sprite: his feet are projected to the screen, and the frame's top-left corner is drawn
at (x − hotspot x, y − 101 − hotspot y), at 1 sprite pixel per pixel of the 600 × 360 view (no
scaling with distance). The Direct3D version draws it as a quad at Kurt's depth. With the default
camera, a 144-pixel frame is about 4.8 u tall, matching his collision box.
