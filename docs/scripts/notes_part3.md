# MDK script opcodes, part 3 (88 handlers from `script_opcodes_part3.asm`)

Every handler in part 3 serves exactly one opcode. Operand layouts come from the
handler code (the `[ebp-0xa8]` reads). I checked the size of each operand read and the
conditional reads by hand. The semantics are less certain where marked (?).

Conventions: `obj` = the running object (`[ebp-0x70]`), `arena` = `obj+0x60` (local `[ebp-0x28]`),
`model` = `obj+0xc` (local `[ebp-0x2c]`). All `off32` operands are `g_cmi + value`.

## Shared operand layouts (the `kind` field on `complex` operands in the JSON)

These layouts recur, and part 1 and 2 opcodes use them too.

- **cond_action**: `u8 act`. Then `act==0xFE`: `off32 then, off32 else`; `act==0xFC` or `act==0x0C`:
  `off32 target` (0 means null); any other act: no more bytes. The act values are the
  opcode numbers of goto (12), gosub (252) and return (253), and 0xFE means "gosub then/else".
  - If the condition is true: 0xFC and 0xFE do a gosub. The handler pushes the pc after the
    operands to `obj+0x24c[depth]` and `obj+0x108` to `obj+0x25c[depth]`, then sets
    `depth = obj+0x248` to `depth+1` (maximum 4; overflow calls `0x440300`, sets
    `obj+0x108 = 0` and returns). Then `obj+0x108 = pc = target` and `obj+0x26c[depth] = 0`.
  - 0xFD returns: it pops the pc and `obj+0x108`.
  - Every other act does a goto: `obj+0x108 = pc = target` and `obj+0x26c[depth] = 0`. For act
    values other than 0x0C, the target is an uninitialised local.
  - If the condition is false, only 0xFE acts: it does a gosub to `else`.

  23 handlers expand this macro identically. Two variants exist:
  - 208 also clears `obj+0x21e` on the true path.
  - 207 peeks the byte first; 0xFF means "no action", and the byte counts toward the layout.
- **compare**: `u8 op, f32 b` and, only if `op` is 7 or 8, `f32 c`. The test is
  `0x45da90(op, a, b, c)`:
  - 1: `a<b`
  - 2: `a>b`
  - 3: `a<b+0.05`
  - 4: `a>b-0.05`
  - 5: `|a-b|<0.05`
  - 6: `|a-b|>=0.05`
  - 7: `b<=a<=c`
  - 8: `a<=b || a>=c`
  - any other op: false

  `a` is converted to float, from an integer if needed.
- **value**: `u8 kind`. If `kind==3`, a `f32` literal follows; otherwise a `u8 index` follows.
  `0x440944(obj, kind, i)` resolves the variable (i is clamped to 0..3):
  - kind 0: global `0x573b4c[i]`
  - kind 1: `arena+0x48[i]`
  - kind 2: `obj+0x234[i]`
  - any other kind: the partner's `(obj+0x2b8)+0x234[i]`, or dummy `0x491eac` if there is no partner.
- **point** (172, 178): `u8 mode`. If `mode==3`: `u8 index`, the point `obj+0x1b0+12*index`.
  Otherwise `f32 x,y,z`, interpreted as:
  - mode 0 (and any mode above 3): absolute
  - mode 1: relative to `obj+0x10`
  - mode 2: object-local, rotated by the yaw (`0x45d770`)
- **pstr**: the handlers take `name = L ? pc+1 : pc` and then `pc += L+1`. `L==0` gives an empty
  string; the string points at the zero length byte.

Irregular layouts in part 3 (see the JSON for the exact text):

- 181: the operands depend on `mode`.
- 173: when the first name is empty, a second pstr and 4 floats follow.
- 228: `u8 L`, then a u8 flag if `L==0`, otherwise a pstr body.
- 158: an `off32` follows only if `flags & 2`.
- 180, 203, 224, 242: optional trailing operands, gated by the first u8.
- 111: 4 bytes are consumed, but only the low 16 bits are used.

## Flow notes

- Most opcodes jump to 0x45a168, the next opcode.
- **196** always ends at 0x45a177, which returns from `script_run` **without saving the pc**, so
  the next frame restarts at `obj+0x108`.
