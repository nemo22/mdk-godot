# MDK script bytecode, part 1 (88 opcodes + interpreter)

Source: `C:\games\MDK\re\script_opcodes_part1.asm` (handlers), `objdump` of `script_run` 0x440bc8–0x441170
and 0x45a0f7–0x45a180, `export_d3d\decomp.c` for helpers. Machine-readable spec: `opcodes_part1.json`
(88 opcodes plus an entry for 0xFF, which the loop handles itself).

All operand sizes were checked by walking the scripts. `p1/full_dis.py` is a disassembler driven by all three
`opcodes_partN.json` files. It follows control flow from every entry point of LEVEL3–8.CMI (dir 0 alien scripts,
dir 2 object-type scripts, dir 3 arena scripts) and through every goto/gosub/branch/spawn-script target. Result:
**66,649 instructions and 7,042 `0xFF` decoded, with no misalignment**. The walk checked every pstr for NUL and
ASCII, float plausibility, var kind/index, action bytes and whether targets fall inside the file. The only
remarks are:
- one invalid opcode, a data problem (see "Uncertain / anomalies");
- opcode 207's action byte 0xFF, which is by design;
- opcode 96's ±1e7 sentinel floats.

`p1/dis.py` is my earlier walker (part 1 plus rough layouts for the other parts). It found the same with
28,698 instructions.
Part-1 opcodes never reached: **6, 10, 155**. Their layouts rest on the handler code only. They are trivial
(none; pstr+u8+action; value+action).
Opcodes never reached in any part: 6, 10, 70, 90, 144–148, 155, 182, 196, 215, 225, 227.

## Interpreter (`script_run`, 0x440bc8)

`script_run(obj)` runs once per frame for every active object with `obj+0x108 != 0` (0x43c7dc). It also runs:
- for the current arena and for the second arena that is active during a transition, on the object embedded at
  `arena+0x118` (game_frame), so the arena script pointer is `arena+0x220` (= `obj+0x108`);
- once, at object creation, in `object_init` 0x43bc20, with `obj+0x108` set to the object-type script
  (dir 2, key `"%s$%s"` = arena$type). The pointer is reset to 0 afterwards, so these are init scripts;
- on the scratch object 0x57fc40 (0x45c9a0), and from 0x47868c.

Alien instance scripts (dir 0, key `"%s$%s_%d"` = arena$type_id) are stored straight into `obj+0x108`
(arena object spawn 0x43bd38, from the DTI records of type 2). Arena records (dir 3) are `pstr, pstr, u32 script offset` (0 = none), see
`cmi_find_arena_script` 0x43da80.

Prologue:
1. `[ebp-0x70] = obj`. The **target position** (vec3 at 0x57fc34) and yaw (0x57fc30) are set to Kurt's
   (`g_damp_position` 0x5739c0, `g_damp_yaw` 0x5739f0). If `obj+7 != 2` they are replaced by the position (+0x10)
   and yaw (+0x4c) of the decoy object `0x573c20` if one exists, or else of the object in `0x491e48` (the object
   with `obj+7 == 1`, set by the object update loop 0x43c7dc). Opcodes 6, 43 and command 43 of opcode 4 use this
   target.
2. `pc = obj+0x108`, the restart point.
3. **Wait**: if `obj+0x22c > 0` then `obj+0x22c -= g_frame_dt` (0x491e24, seconds). If it is still `> 0`, return
   (nothing runs this frame). Otherwise `obj+0x22c = 0`, `pc = obj+0x230` and execution continues in the same
   frame. `obj+0x108` is **not** changed, so a later yield restarts at the old restart point.
4. `[ebp-0x2c] = obj+0xc` (type/model record: name first, `+0x1c` part count, `+0x20` parts of 0x5c bytes, each
   starting with the part name). `[ebp-0x28] = obj+0x60` (arena, name first). Loop counter `[ebp-0x74] = 0`.

