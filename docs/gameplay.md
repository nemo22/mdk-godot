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
  The strafe acceleration uses the same factors (0.5 on slippery floors). No triangle of any level
  has flag 0x04 and no code sets it (only 0x10/0x20 are set at run time), so slippery floors never
  happen; the port leaves them out.
- Turning slows down by 1.6 °/tick² above 4 °/tick, 0.55 °/tick² below.
- Mouse turning sets the turn speed to 3 × clamp(mouse dx / sensitivity / dt, ±4) °/tick.
- Movement: yaw −= turn × dt; dx = (vf·cos yaw + vs·sin yaw)·dt; dy = (vf·sin yaw − vs·cos yaw)·dt.
- The camera rolls (`0x573910`) by ±0.25 °/tick up to ±10° while the forward and turn axes
  (`0x5014cc`, `0x5014c4`: keys or joystick, not the mouse) are both held and Kurt isn't on a moving
  platform: forward × right banks right; going the other way first jumps 2° back towards level
  (`damp_move` 0x467fa4). Otherwise (`0x57ff74` clear) it levels out by
  clamp(0.35·|roll|, 0.05, 2.5) °/tick (`damp_control`). Sliding sets it to `0.9·roll + 0.1·(90° −
  slope angle)` each frame, the snowboard moves it towards the board's bank at 45 °/s. The port:
  `CameraRoll` (test `tests/camera_roll_test.gd`), the view turns about its axis ❓ (the sense of
  the original's camera roll wasn't checked; positive banks right like an object's roll). The
  port's moving-platform exception is left out.

### Vertical (`damp_vertical`, `damp_gravity`)

- Gravity 64 u/s², falling speed capped at 250 u/s.
- Jump: vertical speed 40 u/s (peak ≈ 12 u), when on the ground and the key was released since the
  last jump. During the first 6 ticks, releasing the key subtracts the remaining ticks × 3.333 u/s.
- Falling faster than 16 u/s starts the fall (700), or the chute (701) if the jump key is held.
- Chute: gravity 21.33 u/s², falling speed braked (256 u/s²) to 8 u/s. The canopy is painted in
  Kurt's frames (below, "The chute's frames"); the port: `Kurt._show_chute`, test
  `tests/chute_test.sh` (`--jump` holds the key).
- Landing faster than 100 u/s is a hard landing (probably damage *(inferred)*).
- 50 units below his arena's lowest point (`arena+0x44e`) Kurt dies: health 0, vertical speed 0,
  the death plays as on a floor (see [bsp.md](bsp.md#floor-contact-damp_gravity-0x469efc); port:
  `MDKScriptRuntime._check_fall_out`, `tests/fall_out_test.gd`).
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

### The chute's frames (`damp_animate` 0x4646a4)

#### Summary

✅ The canopy isn't geometry. No lines or polygons are drawn: it's painted into Kurt's sprite
frames. `K_CHUTE` (8 frames: open, then close) and `K_CHUTEC` (12 frames: the loop) in
`TRAVERSE/TRAVSPRT.BNI` show Kurt hanging under a ribbon chute. It has four or five long elliptical
loops ("bands") fanning up from his hands. `damp_animate` (0x4646a4) picks these frames for state
701, and `damp_sprite_draw` blits them like any other Kurt frame.

✅ The port's bug: `kurt.gd` `STATE_ANIMATIONS[State.CHUTE] = ["K_FLOATC", true]`. `K_FLOATC` is
the end-of-level float (state 1001, after `K_TAKEOF`) and has no canopy. The fix is to play
`K_CHUTE`/`K_CHUTEC` as described below.

#### Frames (decoded from TRAVSPRT.BNI) ✅

| Anim | Frames | Size (px) | Hotspot | Content |
| --- | --- | --- | --- | --- |
| `K_CHUTE` f0–f2 | 3 | 68×120 → 104×190 | (13,30) → (39,49) | Pack deploying, small loops |
| `K_CHUTE` f3 | 1 | 244×249 | (111,132) | Loops half open |
| `K_CHUTE` f4 | 1 | 356×287 | (168,197) | Fully open |
| `K_CHUTE` f5–f7 | 3 | 252×257 → 72×138 | (118,142) → (20,29) | Closing (loops shrink back) |
| `K_CHUTEC` f0–f11 | 12 | ≈339–347 × 288–295 | (185,208) → (155,202) | Open canopy swaying left → right |
| `K_FLOATC` (current port) | 17 | ≈95–124 × 113–139 | | No canopy |

- Colours: Kurt's usual range, indices 16–47. The canopy bands are mostly 36, with 33–37 for the
  shading and 16 (black) for the outlines. Nothing new is needed in the palette.
- Placement: same as every Kurt frame. The top-left is at (x − hx, y − 101 − hy) from his projected
  feet, at 1 pixel per pixel (gameplay.md "Kurt's sprite"). No scaling, rotation or tinting. Turning
  and speed don't affect it: the sway is only the baked ping-pong.

#### Animation logic (`damp_animate`, state 701) ✅

`f` = `0x573a78` (frame counter), `open` = `0x573a44` (chute flag). One step per tick, 30 ticks/s.
In a `K_*` table, `T[0]` is the count and `T[1+k]` the offset of frame k.

```
on entering 701:
    f = 0; play CHUTEOUT; frame = K_CHUTE[0]

each tick in 701:
    if f < 4:                                  # opening: K_CHUTE 0..4, 1 frame/tick
        f = min(f + ticks, 4); frame = K_CHUTE[f]
    elif not open:                             # jump released or landed: close
        if CHUTEON playing: stop CHUTEON; play CHUTEIN
        f += ticks
        if f >= 7: f = 7; anim_priority(0x573a80) = 0   # lets 700/200 take over
        frame = K_CHUTE[f]                     # usually jumps straight to f7 (see below)
    else:                                      # open loop: K_CHUTEC ping-pong
        f += ticks
        if f >= 2*12 + 2: f = 4                # 26 -> wrap
        k = f - 4         if f < 12 + 4        # f 4..15  -> frames 0..11
          = 26 - f        otherwise            # f 16..25 -> frames 10..1
        frame = K_CHUTEC[k]
        play_once_looping(CHUTEON)
        if firing and (0x573aa4 & 1):          # muzzle flash
            flash = K_MUZZF[random], offset (20 + rnd(0..4), rnd(0..4))
```

- One sway cycle is 22 ticks (0.73 s): frames 0→11→1, then back to 0.
- Closing reuses `f`. After the loop `f` is 4–25, so `f` + ticks ≥ 7 almost always. Releasing the
  key during the loop shows `K_CHUTE` f7 (the packed chute) for one frame, then falls through to
  700. ❓ Frames f5–f6 are only seen when closing right after opening (f = 4 or 5).
- `open` is recomputed every frame by `damp_vertical` (0x4694bc) and `damp_gravity` (0x469efc). It
  is 1 while airborne (`0x573a48 ≠ 0`) with the jump key held (`0x50152c`). Releasing the key
  requests state 700 instead. ❓ Landing goes straight to 200 (`K_LAND`), with no closing frames
  (the landing request has a higher priority; not traced).

#### Other effects of the open chute ✅

- Draw list (`arena_build_drawlist` 0x4185f0): while `open`, Kurt's bounding box top (`0x5739f4[5]`, max z) is
  raised by 8.0 (`0x49415c`), so the tall sprite isn't culled or sorted as if it were only his body.
- The vertical physics (gravity 21.33, braked to 8 u/s) and the input tweak in `input_read_axes` (0x408334,
  `0x573a44` changes an axis scale) are already documented in gameplay.md, or not chute-visual. ❓ (input tweak not analysed)

#### Porting notes

- Replace `State.CHUTE: ["K_FLOATC", true]` with logic for the two animations, following the
  pseudo-code above (it can't be a single looping animation).
- The frames reach about 300 px above the anchor. The quad's `custom_aabb` (±50 u) is large
  enough; check the sprite shader doesn't clip frames larger than the body frames.
- Keep `K_FLOATC` for `end_level.gd` (state 1001).

## Collision (`damp_collide_move`, `bsp_sweep_box`)

- Kurt is an axis-aligned box swept through the arena BSP.
  - Horizontal sweeps: half extents (0.6, 0.6, 2.5) centered at z + 3 (so obstacles lower than
    0.5 u are stepped over); 4 slide iterations; slides only if (m·n)² ≤ 0.75·|m|², so walls within
    30° of head-on stop him. The port tests the move 0.5 above the feet against the arena first
    and stops him at such a wall (`Kurt._stop_head_on`, test `tests/head_on_test.sh`).
  - Vertical sweeps: half extents (0.4, 0.4, 2.5) centered at z + 2.51.
- Planes with |nz| < 0.75 are walls: the steepest walkable slope is about 41°.
- Near arena borders, the neighboring arena is also tested. Objects are tested with segment versus
  bounding box.
- Arenas swept: Kurt's and the active second one (`0x573a6c`), not the second while on the
  snowboard (see [engine.md](engine.md), the table of what runs where). The port puts every arena
  on the ray layer and only these on Kurt's layer (`Level.set_solid_arenas`, test
  `tests/kurt_arenas_test.sh`; `--profile` prints them).
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
  right turns him by 45°/s (left turns left, as walking); the mouse turns him as walking, its rate
  clamped to 4 × 45°/s (`damp_control`, `0x5014d4`). Moving forward accelerates by 35 u/s² (above 15 u/s) and raises the cap
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
  count (0x490fd8, 0x490fa8); the loaded rounds as 3D models along keyframes (0x41eb10, 0x490e4c).
  Frame order (0x41e128): world, round cameras, iris, `CROSS`, `SNIPERS2`, the clip (on top).
- **Clip on the screen** (0x41eb10): 4 keys of position, angles (a, b, c) and scale at 0x490e4c:

  | Key | x | y | z | a | b | c | s |
  | --- | --- | --- | --- | --- | --- | --- | --- |
  | 0 | −225 | −242 | 65 | −30 | 180 | 90 | 4 |
  | 1 | −203 | −242 | 107 | 0 | 180 | 0 | 9 |
  | 2 | −176 | −242 | 145 | 0 | 180 | 0 | 9 |
  | 3 | −154 | −242 | 174 | 0 | 180 | 0 | 9 |

  Round i is at `t = timer + i`, drawn when `t ≠ 0` and `t < 3`, all fields interpolated between
  keys `trunc(t)` and `trunc(t) + 1`; matrix `s · Rz(a) · Ry(−b) · Rx(c)` (0x46dfe8). Own projection:
  camera at the origin looking along −Y, screen right +X, down +Z, focal 250 px, centre (300, 180)
  of the view. The model is the shown type's (`SW_SHOT`…`SW_BONES`, `0x5743e8`). At rest round 0
  sits in the chamber (t = 0, hidden) and rounds 1, 2 at keys 1, 2 (bottom left, ≈ 47 px tall);
  after a shot everything slides one key up-left in 0.25 s, key 1 → key 0 shrinking into the
  chamber.
- **Air-strike iris** (0x41ef90): opening `0x573c58` (1 open) and pulse `0x573c5c`, both 1 on
  entering sniper mode. With type 5 shown and the clip timer at 0, the target test (0x4641ac) runs
  each frame; valid, the iris closes by dt (1 s). Other type or invalid: it opens by dt, and at 1
  nothing is drawn. Closed (or pulsing), the pulse falls by dt and wraps to 1. Each scope row (view
  rows 80–359, x 108–492, centre (300, 220)) is filled from both edges inwards: red (200, 0, 0,
  alpha 0x60) to `392 · p²`, darker red (alpha 0xC4) to `376 · p²` (the ring, while `p ≠ 1`), red to
  the hole `384 · o²`, clear inside. Nothing marks the target point itself.
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
    gravity 32 (−220 at most); fans lift it. It moves as a 0.5 box (`bsp_sweep_box`, Kurt's arena
    then the second), which faces stop only from their front: LEVEL6 OLYM_3's grunts are killed by
    a round lobbed through the small opening in their glass wall, past the face behind it that looks
    into their room (y = −149). The port casts a front-face ray reaching 0.5 further and puts the
    round 0.5 off the face. On the arena: `0x491ef0` = the round, the triangle
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
- The port has all of it (`MDKSniperRounds`, `MDKAirStrike`, `SniperOverlay`; the round cameras
  and the clip are `SubViewport`s, the iris is drawn row by row on the HUD). The
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
- **The stream** (state 5, `STREAM/STREAM.BNI`, `STREAM.MTI`): Kurt steers down a generated tube,
  hitting the walls hurts; Bones rescues him (`RESCUE`) after segment 177 or at 1 health; after
  LEVEL8 he follows Gunter to a planet instead. See [The stream](#the-stream-state-5-streamc-).
- **Statistics** (state 6, `MISC/STATS.BNI`, `STATS.MTI`): `L1_INTRM` until a key; the debriefing
  typed at 15 characters per second on `L<n>_MAP`; the Score-O-matic; then the briefing `BRIEFn`
  on the next map (health raised to 100, the inventory emptied). See
  [below](#statistics-and-briefing-state-6).
- **In the port**: the order of play, the loading screen (`LoadingScreen`), the end of level
  (`MDKEndLevel`), the statistics, debriefing and briefing (`StatsScreen`: after a level below
  index 4, and the briefing alone for a new game), the fall after every briefing (`MDKFall`), then
  the next level; the stream after every level but the last (`MDKStream`); the save prompt
  (`SavePrompt`). The Score-O-matic's counts
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

## Rides (`0x573c30`, `damp_control` 0x466368)

Kurt rides an object ("control alien") instead of walking: the snowboard of level 4 and the `XD2`
of level 7's `DANT_9`, and the `XE` bomber of level 7's `DANT_5` (0x46bf40).

**In the port** (`MDKRides`, `MDKSnowboard`, `MDKBomber`, `Kurt.walk_mode`): all three, with their sounds;
`if_is_573c30` (171) tests the ridden object; hits on Kurt go to the `XD2`; the waiting board
(0x800900) is a floor only (0x800 walls off, 0x100 floor on; engine.md "Kurt and objects"), so he
lands on it. Kurt running into a triangle group of his arena hits it (kind 8, 0x46634e), which is how
the board breaks the ice walls; the camera rolls with the board's bank (`CameraRoll.follow`) and
its pivot dips during jumps (`MDKSnowboard.jump_pivot`, `Kurt.camera_pivot`, test
`tests/board_pivot_test.gd`). Tests: `tests/snowboard_test.sh`. Kurt moves each physics step (60 per
second), the objects each tick (30): after the ticks of every step the `XD2` is put where Kurt is
and Kurt where the `XE` is (`MDKRides.follow`), else every other frame drew them up to a unit apart
(`tests/ride_sync_test.gd`). The camera can't lag a platform carrying Kurt: it follows his
interpolated transform each frame.

### The snowboard (`XSNOWB`, 0x46ac4c)

### Overview ✅

The board is not a Kurt state but a **"control alien"**: an object `XSNOWB` whose pointer is kept in
`0x573c30` (the ridden object) with the mode `0x573c34`. `damp_control` (0x466368) dispatches on the
mode instead of calling `damp_move`:

| Mode `0x573c34` | Object | Per-frame function |
| --- | --- | --- |
| `0x10039` | `XD`, `XD2` | 0x46a840 |
| `0x20002` | **`XSNOWB`** | **0x46ac4c** (`snowboard_update`) |
| `0x40031` | `X_STRIKE`, `XE` | 0x46bf40 |

Bits of the mode seen for the board: `0x2` Kurt's chain gun works (0x41a304), `0x20000` board
dispatch, `0x8000` (byte `0x573c35` bit 7) **"grounded"** flag written by the board code itself.
Bit `0x1` is clear, so hits hurt Kurt, not the board (0x46a498/0x46a604). Bit `0x20` clear: Kurt
is still drawn (arena_build_drawlist); the board gets draw flag 8 like the object Kurt stands on ❓.

Kurt keeps his own position/box; each frame the board object is snapped under his feet. The
object's spline **path** is only used as a steering guide (the board's heading is pulled towards the
path direction); the object's path update doesn't move it because the board code sets its stop frame
to the current frame (0x43c258 returns early when `round(t) == obj+0xe6`). ✅

### Getting on ✅

1. Scripts give the board `set_targetable 2` (opcode 41): flag `0x800000` (`obj+0x14a` bit 7).
2. When Kurt lands on a targetable object with `0x800000` (`damp_gravity`), `0x573b84` = the
   object and `0x573b8c` = 1. The board script sees it with `if_player_on_me` (114) and does
   `flags_set 0x6000000` (0x2000000 = **rideable**, 0x4000000 = **controls locked**) and usually
   `flags_clear 6` (no gravity, no collisions for the board object).
3. Next frame, `damp_control` (in the "no ridden object" branch, after `damp_move`): if
   `0x573b84 && 0x573b8c` then `0x573c2c = 0x573b84`; if that object is active (`obj+6`), has flag
   `0x2000000` and Kurt isn't firing (`0x573a38 == 0`) and its type name is `XSNOWB`:
   - `0x573c30` = board, mode `0x20002`;
   - board flags `|= 0x80800`, then `&= ~0x800100` (net: +0x800 Kurt passes through it,
     +0x80000, −0x100 platform, −0x800000 standable);
   - if `0x573b8c`: sniper mode is left (0x4645c8), `0x573b8c` = 0;
   - heading `0x573c28` = board yaw `obj+0x4c` (all scripts: `set_yaw 90` → +Y);
   - forward speed `V` (`0x573b0c`), lateral speed `L` (`0x573b10`), `0x573b14`, `0x573b18` = 0;
   - state request cleared (`0x57ff78`, `0x57ff70` = 0). Kurt's position is **not** changed.

### Getting off ✅

- Every board frame starts with: if health `0x574324 == 0` and `0x5742e0 == 0`, clear `0x2000000`
  (so a dead Kurt falls off).
- Otherwise only scripts clear `0x2000000` (`flags_clear 33554432`, see Level 4 below).
- Next frame `damp_control` (flag clear, mode `0x20000`):
  - Kurt: state 100 (`K_STILL`), priority `0x573a80` = 0, `0x573a48` = 1.0. `V`/`L` are **kept**
    and become his walking forward/strafe speeds (same meaning in `damp_move`), so he keeps
    sliding until the walking friction stops him.
  - The board is thrown: `obj+0x28/0x2c` (velocity) = `(V·cos y + L·sin y, V·sin y − L·cos y) × 30 × 1.1`
    u/s with `y` = Kurt's yaw `0x5739f0`; `obj+0x30` = Kurt's vertical speed `0x573a3c`; gravity
    `obj+0x48` = 64 u/s², friction `obj+0x44` = 0; position = Kurt's position.
  - `SKI`, `SKILAND`, `SKITURN` stopped; `0x573c30` = 0.
  - The scripts then set flags 6 (gravity + collisions), `stop_path`, and kill the board
    (`set_health 0`) once it touches the floor (`if_flag14c_2`).
- 0x43d734 (object removed) also clears `0x573c30` if it's the board.

### Per-frame update `snowboard_update` (0x46ac4c) ✅

Order matters; this is the exact order of the code.

#### Variables

| Name | Address | Meaning |
| --- | --- | --- |
| `V` | `0x573b0c` | forward speed, u/tick, along the heading |
| `L` | `0x573b10` | lateral speed, u/tick (positive = right of the heading) |
| `H` | `0x573c28` | heading (deg) — direction of travel, follows the path |
| `S` | `obj+0x100` | steering / carve angle (deg, ±30; positive = left). Board yaw = `H + S` |
| `P` | `obj+0x13c` | board pitch (deg, 0–360; positive = nose up) |
| `T` | `0x573a58` | ticks the turn key has been held |
| `J` | `0x573a54` | ticks the jump key has been held (50 after a jump) |
| `A` | `0x4920d4` | ticks in the air (for sounds) |
| `G` | `0x573c35 & 0x80` | grounded, as left by the previous frame (see "Board attitude") |
| `E` | | controls enabled: `obj` flag `0x4000000` clear |
| `I` | `0x5014ec` | turn input: 4 × the larger of the turn and strafe keys (`input_read_axes` 0x408334; the strafe on a tie), ±4 °/tick; mouse, when it moved: `4 × clamp(dx/sens/dt, ±4)` (up to 16 °/tick; dx in the walk's units of 3°). `I > 0` lowers `S` (clockwise = right). The port: `MDKSnowboard.turn_input`, `tests/board_steer_test.gd` |
| `F` | `0x5014f0` | forward input: +0.05 forward, −0.05 back; mouse `−dy·0.05·0.5` |
| jump / fire | `0x50152c` / `0x501534` | keys |

Note: `input_read_axes` runs after the mode function in `damp_control`, so inputs are one frame old.

#### 1. Setup

- State request: `0x57ff78` = 201 (`K_SURF`), priority `0x57ff70` = 2.
- `P -= |S| × 0.25` (undo last frame's carve tilt, re-added at the end).
- `(s, c) = (sin H, cos H)`.

#### 2. Steering `S`

```
if E and I > 0:                       # right
    T += ticks
    if S > 0: S = 0                   # reversing snaps to straight
    else:
        rate = (G and T < 15) ? T·I·2/30 : I     # ramp over 15 ticks on the ground
        S = max(S − rate·dt, −30)
elif E and I < 0:                     # left
    T += ticks
    if S < 0: S = 0
    else:
        rate = (G and T < 15) ? T·I·2/30 : I
        S = min(S − rate·dt, +30)
else:
    T = 0
    S moves towards 0 by 3·dt (90 °/s)
```

With keys: up to 4 °/tick (120 °/s), full after 15 ticks; ≈ 15 ticks from 0 to ±30. In the air the
ramp is skipped (full rate at once).

#### 3. Speed (only when `G`)

- If `S ≠ 0`: `L = S × (−0.8333) × V × 0.0125 = −S·V/96` (u/tick). S = +30 → `L = −0.3125·V`
  (left). When `S == 0`, `L` keeps its last value ❓ (tiny).
- If controls are locked (`!E`): `V += 0.05·dt` up to 2.5.
- Else:
  - `F > 0`: if `V < 2.5`: `V = min(V + F·dt, 2.5)` (0.05 u/tick², 45 u/s², up to 75 u/s).
  - `F < 0`: if `V > 1.1667`: `V = max(V + F·dt, 1.1667)` (brake to 35 u/s).
  - `F == 0`: below 1.5: `V = min(V + 0.05·dt, 1.5)`; above: `V = max(V − 0.0027778·dt, 1.5)`
    (cruise 45 u/s; decay 2.5 u/s²).
- In the air (`!G`): `V` unchanged; `L` brakes towards 0 by `0.0055556·dt` (`0x4687a4`, constant
  `0x3bb60b61`).

#### 4. Move ✅

```
fwd = (V·dt·c, V·dt·s)
if V ≠ 0: damp_collide_move(fwd.x, fwd.y, 0, 0.75, default box)
lat = (L·dt·s, −L·dt·c)
if L ≠ 0: damp_collide_move(lat.x, lat.y, 0, 0.75, default box)
```

Same collision as walking (box 0.6×0.6×2.5, slide unless within 30° of head-on). **Walls don't
change `V`.** While riding, `damp_collide_move` doesn't sweep the second arena (`0x573c30 != 0`).
Objects Kurt's box touches set `0x573c2c` (the board itself and objects with flags 0x810 are
skipped).

#### 5. Stick to downhill slopes ✅

If on a floor (`0x573c10`) and `0x573a4c == 0`: `n` = floor normal (`0x573c14`, flipped to
`nz ≥ 0`). If `nz > 0.25` and `m = fwd + lat` (requested, u/frame) gives `m·n = m.x·nx + m.y·ny > 0`
(going down): `vz = min(vz, −(m·n)/dt_s)` (vertical speed `0x573a3c`, u/s).

#### 6. Gravity

`damp_gravity()` (0x469efc) as for walking (64 u/s², ≤ 250 u/s, floor `0x573c10`). On the board it
skips the hard landing (no state 806, no 10 damage). `damp_vertical` isn't called: no fall/chute
states. Then `G = (0x573c10 != 0)`.

#### 7. Board attitude (pitch) ✅

- `f = obj+0xac/0xbc/0xcc` (the board's forward axis, matrix column 0). Front end
  `Fp = pos + 4f + (0,0,−0.01)`, back end `Bp = pos − 4f + (0,0,−0.01)`.
- For each end, a BSP ray from `end + (0,0,3)` down to `end` (0x421708, Kurt's arena; then the second
  arena with 0x421680 if `0x573a68 && !0x573b00`). A hit replaces the end with the hit point.
  So only ground within 3 u **above** the end counts (the end is buried).
- `v` = `Fhit − Bhit` (both), `Fhit − pos` (front only), `pos − Bhit` (back only); none: skip.
- If any hit: `G = true` (0x573c35 |= 0x80) and
  ```
  target = atan2_deg(v.z, |v.xy|)            # 0..360
  if 45 < P < 180: target = 45
  elif 180 <= P < 315: target = 315
  wrap target and P to (−180, 180]
  P moves towards target by 90·dt_s (3 °/tick); if P < 0: P += 360
  ```

#### 8. Slope acceleration (when `G`) ✅

`k = sin P`:
- Nose down (`P > 180`): if `V < 2.6667`: `V = min(V − k·0.066667·dt, 2.6667)` (60·sin u/s², up to
  80 u/s).
- Nose up (`0 < P ≤ 180`): if `V > 1.1667`: `V = max(V − k·0.066667·dt, 1.1667)`.

#### 9. Jump ✅

```
if E and jump key and not (arena == "CMEAT_1" and Kurt.y >= 2131):
    if G and J <= 12:
        vz = 28.5 u/s; Kurt.z += 1; floor 0x573c10 = 0
        J = 50; anim frame 0x573a78 = 0; 0x573a80 = 0
        state request 801 (K_SURFJ), priority 8
    J += ticks
else:
    J = 0
```

The key may be pressed up to 12 ticks before landing (buffer). One jump per press. Peak on flat
ground ≈ 6.3 u, ≈ 27 ticks in the air. Jumping is disabled at the end of corridor `CMEAT_1`
(y ≥ 2131).

#### 10. Sounds ✅ (`SKI`, `SKITURN` loop, flag 1 in `LEVEL4S.SNI`; `SKILAND` one-shot; all 2D)

- In the air (`!G`): `A = round(A + dt)`; if `A >= 7` and `SKI` plays: stop `SKI` and `SKITURN`.
- On the ground: if `A >= 15`: `SKILAND` (restart); `A = 0`; `SKI` (play if not playing);
  `SKITURN` (play if not playing) while `|S| > 22.5`, else stopped.

#### 11. Chain gun ✅

Fire key and `0x573a80 <= 7` and `0x57ff70 <= 7`: start firing (`0x573a38` = 1, `0x46c3e4(1)`);
otherwise stop it. So Kurt fires while riding but not during a jump (priority 8).

#### 12. Follow the path ✅

Path = `obj+0xec` (40-byte keys), time `t = obj+0xf0`. Skipped if `t >= last key frame`.

```
d = |spline(t).xy − Kurt.xy|²; step t by +1 while the distance shrinks; t −= 1
step t by +0.2 while the distance shrinks; t −= 0.2       # forward only
if t changed:
    Q = spline(old t); P2 = spline(t + 0.2)   # the last point evaluated
    obj+0xf0 = t; obj+0xe6 = round(t)          # freeze the object's own path update
    pathHeading = atan2_deg(P2.y − Q.y, P2.x − Q.x)
    # unstick: V >= 1.1667 and Kurt moved < 0.5 u/tick this frame (xy)
    if V >= 1.1667 and |Kurt.xy − previous.xy|/dt < 0.5:
        damp_collide_move(2 × normalize(Q.xy − Kurt.xy), 0, 0.75)
```

If `t` didn't change, `pathHeading` (a stack local) keeps a stale value ❓; the unstick only happens
when `t` advances, so a fully blocked Kurt isn't nudged ❓.

#### 13. Heading ✅

```
if G:
    d = pathHeading − H
    ccw = (0 <= d < 180) or d < −180
    rate = 1.3333 + (ccw ? +S : −S) × 1.3333 × (1/30) × 0.75     # = 4/3 ± S/30 °/tick
else:
    rate = 0.4                                                   # 12 °/s in the air
H = turn_towards(pathHeading, H, rate·dt)          # 0x460968, shortest way, no overshoot, 0..360
Kurt.yaw 0x5739f0 = turn_towards(H, yaw, 360·dt_s)  # 12 °/tick; the camera uses this yaw
```

So the player doesn't really choose the direction: the heading follows the path at 40 °/s,
carving towards a turn (S on the same side) raises it up to 70 °/s, against it lowers it to
10 °/s. The real steering is the lateral drift `L` (up to 0.3125·V sideways, ≈ 17° off the
heading).

#### 14. Place the board ✅

- `obj pos = (Kurt.x, Kurt.y, Kurt.z − 0.25)`; `obj+0x4c` (yaw) `= H + S`; `P += |S| × 0.25`
  (nose up by up to 7.5° while carving).
- `0x57ff74 = 1`: `damp_control` doesn't decay the camera roll.
- Camera roll `0x573910` moves towards the board's bank `obj+0x54` at 45 °/s (1.5 °/tick). The bank
  itself comes from the object engine's automatic banking (yaw changes, ±10°) ❓.

#### 15. Ramming ✅

If Kurt's box touched an object this frame (`0x573c2c`, set in `damp_collide_move`), whose flags
have none of `0x40304000` (not a door 0x100000, swinging 0x400000, 0x4000, 0x40000000) and
`0 < health < 65000`: `object_kill(obj)` (0x43d6d4: death script or explosion) and Kurt takes
5 damage (0x46a498: 3 on easy, 10 on hard; red flash; no knock-down on the board, see below).

### Other effects while riding ✅

- No knock-down: `damp_control` skips it while `0x573c30 != 0` (the damage still counts).
- No ledge grab, no chute, no fall states, no hard-landing damage.
- `damp_collide_move`: second arena not swept; the board end rays do test it.
- Teleports (0x41bce4) move the board too (0x43d7bc).
- Items (`0x46ca38`) still run after the board function.

### Animations ✅ (`LEVEL4S.SNI`, loaded by 0x4671bc into `0x492018` / `0x49201c`)

| State | Anim | Frames | Behaviour (`damp_animate`) |
| --- | --- | --- | --- |
| 201 | `K_SURF` | 8 (72×115, hotspot ≈ (55, 0)) | loops, 1 frame/tick; camera pivot `0x573b7c` = 4.5; firing: muzzle flash every other frame at offset (−42 + rand 5, 12 + rand 5) |
| 801 | `K_SURFJ` | 11 (≈ 74×134), half = 5 | frames 0→5 then holds on 5 in the air; landing (`0x573c10`) with frame > 3 jumps to ≥ 6 and plays to 10, then state 201 (priority 2); landing earlier → 201 at once. Camera pivot: `4.5 − 0.2·frame` below frame 5 (down to 3.7), then `+dt_s` per frame (1 u/s) back to 4.5 |

### Level 4 scripts ✅ (`LEVEL4.CMI`; offsets = file offsets)

Every board script: `follow_path <path>, flags1 0` (absolute, so the spawn position is ignored and
the board sits at key 0), `path_stop_at 0`, `set_path_speed 0`, `set_yaw 90`, `flags_set 0x820`,
then waits for Kurt (`set_targetable 2`, `if_player_on_me`). While riding they run
`group_state_near_player 2, 10, 31, 1, 2` every frame (shows the slope triangle groups around
Kurt).

| Spawned by | Path (keys, frames, ≈ length) | On mount | Events | Dismount (flags_clear 0x2000000) |
| --- | --- | --- | --- | --- |
| `MEAT_1` 0x8ca (after group 7 shatters) | 16 keys, 0–300, 3277 u, (1, −70) → (63, 3038) | The board only becomes rideable when alien `XS` dies: its death script (0xb94) sets arena flag 2 and commands `XSNOWB` to 0xa85. Then `flags_set 0x6000000`, `flags_clear 6` (locked: auto-accelerates to 2.5) | Kurt in rect x −8…8, y 58…100: groups 2 off, `arena_show CMEAT_1`, `ICEXP1`, shatter group 2 (ice wall), wait 0.25 s, groups 5/3, **controls on** (`flags_clear 0x4000000`). Rect x 40…98, y 2542…2586: `arena_show MEAT_3` | box x −50…200, y −2674…3176, z −548…−510; `arena_show NONE` |
| `MEAT_7` 0x13740 | 40 keys, 0–750, 9906 u, (0, 14803) → (−218, 23916) | clear 0x4000006, set 0x6000000 (locked); message `TENBONES` "Pick up 10 red bones for a surprise powerup" (5 s), global var 0 = 0 | rect x −42…17, y 14811…14873: `set_574304 1`, door `X4DOOR` #1000 opens; rect y 14828…14873: controls on | rect x −260…−187, y 23970…24100; `arena_show NONE` |
| `CMEAT_3` 0x23953 | 41 keys, 0–750, 10286 u, (420, 4285) → (−2, 13552) | `group_set_hit_flags 3, 72`; set 0x6000000, clear 6 and 0x4000000 (controls on at once); `TENBONES` | — | box x −1000…1000, y 12000…14000, z −2000…−1960 |
| `MEAT_2` 0x4a0f | 14 keys, 0–200, 3564 u | set 0x6000000, clear 6 and 0x4000000 | — | none in its script ❓ (maybe unused) |

After dismount each script sets flags 6, `stop_path`, and `set_health 0` when the board lands.
CMEAT_3's run goes through MEAT_4 and CMEAT_4 into MEAT_5 (≈ 145 s without keys); MEAT_7's through
CMEAT_7, MEAT_8 and CMEAT_8 into MEAT_10. Whether the normal level reaches MEAT_2's is ❓.

### Constants ✅

| Value | Address | Use |
| --- | --- | --- |
| 0.25 | 0x497a84 | carve tilt `|S|/4`; slope `nz` threshold; unstick 0.5² |
| 3.0 | 0x497a8c | S return rate; ray start height |
| 2.0, 1/30 | 0x497a94, 0x497a9c | steering ramp `T·I·2/30`; unstick distance 2 |
| ±30 | 0x497aa4/0x497aac | S limits |
| −0.8333, 0.0125 | 0x497ab4, 0x497abc | `L = S·(−0.8333)·V·0.0125` |
| 1.5 | 0x497ac4 | cruise speed |
| 0.0027778 | 0x497acc | decay above cruise |
| 0.05 | 0x497ad4 | acceleration |
| 1.16667 | 0x497adc | minimum speed (brake, uphill, unstick) |
| 2.5 | 0x497ae4 | max speed with input / locked |
| 4.0 | 0x497aec | board half length for the rays |
| −0.01 | 0x497af4 | ray end offset |
| 45, 180, 315, ±360 | 0x497afc, 0x497b04, 0x497b0c, 0x497b14/0x497b24 | pitch limits; 45 also roll speed |
| 90 | 0x497b1c (f32) | pitch speed °/s |
| 0.066667 | 0x497b2c | slope acceleration × sin P |
| 2.66667 | 0x497b34 | max downhill speed |
| 22.5 | 0x497b3c | `SKITURN` threshold on |S| |
| −1, 0.2, −0.2 | 0x497b44, 0x497b74, 0x497b4c | path search steps |
| ±180 (f32) | 0x497b54, 0x497b58 | heading direction test |
| 1.33333, 0.75 | 0x497b5c, 0x497b64 | heading rate `1.3333 ± S·1.3333/30·0.75` |
| 0.4 | `0x3ecccccd` | heading rate in the air |
| −0.25 | 0x497b6c | board z below Kurt |
| 360 | 0x497b24 | Kurt yaw follow °/s |
| 0.0055556 | `0x3bb60b61` | air brake of L |
| 28.5 | `0x41e40000` | jump speed u/s |
| 2131.0 | `0x45053000` | CMEAT_1 no-jump y |
| 30, 1.1 | 0x497648 (f32), 0x49764c | board throw velocity factor |
| 64 | `0x42800000` | thrown board gravity |
| 12 / 15 / 7 | code | jump buffer ticks / `SKILAND` air ticks / stop `SKI` air ticks |

### The `XD2` (0x46a840)

**Correction**: 0x46a840 is not the `XE` ride. `damp_control` (0x466368) picks the handler from the
control alien's type name:

| Type | Mode `0x573c34` | Handler |
| --- | --- | --- |
| `XD`, `XD2` | 0x10039 | 0x46a840 (this section) |
| `XSNOWB` | 0x20002 | 0x46ac4c snowboard |
| `X_STRIKE`, `XE` | 0x40031 | 0x46bf40 bomber (see "The `XE` bomber" below) |

Mode bits: byte `0x573c36` 1/2/4 selects the handler; 0x1 → Kurt's damage goes to the ridden
object (0x46a498, 0x46a604: its health −damage unless ≥ 65000, killed at < 1); 0x2 clear →
Kurt's chain gun is off (0x41a304); 0x20 → Kurt isn't added to the draw list (0x418a5b) ❓ (hidden).
0x8, 0x10 unused.

**Which level**: of the walkers only `XD2` in level 7 `DANT_9` gets flag 0x2000000 (opcode 116; the
`XE` of `DANT_5` and the snowboards get 0x6000000). `XD` exists in
levels 3–7 but no script makes it rideable. Model `XD2` (parts `XD1_BACK`, `XD1_IN1`, `XD1_IN2`,
animation `XD2_MOVE`, sound `XDSING`) in `LEVEL7O.MTO` ❓ (what the creature looks like).

**Getting on** (`damp_control`, Kurt not riding, state < 800): candidate `0x573c2c` = an object whose
visible part Kurt's box touched in `damp_collide_move`, or the platform he stands on
(`0x573b84` with `0x573b8c`). Mounts when the candidate is active, has flag 0x2000000, Kurt doesn't
fire (`0x573a38` = 0) and is on the ground (`0x573a48` = 0):
`0x573c30` = object, mode 0x10039, object flag |= 0x80000, ride yaw `0x573c28` = object yaw,
Kurt's position = object position, speeds `0x573b0c/10/14/18` = 0. If Kurt is in the air, the
object's flag 0x2000000 is cleared, the "Unrecognised controlalien" message is logged and nothing
happens ❓.

`DANT_9` `XD2`: follows a path; when killed its death script (127785) makes it indestructible,
slumps it (`anim_once`), and every frame sets flag 0x2000000 only while Kurt is **behind** it
(`if_target_angle` beyond ±135°). Once ridden (`if_is_573c30`): opens the `X7DOOR` doors, swaps the
`XD1_*` parts, health 50, loops its animation; when Kurt enters the box
x 130–183, y 4898–4929 it waits 3.5 s, clears 0x2000000 (Kurt jumps off), commands the `XS`
and dies (health 0).

**Each frame** (0x46a840, called instead of `damp_move`):

- Floor factors from the floor triangle `0x573c10`: accel/friction = 1.0/1.0 on a floor, 0.5/0.1 on
  slippery floors (triangle flag 0x04), 0.75/0.75 in the air.
- Turn: turn axis `0x5014dc` ≠ 0 and turn lock `0x573a58` = 0 → `vel_accel_dt(0x573b14, 0x5014dc,
  0x5014e0)` (Kurt's turn accel/limit: 0.9/4 °/tick, 1.3/6 turbo). Lock `0x573a58`: > 2 → 0;
  1 cleared when the axis ≥ 0; 2 cleared when ≤ 0 ❓ (who sets it).
- Forward: axis `0x5014e4` ≠ 0 → `0x573a88` = 1, `vel_accel_dt(0x573b0c, axis × accel factor,
  0x5014e8)` (Kurt's walk: 0.0444 u/tick², max 0.6667 u/tick = 20 u/s; turbo 0.0889, 40 u/s;
  negative = backwards). No strafing.
- No forward input: `vel_friction(0x573b0c, f × 0.0667, f × 0.1778, 0.6667)` (f = friction
  factor; the first rate below 0.6667 u/tick, the second above).
- No turn input: `vel_friction(0x573b14, 0.4125, 1.6, 4)` (°/tick²).
- `DUMMY` (`0x5744a8`): while any turn/forward input, started if not playing (`0x402fd8(snd, 0)`)
  and its volume set to 0x2000 (0x4032e8, −18.75 dB); loops by its SNI flag; stopped when there's
  no input and on dismount. 2D.
- Ridden object animation fps `+0xe0` = 30 while forward or turn speed ≠ 0, else 0 (freezes).
- Move: dx, dy = conveyor push + `0x573b0c` × dt_ticks × (cos, sin)(ride yaw); ride yaw
  −= `0x573b14` × dt_ticks, wrapped to 0–360 (positive turn = clockwise).
  `damp_collide_move(dx, dy, 0, 0.75, 0, 0)` (Kurt's box; ridden object ignored as obstacle).
- Air ticks `0x573a48`: 0 → +1 when vz (`0x573a3c`) < −16; else reset to 0 when vz > 0 or
  (vz = 0 and on the floor `0x573a18 & 1`), otherwise += dt_ticks. Then `damp_gravity` (0x469efc,
  no jump while riding) and `damp_look_updown` (0x4689c8).
- Fire key (`0x501534`) held: object flag |= 0x1, `ALERT` (`0x574464`, 2D, `0x402fd8(snd, 0)`:
  replays whenever it ended), alarm `0x573aec` = 10 (`if_alarm`, opcode 27, true for scripts).
  Released: flag 0x1 cleared and `0x573aec` = 0 (also silences other alarms that frame ❓).
- Ridden object: yaw = ride yaw, position = Kurt's position. Kurt's animation requests
  `0x57ff78/0x57ff70` = 0 (he stands, `K_STILL` ❓).
- **Camera**: Kurt's yaw `0x5739f0` turns towards the ride yaw by ≤ 360 × dt (0x460968); the normal
  third-person camera follows Kurt ❓ (no ride-specific camera code found).

**Getting off** (`damp_control`, flag 0x2000000 cleared by the script): Kurt state 703 (`K_RJMP`),
`0x573a80` = 7, `0x573a4c` = 1, `0x573a50` = 0, `0x573a5c` = 1, `0x573a54` = 1, vz = 40 u/s,
forward speed `0x573b0c` = 0.6667 u/tick (20 u/s along his yaw), `DUMMY` stopped, `0x573c30` = 0:
a running jump forward. If the ridden object is freed (0x43d734), `0x573c30` = 0 and Kurt takes 50
damage.

### The `XE` bomber (0x46bf40)

Level 7, arena `DANT_5`. Kurt rides the flyer `XE` along a fixed path; the view is top-down and he
drops `XBN_BOMB`s on the ground aliens with a cursor. Mode `0x573c34` = `0x40031`, handler
0x46bf40, HUD 0x46be98, top-down camera 0x4183f0. Units: 1 tick = 1/30 s; `dt` = frame time in s
(`0x491e24`), `dtt` = frame time in ticks (`0x491e20`), `ticks` = whole ticks of the frame
(`0x491e18`).

**In the port** (`MDKBomber`, `BomberOverlay`, `FollowCamera._update_bomber_view`): all of it, test
`tests/bomber_test.sh` (`--bomber[=drop]`). The aiming ray tests the parts of the arena's objects,
then the arena; the sky modes 1 (black) and −1 (nothing drawn: `Environment.BG_KEEP`) are
`Level.show_sky`. Differences: the mouse moves the cursor by a third of its screen motion; damage
passed to Kurt goes through `Kurt.hurt` (it honours invulnerability, unlike 0x46a77c).

#### Globals

| Address | Meaning while riding the `XE` |
| --- | --- |
| `0x573c30` | ridden object (the `XE`) |
| `0x573c34` | mode `0x40031`: 0x40000 handler 0x46bf40; 0x20 Kurt not in the draw list; 0x1 hits on Kurt go to the `XE`; 0x2 clear: chain gun off; 0x10 unused ✅ |
| `0x490de0` | **top-down camera on** (camera_update → 0x4183f0); also a debug toggle ✅ |
| `0x490dec` | top-down camera **height above Kurt** (50 at mount, debug keys move it within 20…200) ✅ |
| `0x490de4`, `0x490de8` | zeroed at mount, otherwise only saved/restored (0x42f30c) ❓ unused |
| `0x573acc`, `0x490e0c` | debug box drawing (0x41e784), switched off at mount ✅ |
| `0x573b0c`, `0x573b10` | cursor x, y (screen pixels of the 600×360 view) ✅ |
| `0x573b14`, `0x573b18` | cursor speed x, y (px/tick) ✅ |
| `0x573c64` | bombs left (0…10) ✅ |
| `0x573c68` | refill timer (s) ✅ |
| `0x573ad0` | fire latch: 999 while the fire key is up ✅ |
| `0x574304` | sky mode (sky_draw 0x475b4c): 0 sky image, 1 black, −1 nothing drawn ✅ |

#### Getting on ✅ (`damp_control` 0x466368, branch "not riding")

Conditions (same path as the snowboard/`XD`): Kurt not in sniper mode, state < 800, after
`damp_move`; candidate `0x573c2c` = an object Kurt's box touched in `damp_collide_move` (or his
platform `0x573b84` with `0x573b8c`). Mount if the candidate is active (`obj+6`), has flag
`0x2000000`, `0x573c30 == 0`, Kurt isn't firing (`0x573a38 == 0`) and its type name is
`X_STRIKE` or `XE`. Unlike the `XD`, Kurt may be in the air.

The `XE` has no gravity/collision flags, health ≠ 0 and no flags 0x10/0x800, so Kurt collides
with it: walking into the hovering `XE` mounts it.

Set at mount:

| What | Value |
| --- | --- |
| Kurt yaw `0x5739f0` | `XE` yaw `obj+0x4c` |
| Kurt position `0x5739c0..c8` | `XE` position `obj+0x10..0x18` |
| mode `0x573c34` | `0x40031` |
| state request `0x57ff78`, priority `0x57ff70` | 0, 0 (Kurt's state isn't changed) |
| `0x490de0` | 1 (top-down camera) |
| `0x490e0c`, `0x490de8`, `0x490de4`, `0x573acc` | 0 |
| `0x490dec` | 50.0 |
| cursor `0x573b0c`, `0x573b10` | 300.0, 180.0 (screen centre) |
| cursor speeds `0x573b14`, `0x573b18` | 0 |
| `0x573c68` | 1.0 |
| `0x573c64` | 10 |
| `0x573ad0` | **not set** (keeps its old value; normally 999 from the last release) |

No `XE` flags are changed, no sound plays (the `XE`'s own `FLY` loop goes on).

#### Per frame: 0x46bf40 ✅

Called by `damp_control` instead of `damp_move` (then 0x46ca38: item selection keys only). No
gravity, no collision, no Kurt animation request.

```
o = 0x573c30
Kurt.yaw = o.yaw                                   # top-down view turns with the XE
H = 0x490dec - dt * 25                             # camera descends 25 u/s (0x497b8c = 25.0)
Kurt.pos = o.pos
if H < 0: H = 0; o.flags |= 0x10                   # camera inside the XE: hide it
0x490dec = H

if o.flags & 0x4000000:                            # controls locked (byte 0x14b bit 2)
    0x573b1c = 0                                   # camera look-pitch offset
    vy = 0                                         # 0x573b18 only; vx isn't cleared
else:
    keys = 0
    if axisX (0x5014f4) != 0: vel_accel_dt(vx, axisX/3, limit 10*axisX); keys |= 4
    if axisY (0x5014fc) != 0: vel_accel_dt(vy, axisY/3, limit 10*axisY); keys |= 8
    if keys == 0 and (mouse dx or dy) and mouse on (0x574236):
        cx += dx / 3; cy += dy / 3; vx = vy = 0    # 0x57eb24/0x57eb28, 0x497b94 = 1/3
    if !(keys & 4): brake(vx, 0.6667)              # 0x4687a4, 0x3f2aaaab
    if !(keys & 8): brake(vy, 0.6667)
    cx = clamp(cx + vx*dtt, 128, 472)              # compared as int bit patterns
    cy = clamp(cy + vy*dtt, 64, 296)

    if fire (0x501534) == 0: 0x573ad0 = 999
    else:
        if 0x573ad0 == 999 and bombs > 0: drop_bomb()
        0x573ad0 -= ticks                          # one bomb per press
    if bombs < 10:
        timer -= dt
        if timer <= 0: bombs += 1; timer = 1.0     # +1 bomb per second
    else: timer = 1.0

if o.health != 10000:                              # damage taken by the XE goes to Kurt
    hurt_kurt_raw(10000 - o.health)                # 0x46a77c
    o.health = 10000
    if Kurt.health (0x574324) < 1:                 # Kurt died
        o.health = 0; object_kill(o)               # 0x43d6d4: XE death script
```

##### Inputs (`input_read_axes` 0x408334) ✅

| Variable | Source | Use |
| --- | --- | --- |
| `0x5014f4` / `0x5014f8` | horizontal axis `h` × 1/3 / × 10 (0x493470, 0x493478). `h` = turn (`0x57eb30` −1, `0x57eb34` +1) or strafe (`0x57eba4` −1, `0x57eba8` +1, or turn keys with the strafe modifier), the larger; joystick analog | cursor x accel (px/tick²) / max speed (px/tick) |
| `0x5014fc` / `0x501500` | vertical axis `v` × 1/3 / × 10. `v` = `0x57eb38` −1 (forward), `0x57eb3c` +1 (back); joystick analog | cursor y |
| `0x501534` | fire (`0x57eb48` or a mapped button) | drop |
| `0x57eb24`, `0x57eb28` | mouse dx, dy this frame (raw units ❓) | cursor, 1/3 px per unit |
| `0x574236` | mouse enabled option | |

So left/right move the cursor left/right, forward/back move it up/down ❓ (physical keys as in the
rest of the docs). Turbo doesn't matter.

`vel_accel_dt(v, a, lim)` (0x4688d0): `a·dtt` is added if `v` has the same sign (or is 0), else
`v = a·dtt` (instant reversal); then clamped to `lim`. Cursor: +0.333 px/tick² (300 px/s²), max
10 px/tick (300 px/s) after 1 s. `0x4687a4(v, r)`: `v` moves towards 0 by `r·dtt` without
crossing it: 0.6667 px/tick² (stops from full speed in 15 ticks).

##### Dropping a bomb ✅

```
S   = Kurt.pos + (0, 0, -5)                        # 0x497b9c = -5.0, spawn point
cx  = cursorX - 300; cy = cursorY - 180            # 0x497ba4 = -300, 0x497bac = -180
dir = (M[0][0]*cx + M[0][1]*cy,                    # M = camera matrix 0x573974
       M[1][0]*cx + M[1][1]*cy,                    #   (0x573974, 0x573978 / 0x573984, 0x573988)
       -600 / zoom)                                # 0x497bb4 = -600.0, zoom 0x57391c (2.4)
bombs -= 1
hit = ray(0x46428c, from Kurt.pos, dir, length 1000, flags 3, skip 0x30, need 0)
t   = hit ? sqrt((S.z - hit.z) * 2 / o.gravity) : 2.5     # 0x497bbc = 2.0, o+0x48 (XE's)
vel = ((hit.x - S.x)/t, (hit.y - S.y)/t, 0)
```

- With the top-down matrix (section 4) `dir` is exactly the view ray through the cursor pixel:
  `dir.xy = cx·right − cy·forward`, `dir.z = −focal` (focal = 600/zoom = 250 px). The ray
  starts at Kurt (= the `XE` = the camera once `H` is 0).
- `0x46428c(start eax, dir edx, ebx/ecx unused, len 1000.0, out hit, out obj 0, out tri 0,
  flags 3, skip 0x30, need 0)`: `dir` isn't normalised (flag 0x10000 clear), the end is
  `start + 1000·dir`. Flag 1: objects of Kurt's arena (and the visible second arena) that are
  active, alive, without flags 0x10/0x20, whose box and parts (0x45f97c, 0x414668) the segment
  crosses — each hit shortens the segment ❓. Flag 2: BSP of Kurt's arena, then the second arena
  if `0x573a68 && !0x573b00`. Returns 1 and the hit point; 0 and the end point if nothing.
- Fall time `t`: the drop starts with `vz = 0` and falls by gravity, so `t` makes it land on the
  aimed point. It uses the **`XE`'s** gravity `obj+0x48`; the `XE` script never sets it, so it's
  the default 32 u/s² (0x43bc20), equal to the bomb's ✅. A miss (`t = 2.5` s) towards the far
  end point gives an absurd speed ❓ (looking straight down a miss is unlikely).
- Spawn: type index of `XBN_BOMB` (0x45ca88; nothing if missing, the bomb is still counted) →
  `object_spawn` 0x45cdec(arena `0x573a0c`, S, id 1, type, script 0, flag 0).

| Bomb field | Value |
| --- | --- |
| `+0x30e` | 900 (life in ticks, 30 s) |
| `+0x58` (scale) | 1.0 |
| `+0x30a` (item kind) | `0x81` |
| `+0x44` (friction) | 0 |
| `+0x148` flags | `|= 0x818a6`: gravity 0x2, collides 0x4, 0x20 (not a target), 0x80 no banking, 0x800 Kurt passes, **0x1000 Kurt's projectile** (0x43deac), 0x80000 |
| `+0x28..0x30` velocity | `vel` above (u/s) |
| `+0x4c` yaw | Kurt's yaw |
| — | 0x43b65c: pose / world bounds update |
| `+0x15c`, `+0x158` | sound `DROP` (`PTR_DAT_004920d8` → "DROP"): 0x402db0(handle +0x158, DROP, flags 0x2000e = 3D following `obj+0x10`, volume 0x7fff, pitch 1.0, 50.0); loops |

#### The bomb after the drop ✅ (0x43deac, kind 0x81)

Run every frame by the object update for flag 0x1000. While flying (flag 0x4000 clear):

- Scale grows to 1 at 3/s (already 1).
- **Pitch** `obj+0x13c` goes from 0 down to −90° at 45°/s (0x496ad8 = 45, 0x496ad0 = −90): it
  noses over in 2 s.
- Gravity 32 u/s² (≤ 220 u/s), no friction, BSP collisions (0x45e74c/0x45e810).
- Object contact (0x43eb48): any object (no type mask) without flags 0x830 whose part boxes the
  move crosses; sets contact flag 0x10 and remembers the object (blast source). The `XE` itself
  (flag 0x10 once hidden) is ignored.
- `+0x30e -= ticks`.

It goes off when it touched the arena (contact 0x1/0x2), an object (0x10), or after 900 ticks:
velocity 0, flags −0x6, flag 0x4000, then (shared with kind 5, Bones' `X_TOOTH`):

1. `blast(pos, 150, radius 40, counts kills, source = touched object, targets objects + triangle
   groups (6), hit type −7)` (0x463a94).
2. `blast(pos, 75, radius 40, …, targets Kurt (1), hit type −7)`. Kurt is far above; if hurt the
   damage would go to the `XE` and back to him (section 5).
3. `explosion_spawn(arena, pos, 2.0)` (0x43cb2c): `EXPLODE` object + `EXPLODE` sound.
4. Removed (0x43d7bc), which stops its `DROP` voice.

Same numbers as a grenade (150 / 75 within 40). Triangle groups take `150·(40 − d)/40`.

#### Camera, drawing and HUD ✅

##### Top-down camera (0x4183f0)

`camera_update` (0x4174d0) calls 0x4183f0 instead of the normal camera when `0x490de0 != 0` and
not in sniper mode, and sets `0x5739cc..d4` = Kurt's position. With `s, c = sin, cos(Kurt yaw)`
and Kurt at `(x, y, z)`:

| Row | Direction | Translation |
| --- | --- | --- |
| right `0x573974..7c` | `( s, −c, 0)` | `0x573980 = −(x·s − y·c)` |
| up `0x573984..8c` | `(−c, −s, 0)` = −forward | `0x573990 = x·c + y·s` |
| back `0x573994..9c` | `(0, 0, −1)` | `0x5739a0 = z + H` |

- The camera sits **`H` (0x490dec) above Kurt and looks straight down**; the screen's top is
  Kurt's (= the `XE`'s) heading, so the world turns under the screen as the `XE` follows its path.
  No pitch, roll, sway or wall clearance. Camera position `0x5738ec..f4` = `(x, y, z + H)`.
- Projection rows `0x573944…` = rows × `1/(zoom·0.5)` (x) and `1/(zoom·0.3)` (y; sniper
  projection uses 280/384 instead of 360/600), depth `w = z + H − p.z`: a perspective view, focal
  600/zoom px = 250 px at zoom 2.4, centre (300, 180) — the same lens as the normal view.
- `H` = 50 at mount, −25 u/s → 0 after 2 s (a descent into the cockpit); at 0 the `XE` gets flag
  0x10 (not drawn: arena_build_drawlist skips it). The script unlocks the controls at the same
  moment (2 s).
- The sound listener uses this matrix (0x403348), so 3D sounds pan by screen position.

##### Kurt and the world

- Kurt isn't drawn: mode bit 0x20 keeps him out of the draw list, and damp_animate (0x4646a4)
  skips `damp_sprite_draw` while `0x490de0 != 0`.
- The script sets `0x574304 = −1` 0.1 s after mounting: **no sky** (the background isn't
  drawn ❓ looking down only ground should show), back to 0 when the ride ends.
- Chain gun off (mode bit 0x2 clear, 0x41a304); no sniper mode, no item throwing (`damp_move`
  isn't called).

##### HUD 0x46be98 ✅

Called first by the HUD overlay 0x41e3c8 (from 0x41e128, after the 3D scene) when riding and
`0x573c36 & 4`. Nothing while the `XE` has flag 0x4000000 (locked). Otherwise:

| Element | Where |
| --- | --- |
| `BOMBTARG` (`0x490e14`, `TRAVSPRT.BNI`, loaded with `CROSS` by `level_load` 0x41b0c0) | hotspot at (300, 180), view centre |
| `CROSS` (`0x490e10`, also the sniper crosshair) | hotspot at (round(cursor x), round(cursor y)) |
| bombs left, `"%d"` (0x497b7c) | `FONTBIG` (0x415a20, font arg 0), **right-aligned at x 472**, baseline y 56 |

`rle_draw_hotspot`: top-left = (x − hotspot x, y − hotspot y). Health, inventory and messages
are drawn as usual.

#### Damage and getting off ✅

**Damage.** Mode bit 0x1: hits on Kurt (0x46a498, 0x46a604, which honour invulnerability) are
subtracted from the `XE`'s health instead. Anything that hurts the `XE` (blasts, projectiles)
does the same. Each frame 0x46bf40 forwards `10000 − health` to Kurt with **0x46a77c** and
restores 10000:

```
0x46a77c(d):   # raw hurt, no invulnerability check
  if Kurt.health == 0 and 0x5742e0 == 0: return          # already dead
  easy (0x57423e == 0): d = d*2/3, at least 1;  hard (2): d *= 2
  if d >= 1: red flash 0x573b70 = clamp(0x573b70 + 25·d, 75, 180)
  Kurt.health = max(Kurt.health − d, 0)
  knock-down counter 0x573b20 += d                       # no knock-down while riding
```

`Kurt.health < 1` after that → `XE` health 0 and `object_kill` → its death script (below).

**Getting off** (`damp_control`, flag `0x2000000` clear, mode bit 0x40000):

- `XE` flag 0x10 cleared (visible again), `0x490de0 = 0` (normal camera, no transition),
  `0x573b0c/10/14/18 = 0` (also Kurt's walk speeds: he stands still), `0x573c30 = 0`.
- Kurt keeps his state, yaw and position — the `XE`'s last position — and falls from there with
  normal gravity from the next frame.
- If the `XE` object is freed while ridden (0x43d734): `0x573c30 = 0` and Kurt takes 50 (0x46a498),
  but `0x490de0` stays 1 ❓ (top-down camera stuck; the scripts never do this).
- Who clears `0x2000000`: only the `XE` script, at the end of the path and in its death script.

#### The `DANT_5` script ✅ (`LEVEL7.CMI`; file offsets; jump targets already +4)

##### Trigger

The comm device (triangle group 16, `M_COMM`, at (78, 2299, −67)) hit script 0x11aed: on the
first hit (arena flag 8 clear) gosub 0x11b47: unless arena flag 9, **spawn `XE` at (0, 0, 90)
with script 0x11baa**. The device then shows a boss bar (200 hp) and shatters at 200.

##### Arrival and wait

| Offset | Action |
| --- | --- |
| 0x11baa | instance 9000, no death script, health 65000, path 91213 (absolute, once) at 1.0 frame/tick, flags +0x20 (not a target), loop sound `FLY` |
| | path 91213: 9 keys, (760, 3056, 298) → (85, 2347, −52), 235 frames = 7.8 s, 1165 u |
| 0x11bed | path 91089 (relative, once, 0 → −16 in z) at 0.25: sinks 16 u in 1.3 s to z ≈ −68 |
| 0x11c05 | arena flag 29 (stops the device's `BEEP`), flags +0x10000 (doesn't face its motion), hover path 53849 (relative, loops, ±2 u bob), own var 0 = 30, **flags +0x6000000** (rideable, locked) |
| 0x11c23 loop | health 10000; var −= dt; **var < 0.05 (30 s) or arena flag 9 → 0x11d9d**; `if_is_573c30` → 0x11c4f |

Timeout 0x11d9d: arena flag 9 (never comes back), rise 16 u (path 90965), then 0x11db8 (leave).

##### Ride (0x11c4f, when Kurt is on)

| Offset | Action |
| --- | --- |
| 0x11c4f | flags −0x20; clear arena flag 16; if arena flag 19: set flag 21 (an `XTANK` was out) ❓ |
| 0x11c5f | priority 1; command `XE` #1000 (hidden bunker spawners), all `XTANK`, all `XBANG` → `delete_self` (0x12095); arena flag 12 (ride running) |
| 0x11c92 | gosub 0x12d8c: 6 `XG` (#3500, yaw 270, script 0x11fd0) at (475, 3134), (495, 3134), (325, 3464), (345, 3464), (−60, 3078), (−80, 3078), z −80 |
| 0x11c98 | flags −0x10000 (faces the path); **path 91577** (absolute, once) at **0.35 frame/tick** |
| 0x11cb9 | wait 0.1 s; `set_574304 −1` (no sky); wait 1.9 s; **flags −0x4000000 (controls on, HUD shows)**; health 10000; death script 0x11dcf |
| 0x11cd4 loop | path frames 100 / 342 / 491 / 570 / 610 → gosubs below; path done → 0x11d0e |

Path 91577: 11 keys, frames 0–1000, ≈ 2805 u, **95 s at ≈ 29 u/s**, a loop that ends where it
starts:

| Frame | Point | Time |
| --- | --- | --- |
| 0 | (83, 2347, −52) | 0 s |
| 149 | (344, 2675, 14) | 14 s |
| 224 | (447, 2850, 75) | 21 s |
| 292 | (482, 3023, 4) | 28 s |
| 370 | (475, 3241, 5) | 35 s |
| 505 | (213, 3510, −13) | 48 s |
| 634 | (−45, 3271, 6) | 60 s |
| 743 | (−88, 2967, −7) | 71 s |
| 827 | (−130, 2752, 81) | 79 s |
| 899 | (−83, 2575, −3) | 86 s |
| 1000 | (85, 2347, −52) | 95 s |

The ground is at z ≈ −71…−80, so it flies 20–160 u above it.

Path-frame gosubs (each once, arena flags 23–27), `spawn_ex` `XG` #3500, z −71, script 0x11fd0:

| Frame (time) | Offset | `XG`s at |
| --- | --- | --- |
| 100 (9.5 s) | 0x11e08 | (313, 2665), (388, 2702) |
| 342 (32.6 s) | 0x11e4b | (422, 3255), (446, 3339), (363, 3367) |
| 491 (46.8 s) | 0x11eab | (155, 3460), (86, 3450) |
| 570 (54.3 s) | 0x11eee | (18, 3333), (−22, 3305), (−18, 3273) |
| 610 (58.1 s) | 0x11f4e | (−68, 3264), (−56, 3199), (−96, 3196), (−121, 2960) |

So 18 `XG`s in all: the bombing targets. Their script 0x11fd0: death script 0x12be1 (falls,
`set_gravity 20`, dies), loops an animation; if Kurt is in sight (100, 100) and within 75 u (2D)
it randomly animates or runs (`push_forward 15`); once arena flag 10 is set (ride over) →
0x11fcb: arena flag 28, `delete_self`.

##### End of the path (0x11d0e)

1. Reward 0x11d2b: if arena flag 28 is clear, bunkers 1 and 2 are destroyed (arena flags 13, 14)
   and no `XG` is alive: message `DA5_BOK` "100% Kills!\nBonus powerup!" (5 s) and an `SW_GATT`
   (super chain gun) at (98, 2305, 100).
2. Flags +0x20, `set_574304 0` (sky back), health 65000.
3. Cleanup 0x11d6d: priority 0; command `XG` #3500 → 0x11fcb (survivors deleted); clear arena
   flag 12, set flag 10; **Kurt invulnerable 2 s** (`0x573bd4 = 2`); if arena flag 21 spawn
   `XTANK` at (12, 3030, −71); if arena flag 20 (and bunker 3 not destroyed) spawn `XG` at
   (186, 3250, −4).
4. 0x11db8: `set_574304 0`, **flags −0x2000000: Kurt gets off** at (85, 2347, −52), ≈ 19 u above
   the floor, next to the comm device; the `XE` turns to yaw 270 at 90°/s, then flies the arrival
   path backwards (0x11de9: path 91213, relative, from the end, speed −1) and deletes itself
   (0x11e06).

##### Death script 0x11dcf (Kurt died; see section 5)

`set_574304 0`, flags −0x2000000 (Kurt dropped), cleanup 0x11d6d, arena flag 11, wait 0.01 s,
health 0 → the death script was consumed, so the `XE` explodes (0x43d224) ✅.

#### Constants ✅

| Value | Address | Use |
| --- | --- | --- |
| 50.0 | `0x42480000` (mount), 0x490dec | camera start height |
| 25.0 (f64) | 0x497b8c | camera descent u/s |
| 1/3 (f64) | 0x497b94, 0x493470 | mouse px/unit; key accel px/tick² per axis unit |
| 10 (f64) | 0x493478 | max cursor speed px/tick |
| 0.6667 | `0x3f2aaaab` | cursor brake px/tick² |
| 128, 472 / 64, 296 | `0x43000000`, `0x43ec0000` / `0x42800000`, `0x43940000` | cursor limits |
| 300, 180 | `0x43960000`, `0x43340000` | cursor start |
| −5 (f64) | 0x497b9c | bomb spawn below Kurt |
| −300, −180 (f64) | 0x497ba4, 0x497bac | screen centre |
| −600 (f32) | 0x497bb4 | ray z × zoom (focal) |
| 2.0 (f64) | 0x497bbc | fall time `sqrt(2h/g)` |
| 2.5 | `0x40200000` | fall time on a miss |
| 1000.0 | `0x447a0000` | ray length factor |
| 999 | `0x3e7` | fire latch |
| 10, 1.0 | code | max bombs, refill period (s) |
| 10000 | `0x2710` | `XE` health kept while riding |
| 900, 0x81, 0x818a6 | code | bomb life (ticks), kind, flags |
| 45, −90 | 0x496ad8 (f32), 0x496ad0 (f64) | bomb nose-down rate °/s, limit |
| 150 / 75, 40 | 0x43deac | bomb blast objects+groups / Kurt, radius |
| 2.0 | `0x40000000` | explosion scale |
| `"%d"`, `"XBN_BOMB"`, `"DROP"` | 0x497b7c, 0x497b80, 0x49758c | |
| 300, 180 / 472, 56 | 0x46be98 | `BOMBTARG` / count position |

#### Open questions ❓

- Physical keys behind `0x57eb30…3c` (assumed left/right/forward/back).
- Mouse units of `0x57eb24/28` (raw counts per frame?).
- `X_STRIKE` is accepted as a ride but no script makes it rideable.
- What is visible with `0x574304 = −1` if the ground doesn't cover the view (stale frame?).
- Kurt's death while riding: he's dropped in mid-air by the death script; how the death states
  play from there wasn't followed.

## The fall (state 2, `fall_3d.c`)

Kurt falls from orbit onto the minecrawler before each level (not before LEVEL5, which loads
directly). Init 0x410018, each frame 0x4114a4 (intro 0x41106c), cleanup 0x410b80. `n` below is the
level index + 1 (1–5). Times are in seconds (`t`, `0x5209c4`, counted from the end of the intro) or
ticks (1/30 s); `dt` is the frame time in seconds (`0x491e24`). World units "u", Z up. The files are
described in [formats.md](formats.md#fall-files-fall3d); `tools/python/fall3d_dump.py` lists and
exports them.

**In the port** (`game/fall/fall.gd`, `MDKFall`): all of the above. The ground, the track and the
haze are drawn by a shader (`fall_ground.gdshader`) with the formulas below; the models in a
`SubViewport` with the same projection (a camera looking down, vertical FOV 71.5°, wider windows
see more on the sides); the palette effects (whitening, darkening, the red of death) by a
full-screen shader on the final image (`fall_screen.gdshader`) instead of the palette. Steering
uses the Forward/Back and Turn or Strafe left/right actions; Esc skips the fall (not in the
original). The health and the inventory go on to the level (`GameState.carry`). Approximations:
the radar's colours (translucent green), the smoke trails (a band along the last 32 points instead
of the original tube, 0x439454), the explosion drawn at Kurt's depth rather than always on top.
Test: `--fall=N` (N = the LEVELn number) with `--wait`, `--screenshot` and `--god`.

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
  (offset x, offset y, −min(dz / 225, 10) × 66.67) and steers `v = 0.8 v + 0.2 × 250 × unit` once
  per frame. Once it's more than 5 u above Kurt (`dz ≤ −5`) it has passed (`M_PASS`, timer
  `+0x11c` −1): it no longer homes, flies straight on and is removed 60 ticks later. A missile Kurt
  dodges doesn't come back.
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
  inventory (`PICKUPS`, 0x46cce4), as in the level. Outside sniper mode 0x46cce4 resets its timer
  `0x574328` to 60 every frame, so here the inventory is always on screen.
- At t > 33 s the fall ends (0x4114a4 returns 1): the fall files are freed (0x410b80) and the level
  loads (0x41ba68) with the health (`0x574324`) and inventory (with the pickups) as they are; the
  main loop also sets `0x574270`–`0x574278` to 1000 ❓.
- Stereo mode (`0x574318`, 3D glasses ❓) draws everything twice with eye offsets (`0x491cc8`).
- Sounds (`FALL3D.SNI`): `WINDLOOP`, `C_GRIND` (loops), `EXPLODE1`/`2`, `R_START`, `R_MOVE`,
  `M_PASS`, `M_LNCH`, `P_CHUTE`, `P_COLL`, `P_FALL`, `BONES`, `K_HIT1`–`7`, `K_FINISH`,
  `K_COLL1`/`2`, `K_SEEN`. No music.
- Loaded but unused by the fall code ❓: `FLARE1`–`FLARE4`, `BANG` (a 26-frame RLE animation),
  `PICK`.

## The stream (state 5, `stream.c` ❓)

Played after each level (the end of level's white flash leads into it), before the statistics:
Kurt flies down a randomly generated translucent tube in space. Init 0x433b50, each frame
0x4352ac, cleanup 0x435210. At the end Bones picks him up with a crane (levels 0–3), or, after
LEVEL8 (index 4, the "Gunter variant"), Kurt follows Gunter carrying Bones towards a planet.
`tools/python/stream_tunnel.py` lists `STREAM.BNI`, prints the colour ramp and replays the tunnel
generator (OBJ export).

**In the port** (`game/stream/stream.gd`, `MDKStream`; the tube in `stream_tube.gd`, `StreamTube`):
all of the below: the tube generated ring by
ring with the same random walks, drawn far to near with the vertex colours and alphas (one
`ImmediateMesh` rebuilt each frame, triangles facing away from the eye skipped), the scrolling
`BG`, the lights (billboards, added to the colours behind ❓), the planet, Kurt's steering, drift,
walls, damage and speed, the `SWH150` bonus, the rescue, the Gunter variant, the camera, the fades
(the screen shader of the fall), the health box, the sounds. The health and the pickups come from
the level (`GameState.carry`) and go on to the statistics or to LEVEL5. The rand() sequence isn't
the game's, so the tubes differ from the original's. Esc ends the stream (not in the original).
Test: `--stream=N` (N = the LEVELn number just finished) with `--wait`, `--screenshot`, `--health`.

### The tunnel

### Conventions ✅

- **World axes**: X right, Y forward (the tunnel starts along +Y), Z up; right-handed. Segment
  index `n` is an absolute counter; its ring-buffer slot is `n & 31`.
- **Units**: one segment is 10 units long. Kurt's position along the tunnel is a float segment
  coordinate `s` (obj+0x5c): the spine point at `s` is `lerp(O[trunc s], O[trunc s + 1], frac s)`.
- **Angles** are in degrees (`sincos_deg` 0x440288).
- `rand()` is Watcom's: `state = state × 0x41C64E6D + 0x3039`, returns `(state >> 16) & 0x7FFF`
  (0x4794dd). Below `u = rand() − 0x4000` (−16384..16383).
- `trunc` = 0x4797c0 (`frndint` with the rounding control set to chop).
- In Godot (Y up, −Z forward) map MDK `(x, y, z)` → Godot `(x, z, −y)`.

### Data ✅

| Address | Size | Meaning |
|---|---|---|
| 0x51a274 | i32 | `r`, read index: oldest ring still alive (≈ Kurt's segment) |
| 0x51a278 | i32 | `w`, write index: next ring to generate (`w = r + 31` in play) |
| 0x51fa7c + 0x30·slot | 12 f32 | segment matrix `M[n]`, 3×4 row-major: rows `[m0 m1 m2 tx]`, `[m4 m5 m6 ty]`, `[m8 m9 m10 tz]`; column 1 is the forward axis, `(tx, ty, tz)` = the ring centre `O[n]` |
| 0x51a27c + 0xc0·slot | 16 × vec3 | ring `n`: 16 world points |
| 0x51ba7c + 0x200·slot | 16 × 2 × vec4 | wall planes of the segment between ring `n` and `n+1` (`nx, ny, nz, d`, normal pointing into the tunnel) |
| 0x52007c + 0x20·slot | 32 bytes | colour byte (0–63) per point of ring `n` (only the first 16 are used) |
| 0x52047c + 4·slot | ptr | linked list of the stream objects ("aliens", 0x32e bytes, pool of 399 at 0x523504) in that segment |
| 0x520500, 0x520504, 0x5204fc | f32 | turn angles per segment about local X, Y (forward: roll), Z |
| 0x520508 | f32 | tunnel radius (starts 10.0) |
| 0x520510, 0x520514 | i32 | shade offsets A, B (0–63) |
| 0x520518 | f32 | shade blend `t` (0..1) |
| 0x520898 | f32 | max turn angle (per axis, per segment) |
| 0x52089c, 0x5208a0 | f32 | min / max radius |
| 0x520894 | i32 | final-stream flag = `level index > 3` (Gunta variant, ends at a planet) |
| 0x5744d8 + 0x100·k | 64 × RGBA | vertex colours of the ramp for distance level k = 0..5 (bytes B, G, R, A) |
| 0x5738e4 | ptr | software-renderer blend tables, 6 × 64 × 256 bytes (not used by the D3D path) |

### Initialisation (0x433b50) ✅

1. Clears 0x51a274..0x5208a4 (all of the above), loads `STREAM.MTI` / `STREAM.BNI`.
2. **Palette** `0x52051c` (768 bytes): colours 0–63 = the global palette `0x5735e4`, colours
   64–255 = bytes 0xC0..0x2FF of the `PAL` entry (copied to `0x5205dc`). `set_palette(0x52051c, 3)`.
3. `BG` (600×360) is converted to a 16-bit DirectDraw surface (0x438a70); `PLANET` (128×128) and
   `LIGHT` (64×64, a D3D texture at 0x57f870: 64×64, flag 1) are loaded.
4. **Limits** from the difficulty `D` (0x57423e) and the level index `L` (0x574268, 0–4), with
   `h = L >> 1`:

   | D | max turn 0x520898 | min radius 0x52089c | max radius 0x5208a0 |
   |---|---|---|---|
   | 0 easy | L + 6 | 10 − h | 17 − h |
   | 1 normal | L + 8 | 10 − h | 17 − L |
   | 2 hard | L + 10 | 10 − h | 13 − h |

   (For L = 0..4, normal: max turn 8..12°, radius 10..17 at L 0 down to 8..13 at L 4.)
5. `r = w = 0`, `M[0]` = identity (origin 0), radius = 10.0, `A = rand() & 63`,
   `B = rand() & 63`, `t = 0`, angles 0.
6. Calls the generator 31 times → rings 0..30, `w = 31`.
7. Builds the colour ramp (see [Colours](#colours)), resets the camera matrix, creates Kurt and
   the other actors.

### The generator (0x434838) ✅

Called 31× at init and once each time `r` advances (0x435c4c: `if r + 1 < s − 0.75: r += 1;
generate`), so the ring buffer always holds rings `r .. r + 30` and the tunnel extends ~300 units
ahead. With `n = w` (the ring being made), `p = n − 1`:

0. **Final stream** (0x520894 ≠ 0) and `n > 186`: no more rings; the first time it spawns the
   PLANET sprite at segment `n − 3` (0x4350dc) and returns.
1. **Matrix** (skipped when `n == r`, i.e. only for ring 0 at init):
   `L = Rx(a) · Ry(b) · Rz(c)` with `a = 0x520500, b = 0x520504, c = 0x5204fc` (0x46de70, scale 1,
   translation (0, 10, 0)), `M[n] = M[p] · L` (0x46dba0), then each of the 3 columns is
   normalised (0x438f50, no re-orthogonalisation). Hence
   `O[n] = O[p] + 10 · M[p].column1` and `R[n] = R[p] · Rx(a)Ry(b)Rz(c)`. The rotation matrix
   (rows):
   ```
   [ cb·cc,               −cb·sc,               sb     ]
   [ sa·sb·cc + ca·sc,    ca·cc − sa·sb·sc,    −sa·cb  ]
   [ sa·sc − ca·sb·cc,    ca·sb·sc + sa·cc,     ca·cb  ]
   ```
   So `b` rolls the frame about the forward axis, `a` pitches, `c` yaws.
   The objects left in slot `n & 31` (ring `n − 32`) are freed (0x4351a0), then
   `if rand() & 3: spawn a LIGHT sprite in segment p` (0x434f64, 3 chances in 4, 4 more rand calls).
2. **Ring points** (always), `j = 0..15`, `θ = 22.5·j` (point 0 on local +Z = top, point 4 on +X):
   ```
   jx = (rand() − 0x4000 + 163840) / 163840     ∈ [0.9, 1.1)   (× 6.10352e-6)
   jz = (rand() − 0x4000 + 163840) / 163840
   local = (radius · sinθ · jx, 0, radius · cosθ · jz)
   P[n][j] = M[n] · local   (0x46dcd4: R·v + O)
   ```
   Each coordinate is jittered by ±10 % independently, so the rings are slightly irregular.
3. **Planes and colours of segment p** (not for ring 0), `Pv = P[p]` (older ring),
   `C = P[n]` (new ring), `j1 = (j + 1) & 15`:
   - `shade = trunc((1 − t)·A + t·B)` (once per segment).
   - colour byte `k` (k = 0..31) of slot p: `x = (n + k) & 31; tri = x < 16 ? x : 31 − x;
     byte = (tri + shade) & 63`. Only bytes 0..15 are read (by point index j), so point j of
     ring p gets `(tri((n + j) & 31) + shade) & 63` with `n = p + 1`: a triangle wave around the
     ring that shifts by one per segment → diagonal (spiral) stripes through the 64-colour ramp.
   - plane 2j (triangle `Pv[j], C[j1], Pv[j1]`): `N = normalize((C[j1] − Pv[j]) × (Pv[j1] − C[j1]))`,
     `d = −N·Pv[j]`.
   - plane 2j+1 (triangle `Pv[j], C[j], C[j1]`): `N = normalize((C[j] − Pv[j]) × (C[j1] − C[j]))`,
     `d = −N·Pv[j]`.
   - The normals point into the tube (the replay finds the axis on the positive side of every
     plane; the collision 0x43637c treats `N·x + d − 1.5 ≤ 0` as a hit).
   - `t += 0.1`; when `t > 1`: `t = 0, A = B, B = rand() & 63` (a new shade target every ~11
     segments).
4. `w += 1`.
5. **Turn angles**, each of `a, b, c` independently:
   - normally `angle += u × 6.10352e-5` (a uniform step in [−1°, +1°)): a random walk of the
     *curvature*, so the tunnel meanders and corkscrews;
   - final stream and `w > 168`: the angle moves 1° towards 0 per segment (the tunnel straightens
     before the planet);
   - then `if |angle| > max_turn: angle ×= 0.8`.
6. **Radius**: `radius += u × 6.10352e-5` (±1 per segment), clamped to `[min, max]`
   (below min → min, above max → max). The radius of ring n is the value *before* this update.

Order of `rand()` calls per call (for exact replays): light test (+4 if a light spawns), 32 jitter
values (jx, jz per point), new shade target when `t` wraps, 3 angles in the order c (0x5204fc),
a (0x520500), b (0x520504), radius. The initial seed is not set by
the stream (❓ Watcom default 1 unless `srand` was called earlier).

### Spine and camera ✅

- **Spine** (0x436668): `spine(s) = O[i] + (O[i+1] − O[i]) · (s − i)`, `i = trunc s` (centres
  only, no orientation).
- **Camera position** (0x4352ac), with Kurt's world position `K` (obj+0x10) and his segment
  coordinate `s`:
  ```
  A = spine(s − 0.75)
  B = spine(s + 2)
  B' = B + 1.375 · (K − B)
  eye = 0.4 · A + 0.6 · B'        (= 0.4 A − 0.225 B + 0.825 K)
  ```
  About 0.75 segment (7.5 units) behind Kurt, and 0.825 × his off-axis offset towards his side.
- **Orientation** (0x436828): `target = spine(s + 2)`; `f = normalize(target − eye)`;
  `right = normalize(up × f)`; `up = f × right`, where `up` (0x491cf8) persists from frame to
  frame (starts (0, 0, −1), i.e. it is the screen-down axis): the camera follows the tunnel with
  parallel-transported roll, it never snaps to world up. View rows: `right`, `up` (down on
  screen), `f`; translation `−row·eye`.
- **Projection**: zoom 0x57391c = 2.4, screen 600 × 360, centre (300, 180):
  `sx = 300 + 250 · x/z`, `sy = 180 + 250 · y/z` (focal 250 px on both axes, square pixels:
  horizontal FOV 100.4°, vertical 71.5°). Near plane z = 0.05 (triangles are clipped there,
  0x43731c).

### Drawing (0x43592c, each frame) ✅

Order: BG blit (0x438bfc) → begin scene → 0x436b00 (tunnel + objects) → end scene → HUD. No
z-buffer is relied on: everything is painter-sorted back to front.

#### Background (0x438bfc)

`BG` (600×360, palette indices 1–255, a nebula) scrolls toroidally. Kept offsets `bx` (0x491d2c)
and `by` (0x491d30); with the current view rows `r, u, f` and last frame's `r', u', f'` (0x491d34):
```
by = trunc(by + 180 · (u.z·f'.z − f.z·u'.z))      then wrapped to 0..359
bx = trunc(bx + 300 · (r.x·u'.x − u.x·r'.x))      then wrapped to 0..599
```
(pitch changes scroll vertically, roll changes horizontally; world-axis specific, a cheap
approximation.) Screen pixel (px, py) shows `BG[(px + bx) mod 600, (py + by) mod 360]` (drawn as
up to 4 blits). In the stereo mode (0x574318) `bx` is shifted by the eye offset 0x491cc8.

#### Tunnel (0x436b00)

1. Projects the newest ring `w − 1`; its vertex colour values are all `−0x545` (ramp colour 0,
   level 5).
2. For each slot `n` from `w − 2` down to `r` (far to near), with `d = n − r` (0..29):
   - distance level `k`: d ≥ 26 → 5, 21–25 → 4, 16–20 → 3, 11–15 → 2, 6–10 → 1, ≤ 5 → 0;
   - projects ring n; vertex colour value of point j = `−(0x405 + 64k + colour[n][j])`, i.e.
     entry `64k + colour` of the RGBA table (the vertices of ring n+1 keep the values computed one
     iteration earlier, with the farther level, so alpha is Gouraud-blended between levels);
   - 32 triangles, for j = 0..15 (j1 = (j + 1) & 15), older ring `Pv = ring n`, newer `C = ring n+1`:
     `(Pv[j], C[j1], Pv[j1])` with plane 2j, then `(Pv[j], C[j], C[j1])` with plane 2j+1;
     a triangle is skipped when the eye is on the negative side of its plane (`N·eye + d < 0`,
     0x4372c0) — only the inside of the tube is drawn;
   - Gouraud triangles (0x43731c → 0x471c20), vertex colour = RGBA table entry, alpha-blended
     over what is behind;
   - then the objects of segment n (0x40b990, depth-sorted list): models (Kurt, Bones, Gunta,
     SWH150...) through 0x43b104, sprites through 0x436f10 (LIGHT) or 0x4371f0 (PLANET).
3. Total: 30 segments × 32 triangles = 960 triangles per frame.

#### Colours

- **Ramp** (0x433b50 from the table at 0x491ccc): a start colour then 8 keys of 8 steps each,
  bytes stored B, G, R (the engine's RGBQUAD order: the D3D vertex colour puts byte 0 in the low
  (blue) byte, and the software blend table blends byte 0 with the palette's blue):

  ```
  0x491ccc: 5a ce de 00 | 21 7b 8c 08 | 08 31 7b 08 | 84 a5 c6 08 | 8c 7b 84 08
            e7 c6 d6 08 | 84 a5 c6 08 | 08 31 7b 08 | 5a ce de 08 | 00 00 00 00
  ```
  Keys as RGB: start (222, 206, 90) gold → (140, 123, 33) olive → (123, 49, 8) rust →
  (198, 165, 132) tan → (132, 123, 140) grey-violet → (214, 198, 231) lavender → (198, 165, 132)
  → (123, 49, 8) → (222, 206, 90). Entry `i` of a key with `n = 8` steps: `c = (key·i + prev·(8 − i)) / 8`
  (integer division), i = 0..7 — ramp[0] = gold, ramp[8] = olive, ..., ramp[56] = rust, ramp[63]
  = 7/8 of the way back to gold; it wraps smoothly (the colour byte is `& 63`).
- **Alpha per distance level** k = 0..5: 0x5A, 0x55, 0x50, 0x3C, 0x28, 0x0F (35 %, 33 %, 31 %,
  23 %, 16 %, 6 %): the tube is faint and fades into the nebula with distance.
- Blend: `out = dst + (ramp − dst) · a / 256` (the software tables 0x5738e4, level k at
  `+0x4000·k + 0x100·c`, map each of the 256 palette colours to the nearest palette index of
  this blend, 0x4081a4; the D3D path uses the same RGBA with vertex alpha, state flag 2 in
  0x471290 ❓ presumably SRCALPHA/INVSRCALPHA).
- The tunnel ignores the palette (direct colours in D3D).

#### Light sprites (0x434f64 spawn, 0x43596c move, 0x436f10 draw)

3 in 4 new segments get one, in segment `p`: local position `(u/4096, (s − trunc s)·10, u/4096)`
(x, z uniform in ±4, on the ring plane), size `4 + rand()/8192` (4..8), speed `−3 − rand()/8192`
(−3..−7 segments/s: they fly back towards and past Kurt). Each frame `s += speed·dt`; the world
position is `M[trunc s] · (x, (s − trunc s)·10, z)`; freed when `s` leaves `[r, w)`. Drawn as a
screen-aligned textured quad (`LIGHT`, 64×64, indices 0–63 of the global palette, index 0
transparent ❓) centred on the projected point, half-size `trunc(250·size/z) >> 3` pixels (world
width ≈ size/4 = 1..2 units), not drawn when z < 0.05, clipped to the 600×360 screen.

#### Planet (final stream only, 0x4350dc, 0x4371f0)

Spawned once when the generator passes segment 186, at segment `w − 3` on the axis
(local (0, 0, 0)), size 36. Drawn as a 2D scaled sprite (0x404690) centred on the projected
point: scale `f = trunc(250·36/z)`, drawn size `128·f/256` pixels (world diameter 18 units); not
drawn when z < 0.05.

### Palette and fades (0x4352ac) ✅

`T` = 0x520860 (starts 0). While `T ≠ 1` or the stream is ending (0x52050c):
- **start**: `T += dt`; at `T ≥ 1`: `T = 1`, palette = 0–63 global, 64–255 PAL (0x4148d0).
  Before that each component `c` of 0x52051c becomes:
  - normal stream, alive: `trunc(c·T + 255·(1 − T))` (fades in from white);
  - final stream: `trunc(c·T)` (from black);
  - dead (health ≤ 0), `T ≤ 1`: R = `trunc(256·T)` (byte, so 0 at T = 1), G, B = `trunc(c·T)`;
    `T > 1` (set to 2 on death in the final stream): R = `min(255, R + trunc((2 − T)·255))`, G, B
    unchanged (a red flash).
- **end** (0x52050c set): `T −= dt` with the same formulas; at `T < 0` the whole palette is set to
  white (normal stream, alive) or black, and the state ends.
- ❓ In the D3D build these fades only affect palette-based surfaces; the BG surface is converted
  once at init and the tunnel uses direct colours, so how visible the fade is there is unverified.

### Open questions (tunnel) ❓

- Blend state of the tunnel triangles (flag 2 of 0x471290) and of the LIGHT texture (flag 1): alpha
  blending assumed from the software tables.
- Screen-y sign of the projection (row 1 of the view = (0, 0, −1) initially suggests y grows
  downward with world +Z up on screen).
- The rand seed at the start of the stream.
- Colour bytes 16–31 of each segment are written but never read.

### Gameplay

### Globals ✅

| Address | Meaning |
| --- | --- |
| `0x574324` | health (the game's health, carried in from the level and out to the next state) |
| `0x574268` | level index `i` (0–5); `0x520894 = (i > 3)` selects the **Gunter variant** |
| `0x57423e` | difficulty (0 easy, 1 normal, 2 hard) |
| `0x51a274` | `tail` — oldest live segment (Kurt's segment is about `tail + 1`) |
| `0x51a278` | `head` — number of segments generated (next one to generate); ring of 32 (`& 0x1f`) |
| `0x51fa7c` + 0x30·(s & 31) | segment `s` matrix (3×4, row-major, translation in [3], [7], [11]) |
| `0x51ba7c` + 0x200·(s & 31) | segment `s` wall planes: 32 × (nx, ny, nz, w) |
| `0x52047c` + 4·(s & 31) | per-segment object lists (linked through obj+0) |
| `0x520878` | Kurt |
| `0x520884` | Bones (null until the rescue) |
| `0x52088c` | the `SWH150` pickup (normal variant) |
| `0x52087c` | `GUNTA` (Gunter carrying Bones; Gunter variant) |
| `0x520888` | the planet sprite (Gunter variant, end of the tube) |
| `0x520880` | handled by `0x43650c` (a ship keeping ≥ 5 segments ahead of Kurt) but **never assigned** |
| `0x52050c` | "ending" flag (fade out, then leave) |
| `0x520860` | fade level `f` (0 at start, 1 = normal, 2 on death) |
| `0x491cf4` | frame counter (objects store it at obj+0x11c so a relinked object isn't updated twice) |
| `0x50151c`, `0x501520` | yaw rate, pitch rate (°/s), from `0x40934c` |
| `0x520898`, `0x52089c`, `0x5208a0` | tunnel bend limit, radius min, radius max (see below) |

Stream object layout (0x32e bytes, pool of 399 at `0x523504`, "No Aliens available in stream" if
exhausted): +0 next, +4 (u16) segment `& 31`, +0xc model instance (0 = sprite), +0x10..0x18 world
position, +0x1c/+0x20/+0x24 local offset (x across, y along, z across) in the segment frame,
+0x28..0x30 Kurt's smoothed direction, +0x34 speed (segments/s), +0x4c yaw, +0x54 roll, +0x58
scale, +0x5c `t` (position along the tube in segments, float), +0xac world matrix, +0x108 sprite
(image struct) for sprite objects, +0x114 animation, +0xdc/+0xe0/+0xe4/+0x118 animation time,
rate (30), frame, hold (see engine.md), +0x13c pitch, +0x148 flags (8 = animation loops), +0x180
previous position. ✅

### Init (0x433b50) ✅

- Loads `STREAM/STREAM.MTI` and `STREAM/STREAM.BNI`. Working palette `0x52051c`: colours 0–63 =
  the system palette `0x5735e4`, 64–255 = `PAL` (bytes 192…767). Images: `BG` (600×360, the
  scrolling background), `PLANET` (128², `0x520850`), `LIGHT` (64², `0x520890`, wrapped in the
  sprite struct `0x57f870`, 64×64).
- Sounds (volume 0x7fff): `WIND` (looping, **started at once** and stopped in the cleanup, volume
  never changed), `HITSIDE`, `RESCUE`, `APPLE`, `HURT1`–`HURT7`.
- Models: `KURT`, `BONES`, `PROFSHIP` (unused), and `SWH150` or (Gunter variant) `GUNTA`.
  Animations: `KURTANIM` (199 frames), `BONESANIM` (111 frames; tracks for the crane, rope, Bones
  *and* Kurt's parts), `SWHANM` (10 frames) or `GUNTANIM` (100 frames; Gunter + Bones parts),
  `FL_HVR`, `FL_WAVE` (loaded, never used — the professor's ship is dead content).
- Difficulty (with `h = i >> 1`, integer):

  | Difficulty | `0x520898` bend limit | `0x52089c` radius min | `0x5208a0` radius max |
  | --- | --- | --- | --- |
  | easy | i + 6 | 10 − h | 17 − h |
  | normal | i + 8 | 10 − h | 17 − i |
  | hard | i + 10 | 10 − h | 13 − h |

  (Used by the generator: per-segment turn angles random-walk by ±1 and are scaled × 0.8 when
  |angle| exceeds the limit; the radius `0x520508`, starting at 10, random-walks by ±1 and is
  clamped to [min, max]. Geometry is documented separately.)
- `tail = head = 0`, generator called 31 times → `head = 31`. The first call builds only the ring
  of points; each later call also spawns a light (see below), so ~22 lights exist at the start.
- Camera state reset; up vector `0x491cf8` = (0, 0, −1) initially (persists).
- **Kurt**: `t = tail + 0.75 = 0.75`, segment 0, yaw 90, pitch 0, roll 0, scale 1, local x = z = 0,
  direction +0x28 = (0, 1, 0), speed 6, `KURTANIM` looping at 30 fps.
- **Normal variant** — `SWH150`: `t = 16`, segment 16, yaw 0, speed **5.48**, `SWHANM` looping,
  x = z = 0 (on the axis).
- **Gunter variant** — `GUNTA`: `t = 5`, segment 5, yaw 90, speed **6**, `GUNTANIM` looping.
- `f = 0`, `0x52050c = 0`. Game state `0x574262 = 5`.

### Per-frame update (0x4352ac) ✅

In order:

1. `frame_counter++`.
2. **Rescue / end check** — only if `health > 0` and (`tail > 177` or `health == 1`):
   - Normal variant, Bones not yet there: spawn **Bones** (see Rescue), play `RESCUE` (only if not
     already playing).
   - If Bones exists and Bones' frame (+0xe4, s16) `> 80`: `ending = 1`.
   - Gunter variant: if `head >= 186`: `ending = 1` (always true by then, since the tube stops
     being extended at 187 — so in practice the Gunter stream also ends at `tail > 177`).
3. **Fade** (skipped when `f == 1` and not ending):
   - Not ending: `f += dt`; at `f >= 1`: `f = 1`, set the plain palette (0x4148d0), no effect.
   - Ending: `f −= dt`; when `f < 0`: set every palette entry to **white** (255) if normal variant
     and `health > 0`, else **black**, and **return 1** (the stream is over, nothing else this
     frame).
   - Palette effect for `0 ≤ f < 1` (or `f > 1`), per byte `c` of the working palette:
     - `health > 0`, normal variant: `c' = trunc(c·f + 255·(1 − f))` — fades from/to **white**.
     - `health > 0`, Gunter variant: `c' = trunc(c·f)` — fades from/to **black**.
     - `health ≤ 0` (death, only possible in the Gunter variant): if `f > 1`: red
       `= min(255, r + trunc((2 − f)·255))`, g, b unchanged (a red flash rising for 1 s); if
       `f ≤ 1`: red = `trunc(256·f)` (as a byte), g = `trunc(g·f)`, b = `trunc(b·f)` (red to black
       in 1 s).
   So the stream fades in from white (normal) or black (Gunter) over **1 s**, and fades out over
   1 s (2 s with the red flash on death).
4. **Objects**: for each segment `s` from `tail` to `head − 1`, for each object in list `s` not yet
   updated this frame: Kurt → `0x435c4c`; `0x520880` → `0x43650c` (never); Gunter → `0x435a34`;
   SWH150 → `0x435b18`; Bones → skipped; anything else (lights, planet) → `0x43596c`.
5. Bones (if any) → `0x4364bc`.
6. **Camera** (see below), sound listener update (`0x403348` with the camera matrix).
7. Draw (if `0x5742a4`): `0x43592c`; in the stereo mode (`0x574314`) drawn twice with the eye moved
   ±0.25 u along the camera's right axis.
8. `timer_frame`; return 0.

#### Tube helpers ✅

- `centre(t)` (0x436668): `s = floor(t)`, `u = t − s`; linear interpolation between the
  translations of segment matrices `s` and `s + 1`.
- `frame(t, t + 1)` (0x4366f4): origin `centre(t)`; forward `Y = normalize(centre(t+1) − centre(t))`;
  `X = normalize(Y × (−camera_up))` with `camera_up` = the camera matrix row `0x573984` (the
  previous frame's); `Z = X × Y`. Columns X, Y, Z, origin.
- Objects other than Kurt are placed at `segment_matrix[floor(t)] · (x, 10·(t − floor(t)), z)`.
- Relink (0x436440): moves the object to list `floor(t)`; if `floor(t) < tail` or `≥ head` it
  fails and the object is freed.

#### Kurt (0x435c4c) ✅

`controlled = (Bones == null) and (health > 0)`.

1. **Input** (0x40934c): yaw rate `= +180` if `0x57eb30`, else `−180` if `0x57eb34`, else
   `−180 · 0x57ea18` (analog x); pitch rate `= +180` if `0x57eb38`, else `−180` if `0x57eb3c`, else
   `−180 · 0x57ea1c` (analog y). Same key variables as the fall (left/right/up/down ❓ — in the fall
   eb30/eb34 are −x/+x). Units °/s.
2. **Speed**: if `speed < 6`: `speed = min(speed + 1·dt, 6)` (accelerates 1 segment/s² back to
   6 segments/s = 60 u/s).
3. `t += speed · dt`.
4. **Advance**: if `t − 0.75 > tail + 1`: relink Kurt (and Bones) to segment `tail + 1`,
   `tail++`, generate one new segment (`0x434838`). Hence `head − tail = 31` while generating and
   Kurt stays ~1.75 segments after `tail`.
5. Animation update.
6. `F = frame(t, t + 1)`.
7. Drift:
   - controlled: `v = normalize(0.75·v + 0.25·F.Y)` (a lagging copy of the tube direction);
     `x += 100 · dt · (v · F.X)`, `z += 100 · dt · (v · F.Z)` — when the tube bends Kurt keeps going
     straight and drifts toward the outer wall.
   - not controlled: `x` and `z` each move toward 0 at 6.25 u/s (clamped at 0).
8. **Yaw** (+0x4c, neutral 90):
   - controlled and rate < 0: `yaw = max(yaw + rate·dt, 45)`;
   - controlled and rate > 0: `yaw = min(yaw + rate·dt, 135)`;
   - otherwise back toward 90 at 180°/s (clamped at 90).

   **Pitch** (+0x13c, neutral 0): same with limits −45 / +45, back toward 0 at 180°/s.
   Full deflection takes 0.25 s.
9. Steering motion: if `yaw ≠ 90`: `x += cos(yaw) · 25 · dt`; if `pitch ≠ 0`:
   `z += sin(pitch) · 25 · dt` (max ±17.7 u/s sideways). So +yaw rate (→ 135) moves −x, +pitch
   rate moves +z.
10. Previous position → +0x180. Model matrix = `F · R(roll, pitch, yaw, scale 1, translation
    (x, y = 0, z))` (0x46dfe8 then 0x46dba0); position = its translation.
11. **Wall collision** (controlled only), `0x43637c(position, t)`: planes of segment `floor(t)`
    (32). For each plane in order: `d = n·p + w − 1.5`; at the first with `d ≤ 0` return
    `k = d / (n · (p − centre(t)))` (the fraction of the way to the tube centre that puts Kurt
    back 1.5 u inside that wall); no plane → −1. If `k ≥ 0` (hit):
    - `r = sqrt(x² + z²)`; `yaw = 90 + 45·x/r`; `pitch = −45·z/r` (Kurt is turned to face back
      toward the centre at full deflection, so step 9 carries him inward next frames);
    - `x *= 1 − k`, `z *= 1 − k`; the matrix translation is recomputed with the old rotation;
    - sounds: `HITSIDE` (only if not already playing) and one of `HURT1`–`HURT7` at random
      (`rand_n(7)`, restarted);
    - **damage** if `health > 0`: easy −2, normal −(2 + rand_n(2)) = −2/−3, hard
      −(4 + 2·rand_n(2)) = −4/−6. If then `health < 1`: normal variant → `health = 1` (which
      triggers the rescue next frame); Gunter variant → `health = 0`, `ending = 1`, `f = 2`
      (death: red flash, fade to black, then game over);
    - `speed *= 0.9`, minimum 4.5.

    The test runs every frame, so grinding along a wall hurts repeatedly (HITSIDE isn't
    restarted, HURT is).

#### Lights (spawned by the generator, updated by 0x43596c) ✅

- Each generator call after the first (i.e. every new segment) frees every object still in the
  reused slot `head & 31`, then with probability 3/4 (`rand() & 3 ≠ 0`) calls
  `0x434f64(t = head − 1, pos = null, speed = −3)`:
  - sprite (`model = 0`, image struct `0x57f870` = `LIGHT` 64×64), scale (+0x58)
    `4 + rand()/8192` (4–8);
  - `x = (rand() − 16384)/4096`, `z = (rand() − 16384)/4096` (±4 u off the axis);
  - speed `−3 − rand()/8192` (−3 … −7 segments/s: they fly toward Kurt, i.e. 9–13 segments/s
    relative to him).
  (0x434f64 also accepts a given position and a positive speed; only this call exists.)
- Update: `t += speed·dt`, relink (freed once behind `tail`), position = segment matrix ·
  `(x, 10·frac(t), z)`; only the translation of +0xac is refreshed. No interaction with Kurt.

#### SWH150 — the health bonus (normal variant, 0x435b18) ✅

A walking "super health" (7-track model, `SWHANM` 10 frames looping) running down the tube's axis
ahead of Kurt: `t += 5.48·dt`, relink (freed if it leaves the ring), animation, oriented by
`frame(t, t + 1)`, placed on the axis. If `|position − Kurt.position| < 5`: **health = 150**
(above the usual 100), `APPLE` (restarted), freed.

Timing: it starts 15.25 segments ahead and Kurt gains 0.52 segments/s at full speed, so it's caught
after ≈ 28–29 s — just before the rescue at `tail > 177` (≈ 29.8 s), and only if Kurt never lost
speed on a wall (each hit × 0.9) and is within 5 u of the axis. A no-hit bonus.

#### Rescue — Bones (normal variant) ✅

Trigger (frame step 2): `health > 0` and (`tail > 177` or `health == 1`), i.e. after ≈ 30 s, or at
once when a hit leaves Kurt at 1 (or when he arrives with 1 health).

- Bones object allocated at Kurt's `t` and segment; copies Kurt's matrix (+0xac), position, yaw,
  pitch, roll; scale 1; model `BONES`.
- Both Kurt and Bones get `BONESANIM`, frame −1, time 0, hold −2 (no hold), rate 30; Kurt's
  loop flag is cleared (plays once). The animation contains the crane, the rope, Bones and Kurt's
  body, so the two models play one shared scene at Kurt's transform.
- Each frame after the object loop (0x4364bc) Bones copies Kurt's position and matrix and advances
  its animation. Kurt is no longer controlled: he drifts back to the axis (6.25 u/s), yaw/pitch
  return to neutral, no collisions; he keeps flying at up to 6 segments/s.
- When Bones' frame exceeds 80 (≈ 2.7 s): `ending = 1` → 1 s fade to white → leave.

#### Gunter variant (index 4, after LEVEL8) ✅

- No SWH150 and no rescue. `GUNTA` (Gunter holding Bones; `GUNTANIM` looping) flies along the axis
  from `t = 5` at a constant 6 segments/s (0x435a34: move, relink — freed and nulled when it leaves
  the ring —, animate, orient by `frame(t, t + 1)`, place on the axis). Kurt, also at 6, keeps the
  distance only if he never hits a wall. No interaction.
- The generator: from `head > 168` the turn angles are pulled toward 0 by 1 per segment (the tube
  straightens); when called with `head > 186` it no longer builds segments (head stays 187) and,
  once, spawns the **planet** (`0x4350dc(t = head − 3 = 184)`): a sprite, `PLANET`, scale 36, on
  the axis, speed 0 (static). It's seen at the end of the straight tube.
- End: `tail > 177` (and `head ≥ 186`) → `ending` → 1 s fade to **black** → leave.
- Health can reach 0 here: death sets `ending` and `f = 2` → 1 s red flash, 1 s red-to-black,
  then game over.

#### Camera (in 0x4352ac, 0x436828) ✅

- `A = centre(t − 0.75)`, `B = centre(t + 2)` (Kurt's `t`);
  `B' = B + 1.375 · (Kurt.position − B)` (on the line from B through Kurt, 37.5 % past him);
  `camera = 0.4·A + 0.6·B'`.
- Looks at `centre(t + 2)`: `fwd = normalize(target − camera)`, `right = normalize(up × fwd)`,
  `up = fwd × right` with `up` persistent across frames (starts at (0, 0, −1)). Rows right / up /
  fwd go to `0x573974` / `0x573984` / `0x573994`.
- Projection: zoom 2.4 (`0x57391c`), 600 × 360 view, centre (300, 180). (Drawing is documented
  separately.)

#### HUD ✅

The shared level overlays: messages (0x425474) and the health box (0x420830: `SC_STAT` bottom
right, digits `SNIP_TXT`; the number blinks when health ≤ 20). The stream's BNI has its own copies of
`SC_STAT`, `SC_BSTAT`, `SNIP_TXT`. No other HUD. The background `BG` is scrolled by the camera
angles (0x438bfc, wraps at 600 × 360).

### The end (main loop 0x401cb8, state 5) ✅

When 0x4352ac returns 1: `0x46f8a0`, cleanup `0x435210` (stops `WIND`, frees models and objects),
then:

- `health < 1` → game over (0x42618c(1), back to the menu);
- `i < 4` → statistics (state 6, `0x431b00(0)`, starting at the intermission) — health (possibly
  150) carries over;
- else `i = 5`, the save prompt (`0x42b520(1)`, type 3), state 7: LEVEL5 loads directly.

### Timeline (normal variant, no hits) ✅ (derived)

| Time | Event |
| --- | --- |
| 0–1 s | fade in from white; Kurt at 60 u/s; lights stream past |
| ≈ 28.4 s | SWH150 caught (health 150, `APPLE`) |
| ≈ 29.8 s | `tail` = 178: Bones + `RESCUE`, `BONESANIM` on Kurt and Bones |
| + 2.7 s | Bones frame > 80: fade to white 1 s |
| ≈ 33.5 s | statistics |

### Open questions (gameplay) ❓

- Physical keys behind `0x57eb30`…`0x57eb3c` (and whether the analog signs make "left" steer left
  on screen); the sign convention of 0x46dfe8's yaw/pitch.
- `PROFSHIP`, `FL_HVR`, `FL_WAVE` and `0x43650c` (keeps an object ≥ 5 segments ahead of Kurt at
  his speed, oriented by the tube frame, placed at `seg_matrix · (x, 10·frac, z)`) are unused:
  `0x520880` is only read.
- Palette effect for death at exactly `f = 1`: `trunc(256)` wraps to red 0 for one frame.

## Videos

✅ verified in code/data, ❓ guess.

**In the port**: `MDKFlc` decodes FLCs (tested against Pillow, `tests/flc_test.gd`), `MDKGif` the
slideshow's GIFs (`tests/gif_test.gd`), `MDKVideo` shows either through `flc.gdshader` at the
original's game rate (34 ms a frame). The main menu plays `MDK12.FLC` behind its items and then
the slideshow (`MenuSlideshow`); event 81 opens `EndMovie` (`MDKEND.FLC` with its sounds, flash and
hold, `--end` to test), then `MDKBZK.MVE` (`MDKMve`, tested against ffmpeg, `tests/mve_test.gd`;
centred on the 640 × 480 screen, its sound through an `AudioStreamGenerator`; the sound is a bit
shorter than the frames, 1462 samples against 66.7 ms, so the next frame comes early whenever less
than 0.25 s of sound is queued), then the menu. The `INTRO1A` splash (`IntroSplash`) comes before
the menu at start, after Kurt died and after the end movies (`GameState.splash`; `--menu` skips it
unless `--splash` is given). Not done: the abort prompt during the end FLC (Esc goes to the menu, also during the MVE, which the original can't stop), the
slideshow's key `0x57ea34`.

### Where videos play


#### `MDK12.FLC`: the main menu background (0x4260e4)

0x4260e4 opens `MISC\FLIC\MDK12.FLC` (0x4262a8) and makes it the menu background. If the file is missing it shows the `MDKOPT` still with its palette (0x4148d0) ✅.
Its 4 callers are all "the main menu opens" ✅:

| Caller | When |
| --- | --- |
| 0x42618c(0) (menu init) | back to the menu without a splash: game aborted (Esc → abort prompt → 0x403e08, also during the end FLC), save list closed (0x428f9c), loading a save failed (0x429100, 0x430930), 0x403dbc |
| 0x426edc, end | after the `INTRO1A` splash. `0x42618c(1)` shows that splash first: at program start (0x40272c), on game over (0x40216e), after the end videos (0x47727c) |
| 0x427210, end | `INTRO1A` + `INTRO2` splash. **Unused**: `OPTIONS.BNI` has no `INTRO2` ✅ |
| 0x427644, end | `SHINY.FLC` + `PIE.FLC`. **Unused**: needs a `PLAYMATE` entry in `OPTIONS.BNI` (0x427898), which is absent ✅ |

The dispatcher is 0x427898: `PLAYMATE` → 0x427644, else no `INTRO2` → 0x426edc, else 0x427210. `0x4911a0` holds the sub-state.

- The `INTRO1A` splash (0x426edc) is a still image, not a video ✅: two 8-bit palettes (768
  bytes each), then 600 × 360 run-length pixels (0x426e04: a negative count copies that many bytes,
  a positive one repeats the next byte, 0 ends). The palettes show different parts of the one
  image: the first the Shiny Entertainment logo, the second the publishers' lines. Steps (timer
  `0x57f1a4`): from black to palette 1 in 1 s (0x417040, colour (0, 0, 0)), 3 s (`0x495074`),
  palette 1 to palette 2 at 0.5/s (`0x49506c`, 0x4170ec), 3 s, palette 2 to black in 1 s. Any
  key (once all keys were released) goes straight to the menu.
- The options sub-screens (sound options 0x42bb6c/0x42bbc0) don't replay MDK12 ✅ (they don't call 0x42618c).

#### Menu attract slideshow (`MISC\MDKS_%3.3d.GIF`, 0x4279a0), not a video, but it replaces the FLC

While the FLC plays, the idle timer `0x4911cc` stays at 0. After the FLC ends ✅:
- after 5 s (`0x495054`): `MDKS_001.GIF` replaces the background. The menu items are hidden while image #1 shows.
- after 4 s (`0x49505c`): `MDKS_002`, and so on, each shown 2 s (`0x495064`) with the menu items over it.
- After the last GIF (`MDKS_009` missing) the counter goes back to 0 and the last MDK12 frame shows again (the FLC is not replayed). The cycle then restarts.
- Each GIF uses its own palette and must be 600×360.
- Menu navigation resets the timer. On image #1 it sets the timer to 999, so the next image comes at once. Key flag `0x57ea34` advances at once ❓ (which key).

#### `SHINY.FLC` → `PIE.FLC` (0x427644), unused in retail

Sub-states:
1. Draw `MDKOPT`, then load SHINY completely into memory (0x426310) with a loading bar.
2. Play SHINY one frame per tick.
3. Load PIE (loading bar, last SHINY frame behind it).
4. Play PIE.
5. Then `MDK12` + menu.

Any key skips straight to MDK12 + menu ✅. Probably the Shiny/Interplay logo intro of an OEM/demo build ❓.

#### The end: `MDKEND.FLC` → `MDKBZK.MVE` (game state 8, 0x47727c)

- Event 81 → `0x477248(1)` → state 8.
- The first frame (0x47730c):
  - unloads the level (0x41e658);
  - loads the whole FLC into memory with a loading bar (100..500 × 340..350 of the 600×360 view);
  - loads `MISC/FINISH.BNI` sounds;
  - allocates the 600×360 target and the 768-byte `fliclut` palette copy.
- Each frame: 0x477604 (extras + one FLC frame). When the FLC ends: cleanup (0x4777f4), then `MDKBZK.MVE` (0x477870, blocking), then `0x42618c(1)` → `INTRO1A` splash → MDK12 + menu ✅.
- `0x477248(0)`: the cheat at 0x42c5f0 (compared string `pxxyhccixyiisjn` at 0x4956d0; the typed form is ❓, the buffer goes through 0x42e060 first) jumps straight to the MVE, without the FLC ✅.
- Esc during the FLC opens the abort prompt (0x403cf8; state 8 is not excluded). "Quit" → 0x403e08 → 0x4772e8 cleanup → `0x42618c(0)`, which skips the MVE ✅. There is no other skip for the FLC.

#### `BONEFLC`: not a video

It is a pickup type. op_161 (`spawn_flagged`) creates it as a 9×9×6 box object. In the used-at-once table (0x4920e0 / string ref 0x49210c), case 11 of 0x46d478 only plays a sound (`0x5744d0`, `BONES` ❓). It shows no message and plays no FLC ✅.

### FLC playback

The player state is a 0x458-byte struct (menu: `0x57ed40`, end: `0x5994a0`).

- **Open** ✅:
  - from a file streamed into memory (0x414b68, used by MDK12);
  - from a memory image (0x4149b0, used by SHINY/PIE/MDKEND).
  - The magic must be `0xAF12` (FLC) or `0xAF11` (FLI). Decoding starts at `oframe1`.
- **Per frame, not blocking** ✅: one call to 0x414ee8 decodes one frame per game frame. The game frame is limited to ≥ 34 ms (≈ 29.4 fps).
  - **The header `speed` is stored (+0x124/+0x12c) but never read.** All FLCs play at the game frame rate, including `shiny.flc` (speed 60).
  - MDK12 is streamed: the first call decodes frame 1. The following ~9 calls each read 64 KB without decoding, then playback continues ✅. So frame 1 holds about 0.3 s.
- **End**: 0x414e84 is true when frames decoded == header `frames`. The ring frame is never shown. No loop: loop flag bit 1 is never set ✅. The last frame stays in the buffer, so **MDK12's last frame is the menu background** ✅.
- **Chunks** ✅:
  - 4 `COLOR_256`: all 256 entries, used directly as 8-bit RGB → 0x47070c (palette → RGB565 LUT `0x581c28`), no remapping. In all four files the palette appears only in frame 0.
  - 11 `COLOR_64` (sets only 64 entries; unused).
  - 15 `BYTE_RUN`, 7 `DELTA_FLC`, 16 `COPY`.
  - 12, 13, 18 are skipped. Any other chunk type is an error.
- **Target** ✅: the decoder writes into a 600×360 8-bit buffer (stride 600). For MDK12/SHINY/PIE that buffer is the `MDKOPT` BNI entry itself, overwritten and cleared. 0x46fa3c converts the buffer through the LUT to the 16-bit back buffer at **(20, 60) of 640×480**, the game view origin (`0x49229c/0x4922a0` = 20/60).
- **Over MDK12** ✅: the menu items (0x42c488, at y 0x1f + 0x24·i, centred) and the mouse cursor (0x42c010). The FLC palette replaces all 256 entries, so the text colours come from the FLC palette ❓.
- **Over the end FLC**: nothing is drawn, only a palette flash (§3) ✅.
- **Skip keys**:
  - menu/intro FLCs: any key (`0x57ea5c` = any key held, armed by `0x57f19c` once all keys are released). In the debug mode of `SEETHEWHOLEGAME`, item keys 3–8 pressed at that moment are remembered (0x4278d0 → `0x57f198`) and start that level (see "Menus").
  - MDK12 in the menu: nothing to skip (the menu works during it).

### End movie extras (0x477604, frame counter `n` = `0x599914`, 0-based, checked before decoding frame n)

| n | Extra (✅) |
| --- | --- |
| 1 | `DOGSHIP` starts (looped) |
| 0x81 = 129 | `DROP` (0x4992f0) |
| 0x85 = 133 | `FLYBY` |
| 0xba = 186, 0xc4 = 196 | `EXPLODE1` |
| 0xbc = 188 | `DOGSHIP` stops |
| 0xc2 = 194 | `ENDEXP` |
| 0xd2 = 210 | the current palette is copied to `fliclut` (0x470af8) |
| 210..232 | white flash: every RGB + `round(255·(n−210)/23)`, clamped (0x477594, `0x499340` = 1/23) |
| 233 | +255 (white). **The FLC freezes 30 ticks (1 s)** (`0x599910`) |
| 233..260 | back down: + `round(255·(260−n)/28)` (`0x499344` = 1/28) |

- The sounds are 2D, volume 0x7fff. Only `DOGSHIP` loops. There is no music.
- The FLC is 316 frames ≈ 10.7 s + 1 s freeze.

#### `MDKBZK.MVE` (0x477870)

- **Own player, blocking**: the linked Interplay MVE library at 0x485b80..0x48b1d8. Calls in order:
  - memory callbacks 0x477228/0x477238;
  - show-frame 0x477088;
  - read 0x4771f8 (`fread`);
  - palette 0x476ff0;
  - screen 640×480, pitch 640 (0x485c70);
  - DirectSound `0x492294` (0x485c60);
  - DirectDraw `0x492310`;
  - `rmPrepMovie(file, x = −1, y = −1, track 0)` (0x485f10).
  Then a Win32 `PeekMessage` loop calls `rmStepMovie` (0x4861b0) until it returns non-zero (end/error) → `PostQuitMessage` ✅.
- **Not skippable** ✅: the loop never reads keys. Only closing the window (WM_DESTROY) ends it.
- **Afterwards** ✅: `rmEndMovie` (0x4875f0), clear screen, global palette (0x4148b0), `0x42618c(1)` → INTRO1A splash → MDK12 menu. There are no credits.
- **Drawing** ✅: 8-bit DirectDraw surface → RGB565 LUT row by row (0x46fae0) into the back buffer, locked at the rect (dstX, dstY, w, h). x/y = −1: centred by the library ❓ → 432×320 at (104, 80).
- **Palette** ✅: 6-bit → 8-bit (`v<<2 | v>>4`), 0x476ff0 → 0x47070c.
- **Sound** ✅: the movie's own audio track through DirectSound.

### Sound during videos

| Video | Sound |
| --- | --- |
| MDK12 (menu) | `MAINSONG` (started by 0x426050 just before 0x4260e4) ✅ |
| INTRO1A splash, SHINY/PIE | `MAINSONG` (0x42618c always starts it) ✅ |
| MDKEND.FLC | `FINISH.BNI` effects only (§3) ✅ |
| MDKBZK.MVE | its own audio stream ✅ |

### MVE format for a decoder

The exe's opcode switch (0x4861b0) ✅:

| Op | Handling |
| --- | --- |
| 0 | end of stream |
| 1 | end of chunk |
| 2 | create timer |
| 3 | init audio |
| 4 | start audio |
| 5 | init video buffers (0x486f50: 8-bit or 15-bit `0x7c00/0x3e0/0x1f`) |
| 6 | old video codec (0x488144) |
| 7 | show frame (end of frame) |
| 8, 9 | audio data / silence (by stream mask) |
| 10 | video mode (ignored here) |
| 11 | gradient |
| 12 | palette |
| 13 | compressed palette |
| 14 | skip-display marker |
| 15 | decoding map (consumed by 0x11) |
| 16 | 0x48835e |
| 17 | video data, version ≥ 3 required; 8-bit decoder **0x488609**, 16-bit 0x48a084/0x48b1d8 |
| 19, 21 | not handled (skipped) |

Header check (0x485fb0): 20-byte `"Interplay MVE File\x1a\0"`, `u16 0x1a`, `u16 0x0100`, `u16 0x1133` (`~0x100 − 0x1133 = −0x1234`) ✅.

**MDKBZK.MVE contents** (parsed ✅): 3146 chunks.

| Chunk | Type | Contents |
| --- | --- | --- |
| 0 (off 26) | 2 init video, len 804 | op 10 v0 `640, 480, 0x0101`; op 5 v2 `54×40 blocks, 1, truecolor 0` → **432×320 8-bit**; op 12 v0 palette start 1, count 254 (6-bit); op 21 v0 `00 95 05 05`; op 1 |
| 1 | 0 init audio, len 18 | op 3 v1 → flags `0xaa9f`: stereo, 16-bit, compressed; rate `0x5622` = **22050 Hz**; min buffer 88280 |
| 2..15 | 1, audio only (14 frames of preload) | op 8 v0 + op 9 v0 (mask `0xfffe`) |
| 16.. | 3, video | op 2 v0 (first only); op 15 v0 (1080 B = 54·40 / 2: 4-bit opcode per 8×8 block); op 8; op 9; op 17 v3 (14-byte header: `u16 seq…, u16 54, u16 40, u16 flags` (bit 0 = delta/swap ❓), then data); op 19 v0 (132 B, ignored); op 4 v0; op 7 v1 (`palette start, count, 0`); op 1 |
| 3143 | 3 | silence only, show |
| 3144 | 4 shutdown | op 0 |
| 3145 | 5 end | — |

- **Timer**: op 2 = `8341 µs × 8` = 66.73 ms/frame → **14.99 fps**.
- **Length**: 3128 frames ≈ **208.7 s**.
- **Video**: 3126 op-17 frames, 8-bit Interplay video, 16 block opcodes, 2 buffers. Same as ffmpeg `interplayvideo`.
- **Audio**: 1470 samples/frame, Interplay DPCM (an initial s16 per channel, then 1 byte/sample indexing the 256-entry delta table). Same as ffmpeg `interplay_dpcm`.

### Port notes

- MDK12: decode into a 600×360 image at 29.4 fps, no loop. Keep the last frame. Menu items and cursor on top. Slideshow afterwards.
- MDKEND: 316 frames at the game rate, sound and flash table above, then the MVE. Godot can't play MVE: convert it offline (ffmpeg reads it) to OGV, or write a decoder.

## Menus

✅ verified in code/data, ❓ guess. Coordinates are in the 600 × 360 view, whose origin is screen
(20, 60) of 640 × 480.

**In the port** (`MenuItems`, `MenuEntry`): every page is drawn in `FONTBIG` (`FONTSML` when the
rows get below 24, the key bindings) through `SYS_PAL`, rows of 36 from y 5 (baselines 31 + 36 ×
row; longer pages get lower rows), the selected item growing from 65 % to full size in 5 ticks
and the one left shrinking back, `SND_PUSH` on each move. The main page is a column at the view's
left edge (items centred on half its width), the others are centred; the view is fitted to the
window as the videos are. Esc on the main page asks `ABORT1` "Really Quit?" (rows 3–5, Y/J/O/S/T
yes, N or Esc no). Kept from the port, not in the original: the "Level" item, the pause menu
(the original's Esc goes straight to "Really Quit?"), the options page (volumes, mouse, window,
difficulty, gore, keys). Gore: `Settings.gore` (saved, default on), the switches `--bloodyes` and
`--nobloodno`, and the cheat `TOOSCARYFORME` typed in a level (`runtime.option`); without it flesh
sparks are blue, objects burst without slime, op 129 mode 2 blows nothing off, bullet holes are
`BHOLE2` and the Score-O-matic leaves out the head shots. The mouse cursor is `ARROW` (scaled by
whole steps to the window). The cheat `SEETHEWHOLEGAME` typed in a level turns on the main menu's
debug keys (`GameState.debug_keys`): 3–8 start that level, F the fall of level index 4, S the
stream after index 0, D the statistics with random counts (below 100 ❓). Not done: the
original's options sub-pages, the key repeat (30 ticks, then every 3).

### Common machinery

#### Fonts (`MDKFONT.FTI`, 0x41576c) ✅

| Entry | Global | Space width | Draw (x = left, y = baseline) |
| --- | --- | --- | --- |
| `FONTBIG` | `0x574424` | 6 | 0x415a20 (scale 1), 0x415d8c (scaled), width 0x4159d4 |
| `FONTSML` | `0x574420` | 4 | 0x415bd8, width 0x415b8c |

- Font = 256 × u32 glyph offsets (0 = no glyph, advance by the space width), glyph = `i8 top`,
  `i8 bottom`, `u8 width`, then `width × (top + bottom + 1)` palette indices, 0 transparent. Rows
  start at `baseline − top`. Advance = glyph width, no kerning.
- Pixels are palette indices 1–62 (FONTSML also uses 1–59), drawn through the current palette LUT
  `0x581c28`.
- Centred helpers: 0x415b30 (FONTBIG, x = (600 − w) / 2; falls back to FONTSML if w > 599),
  0x415d44 (FONTSML centred), 0x415ff0 (FONTBIG centred, scaled: x = round((600 − w·s) / 2)).
- `param_1` ≠ 0 on the draw functions adds a **blinking selection box** (0x415914): two nested
  rectangle outlines around the text, colours 1/2 swapped every 8 ticks (`timer & 8`). FONTBIG
  menus never use it (they scale instead); the FONTSML pages (keyboard, mouse, joystick, saved
  games) do.
- `FONTSML` holds icon glyphs for special keys: the key-name tables map scancodes to codes 1–0x1f
  and 0x80–0x92 (Esc, Backspace, Tab, Enter, Ctrl, Shift, Alt, Space, Caps, F1–F12, arrows…).

#### Text colours ✅

The glyphs only use palette entries 1–63. `SYS_PAL` (FTI, 64 RGB triplets, entry 0 forced black
by 0x4022c4, copied to `0x5735e4`) defines them. `MDK12.FLC`, all `MDKS_00n.GIF` and all
`LOAD_n.LBB` palettes carry the same 63 entries (checked byte for byte), so the menu text has the
same colours whatever image is behind it. **The port can render the glyphs through `SYS_PAL`.**
Useful entries: 0 black, 1 white, 2 (155,255,0), 3 green, 4 (0,151,0), 6 cyan, 14 (0,0,195).

#### The growing selection (0x42c374) ✅

`scale(active, key_x, key_y)`, an item being identified by its (x, y) pair:

| Item | Scale |
| --- | --- |
| selected, `t` ticks since it was selected (`0x57f2ec`, advanced by the frame's ticks on the `active` call) | `0.65 + t × 0.35 × 0.2` until t = 5, then 1.0 |
| previously selected, t < 5 | `1 − t × 0.07` (shrinks back) |
| other | 0.65 |

Scaled glyphs keep the baseline (0x415d8c, nearest-neighbour, 16.16 steps); below 0.05 nothing is
drawn. Callers: 0x42c488 (FONTBIG centred on a given x: `x = cx − w·s/2`), 0x42c4d8 (FONTBIG
centred on 300), 0x42c460 (FONTBIG left at x = 4).

#### Input helpers ✅

Key flags come from a 128-bit scancode bitmap (`0x4921f8`), extended keys in the 0x60 range
(0x67 Up, 0x69 Left, 0x6a Right, 0x6c Down, 0x66 Home, 0x6b End, 0x68 PgUp, 0x6d PgDn).

| Helper | Key | Behaviour |
| --- | --- | --- |
| 0x42c104 | Up (`0x57ea48`) | auto-repeat: at once, then after 30 ticks every 3 ticks |
| 0x42c188 | Down (`0x57ea4c`) | same |
| 0x42c20c | Left (`0x57ea40`) | same |
| 0x42c290 | Right (`0x57ea44`) | same |
| 0x42c0b4 | Enter (edge, `0x57ea54`) or mouse button (`0x57eb20`, edge) | activate |
| — | Esc (edge, `0x57ea50`) | back (each page tests it itself) |

Each of these plays **`SND_PUSH`** (WAV in `MDKFONT.FTI`, 0x42c084, unless `0x4913a4`) when it
fires. Mouse hover does not click. The sound page plays `OPTBUTT` instead.

Mouse: cursor `0x57eb14/0x57eb18`, clamped to x ≤ 590, y ≤ 350 on every page; rows are picked
from y only (any x), when the mouse moved (`0x57eb24/28`) or a button is held.

#### Cursor (0x42c010) ✅

`ARROW` (FTI) is a one-frame RLE sprite (same format as `K_*`), 8 × 17, hotspot (0, 0), drawn at
the mouse position last, on every page.

### Main menu (game state 0, 0x4265c0) ✅

Background: `MDK12.FLC` (then the attract slideshow, see gameplay.md "Videos"). No title.

| Row | Text | y (baseline) | Action on Enter / click |
| --- | --- | --- | --- |
| 0 | `OPT0` "Continue" (only if `LASTGAME.SAV` is valid, `0x57f1a0`) | 31 | 0x426504 (stop music, free menu), load `LASTGAME.SAV` (0x430930); failure → 0x42618c(0) |
| 1 | `OPT1` "New Game" | 67 | 0x426504(1), 0x4240a0(0): level index 0, statistics/briefing (state 6) |
| 2 | `OPT2` "Saved Game" | 103 | 0x426504(2), 0x428cfc (list) |
| 3 | `OPT3` "Options" | 139 | 0x429730 (options page) |
| 4 | `OPT4` "Quit" | 175 | quit the program (`0x57425e` = 1) |

- Without "Continue" the rows shift up: New Game at y 31 … Quit at y 139 (y = 31 + 36·k, k = visible index).
- **x**: every item is centred on `cx = max_width / 2`, max over all five texts in FONTBIG (OPT0 is
  measured even when hidden). English: widths 158/190/224/139/75 → cx = 112 (screen x 132). So the
  menu is a column at the **left edge of the view**, not centred on screen.
- FONTBIG, scale from 0x42c374 (selected grows 0.65 → 1.0 in 5 ticks).
- Initial selection (0x42618c): Continue if present, else New Game.
- Up/Down wrap (4 ↔ 0, or 4 ↔ 1 without Continue). Mouse row = `(y − 5) / 36` (+1 without Continue),
  valid rows only. Navigation resets the slideshow timer.
- **Esc** opens the "Really Quit?" prompt (main loop 0x401cb8 → 0x403cf8; Yes quits the program).
  F-keys do nothing in the main menu (the F-key dispatch in 0x401cb8 needs a level, state ≠ 0).
  Correction to gameplay.md "Skip keys": 0x4278d0 remembers the item keys 3–8, not function keys,
  and only in the debug mode below.
- The items are hidden while the first slideshow GIF shows (`0x4911c0` = 1).
- `OPTSTRT` "Starting New Game..." has no code reference (unused) ✅.

#### No level select ✅

The retail menu has no level item. A hidden debug mode exists: the cheat **`SEETHEWHOLEGAME`**
(typed in a level, toggles `0x5742bc`) enables, in the main menu:

| Key | Effect |
| --- | --- |
| `3`…`8` (item keys 3–8, `0x57eb78…0x57eb8c`) | 0x426574: start `LEVELn` directly (table `0x490030` = {7,6,3,4,8,5,2,1} gives the index), no briefing/fall |
| `F` (`0x57ea64`) | the fall of level index 4 (0x410018) |
| `S` (`0x57ea80`) | the stream, level index 0 (0x433b50) |
| `D` (`0x57ea60`) | the statistics screen with random counters (0x431b00(0)) |

The port's "Level: N" item is not in the original; keep it behind a debug flag or drop it.

### Options page (overlay 11, 0x4298f8; opened by 0x429730 from the menu or F12 in game) ✅

On a cleared (black) screen; the palette is saved (`svlut`) and replaced by `SYS_PAL`; the game
(if any) is paused. FONTBIG, centred on x = 300, y = 31 + 36·row, growing selection (0x429838).
Selection `0x57f240`, starts at 9 (Quit).

| Row | Text | y | Action (Enter/click; Left/Right too) |
| --- | --- | --- | --- |
| 0 | `OM_HELP` "Help" | 31 | 0x425e70 → help page |
| 1 | `OM_SOUND` "Sound" | 67 | 0x42bb6c → sound page |
| 2 | `OM_JOY` "Joystick" | 103 | 0x428454 → joystick page |
| 3 | `OM_MOUSE` "Mouse" | 139 | 0x42a0d4 → mouse page |
| 4 | `OM_KEY` "Keyboard" | 175 | 0x427a60 → keyboard page |
| 5 | `OM_PERF` "Performance" | 211 | 0x42a8e0 → performance test |
| 6 | `OM_SK_0/1/2` "Skill - Easy/Normal/Hard" | 247 | Enter/Right +1, Left −1, wraps (`Skill`, `0x57423e`) |
| 7 | `OM_DISPL` "Display" | 283 | 0x425940 → display page |
| 8 | "Direct3D" (literal, not `OM_3D`) | 319 | 0x475fe8 → Direct3D page |
| 9 | `OM_QUIT` "Quit" | 355 | 0x4297a8: close |

- Rows 2–4 are hidden and skipped when `0x5742c4` is set (command-line `-mapok` toggles it).
- Mouse row `(y − 5) / 36`, 0–9. Esc = Quit.
- Close (0x4297a8): writes `MDK.CFG` if anything changed (`0x57424a`), restores the palette,
  resumes the game. From the menu it returns to the main menu without replaying MDK12 (the FLC just
  continues).
- The dispatcher on `0x574263` (overlay) in 0x401cb8: 1 saved list 0x429100, 2 sound 0x42bd20,
  3 joystick 0x428638, 4 mouse 0x42a258, 5 keyboard 0x427bbc, 6 performance 0x42ae18, 7 display
  0x425b08, 8 save prompt 0x42b75c, 9 abort prompt 0x403eb4, 10 help 0x425f60, 11 options 0x4298f8,
  14 Direct3D 0x476160.

### Sub-pages ✅

All on black, cursor drawn, back with Esc.

#### Sound (0x42bb6c open, 0x42bd20 frame, 0x42bbc0 close)

- Stops `MAINSONG`, loads `MISC/MDKSOUND.SNI`, loops `OPTSONG`; `OPTBUTT` on every key.
- `SND_TITL` "Sound Settings" centred y 31; `SND_INFO` "Left/Right to Change Volumes" centred y 350
  (FONTBIG).
- Rows i = 0..2, baseline 87 + 46·i: "Effects" (`SND_FX`, `SoundFX`), "Music" (`SND_MUSI`,
  `SoundMusic`): label FONTBIG left at x 4 (growing selection); bar = filled rect colour 4 from
  x 210 to 210 + vol·280/100, y 75 + 46i … 86 + 46i; `SND_0` "0%" FONTSML at x 175, `SND_100`
  "100%" at x 498. Row 2 `SND_DONE` "Done" FONTBIG centred.
- Left/Right ±10, clamped 0–100, applied at once (0x403114). Mouse row `(y − 61) / 46`.
  Enter on Done or Esc closes. `SND_SET` / `HMI_*` (DOS device setup) unused here.

#### Display (0x425940 open, 0x425b08 frame)

- Rows (FONTBIG centred, growing): y 31 `DSP_BRGT` "Brightness %d" (0–7, `Brightness`
  `0x574242`), y 67 `DSP_DETH`/`DSP_DETL` "Detail is High/Low" (`ForcePCorrect` `0x574246`),
  y 103 `DSP_QUIT` "Quit". Mouse row `(y − 5) / 36`.
- Left/Right/Enter change; brightness reloads the palette at once (F11 in game also cycles it,
  0x425ab4).
- Below: four 48-step ramps (grey, red, green, blue; palette entries 64–111, 112–159, 160–207,
  208–255 = i·255/47), each step a 10 × 32 box from x 60, rows at y 200, 232, 264, 296 (0x4258a0).

#### Help (0x425e70 open, 0x425f60 frame)

`HELP_TOP` centred FONTBIG y 31; `HELP_01`…`HELP_18` FONTSML at y 60 + 16·i, the text before the
tab at x 4, after it at x 150; `HELP_BOT` FONTSML centred y 354. Any of Enter/arrows/Esc returns
to the previous overlay (or the game, F1).

#### Keyboard (0x427a60 open, 0x427bbc frame)

- 19 bindings, FONTSML, column = i / 10, row = i % 10: label at x 10 + 310·col, key glyph at
  x 210 + 310·col, y 64 + 30·row. Order: Left, Right, Up, Down, Jump, Strafe Left, SideStep,
  Strafe Right, Sniper, Fire, Turbo, SetTurbo, Look Up, Look Down, Zoom In, Zoom Out, Next Item,
  Last Item, Use Item (`KM_*`).
- `KM_RESET` "Set Defaults" centred y 16 (restores `0x491935`), `KM_QUIT` "Quit" centred y 32.
- The key is shown as one character from a per-language table (`0x4911d0` English, `0x491250`
  `LANG` = F, `0x4912d0` = G).
- Selection: blinking box on the label; Enter → waiting (box on the key, `KM_DOIT` "Type New Key,
  ESC to Cancel" centred y 354), next key stored (`Key*` in `MDK.CFG`).
- Arrows (all four) move through 0–20 with wrap; mouse: y 2–17 → Set Defaults, 18–33 → Quit,
  else row `(y − 50) / 30`, +10 if x > 319.

#### Mouse (0x42a0d4 open, 0x42a258 frame) / Joystick (0x428454, 0x428638)

Same layout (FONTSML): left column centred on x 150, y 16 + 16·i: `JOY_TEST` "Test",
`M_ENA`/`M_DIS` (`MouseOn`), `M_NORM`/`M_REV` (`MouseYReversed`), `JOY_QUIT` "Quit"; axis rows at
the bottom left with a bar; a test box (50, 110)–(150, 210) with a dot following the motion; on the
right a 16-row grid `JOY_BA`…`JOY_BP` (actions) × buttons (4 for the mouse) of check boxes
(`MouseWButtMapA…D`). The joystick page has `JOY_ENA/DIS`, `JOY_GPAD/JOY_PROP`. Low priority for
the port ❓ (details not mapped).

#### Performance (0x42a8e0, 0x42ae18)

`PRF_TEST` centred y 31; reference rows `PRF_P90`, `PRF_P166`, `PRF_P200`, `PRF_THIS` FONTSML at
x 10, y 100/122/144/166; elapsed `PRF_ELAP`. A rendering benchmark; skip in the port.

#### Direct3D (0x475fe8, 0x476160)

English literals in the exe (not FTI): "Direct3D Configuration" centred y 31; rows i = 0..6 FONTSML,
label x 100, value x 350, y 104 + 20·i: Bilinear filtering, Smooth shaded stream, Masked textures,
Texture error detection, Max texture size, Kurt is a, Screen fades; "Test" y 244, "Quit" y 264.
Bits of `D3DOptions`. Not relevant to the port.

#### Saved games (0x428cfc open, 0x429100 frame, 0x428f9c close)

- `SAVES/*.SAV`, names ≤ 8 chars, sorted (qsort, 0x428cf0).
- `SVOPT1` "Select Saved Game\nESC to Quit": FONTBIG centred, lines at y 31 and 67 (0x42c314, 36 px
  per line). None: `SVOPT3` centred at y 100.
- Names FONTSML at x 98, y 103 + 16·i, 13 visible, blinking box on the selected one.
- Preview: `LOAD_n.LBB` (light saves) centred on x 450 at y 103, or the 64 × 45 thumbnail at
  (418, 103); the preview's palette is installed. `SVBAD` FONTSML at (10, 354) if unreadable.
- Keys: Up/Down, Home/End, PgUp/PgDn (±13, repeat every 7 ticks), a letter/digit jumps to the first
  name ≥ it; mouse row `(y − 103) / 16` + scroll, above 103 / below 311 scrolls. Enter/click loads,
  Esc closes (from the menu: 0x42618c(0), MDK12 restarts).

### Abort prompt "Really Quit?" (overlay 9, 0x403cf8 open, 0x403eb4 frame) ✅

Opened by Esc (in a level and in the main menu; not in the statistics state 6 nor during the
splash) and F10. Pauses the sounds, keeps the old palette (`0x49005c`) and sets entries 0–63 to
`SYS_PAL`. Each frame on a cleared (black) screen:

| Line | Text | y | Font |
| --- | --- | --- | --- |
| title | `ABORT1` "Really Quit?" | 139 | FONTBIG centred, scale 1 |
| 0 | `ABORT2` "Yes" | 175 | FONTBIG centred on 300, growing |
| 1 | `ABORT3` "No" | 211 | same |

- Initial selection Yes (0). Up/Down wrap; mouse row `(y − 149) / 36`.
- Enter/click on the selection; **Y, J, O, S, T** (`0x57ea8c`, multi-language yes) = Yes;
  **N** (`0x57ea74`) or **Esc** = No.
- Yes (0x403e08): in a level → unload it, back to the main menu (0x42618c(0), no splash); in the
  menu → quit the program. No (0x403dbc): restore the palette and resume.

### Pause (0x42d2a0) ✅

Not a menu. **P** (`0x57ea78`) or **Pause** (`0x57eb10`) in a level toggles `0x490050`; P/Pause/Esc
resume. The frozen frame stays; `PAUSED` "Game Paused" FONTBIG centred at y 150 on a black box
(0x42d220: filled colour 0 from x 296 − w/2 to 304 + w/2, y 120–157, white outline 298 − w/2 …
302 + w/2, y 122–155). It blinks: shown 30 ticks, hidden 15 (period 45 ticks = 1.5 s).

### In-game function keys (0x401cb8, level loaded, no overlay) ✅

| Key | Action |
| --- | --- |
| F1 (`0x57eab4`) | help 0x425e70 |
| F2 (`0x57eab8`) | save prompt 0x42b520(0) |
| F3 (`0x57eabc`) | saved games 0x428cfc |
| F10 (`0x57ead8`) | abort prompt 0x403cf8 |
| F11 (`0x57eadc`) | brightness +1 (0x425ab4) |
| F12 (`0x57eae0`) | options 0x429730 |
| Esc | abort prompt |

**There is no in-game pause menu with Resume/Options/Main menu**; Esc goes straight to "Really
Quit?". The port's `PauseMenu` (Resume, Options, Main menu, Quit) is an invention.

### Gore (`0x5742dc`) ✅

**No menu item and no `MDK.CFG` key.** Default 1 (set at start, 0x40272c → 0x4027e6), not reset
per game.

| Setter | Effect |
| --- | --- |
| command line `-bloodyes` (0x402570) | 1 |
| command line `-nobloodno` (0x402550) | 0 |
| cheat `TOOSCARYFORME` typed in a level (0x42c5f0, 0x42d07e) | toggles, reloads `BHOLE`/`BHOLE2` |

(Cheats and these switches are stored encoded: 0x42e060 shifts the i-th character from the end
by 3 + 7i.)

Tests:

| Address | Function | With gore on / off |
| --- | --- | --- |
| 0x41b90f | `level_load` | sniper hit marker `BHOLE` / `BHOLE2` |
| 0x41e919 | 0x41e8f4 sparks, kind 0 (flesh) | green (colours 3–6) / blue (13–16) |
| 0x43290b | 0x4328a4 Score-O-matic | "Head shots" row shown / skipped |
| 0x43d55e | 0x43d224 object break-up | up to 32 slime drops / none |
| 0x45c4af | 0x45c498 op 129 mode 2 | parts blown off / names skipped |
| 0x445579, 0x4485b9, 0x45706f | script interpreter (0x440bc8 area) | op 128 `attach_effect`, op 136 `spawn_debris` (1 drop when off), op 232 `if_option` ❓ (mapping of the three addresses to the ops not checked) |

The gore colour is green vs **blue**, not red.

### `MDK.CFG` (0x42e654 read, 0x42e9a0 write) ✅

- Read at start: `getenv("mdk_cfg")` path, else `C:\MDK.CFG`, else `MDK.CFG`. Lines `key = value`,
  `;` starts a comment, keys case-insensitive.
- Written when leaving the options page with changes (`0x57424a`), to the same file: header
  `; MDK Configuration file automatically generated by MDK`, then only keys that differ from the
  defaults (`cddata`, `hddata`, `hduse` always).
- Table `0x4913d0`, 95 entries of 9 bytes (`char *name, u8 type, void *var`); default =
  `var − 0xe288d`. Types: 0 int `%d`, 1 float `%g`, 2 bool (`T…` = true), 3 string, 4 hex `0x%X`.

| Key | Var | Default | Menu |
| --- | --- | --- | --- |
| `cddata`, `hddata`, `hduse` | 0x573fb4, 0x574034, 0x5740b4 | –, –, 2 | install paths |
| `SoundFX`, `SoundMusic` | 0x5740cc, 0x5740d0 | 70, 100 | Sound |
| `SoundIDX/ID/IRQ/DMA/Port` | 0x5740b8… | | DOS sound setup |
| `JoyOn`, `JoyMin/Cen/Max X/Y/Z`, `JoyType`, `Joy[WD]AxesMap`, `Joy[WD]ButtMap[A–L]` | 0x5740d4… | JoyOn 0 | Joystick |
| `Mouse[WD]AxesMap`, `Mouse[WD]ButtMap[A–D]`, `Mouse[WD][XYZ]Scale` | 0x574178… | | Mouse |
| `MouseOn`, `MouseYReversed` | 0x574236, 0x57423a | 1, 0 | Mouse |
| `KeyLeft`…`KeySideR` (19) | 0x5741c2… | scancodes, table 0x491935 | Keyboard |
| `Skill` | 0x57423e | 1 (Normal) | Options row 6 |
| `Brightness` | 0x574242 | 0 | Display, F11 |
| `ForcePCorrect` | 0x574246 | false | Display "Detail" |
| `D3DOptions` | 0x57424e | (bits) | Direct3D |
| `S3DOn`, `S3DDoppler`, `S3DFallOff` | 0x574252… | | none |

### Port gaps

- Replace Godot buttons by FTI glyphs (FONTBIG/FONTSML) drawn through `SYS_PAL`, positions above,
  growing selection, `ARROW` cursor, `SND_PUSH` on keys.
- Main menu: left column centred on x 112 of the view; drop "Level: N" (or debug only).
- Options: Help, Sound, (Joystick), Mouse, Keyboard, Skill, Display, Quit; drop Performance and
  Direct3D. Port-only extras (master volume, music filter, fullscreen, sensitivity) need a place ❓.
- Esc in a level → "Really Quit?" Yes/No, P/Pause → blinking "Game Paused"; F1/F2/F3/F10/F11/F12.
- Gore: a port setting (default on) or the `TOOSCARYFORME` cheat; nothing in the original UI.

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
- **The prompt** (0x42b520(1), each frame 0x42b75c, on a cleared screen ❓): `SV_ASK` at row −1,
  `ABORT2` "Yes" and `ABORT3` "No" at rows 0 and 1 (baseline `175 + 36 × row`, centred, in
  `FONTBIG`; up/down or the mouse select, rows `(y − 149) / 36`); unselected lines are drawn at 65 %
  and the selected one grows to full size in 5 ticks (0x42c374: `0.65 + ticks × 0.35 × 0.2`).
  "Yes" asks the name: `SV_TITLE` centred at y 31, the name below it one character per 28 pixels
  from x 202 (baseline 200), the cursor `_` blinking every 8 frames; typed letters and digits (and
  `_`, `$`, table 0x4955c8) replace the one at the cursor, up to 8; Backspace, Delete, Home, End,
  Left and Right edit; Enter saves (at least one character), Esc gives up. The name offered is the
  new level index + 1 (`"%d"`, 0x4955a4). After the Gunter stream it's the same with type 3 (the
  last level, named "6").
- **In the port** (`GameState`, `SavePrompt`): light saves as JSON in `user://saves/<NAME>.sav`,
  `LASTGAME` on death with "Continue" in the menu, the "Saved Game" list, and the prompt after the
  Score-O-matic and after the Gunter stream (drawn on black). A type 6 save shows the briefing and
  the fall first.
- **Full saves in the port** (F2, type 1003): the game stops and asks the name at once (offering
  the level's number ❓ what the original offers); the JSON save holds the level state as base64
  of `var_to_bytes` (floats stay exact). Each part saves itself: `MDKScriptRuntime.snapshot` (its
  globals, each arena's state with its controller and hit-script objects, every object's script
  variables through `MDKSnapshot`, which turns references into indices), `Level.snapshot_groups`
  (triangle groups' flags and textures), `MDKFans`, `MDKItems` (the bomb and the decoy) and
  `Kurt.snapshot` (place, health, pickups, clip). Loading recreates the objects from their type
  (or as boxes), sets their variables, and the scripts carry on where they were; Kurt stands
  still. Not saved: effects, debris, twisters, sniper rounds in flight, playing sounds (loops
  restart), the camera. F2 does nothing in a cutscene, at the end of the level, with a strike out,
  riding, sniping or dead. Test `tests/snapshot_test.sh` (`--snapshot=NAME`, `--load=NAME`): the
  state taken again right after loading has the same hash.

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
- **Inventory** (0x46cce4): always when Kurt has items, except in sniper mode, the items'
  `PICKUPS` icons (frame = item type − 1) at `(32 + 48 × slot, 328)` with their count above when
  above 1, at most 999; new items fly there from the pickup's place on screen. The selected slot is
  framed (`48 × slot + 8…+0x37`, 304–351), unless it's the super chain gun.
  - The timer `0x574328` gates the drawing, but 0x46cce4 itself sets it to 60 every frame unless
    in sniper mode with a phase (`0x573a60` and `0x573a64` ≠ 0), where it sets 0 (0x46ccfc–0x46ce07).
    Its other writers (60: `damp_animate`, `damp_move`, `damp_collect_pickups`, 0x46cb74, the throw
    0x46ce78, 0x46d1e8; 0: level start 0x432630) change nothing visible. Neither the super chain
    gun's tick-down (0x41a304) nor firing writes it.
  - The super chain gun's slot shows its ticks: each frame its count is set to `0x5743ef` (0x46cd85),
    so it counts down on screen while Kurt fires; at 0 the slot goes (0x46d0c0). Normal bullets have
    no count. Sniper ammo counts are shown only by the sniper screen.
  - Also drawn in the fall (0x4119ec).
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
  pushed away from it (`camera_clearance`, below).
- Projection: the 3D view is 600 × 360 with a focal length of 250 px: horizontal FOV 100.4°,
  vertical FOV 71.5°.

### `camera_clearance` (0x417ee8)

The original never moves the camera closer. When the arena BSP is between Kurt's head and the
camera, it moves **Kurt** (with collision) away from the wall and shifts the camera by Kurt's
actual movement. Distance and pitch are untouched.

#### Call site (`camera_update` 0x4174d0)

```
camera_update():
    if !sniper(0x573a60) && topdown(0x490de0): topdown camera (0x4183f0); return   # no clearance
    ... pitch, sway, D, H → camera point C = 0x5738ec..f4 (feet-relative, see gameplay.md "Camera")
    ... camera axes 0x5738f8.. / 0x573904..
    if 0x490db0 != 0 && |0x573b1c| == 0:
        camera_clearance(&C)          # C is the global camera position, modified in place
    build view planes from C
```

- `param_1` = `&0x5738ec`, the camera position just computed for this frame (the desired point),
  edited in place; the view matrix is built from it afterwards ✅.
- Skipped when:
  - top-down camera (`0x490de0`, not in sniper mode): early return ✅;
  - `0x490db0 == 0`: debug toggle, default 1, flipped by cheat `lchsyamqxrzxj` (0x42c5f0) ✅;
  - look offset `0x573b1c != 0` (look up/down keys held or returning) ✅.
- Not skipped: sniper mode (D = 0, eye z + 4: the segment z + 5.5 → z + 4 rarely hits ❓),
  riding (`0x573c30`), sliding, airborne, cutscenes — no test in either function ✅
  (`camera_update` is called unconditionally every `game_frame`, 0x41d4d8 ✅).
- Camera is recomputed from Kurt's position every frame; nothing persists ✅.

#### Pseudo-code

Constants ✅: `0x4940f8` f64 5.5 (eye height), `0x490e20` box half extents (0.1, 0.1, 0.1),
`0x494100` f32 +4, `0x494104` f32 −4, `0x494108` f64 0.5. `K` = Kurt's feet `0x5739c0/c4/c8`
(`_g_damp_position`).

```
camera_clearance(C):
    E = K + (0, 0, 5.5)                                          # head
    hit = bsp_sweep_box(E → C, box ±0.1, iterations 0, BSP of Kurt's arena 0x573a0c)
    if !hit && second(0x573a68) && !streaming(0x573b00):         # 0x573a6c NOT required
        hit = bsp_sweep_box(E → C, box ±0.1, 0, BSP of 0x573a68)
    if hit:
        P    = contact point (box centre at contact, out param)
        d    = |C.xy − P.xy|                    # FUN_004174ac: 2D distance, EAX=&P, EDX=C
        pl   = FUN_00409674()                   # = 0x4d4e60, hit plane (nx, ny, nz, dist) of the sweep
        n    = (pl.nx, pl.ny)                   # NOT renormalised: |n| < 1 on slopes
        if dot(pl.n, E) + pl.dist < 0: n = −n   # local_48: make n point to Kurt's side
        push = d · n                            # (local_30, local_2c), horizontal only

        if on_floor(0x573c10 != 0):             # airborne: no floor test
            # FUN_00421680 = segment vs BSP of Kurt's arena only (returns hit tri or 0)
            ok(v) = seg(K + (v.x, v.y, +4) → K + (v.x, v.y, −4)) hits
            side  = 0.5 · d · (n.y, −n.x)       # perpendicular to n
            if   ok(push):          pass
            elif ok(push + side):   push += side
            elif ok(push − side):   push −= side
            else: return                        # no floor there: no push, object pass skipped too

        K0 = K
        damp_collide_move(push.x, push.y, 0, 0.75, default box, 0)   # moves K with collision
        C += K − K0                             # 3D: the camera follows Kurt's real movement

    if 0x573a2c:                                # object collision on (default 1, debug toggle)
        E = K + (0, 0, 5.5);  T = C             # C already includes the push above
        for obj in Kurt's arena list (arena+0x68):                     # second arena not tested
            if obj+6 && obj+8 && !(flags & 0x810) && (flags & 0x1000000):
                if FUN_0045fa88(E, T, obj bounds +0x198, box 0x490e20):    # broad phase
                    for part in obj.model(+0xc).parts(+0x20, stride 0x5c, count +0x1c):
                        if FUN_0045f588(E, T, part box +0x44, &P) == 1: T = P    # clip end
        K0 = K
        damp_collide_move(T.x − C.x, T.y − C.y, 0, 0.75, default box, 0)  # always called; 0 if no hit
        C += K − K0
```

All lines ✅ except the names of the object fields (meaning taken from engine.md "Flags"; flag
0x1000000 = "solid for thrown items", the same set the items stop on ✅ / meaning ❓). Part
visibility (`obj+0x2c8`) is not checked ✅. A part the head is in (0x45f588 returns 2) doesn't clip
the view: Kurt teleported into a door isn't shoved through it (`tests/doorway_teleport_test.gd`).

#### Answers

1. `param_1` = the freshly computed camera position `0x5738ec` (desired point). Gates: see above.
2. Sweep: box ±0.1 from Kurt's head (feet + 5.5) to C, no sliding. Kurt's arena first; the
   second arena only if the first missed, `0x573a68 != 0` and `0x573b00 == 0` (it does not need
   `0x573a6c`, unlike `damp_collide_move`).
3. On hit: `d` = horizontal distance contact → desired camera (the part of the view segment past
   the wall). `0x409674` returns the hit plane pointer `0x4d4e60` (set by `bsp_sweep_node`).
   The plane normal's XY is flipped toward Kurt's head; push = `d · n.xy`, z = 0. On a floor, the
   push target must have floor under it (vertical segment ±4 around Kurt's feet z, Kurt's arena
   only); else ±0.5·d sideways along the wall; else nothing. The move goes through
   `damp_collide_move(dx, dy, 0, 0.75)` (4 slide iterations, Kurt's horizontal box, arenas and
   objects), which writes `_g_damp_position/0x5739c4/0x5739c8` (and 0x5739f4.. bbox, 0x573c2c
   touched object). The camera gets Kurt's real delta. No per-frame limit besides collision; one
   push per frame, converging in about one frame against a perpendicular wall.
4. Kurt blocked (wall behind him) or no floor: the camera is **not** moved closer. It keeps its
   distance and stays behind/inside the wall for that frame (shifted only by whatever Kurt
   actually moved) ✅. Walls hit at a grazing angle or floors/ceilings (n.xy ≈ 0) give little or
   no push, so the camera can also end up below a floor / above a ceiling ✅ (by the maths).
5. D, H and pitch are not read or written; Kurt's speeds untouched (`damp_collide_move` only adds
   to the position) ✅. Only link to pitch: disabled while the look offset `0x573b1c` ≠ 0.
   The push happens after the arena-crossing check (0x41c550 in `game_frame`), so a push across a
   connection is noticed next frame ❓.

#### In the port

`FollowCamera._physics_process` (after Kurt moved, `process_physics_priority` 1): a ray (not a
0.1 box) from the head to the camera point on Kurt's collision layer, the push and the floor
probe as above through `Kurt.shove` (move and one slide), then the object pass with the parts'
world boxes. Differences: it runs whatever the look offset (the port's look offset is the mouse's
and stays); it's skipped in sniper mode, cutscenes, the `XE` ride and when Kurt is dead. Test
`tests/camera_push_test.sh`.

## Kurt's sprite (`damp_sprite_draw`, `rle_draw_hotspot`)

Kurt is a 2D sprite: his feet are projected to the screen, and the frame's top-left corner is drawn
at (x − hotspot x, y − 101 − hotspot y), at 1 sprite pixel per pixel of the 600 × 360 view (no
scaling with distance). The Direct3D version draws it as a quad at Kurt's depth. With the default
camera, a 144-pixel frame is about 4.8 u tall, matching his collision box.