- **158** also returns without saving the pc when the object died (`obj+8 == 0`).
- **112/173**: an unknown arena is a fatal error; after it, `obj+0x108 = 0`, `depth = 0`, and the handler returns.
- **227** ends with a goto to either of its two targets, or continues. Its offsets are not null-checked.
- Gotos and gosubs always set `obj+0x108` (the restart point) to the target, as opcode 1 does.

## Object structure (offsets seen in part 3)

| Offset | Meaning |
|---|---|
| +0x00 | next object in the arena list |
| +0x04 | u16 enemy type index (table `0x520a84`, 0x88-byte entries, max 80) |
| +0x06 | u8 active |
| +0x08 | s32 health (0 = dead) |
| +0x0c | model instance pointer (starts with the name; `+0x10` animated texture pointer array, `+0x18` its count, `+0x1c` part count, `+0x20` parts, 0x5c bytes each, name first) |
| +0x10..0x18 | position |
| +0x1c..0x24 | spawn position copy / jump target (226) |
| +0x28..0x30 | velocity (211 clears) |
| +0x34 | cleared by 88 mode 2 |
| +0x4c | yaw (degrees) |
| +0x50 | previous yaw |
| +0x54 | roll/bank |
| +0x58 | height factor (203) |
| +0x5c | height offset (227) |
| +0x60 | arena |
| +0xec | movement state? (cleared by 88 and 227) |
| +0x104 | f32 (199) |
| +0x108 | script restart pc |
| +0x11c | u16 object kind (= 7 for spawned enemies) |
| +0x11e | u8 movement command char ('X' in 88, '+' in 227) |
| +0x11f | its parameter |
| +0x120..0x128 | movement target (227, then `0x45a1dc`) |
| +0x13c | pitch |
| +0x146 | u16 instance number (high half of the dword +0x144) |
| +0x148 | flags dword. 0x2: ignore z in probes/moves. 0x20: explosion object. 0x80: no automatic banking (97). 0x40000: tested by 176. 0x400000 (byte +0x14a 0x40): set by 226. 0x100000: rotate 180 degrees when changing arena. Spawn presets: 0x2008A6 (161/206), 0x1108000 (doors, 149) |
| +0x14c | flags2 (227 clears bit 3) |
| +0x180..0x188 | home position |
| +0x198..0x1ac | box (6 floats, for collisions) |
| +0x1b0 | points array: vec3 × n, the model's hot points (156, 172, 178, 243) |
| +0x21d/+0x21e | event bytes. Hit sets 0xFC/0xFD; `+0x21e` is cleared when the script ends (0xFF) and by 208 |
| +0x21f | u8 (205) |
| +0x22c/+0x230 | wait timer / pc to resume after the wait |
| +0x234 | f32[4] object variables |
| +0x248 | gosub depth |
| +0x24c | u32[4] return pcs |
| +0x25c | u32[4] saved restart pcs |
| +0x26c | u16[depth] per-level counter, reset on goto/gosub |
| +0x27c..0x290 | six floats (239) |
| +0x294..0x29c | per-axis move velocities (200) |
| +0x2a0/+0x2a1/+0x2a4..0x2ac | reset by 227 |
| +0x2b8 | partner object (179, 180, 213, 214, 227, 228, value kind ≥4) |
| +0x2bc | pending new arena for `0x43ca00` |
| +0x2c0 | f32 (210) |
| +0x2c8 | part-hit bit mask (208) |
| +0x2d0..0x2fe | u8, u8, 12 floats (242) |
| +0x302.. | union of door data and jump data, below |

Layout at +0x302, door (149–153):

| Offset | Meaning |
|---|---|
| +0x302 | other arena |
| +0x306 | animation A |
| +0x30a | animation B |
| +0x30e | f32 (20.0 by default) |
| +0x312 | flags (8 by default) |
| +0x316/31a/31e/322 | 4 names |
| +0x326 | LOCK part mask |
| +0x32a | HC* part mask |

Layout at +0x302, jump (226):

| Offset | Meaning |
|---|---|
| +0x302 | p0 |
| +0x306 | dz |
| +0x30a | p1 |
| +0x30e | yaw |

## Arena structure (0x466 bytes each, `g_arenas`, name at +0)