Loop (0x440ccd): `op = *pc++`.
- `0xFF`: 0x45a16d clears `obj+0x21e` (the hit event of this frame) and returns. `obj+0x108` is untouched, so
  the next frame starts again at the restart point. This is the normal end of each frame's run.
- Otherwise `++count`; if `count > 1000`, debug log `"Alien %s looped %d commands, off %lx"`
  (type name, count, pc−g_cmi), `obj+0x108 = 0` (script disabled), return.
- Dispatch 0x441140: `jmp [0x440d4c + (op-1)*4]` for 1..253. Opcodes 0, 254 and the table entries 7, 30, 141
  go to 0x45a0f7: debug log `"%s %s Unknown command opcode %d %lx"` (arena name, type name, op, pc−g_cmi),
  then `obj+0x108 = 0`, `obj+0x248 = 0`, `obj+0x26c[0] = 0`, return.

Epilogue: handlers end with `jmp 0x45a168` (→ 0x440ccd, next opcode) or `jmp 0x45a177`
(`lea esp,[ebp-0x14]; pop edi..ebx; pop ebp; ret`). **No handler saves the pc on return.** Returning therefore
means "yield: next frame restarts at `obj+0x108`", except for:
- opcode 64 (wait), which saves the resume pc in `obj+0x230`;
- opcode 154, which sets `obj+0x108` to its own address first;
- error paths, which set `obj+0x108 = 0` (script stops).

`fatal_error` 0x40a2d0 only appends to `debug.err` when the debug flag 0x5742f8 is set. Every "error" in this
interpreter is non-fatal.

### Restart point, goto, gosub
- `obj+0x108` is the restart point. Opcode 1 sets it to the next instruction. A goto sets it to the target.
- Gosub stack, 4 levels: depth `obj+0x248` (s32), return pcs `obj+0x24c[4]`, saved restart points
  `obj+0x25c[4]`.
  - Gosub: `ret[d] = pc` (after all operands), `saved[d] = obj+0x108`, `d++`, `obj+0x108 = pc = target`,
    `u16 obj+0x26c[d] = 0`. If `d >= 4` beforehand: log "Gosub overflow on %s ID %d", `obj+0x108 = 0`, return.
  - Return: `d--`, `pc = ret[d]`, `obj+0x108 = saved[d]`. If `d == 0`: log "Gosub underflow…",
    `obj+0x108 = 0`, return.
  - Goto: `obj+0x108 = pc = target`, `obj+0x26c[d] = 0` (the stack is kept).
  - Opcode 125 clears the depth. Opcode 9 clears the depth and stops the script.
- `u16 obj+0x26c[depth]`: per-level frame counter used by the timer conditions 18/155 (`+= g_frame_ticks`,
  compared with seconds×30). It is zeroed by every goto/gosub.
- Another object can take over a script with opcode 4 command 7 (0x4405d0). Goto variant: sets
  `obj+0x108 = obj+0x230 = obj+0x10c = target`, clears the wait, depth = 0, leader `obj+0x138 = sender`.
  Command 0xFC variant: a remote gosub that pushes their current `obj+0x108` (as both return pc and saved restart
  point).

### Shared operand encodings (used in the JSON "complex" layouts)
- **pstr**: `u8 L` then L bytes (the NUL is included). Handlers take `pc+1` as the string (or `pc` if `L == 0`,
  which reads as the empty string), then `pc += L+1`.
- **branch action** (`[ebp-0x20]`, decode block of 0x89 bytes repeated in each handler): `u8 A`, then
  - `A == 0xFE`: `off32 then, off32 else`;
  - `A == 0xFC` or `A == 0x0C`: `off32 target` (offset 0 → null pointer);
  - `A == 0xFD` or any other value: no operand.

  The action runs after **all** operands of the opcode have been read. If true: 0x0C = goto, 0xFC/0xFE = gosub
  (then), 0xFD = return, any other value = goto with a stale `[ebp-0xb8]` (never seen in the data). If false and
  `A == 0xFE`: gosub else. Otherwise execution falls through. The values match opcode numbers 12 (goto),
  252 (gosub) and 253 (return).
