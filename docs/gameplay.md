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
- Ledge grab (`damp_ledge_grab`): while falling and pushing forward, a segment at head height
  (+4.604) is tested; the ledge must be flat (|nz| ≥ 0.85) and faced within 30°, with room above.

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
  it; from level 6 on there's only one strike and it dives into the target (a 450-damage blast).
- **Sounds**: `SNIPERON`, `SNIPEROFF`, `BREATH`, `ZOOM`, `SNIPERSHOT`, `SNIPRELD`, `RASPBER`.
- The port has all of it but the 3D clip on the screen and the iris around the air strike's target
  (`MDKSniperRounds`, `MDKAirStrike`, `SniperOverlay`; the round cameras are `SubViewport`s). The
  air strike's curve goes through the same 5 points with Godot's `Curve3D`, not the original's
  spline parameters (0.5, 1.0, 0.5 ❓).

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