| Offset | Meaning |
|---|---|
| +0x10 | triangle count |
| +0x28 | triangles, 0x24 bytes each: u16 v0,v1,v2; s16 +6 texture (140); +0x20 flags, top byte = group id, bits 0x10/0x20 (98) |
| +0x18 | animated texture count |
| +0x20 | animated texture pointer array (133) |
| +0x24/+0x28/+0x2c | BSP data passed to the segment tests `0x421680`/`0x421708` |
| +0x38 | hotspot count |
| +0x3c | hotspots, 0x24 bytes each: type (7 = fan hotspot, 9 = wind box), id, box floats at +0xc..+0x20 |
| +0x48 | f32[4] arena variables |
| +0x68 | object list head |
| +0x6c | u8[16], hit behaviour of triangle groups 1–16 (168; read by `0x40d560`) |
| +0x7c | u8[16], hit-type mask that triggers the group's script (99) |
| +0x8c | u32[16], group hit-script offset, raw, relative to g_cmi (99) |
| +0xcc | s32[16], per-group counters, increased by hits (162, 163, 181) |
| +0x114 | mask of destroyed groups |
| +0x10c/+0x110 | group bit masks for triangle flags 0x20/0x10 (98, 168, 194) |
| +0x118 | embedded object: the arena's own script object, also used as the boss-bar holder (181) |
| +0x45e | fan/conveyor list |
| +0x462 | f32 camera limit (196, 203) |

## Globals

| Address | Meaning |
|---|---|
| 0x573a0c | the player's arena |
| 0x573a68 | neighbour arena (223) |
| 0x5739c0 | player position (g_damp_position) |
| 0x5739cc | previous player position |
| 0x5739f0 | player yaw |
| 0x5739f4 | player box |
| 0x573a3c | player vertical speed |
| 0x573b84 | object the player stands on |
| 0x573a1c | its top z |
| 0x573a38 | unknown flag (181, 209) |
| 0x573c10 | triangle under the player |
| 0x573c30 | player-related object pointer (171; excluded from blasts) |
| 0x573b4c | f32[4] global script variables |
| 0x573b68 | screen flash intensity (215) |
| 0x573c74/0x573c78 | boss bar alpha / object |
| 0x573c80..0x573c90 | pending teleport (arena, x, y, z, yaw) |
| 0x574324 | player health |
| 0x5742dc | 0/1 option set by cheat codes (232) |
| 0x573c4c | 217 (random 0..31 at some point; used by 0x57f438 computations) |
| 0x574304 | 202 |
| 0x573918 | camera pitch? (203) |
| 0x57fc30/0x57fc34 | yaw/position snapshot of the player (or of camera objects 0x573c20/0x491e48 when `obj+7 != 2`) taken at `script_run` entry |
| 0x4d5354..0x4d5380 | lighting parameters (137–139) |
| 0x520a84 | enemy type table |
| 0x57ecf0 | 4-entry display queue (247) |
| 0x57fc40 | scratch object for triangle-group hit scripts (0x45c9a0) |
| 0x573f8c | free fan list |

## Helper functions (suggested names)