- **value** (0x440944 `script_var_ptr`): `u8 kind`; `kind == 3` → `f32` literal; otherwise `u8 index` (0..3,
  clamped). kind 0 = global `0x573b4c[i]`, 1 = arena `(obj+0x60)+0x48[i]`, 2 = own `obj+0x234[i]`,
  other = linked object `(obj+0x2b8)+0x234[i]` (dummy 0x491eac if there is none).
- **off32**: `g_cmi + u32`, where g_cmi is file offset 4. Code targets appear in: branch actions, 12, 94, 95,
  252, the script of 29, and the action of 4/command 7. Data pointers appear in: 2 (path), 28 (path), 3/59
  (animation record: `u32` = 0 → looked up by the name at +4 via `arena_find_animation`).

Opcodes that never fall through (for a disassembler): 9, 12, 94, 253, 255. Opcodes 16 and 56 can end the
frame (death) but do fall through in the stream.

## Object fields (obj = alien/object, 0x32e bytes, allocated by 0x45fd4c)
| Offset | Meaning |
| --- | --- |
| +0x00 | next object in the arena list (arena+0x68) |
| +0x04 | u16 model index in the table 0x520a84 |
| +0x06 | u8 active |
| +0x07 | u8 target mode (opcode 251): 1 = is the global alien target (0x491e48), 2 = always targets Kurt |
| +0x08 | s32 health (≥ 65000 = indestructible) |
| +0x0c | pointer to the type/model record (name first; +0x1c part count; +0x20 parts, 0x5c bytes each, name first, bbox at +0x44) |
| +0x10/14/18 | position x, y, z (z is up) |
| +0x1c | spawn position (vec3) |
| +0x34 | current speed |
| +0x38 | max speed (default 50) |
| +0x3c | acceleration (default 10) |
| +0x40 | deceleration (default 15) |
| +0x44 | friction, units/s² (default 64; opcode 82, see [engine.md](../engine.md)) |
| +0x48 | gravity, units/s² (default 32; opcode 55; not a turn rate) |
| +0x4c | yaw (degrees) |
| +0x50/54 | previous yaw / bank (opcode 23 clears +0x54) |
| +0x5c | height offset for the target point (opcode 43) |
| +0x60 | arena |
| +0xac | sound emitter data (passed to sound_play_3d) |
| +0xdc | animation time (−1 = restart), advanced by `dt × obj+0xe0` |
| +0xe0 | animation fps (default 30) |
| +0xe4 | s16 current animation frame (−1 at start) |
| +0xe6 | s16 path stop frame (−1 = none) |
| +0xe8 | path speed (frames per tick, negative = backwards) |
| +0xec | path (spline record) pointer, 0 = none |
| +0xf0 | path time (frame) |
| +0xf4/f8/fc | path origin offset |
| +0x100 | yaw offset added to the path heading |
| +0x108 | script restart point (0 = no script) |
| +0x10c | script target last set by a command (opcode 4 command 7) |
| +0x110 | death script (set by opcode 76, part 2/3); used by object_kill 0x43d670 |
| +0x114 | animation pointer |
| +0x118 | s16 end/hold frame of the animation; 0xFF00 = animation ended |
| +0x11a | u8 command priority; +0x11b u8 obey level (opcodes 11/73) |
| +0x11c | s16 (set to 7 on spawn, counts down in the movement code) |
| +0x11e | u8 movement command: 0 idle, 1 formation, 6 go to the target, 15 alarm, 30 chain, 43 go near the target, … (handled by 0x45b6c8) |
| +0x120/124/128 | movement destination |
| +0x12c/130/134 | formation offset |
| +0x138 | leader / commanding object |
| +0x13c | smoothed bank value (opcode 218) |
| +0x140 | string (opcode 24); u16 +0x144 (opcode 24); s16 +0x146 = object id (level data / opcode 29) |
| +0x148..+0x14c | flag bytes (see the opcodes) |
| +0x150, +0x154 | strings (opcodes 26, 25) |
| +0x158/+0x15c | tracked sound voice / its name (opcode 89 flag 4) |
| +0x160[slot] | attached effects (opcode 128) |
| +0x1b0[slot] | 12-byte attachment points (vec3), used by 89/128/132 |
| +0x21d | s8 type of what caused the last hit (projectile type 1..4, 0xFC/0xFD) |
| +0x21e | s8 hit event this frame: >0 = hit on part index+1, −1/−2/−3 = other hit kinds; cleared by 0xFF |
| +0x21f | u8 indestructible flag |
| +0x22c / +0x230 | wait timer (s) / resume pc |
| +0x234[4] | script variables (f32) |
| +0x248, +0x24c[4], +0x25c[4], +0x26c[] | gosub depth, return pcs, saved restart points, u16 frame counters |
| +0x2a0/+0x2a1/+0x2a4..+0x2ac | movement planner state (cleared by opcode 43) |
| +0x2a2 | u16 copy of the health set by opcode 16 |
| +0x2b8 | linked object (var kind "other", selector 9) |
| +0x2c8 / +0x2cc | hidden-parts mask / locked (blown-off) parts mask |
| +0x302..+0x32e | union: path speed control (opcode 164), weak parts (opcode 198: +0x302 name prefix, +0x306 length, +0x30a, u16 +0x30e[8] hp, +0x31e[8] max hp), opcode 23 writes +0x302 = 1 |

