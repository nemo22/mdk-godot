# MDK sound system

Reverse engineered from `MDKD3D.EXE` (Watcom register calling convention: EAX, EDX, EBX, ECX, then
the stack). ✅ = read in the decompilation and checked in the disassembly where Ghidra lost FPU or
stack values; ❓ = uncertain or inferred. Addresses are virtual addresses in `MDKD3D.EXE`.

The sound code (`0x402b40`–`0x403c70`) is a thin layer over DirectSound (`0x46ec98`–`0x46f408`).
Every "voice" is one DirectSound buffer (a sample's own buffer, or a `DuplicateSoundBuffer` copy
when it's busy). There's no software mixing, no hardware 3D (DirectSound3D isn't used): the game
computes the volume, pan and frequency of each 3D voice itself, once per frame.

## 1. Data structures ✅

### Samples (`0x403a7c` `snd_load(name EAX, wav EDX, volume EBX, flags ECX)`)

A pool of 127 sample slots (0x18 bytes, free list `0x4d2e24`, loaded list `0x4d2e20`; "Out of
sound samples" / "Duplicate sound %s" are fatal):

| Offset | Content |
| --- | --- |
| +0 | next |
| +4 | flags: bit 0 **loop** (the buffer is played with `DSBPLAY_LOOPING`), bit 1 **music** (scaled by the music volume setting instead of the effects one) |
| +8 | default volume, 0..0x7fff |
| +0xc | sample rate (from the WAV header) |
| +0x10 | DirectSound buffer record (`0x580000` pool, 256 records of 0x18 bytes; buffers are created with `DSBCAPS_STATIC \| CTRLFREQUENCY \| CTRLPAN \| CTRLVOLUME` = 0xe2) |
| +0x14 | name (looked up case-insensitively by `0x403c38 snd_find`) |

The SNI table entry is `char[12] name, u16 flags, u16 volume, u32 offset, u32 length`: **the
second u16 is the sample's default volume** (the loaders pass `+0xc` as flags and `+0xe` as the
volume). `LEVELnS.SNI` entries with flag 0x8000 aren't loaded (`0x43121c`; none have it).
Values in the shipped archives:

- Flags 1 (loop): `BREATH`, `MULTIFIRE`, `GATTFIRE`, `CHUTEON`, `XF_AMB`, `GRUNTFIRE`, `TANKMOVE`,
  `DUMMY`, `FAN`, `ZOOM`, `NUKE`, `DROP` (TRAVERSE); `WHEEL8` (L3), `SKI`, `SKITURN` (L4),
  `BUTBRAKE`, `BUTSLIDE` (L6); `WINDLOOP`, `C_GRIND` (FALL3D). Also `CGUN` (stats) and `DOGSHIP`
  (end movie) are loaded with flag 1 by code.
- Flags 3 (music + loop): every `LEVELnO.SNI` track, `CORRIDOR` (LEVELnS), `OPTSONG`
  (MDKSOUND.SNI); `MAINSONG` is loaded with 3 by code.
- Volume: 0x7fff for every effect **except `BREATH` = 0x5000**; 0 for every music track (music
  always starts silent and fades in, see §3).

### Voices (`0x4d1b90` playing list, `0x4d1bd8` free list, 64 records of 0x48 bytes at `0x4d1c20`)

| Offset | Content |
| --- | --- |
| +8 (byte) | update flags: 1 = start at the given volume (else 0), 2 = compute volume, 4 = compute pan, 8 = compute frequency (Doppler) |
| +9 (byte) | bit 0: "fixed" — freeze the voice after its second update (flags become 1) |
| +0xa (byte) | position source: 1 = own copy at +0x18, 2 = follow the pointer +0x10, 4 = pointer +0x10 plus matrix +0x14 × offset +0x18; none = origin |
| +0xb (byte) | state: 0x20 paused, 0x40 finished (freed on the next listener update), 0x80 stopped |
| +0xc | handle: pointer that receives the voice and is cleared when it ends (e.g. `obj+0x158`) |
| +0x24 | distance at the previous update (−1 = never updated) |
| +0x28 | sample; +0x2c DirectSound buffer record |
| +0x30 | base volume (0..0x7fff); +0x3c current volume; +0x40 pan; +0x44 frequency |
| +0x34 | pitch multiplier (the "1.0" of the 3D calls) |
| +0x38 | the "50.0"/"200.0" argument: **stored but never read** |

The 32-bit flags argument of the 3D play function is these bytes: `0x1000e` = own copy of the
position + volume/pan/Doppler, `0x10006` = own position, no Doppler, `0x10106` = own position,
computed once, starts at full volume, `0x2000e` = follows a position pointer, `0x40000` = follows
an object's matrix with an offset.

## 2. The mixer

### API ✅

| Address | Function |
| --- | --- |
| `0x402b40` | init (64 voices, 127 samples; `DAT_004d1b58` = 0x103: enabled, 3D, mode 0x100) |
| `0x403a7c` | load a sample (see above); `0x403bc0` free one; `0x403c14` free all |
| `0x403c38` | find a sample by name |
| `0x402f08` | **2D play**: new voice, flags 1, volume = the sample's default volume, pitch 1, frequency = sample rate |
| `0x402fd8(sample, restart)` | 2D play: `restart` = 0 → nothing if a voice of the sample is playing; 1 → stop its voices, then play |
| `0x403004` / `0x4030cc(sample, restart, freq)` | 2D play at a given frequency (if already playing, only sets the frequency) — `BUTSLIDE` |
| `0x402db0(handle, sample, flags, pos_copy, pos_ptr, matrix, volume, pitch, unused)` | **3D play** (stack: pos_ptr, matrix, volume, pitch, unused); frequency = rate × pitch |
| `0x402ed8` | 3D play after stopping the sample's voices (restart) |
| `0x402d5c(sample)` | stop every voice of a sample; `0x402d04(voice)` stop one voice |
| `0x4032a8(sample)` | the first live voice of a sample (0 = not playing); `0x402d98` bool version |
| `0x4032e8(voice, vol)` | set a voice's base and current volume |
| `0x403348(matrix)` | **listener update** (once per frame; NULL = only process voices) |
| `0x403160` / `0x4031e0` | pause / resume every voice; `0x40319c` pauses only non-music voices |
| `0x403114` | re-apply volumes (after a volume setting change) |
| `0x403220` | stop every voice |
| `0x402c4c` / `0x402c64` | select mixer mode 0x200 (sniper) / 0x100 (normal) |

### Volume ✅

Final DirectSound volume of every voice (`0x402c7c`, `0x46efcc`, `0x46f19c`):

```
v      = voice volume (0..32767) × setting / 100      setting = SND_FX 0x5740cc or, for music
                                                     samples (flag 2), SND_MUSI 0x5740d0 (0..100, steps of 10)
mB     = round(v × 2500 / 32767) − 2500              (0.0762963 = 2500/32767 at 0x497ee4)
dB     = −25 + 25 × v / 32767
```

So **volume is linear in decibels over a 25 dB range**: full = 0 dB, half = −12.5 dB, and volume 0
is **−25 dB, not silence** (there is no mute: a sound at distance > 250 or with the effects setting
at 0 is still heard at −25 dB). Pan: `DS pan = pan × 10000 >> 15` (±32767 → ±10000 = ±100 dB,
i.e. a full-side pan silences the other channel). Frequency: `SetFrequency(freq)` in Hz.

A 2D voice (flags 1) is never updated: default volume (0 dB for all effects, −9.4 dB for `BREATH`),
centre pan (❓ `0x46f19c` never calls `SetPan`, so a reused buffer may keep the pan of its previous
3D use), frequency = the sample rate.

### Listener and 3D voices, normal mode 0x100 (`0x40347c`) ✅

`0x403348` copies the 3×4 camera matrix `0x573974` (rows right, up, and **back** = −forward, each
with its translation; `camera_update` 0x4174d0) and updates every live voice that isn't paused. For
a voice with any of the flags 2/4/8, with source position `p` (per the position mode):

```
q = M·p + t                        (listener space: q.x right, q.y up, q.z = −depth)
d = |q|                            (1 if |q|² ≤ 0)

Doppler (flag 8, not on the first update):
  f = 1 + (d_prev − d) × 30 / (frame_ticks × 1100)       frame_ticks = 0x491e20 (smoothed ticks/frame)
  f = 0.25 if f < 0.25; f = 3 if f > 3
  frequency = round(sample_rate × f × pitch)             (speed of sound 1100 units/s)

Pan (flag 4, not on the first update):
  pan = round(32767 × (q.z/d × B.x − q.x/d × B.y))       B = the back row (0x4d1b7c, 0x4d1b80)

Volume (flag 2, not on the first update):
  d < 20          → vol = base
  20 ≤ d ≤ 250    → vol = round(base × (250 − d) × 0.00434783)      (= base × (250 − d) / 230)
  d > 250         → vol = 0            (→ −25 dB)
d_prev = d
```

Constants: 30 (`0x4930d0`), 1100 (`0x4930d8`), 0.25/3 (`0x4930e0/e8`), 32767 (`0x4930f0`),
20/250 (`0x4930f8/0x493100`), 1/230 (`0x493108`). The "1.0, 50.0" of the script calls are the
pitch and the unused +0x38; **there is no min/max distance parameter** — the 20/250 linear ramp is
hard-coded for every 3D sound (explosions pass 200.0 there, which is equally ignored).

Resulting loudness: 0 dB up to 20 units, then linear in dB down to −25 dB at 250 units
(−12.5 dB at 135), then a −25 dB floor.

**Pan quirk** ✅ (the arithmetic is unambiguous, the intent ❓): the pan mixes listener-space
components with the *world* X/Y of the back vector. It's a correct left/right pan only when the
camera faces world +Y (MDK coordinates); facing −Y left/right are swapped, facing ±X the pan
follows front/back instead (a sound straight ahead is panned fully to one side). A port that wants
"correct" stereo should use `pan = q.x / d`; to replicate the original exactly, use the formula.

The first update of a voice only records `d_prev` (its volume stays at the start value: the given
volume with flag 1, else 0 = −25 dB, for one frame). Voices with the "fixed" bit (0x100, the
ricochets `0x10106`) are computed on their second update and then frozen (flags → 1): they keep
that pan/volume even if the camera moves.

### Sniper mode 0x200 (`0x403750`, set on entering the scope `damp_animate` state 803, reset by `0x4645c8`, `0x467384`, stream init) ✅

Sounds are heard **through the scope**: loudness depends on where the source is in the scope view.
No pan update (the voices keep their last pan); Doppler as above.

```
if q.x² + q.y² > 4:  r = sqrt(q.x² + q.y²);  q.x −= 2 q.x / r;  q.y −= 2 q.y / r
                     sx = q.x × 2 / zoom;  sy = q.y × 2 × 384 / (280 × zoom)
else:                sx = sy = 0
if q.z > 0 (behind): vol = 0
else:  g = min(1, 400 / zoom × 0.75 / |q.z|)                (= 300 / (zoom |q.z|))
       g = max(0, g × (1.3 − sqrt(sx² + sy²) / |q.z|))
       vol = min(32767, base × g)
```

`zoom` = `0x57391c` (1 on entering, down to 0.25). `sqrt(sx²+sy²)/|q.z|` is the offset from the
crosshair in scope half-sizes (the scope is 384×280 px with focal length 384/zoom), so a sound is
at 1.3× (clamped to full) within 2 units of the line of sight, fades linearly to silence (−25 dB)
at 1.3 scope half-widths off-axis, and beyond `300 / zoom` units depth it falls as 1/depth.

### Voice limits and lifetime ✅

- 64 voices; when none is free the new sound is **dropped** silently (no stealing, no priority).
  256 DirectSound buffer records in all (samples + duplicates).
- A voice ends when its buffer stops (`0x46ee28` polls `GetStatus` when sounds are started/found):
  it's flagged 0x40 and its handle (`*voice+0xc`) is cleared, and it's recycled on the next
  `0x403348`.
- Looping is decided **only by the sample's SNI flag bit 0**, never by the caller. A "loop sound"
  (`set_loop_sound`, `obj+0x158`) whose sample hasn't flag 1 plays once.
- Object voices stored in `obj+0x158` (name `obj+0x15c`): stopped when the object is freed
  (`0x43d7bc`, `0x43d224`) or its arena is deactivated (`0x43f800`, the name is kept), and restarted
  with flags 0x2000e when the arena is activated again (`0x43f8e0`, called by `arena_activate`).
  This also restarts a `play_sound` with flag 4 (it uses the same slot) ❓ quirk.
- Arena overlay sounds: up to 16 samples per arena from the arena's MTO data ("Too many overlay
  sounds") are registered when the arena loads (`arena_load_step` 0x41983c) and stopped/freed on
  `arena_switch` (list `0x573b94`); they're only played by name from scripts.

### Pause, menus, focus ✅

- `0x403160` pauses every voice (DirectSound `Stop`, position kept, flag 0x20) — **music too** — in:
  the in-game menu (`0x425e70`, only when entered from a level), window deactivation (main loop
  `0x401cb8`), the save list (`0x428cfc`), `0x429730`, the save prompt (`0x42b520`) and the quit
  confirmation (`0x403cf8`). `0x4031e0` resumes them where they were (looping kept) and re-applies
  the volumes; after the in-game menu `0x41bc98` also restarts `BREATH` in sniper mode.
- `0x40319c` pauses only the effects (not the music): Bones' strike cutscene (`0x4398f0`).
- `0x403220` stops everything: level end/unload (`0x40a4a8`, `0x40a51c`, `0x41e568`), end of the
  fall (`0x410b80`), shutdown.
- Changing a volume setting in the sound options calls `0x403114`: playing voices change at once.

### Timing

The listener update (`game_frame` 0x41d4d8 → `0x403348(0x573974)`), the music fades and the
Doppler all run **once per frame**, not per tick; the frame limiter caps at ~29.4 fps (34 ms), so
"per frame" ≈ per tick on a fast machine.

## 3. Music ✅

### Arena music

- Per arena the CMI arena record has two names (`0x43d9cc`): **the first is always `NONE` or empty
  in the shipped levels** (it would play in a second slot), the second is the track; the special
  record `C` gives the level default, `CORRIDOR` (a flags-3 entry of `LEVELnS.SNI`, loaded with the
  level; `0x57449c`).
- Tracks live in `LEVELnO.SNI` and are **streamed**: when an arena becomes Kurt's or the
  neighbour one (`0x419d00`), if it has music (`arena+0x44` bit 2, cleared when both names are
  empty) and its music isn't the one loaded (`0x573b30`), `0x4192c4` **stops and frees the
  previously loaded arena tracks at once** (no fade, even if they're still fading out) and
  `0x431590` starts reading the new ones (up to 512000 bytes) 0xf768 bytes per frame
  (`0x4193a4`/`0x4317d8` from `game_frame`); when done they're registered as samples and, if the
  arena is still Kurt's (`0x573a0c`), started.
- `0x419158(arena)` switches the music: if `arena` is the loaded one, its tracks, **otherwise the
  level default `CORRIDOR`** — so corridors (arenas `CHMO_1`… with no names) and arenas whose
  music is still loading play `CORRIDOR`. `NONE` (not a sample) means silence. For each of the two
  slots: if the new track differs from the current and from the fading one, the fading one is
  stopped, the current one becomes the fading one (keeping its volume), and the new track starts
  (`0x402fd8`, restart 0) at volume 0; if the new track is the fading one they're swapped back
  (a quick return resumes the old track where it was).
- Fades (`0x418ffc`, each frame): current tracks `vol += 0x80` up to 0x7fff (**256 frames ≈ 8.7 s**
  at 29.4 fps), fading tracks `vol −= 0x100` (**128 frames ≈ 4.35 s**), stopped when below 0.
  Because volume is linear in dB, the fade-in is a straight line from −25 dB to 0 dB and the
  fade-out from the current level to −25 dB, then a cut to silence. Volume is × the music setting.
- Loading a saved game clears the music slots (`0x42fb18`).
- At level start the start arena's music is loaded synchronously (`0x41a11c`) and fades in the
  same way.

### Other music

- `MAINSONG` (menu BNI, loaded with flags 3, volume 0x7fff): played looping at full volume when
  the main menu opens (`0x42618c` → `0x426050`), stopped and freed when a game starts or a submenu
  replaces it (`0x426504` → `0x4260a4`). No fade.
- Sound options screen (`0x42bb6c`, `MISC/MDKSOUND.SNI`): stops `MAINSONG`, plays `OPTSONG`
  (3-second loop, music volume so the slider can be heard) and `OPTBUTT` (restart) on every key;
  leaving (`0x42bbc0`) stops `OPTSONG`, frees the archive and restarts `MAINSONG`. `SNDTEST` unused.
- No music in the fall, the stream, the statistics or the end movie (effects only).

## 4. Sounds played by the code

2D = `0x402f08`/`0x402fd8` (no position, full default volume); "new" = always a new voice,
"restart" = stop then play, "once" = only if not already playing; loop = SNI flag 1.

### Kurt (`damp_animate` 0x4646a4 unless noted) ✅

| Sound | Event | Type |
| --- | --- | --- |
| `FOOT3`/`FOOT4` or `FOOT1`/`FOOT2` | running (state 600) on frames 0 and 13; running while firing (601) on frames 4 and 17; the pair alternates after each second step (`0x491f30`, starts with 3/4) | 2D new (per-level samples in `LEVELnS.SNI`) |
| `LAND` | touching the floor in 700 fall, 702/703 jumps | 2D new |
| `CHUTEOUT` | entering state 701 (chute opens) | 2D new |
| `CHUTEON` | while the chute is open (after its 4 opening frames) | 2D once, **loop** |
| `CHUTEIN` | chute closed (`0x573a44` = 0) while `CHUTEON` plays: `CHUTEON` stopped | 2D new |
| (stop `CHUTEON`) | grabbing a ledge (state 800) | ❓ where it stops on a chute landing |
| `MULTIFIRE` / `GATTFIRE` | fire held (`0x46c3e4`): **`MULTIFIRE` = normal chain gun, `GATTFIRE` = super chain gun** (`0x5743ef` > 0); the other one is stopped; both stopped on release | 2D once, loop |
| `FAN` | in an updraft (`damp_gravity`), stopped outside | 2D once, loop |
| `BUTSLIDE` | sliding (`damp_buttslide`, `0x4030cc`): 15000 Hz while accelerating (state 809), 11025 Hz otherwise; stopped while braking | 2D, loop |
| `BUTBRAKE` | braking (state 810) | 2D once, loop |
| `SKI`, `SKITURN`, `SKILAND` | snowboard (`0x46ac4c`): `SKI` while on the ground, `SKITURN` while turning faster than a threshold, `SKILAND` (restart) when landing after > 14 frames in the air; `SKI`/`SKITURN` stopped after 6 frames in the air; all stopped leaving the board (`damp_control`) | 2D |
| `DUMMY` (volume 0x2000 = −18.75 dB), `ALERT` | riding `XD`/`XD2` (`0x46a840`; `XE` is the bomber ride 0x46bf40): `DUMMY` loops while moving; fire plays `ALERT` (once) and raises the alarm | 2D |

No sound for jumping, being hurt or dying comes from the code (only scripts).

### Sniper ✅

| Sound | Event | Type |
| --- | --- | --- |
| `SNIPERON` | entering (state 803) + mixer mode 0x200 | 2D restart |
| `BREATH` | sniper phase 2 (`game_frame`), again after resuming from a menu (`0x41bc98`) | 2D once, loop, **−9.4 dB** |
| `ZOOM` | while the zoom speed moves the zoom within its limits (`0x4678b0`), else stopped | 2D once, loop |
| `SNIPRELD` | each round loaded into the clip (`0x41eb10`) | 2D restart |
| `SNIPERSHOT` | each shot (`0x461e88`) | 2D new |
| `RASPBER` | firing the air strike when unavailable (`0x461e88`) | 2D restart |
| `SNIPEROFF` | leaving with the key (state 900) or by falling (`0x467384`); `BREATH` and `ZOOM` stopped, mode 0x100 | 2D restart |
| — | forced exit (`0x4645c8`): `ZOOM`, `BREATH` stopped, mode 0x100, no `SNIPEROFF` | |

`ZOOMBEG` is loaded but never played by code.

### Pickups and items ✅

| Sound | Event | Type |
| --- | --- | --- |
| `COLLECT` / `WMIB` | inventory pickup (`damp_collect_pickups` 0x46c448, `0x46d1e8`): `WMIB` for the Interesting Bomb, else `COLLECT` | 2D restart (only in game state 3) |
| `APPLE`, `BONES`, `COLLECT` | used-at-once pickups (`0x46d478`): `APPLE` health (cases 5–9), `BONES` `SW_BONES` (case 4) and case 11 (❓ `BONEFLC`), `COLLECT` the other sniper ammo (0–3) and `SW_EWJ` (10) | 2D restart |
| `COW` | the `SW_EWJ` easter egg spawns `SW_HCOW` (`0x46d718`) | 2D restart |
| `RUNNER` | a pickup starts running away from Kurt (`0x43daf4`) | 2D once |
| `TORNADO` | the tornado item starts spinning (`0x43deac` kind 3) | **2D once** |
| `DUMMY` | the decoy walks (`0x43e860`) | 3D `0x2000e`, follows it, loop, handle `obj+0x158` |
| `NUKE` | the key turns into the nuke (`0x43deac` kind 7) | flags **1**: no position, full volume, loop, handle `obj+0x158` |
| `EXPLODE` | the nuke blast (`0x43efcc`), grenade/effect explosions (`0x43cb2c`) | 3D `0x10006` (fixed) |
| `DROP` | each falling `X_TOOTH` bomb of Bones' strike (`0x43deac`), the ridden strike's drops (`0x46bf40`) | 3D `0x2000e`, follows, loop |

### Objects ✅

| Sound | Event | Type |
| --- | --- | --- |
| object's (op 26) or `RICO1`–`RICO3` (random) | chain gun sparks (`0x41e8f4`), every 4th frame (`0x573aa4 & 3`) unless forced; the object's own sound restarts (`0x402ed8`) | 3D `0x10106`: fixed, computed once, starts at full volume, no Doppler |
| object's (op 25) or `EXPLODE` | object death (`0x43d224`) | 3D `0x10006` at the explosion |
| frame sound (op 24) | object animation reaches the frame (`object_anim_update` 0x43a89c) | 3D `0x1000e` fixed at the object's position then |
| door sounds (op 151) | opening/closing/open/closed (`0x43cc68` → `0x43cf9c`) | 3D `0x10006` fixed |
| `ALERT` | movement command 15 "alarm" (`0x45b6c8`), every 32 frames while in Kurt's arena | 3D `0x1000e` fixed |
| script `play_sound` (op 89, `0x442402`) | flags & 0x80: 2D (0 new, 1 restart, 2 once, 3 nothing); else 3D flags 0xe \| position: 0x10 → follows `obj+0x10` + `obj+0xac` matrix × offset; 0x20 → follows slot point `obj+0x1b0 + 12n`; 0x40 → fixed floats; none → **fixed copy of the object's position** (follows `obj+0x10` if flags & 4); mode 0 new, 1 restart, 2 once (restart path), 3 stop | volume 0x7fff, pitch 1.0 |
| `set_loop_sound` (op 107) | `0x2000e`, follows the object; loops only if the sample has SNI flag 1 | |

### Level flow ✅

| Sound | Event | Type |
| --- | --- | --- |
| `NUKE` + `TORNADO` | end of a level (`0x40a9e0`, `endlev.c`) | 2D new (`NUKE` loops until the level's stop-all) |
| arena music, `CORRIDOR` | §3 | music |
| `MAINSONG`, `OPTSONG`, `OPTBUTT`, `SND_PUSH` | main menu, sound options, menu key clicks (`0x42c084`, restart; loaded by `0x42c04c`) | 2D |
| stats screen | `CGUN` (loop), `SNIPER`, `RICO1`–`3`, `ALDIE`, `XGHEAD1`/`2`, `TELETYPE` — see gameplay.md | 2D |
| the fall | `FALL3D.SNI` sounds, see gameplay.md (`WINDLOOP` volume `0x5209b8 × 0x5000 / 0xc00`) | 2D |
| the stream | `WIND`, `HITSIDE`, `RESCUE`, `APPLE`, `HURT1`–`7`, see gameplay.md | 2D |
| end movie (`MDKEND.FLC`, `0x477604`, `MISC/FINISH.BNI`) | frame 1 `DOGSHIP` (loop, stopped at 0xbc), 0x81 `DROP`, 0x85 `FLYBY`, 0xba and 0xc4 `EXPLODE1`, 0xc2 `ENDEXP` | 2D |

Only used by scripts (never by code): `ALDIE` (level copy), `GRUNTFIRE`, `XF_AMB`, `TANKMOVE`,
`WOW1`/`2`, `XG_*`, `XU_JUMP`, `LASER1`–`3`, `WHEEL8`, the per-level `LEVELnS` effects.

## 5. In the port

- `SoundMixer` (`game/audio/sound_mixer.gd`) plays the effects like §2: volume linear in dB over
  25 dB, the 20/250 distance law, Doppler, the scope listening in sniper mode, 64 voices (new ones
  dropped), looping from the SNI flag (`MDKSni.get_sound()`, the default volume in the `volume`
  meta), 2D/3D and fixed/following voices as in §4 (script `play_sound` positions 0x10/0x20/0x40,
  `set_loop_sound`, the decoy's `DUMMY`, Bones' `DROP`, the nuke's `NUKE`, 2D pickups, tornado and
  end of level). Kurt's own loops (`MULTIFIRE`/`GATTFIRE`, `FAN`, `BUTSLIDE`/`BUTBRAKE`, `BREATH`,
  `ZOOM`) keep their players; `CHUTEON`/`CHUTEIN` follow the chute. Death, teleports, rides,
  cutscenes and the level's end stop `CHUTEON` without `CHUTEIN` (`tests/chute_sound_test.gd`).
- `LevelAudio` fades the arena music as in §3 (8.7 s in, 4.35 s out, `CORRIDOR` in corridors,
  swapping back to a fading track); the tracks are loaded at once, not streamed.
- Differences: Godot pans the 3D voices correctly (not the original's heading-dependent pan) and
  also in sniper mode; the volume settings are the buses' gains (0 mutes); the "fixed" voices
  (ricochets) keep being updated; no Doppler on 2D voices, as in the original.
- The port's options screen (main and pause menus) plays `OPTSONG` on the music bus and `OPTBUTT`
  on each change (`MenuItems`, test `tests/option_song_test.gd`); the main menu stops `MAINSONG`
  meanwhile. In the original `OPTBUTT` also sounds on the selection key.
- The end movie's sounds play by frame (`EndMovie`). `MDKBZK.MVE` plays its own sound (`MDKVideo.play_movie`).