| Address | Name | Notes |
|---|---|---|
| 0x45ca88 | enemy_type_find(name) | index into 0x520a84; fatal "ENEMY name %s not found" |
| 0x45cb04 | enemy_max_instance(name, arena) | highest instance number with that name, −1 if none |
| 0x45cdec | enemy_spawn(arena; x, y, z, instance, type, script, door_flag) | stack args; returns obj |
| 0x45cca8 | box_object_spawn(arena; x, y, z, sx, sy, sz, name, script) | |
| 0x45cb88 | find_connector(arena, other_arena, type) | |
| 0x43ca00 | object_change_arena(obj) | moves to `obj+0x2bc` |
| 0x43c0f8 | path_eval_spline(path, t, &out) | |
| 0x440b88 | anim_ref_resolve(&ptr) | a record starting with u32 0 is followed by a name looked up with arena_find_animation; otherwise the record is the data |
| 0x42d9c0 | anim_texture_set_frame(tex, relative, frame) | |
| 0x413a94 | fan_create_at_hotspot | |
| 0x413ba0 | fan_create_box | |
| 0x413fa0 | fan_remove | |
| 0x4140e4 | fan_set_enabled | |
| 0x414070 | fan_set_strength | |
| 0x414110 | conveyor_create | |
| 0x413a48 | fan_alloc | |
| 0x413a10 | fan_find | |
| 0x40c828 | light_triangle_group(group; a, radius, arena, c) | |
| 0x40c7e8 | tri_group_set_texture(group, value, arena) | |
| 0x40c694 | tri_group_set_state(group, op, count, tris) | |
| 0x43cb2c | explosion_spawn(arena, &pos; scale) | |
| 0x463a94 | blast_damage(&pos, damage; radius, 1, 0, flags, −5) | |
| 0x45d770 | obj_local_to_world(obj, &in, &out) | |
| 0x440944 | script_var_ref(obj, kind, index) | |
| 0x45da90 | script_compare(op; a, b, c) | |
| 0x440300 | gosub_error(obj) | "Gosub overflow/underflow on %s ID %d" |
| 0x440220 | atan2_deg(y, x) | returns [0,360) |
| 0x440288 | sincos_deg(angle, &sin, &cos) | |
| 0x417450 | distance(a, b) | |
| 0x417480 | distance_sq(a, b) | |
| 0x4603d4 | probe_wall(obj; rel_angle, dist) | |
| 0x46046c | probe_floor(obj; dx, dy, depth) | returns the hit |
| 0x4605d0 | can_see_player(obj; max_dist, k) | |
| 0x460518 | point_sees_player(&point; range) | |
| 0x421680 / 0x421708 | BSP segment tests | |
| 0x45cf60 | collide_damage(obj, targets, damage, flags) | |
| 0x45ee40 | model_find_part(obj, name) | |
| 0x460968 | turn_towards(target, current, step) | |
| 0x4611e4 | avoid_objects(obj) | |
| 0x4612e0 | camera_track_object(obj, mode; v) | |
| 0x460f00 | place_x(obj; xmin, xmax, ylimit) | |
| 0x461024 | ? (219) | |
| 0x45a1dc | move_start(obj) | |
| 0x41a244 | arena_find_by_name | NONE gives NULL, unknown is fatal |
| 0x419c54 | arena_find | NULL if unknown |
| 0x41a1ac | arena_show_by_name | "BSPShow %s not found" |
| 0x41a2d0 | arena_set_neighbour | |
| 0x41738c | screen_flash_white(n, frames) | |
| 0x425400 | hud_queue_message(name, flags; time) | |
| 0x415620 | resource_find(name) | table at 0x4d1b50, 8-char names |
| 0x40d560 | tri_group_hit(arena, tri, count, hit_type, param, pos, ...) | uses arena+0x6c/0x7c/0x8c/0xcc |
| 0x45c9a0 | run_hit_script(offset, arena, param) | runs `script_run` on scratch object 0x57fc40 |

## Uncertain / open

- Semantics marked "?" in the JSON: 171 (meaning of 0x573c30), 176 (flag 0x40000), 219 (0x461024),
  203/196 (0x573918, arena+0x462 read as camera pitch/limit), 224 (0x468b64/0x468be0), 247 (what
  the queue shows), 239/242/210/199/205/202/217 (the fields they set).
- 196 (yield without saving the pc) and 222 (compares the per-call opcode counter) look odd but
  match the code exactly.
- 181 with mode ≥ 2 reads no further bytes. In the true path of a cond_action, act values other than
  0x0C/0xFC/0xFD/0xFE would jump to garbage, so scripts presumably never use them.
- `off32` operands carry an extra key `"role"`: `"code"` (script/jump target) or `"data"`
  (150 animation records, 206 spline path). A walker must not disassemble data offsets:
  following 150's offsets as code gave the only "opcode 0" errors.

## Validation

I combined this JSON with the part 1 spec (`p1/spec.py`, `p1/dis.py`) and `opcodes_part2.json`, using the
part 2 agent's walker `p2work/combined.py`: the walk follows every code offset from all
directory entries of LEVEL3–8.CMI. It decodes 66,649 instructions with no overlaps between
instructions. The only unknown opcode left is 141 at the arena entry `A:HMO_9` (LEVEL3 0x1c99a), and
it does not involve part 3. Following 99's offsets as code adds about 1,560 cleanly decoded
instructions, which confirms that they are script offsets.

- The only warnings in part 3 are the expected act byte 0xFF of 207.
- The decoded operand values look sane:
  - arena and type names
  - hit masks (3)
  - instance numbers 1000+ (111)
  - boss bar mode 1 with range 0..720 and max 100
  - door flags 16/80 and door parameter 20.0
- Opcodes never reached by the walk, so validated only by reading the code: 90, 137, 144, 145,
  146, 147, 148, 162, 163, 178, 196, 215, 227.