## Helpers (address: suggested name)
- 0x440300 `gosub_stack_error` (debug log only; "Gosub underflow/overflow on %s ID %d")
- 0x440944 `script_var_ptr(obj, kind, index)`
- 0x440b88 `resolve_anim_ref(&ptr)` (if `*ptr == 0` → `arena_find_animation(ptr+4)`)
- 0x440384 `command_objects(obj, command, arg, selector, name, param)`; 0x4405d0 `command_object`
- 0x402b24 `rand_below(n)` (`rand()*n >> 15`); 0x4794dd `rand`; 0x4797c0 `round` (x87)
- 0x43c0f8 `spline_eval(path, t, out)`; 0x43c794 `path_apply(obj)`
- 0x43d6d4 `object_kill(obj)` → 0x43d670 (switch to the death script `obj+0x110` if it has one, else 0x43d224 explode)
- 0x4635b0 `bomb_set_path`; 0x4634ac its per-frame callback
- 0x4605d0 `can_see_kurt(obj, range, cone)`; 0x460730 `kurt_faces_object(obj, min, max, cone)`; 0x421680 BSP ray test
- 0x45da90 `compare_values(op, v, a, b)`: 1 `<`, 2 `>`, 3 `<=`, 4 `>=`, 5 `==`, 6 `!=` (±0.05), 7 `a<=v<=b`, 8 `v<=a || v>=b`
- 0x417450 `distance3d`; 0x45da40 `angle_to`; 0x440288 `sincos_deg`
- 0x45a1dc `plan_move` (movement toward obj+0x120 around obstacles)
- 0x45c510 `blow_off_parts(obj, pc, flag)` (reads `u8 N, N×pstr`, returns the new pc); 0x45c498 same, only if effects detail is on
- 0x45fd4c `object_alloc(arena)`; 0x43bc20 `object_init` (defaults + type init script); 0x404374 `model_instance_create`
- sound: 0x403c38 `sound_find(name)`, 0x402d98 `sound_is_playing`, 0x4032a8 `sound_find_voice`,
  0x402db0 `sound_play_3d`, 0x402ed8 `sound_restart_3d`, 0x402d5c `sound_stop`, 0x402f08 `sound_play_2d`,
  0x402fd8 `sound_play_2d_ex(snd, restart)`
- effects: 0x405138 `effect_alloc`, 0x405250 `effect_free`, 0x4067b8 `effect_attach`, 0x406434 `spawn_effect_a`,
  0x4052d4 `effect_init_b`, 0x406b3c `spawn_particle(template, vel, list, life)`
