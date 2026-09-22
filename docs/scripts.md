# MDK scripts

Arenas, objects and aliens are driven by bytecode scripts stored in `LEVELn.CMI` (see
[formats.md](formats.md#cmi-scripts-)). The interpreter is `script_run` (0x440bc8).

- Opcode reference: [script_opcodes.md](script_opcodes.md) (generated from
  [`tools/python/script_opcodes.json`](../tools/python/script_opcodes.json)).
- Reference disassembler: [`tools/python/mdk_script_dis.py`](../tools/python/mdk_script_dis.py).
  It decodes every script of levels 3–8 (66,649 distinct instructions) without losing sync.
- Detailed notes from the reverse engineering (object fields, helpers, globals, per-opcode
  details): [scripts/notes_part1.md](scripts/notes_part1.md) (interpreter, opcodes 1–37 and others),
  [notes_part2.md](scripts/notes_part2.md), [notes_part3.md](scripts/notes_part3.md).

## Which scripts run

- **Arena scripts** (CMI directory 3, via the arena record): run every frame for the current arena
  (and the second arena during a transition), on an object embedded in the arena. They spawn
  pickups (`spawn_flagged x, y, z, "SW_H01"`), objects and aliens (`spawn x, y, z, "XG", script`),
  and wait for Kurt to reach areas (`if_kurt_in_rect`) to start the next waves.
- **Object type scripts** (directory 2, `ARENA$TYPE`): init scripts, run once when an object of that
  type is created (health, weak parts, flags, orientation…).
- **Alien instance scripts** (directory 0, `ARENA$TYPE_n`): the behavior of aliens placed by the DTI
  records of type 2.
- Scripts started by `spawn` opcodes and by commands from other objects (`command_objects`).

## Interpreter

Each object has a script **restart point** (`obj+0x108`, 0 = no script). Every frame, the
interpreter:

1. Sets the *target* to Kurt's position and yaw (or a decoy's).
2. If the wait timer (`obj+0x22c`, seconds) is running, decrements it and returns while it's
   positive; when it expires, execution resumes at the wait's resume point (`obj+0x230`).
3. Otherwise starts at the restart point and executes opcodes until one ends the frame: `0xFF`
   (the normal end of each frame's run), a handler that yields, or more than 1000 opcodes.

Handlers never save the current position: after yielding, the next frame starts again at the
restart point. `set_restart` (opcode 1) moves the restart point to the next instruction, and a goto
moves it to its target. So a typical loop is:

```
set_restart
if_anim_done  goto next_step      ; checked every frame
if_hit        goto hurt
gosub         common_checks
end                               ; 0xFF: end of this frame
```

- **Gosub stack**: 4 levels (return points and saved restart points); `return` restores both.
- **Per-level frame counter** (`obj+0x26c[depth]`), reset by goto/gosub, used by timer conditions.
- **Errors** (unknown opcode, stack over/underflow, more than 1000 opcodes) only stop the script
  (`obj+0x108 = 0`) and write to `debug.err` in debug mode.

## Shared operand encodings

- **pstr**: `u8 length` (including the NUL), then the characters.
- **Branch action** (at the end of most conditional opcodes, executed after all operands are read):
  `u8 action`, then `0x0C` (goto) or `0xFC` (gosub) + `off32 target`, `0xFE` (gosub then/else) +
  `off32 then, off32 else`, `0xFD` (return) without operand.
- **Value**: `u8 kind`; kind 3 = `f32` literal; otherwise `u8 index` of a variable: 0 = global,
  1 = arena, 2 = own object, other = linked object (`obj+0x2b8`). Each has 4 `f32` variables.
- **Comparison** (`compare_values` 0x45da90): `u8 op, f32 a` (+ `f32 b` for ops 7 and 8): 1 `v < a`,
  2 `v > a`, 3 `v < a + 0.05`, 4 `v > a − 0.05`, 5 `|v − a| < 0.05`, 6 `|v − a| ≥ 0.05`,
  7 `a ≤ v ≤ b`, 8 `v ≤ a or v ≥ b`, other ops false.
- **off32**: offset relative to file offset 4 of the CMI file: code (goto/gosub targets, spawned
  scripts) or data (animation records: `u32 0` then the animation name, looked up in the arena;
  path records: `u32 key count`, then 40-byte spline keys).

## Movement and animation

Scripts don't move objects themselves: movement opcodes set a movement command (`obj+0x11e`, the
number of the opcode that started it: 6, 43, 61, 74, 78, 88, 197, 229…), a path, velocities or a
one-frame push, which the engine carries out after the script every frame. Animations are played at
`obj+0xe0` frames per second (30 by default); opcode 3 plays one once and 59 loops it, and
conditions such as `if_anim_done` test their state. See [engine.md](engine.md#objects).

## The port's VM

- [`MDKScriptDecoder`](../mdk/script/script_decoder.gd) decodes instructions (cached per offset)
  from the operand layouts generated into [`script_opcodes.gd`](../mdk/script/script_opcodes.gd); it
  decodes every script like the Python disassembler.
- [`MDKScriptVM`](../game/scripts/script_vm.gd) runs a frame of an object's script like
  `script_run`. Opcodes that aren't implemented yet are still decoded (so scripts never lose sync)
  and their conditions are false; `--profile` lists the ones that were hit. The levels use 236
  opcodes; 24 aren't implemented yet, mostly effects (`attach_effect`, lights, debris), swinging
  objects and cutscene events. `tools/python/opcode_coverage.py` lists them and
  `tools/python/find_opcode.py` shows where the levels use an opcode.
- Each object's target is chosen when its script runs (`script_run`): Kurt, or the walking decoy
  (`0x573c20`), or the aliens' target set by `set_target_mode` 1 (`0x491e48`), unless the object has
  target mode 2 (always Kurt).
- Group hit scripts run in a scratch object per arena (the original's `0x57fc40`), see
  [engine.md](engine.md#group-hits-0x40d560).
- [`MDKScriptRuntime`](../game/scripts/script_runtime.gd) runs the scripts at 30 Hz: the arena
  script of Kurt's arena, the DTI aliens spawned when Kurt first enters an arena, and the objects of
  that arena; [`MDKObjectMotion`](../game/scripts/object_motion.gd) moves them like the engine.

## Findings about opcodes

- Opcode 41 (`set_targetable`) sets flag 0x100, the platform flag Kurt stands on (and 0x800000
  with mode 2); when cleared while Kurt stands on the object, he's let go (`0x573b84`).
- `wait_anim_frame` (154) makes itself the restart point: the script resumes there every frame
  until the animation reaches the frame (32767 = its end), then goes on.
- `touch_damage` (158, 0x45cf60) hurts Kurt once per visible part touching him, and other objects
  (not flags 0x820) touching its box with hit event −3 and hit type −4; with flags bit 0 the
  object dies when it hits, with bit 1 the script jumps to the target.
- `explode` (184) blasts with every target bit (−1), hit type −5, not counting kills (group hit
  kind 4); `explosion_damage` (178) uses its flags as targets and counts kills.
- `push_kurt` (248) knocks Kurt down (state 901) unless he's already down (priority ≥ 9) or hangs
  (state 800); the push is `a × frame time` added to `0x573c08`, a displacement per tick, and it
  stops firing.
- `if_kurt_looks_at_me` (87, 0x460730): the cone around Kurt's yaw narrows linearly from 90° at
  distance 0 to `cone` at `max_range`; the line of sight goes from Kurt's z + 5 to the object's z + 2.
- `find_object` (245) mode 2 looks for Kurt's items (flag 0x1000): level 5's `XGUNTAM` uses it to
  go and eat thrown seals and bones.
- `hud_message` (247, 0x425400) queues a text of `MDKFONT.FTI` (e.g. `MU5_INI`, the bones' countdown
  `BONE1`–`BONE10` in level 4, the practice room's hints `DA2_*` in level 7), always with flag 1
  (growing and shrinking), see [gameplay.md](gameplay.md#hud-0x41e128).
- `pick_waypoint8` (221, 0x460a6c) weighs every type-8 waypoint: `500 − distance` (2D), plus
  `200 − distance to Kurt` when Kurt is within 200 of it, plus 250 when the object is closer to
  Kurt than to the waypoint and the waypoint is farther from Kurt than from the object, less half
  the height difference, at least 1. Mode 0 only takes waypoints 50–500 units away, mode 1 those
  whose id is within 3 of the nearest one.
- `path_speed_by_kurt` (164) compares how far the object is ahead of Kurt along its own heading
  with the set distance (±5) and moves the path speed towards the far, middle or near speed by
  `(near − far) × 0.5` per second.
- `lob_to_kurt` (189) only throws when the target is at or below the object: it solves the fall
  time and sets the horizontal speed to `friction × 0.5 × t + distance / t`, at most the maximum.
- `boss_bar` (181) only acts while Kurt fires. Mode 0 shows `max − counter` of a triangle group
  (the destructible parts of the level 3 and 4 bosses), mode 1 `(high − v) / (high − low) × max` of
  an arena variable `v` (`arena+0x48`: `HMO_3`, `DANT_7`, level 8's `XEARTH`).
- The alarm (movement command 15) plays `ALERT` every 32 frames and keeps `0x573aec` at 10 ticks
  (`if_alarm`).

## Data bugs in the original

- `LEVEL3`'s `HMO_9` arena script starts with opcode 141, which has no handler: the script stops at
  once (the original writes "Unknown opcode" to its debug log). The arena has no script in practice.

- LEVEL3 `HMO_9`'s arena script starts with the invalid opcode 141, so it stops immediately.
- 8 of the 11 uses of opcode 250 (`if_in_box`, in LEVEL7 `DANT_6`) have an empty Z range and can
  never be true.
- Opcode 182 (`switch_goto`, unused by the levels) doesn't advance through its table, so it always
  jumps to entry 1. Opcode 183 (`switch_gosub`) does it right.
