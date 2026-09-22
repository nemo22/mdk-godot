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