- 0x477cf4 `special_event(obj, n)`; 0x45d140 bullet holes (see engine.md); 0x467f7c `max_573aa8`
- 0x40a2d0 `fatal_error`: really a debug log (writes only when 0x5742f8 is set)

## Globals
- 0x574b2c `g_cmi`; 0x491e24 `g_frame_dt` (s); 0x491e18 `g_frame_ticks`
- 0x57fc34 target position (vec3), 0x57fc30 target yaw, 0x57fc40 scratch script object
- 0x573c20 decoy/priority target object; 0x491e48 object with target mode 1
- 0x573a0c current arena; 0x573a68 second arena (transition); 0x573b00 flag that disables the second arena for ray tests
- 0x573b4c global script vars [4]
- 0x573c98 3 player projectile slots (0xfc bytes each; +0xd0 type 1..4, +0x20 position); 0x491ef0 bomb projectile (type 4) that hit the world
- 0x5743ef + i×4 Kurt's weapon/ammo counters; 0x57432c inventory (0x24-byte entries: +0 type, +4 count), count 0x5743e0
- 0x5742dc effects/detail enabled; 0x5742f8 debug log enabled; 0x5742b8 cheat mode ("ityflvbg"); 0x57eac0 a key flag
- 0x573aec alarm counter; 0x573bd4 float set by opcode 244; 0x57391c float max'ed by opcode 5 (when 0x573a60 != 0 and 0x573a64 > 0); 0x573aa8 float max'ed by opcode 135; 0x573c80 set to −1 by opcode 131
- 0x520a84 model table (80 × 0x88 bytes, name first)
- 0x491eb4 particle template used by opcode 136 (0x491ec0/0x491ed0/0x491ee0 = position written by the opcode)

## Uncertain / anomalies
- **Opcode 250 box order.** The engine tests `f1<=x<=f4`, `f2<=y<=f5`, and `f3<=z<=f6` only when mode == 3.
  Three of the 11 uses in the data give sensible boxes with this order, which confirms it:
  - LEVEL4 MEAT_5: `SW_NUKE` in `(-136, 13306, -1993)–(-116, 13351, -1977)`;
  - LEVEL7 DANT_2: two uses of `(-55, 881, -31)–(68, 1028, 208)`.

  The other 8 are in LEVEL7 DANT_6 (0x16e65…0x16f53, called through opcode 183). They are written like
  `(489, -106, 4146, 4114, 525, -30)`, so the z range is empty and these checks can never pass in the original
  game (a data bug; the author apparently meant x ∈ [f1, f5]). Keep the engine order.
- **LEVEL3 HMO_9 arena script** (0x1c996 → file 0x1c99a) starts with opcode 141, which is invalid. In the
  original it logs "Unknown command" and the arena script stops. It looks like a data bug.
- A branch action byte other than 0x0C/0xFC/0xFD/0xFE would goto a stale pointer. A goto whose chosen offset
  is 0 jumps to a null pc (it would crash). Neither happens in the data.
- Opcode 4 selectors other than 2..10 compare names against a stale pointer. Seen in the data: command 7 with
  selectors 2, 3, 4, 5, 6, 7, 9, 10, and command 1 with selector 2.
- Opcode 42: when the first pstr is empty, a second pstr follows and the hit event is not cleared (1,347 of 3,608
  uses, usually `"" "ANY"`).
- Opcodes 21 and 118 consume 4 bytes but use the low 16 bits. Data: opcode 21 is mostly −2 (0xFFFFFFFE =
  "stop at the current frame").
- Opcode 186's first u8 is read and ignored. Opcode 198's last u32 is stored in `obj+0x30a` (purpose unknown,
  always 0 in the examples seen).
- Not identified: flag `obj+0x14c & 2` (opcode 37), `obj+0x2a0` (231), `obj+0x44` (82), opcode 130
  (0x45d140), the meaning of events > 50 in opcode 131, and the globals of opcodes 5/135/244.
