# Roadmap

## Done

- Level loading: all 6 levels (arenas, textures, animated textures, palettes, special materials,
  sky), collision with the arena geometry.
- Kurt: sprite animations, animation states, movement with the original constants (acceleration,
  turbo, turning, jumping, falling, chute), third person camera following the original formula.
- Main menu with the original background, texts, music and sound (the original font isn't decoded).
- Model and animation formats (models section and CMI models), model viewer.
- Level viewer (`--viewer`) and model viewer (`--models`).
- Scripts: bytecode decoder (every script of the game) and VM with 107 of the 251 opcodes; arena
  scripts, DTI aliens, spawned objects, commands between objects.
- Object movement like the original: spline paths, walking, flying, chasing, formations,
  projectiles, gravity, friction and collisions with the arena.

## Next

1. **Aliens and scripts**: the remaining opcodes (hits and weak parts, effects, doors and triangle
   groups, sounds attached to animations, the bomb/decoy), path planning around walls
   (`plan_move`), automatic banking, chains.
2. **Weapons and sniper mode**, HUD.
3. **Sound**: SNI sounds, arena sounds, music, footsteps.
4. **Movement details**: ledge grab, slippery floors, conveyors, updrafts, camera roll, pushing Kurt
   away from walls instead of moving the camera closer, stopping on walls hit head-on.
5. **Level flow**: the falling sequence (`FALL3D`), the stream between arenas (`STREAM`), end of
   level statistics, loading screens (`LOAD_n.LBB`), saving.

## Menu

- Main menu (new game, load game, options, quit), pause menu, level select (partly done).
- Options: video (including the enhanced mode below), sound, controls.
- Original assets where possible (`MISC/OPTIONS.BNI`, `MISC/MDKFONT.FTI`, menu video `MDK12.FLC`).

## Enhanced graphics mode

A toggle between the original look and an enhanced one:

- **Texture filtering**: bilinear/trilinear filtering with mipmaps and anisotropic filtering
  (textures are converted from palette indices to RGBA for this; the original mode keeps
  nearest-neighbor palette lookup).
- **Dynamic lighting**: per-vertex normals, lit materials, a sun light per level (direction and
  color matched to the sky), shadows, lights for muzzle flashes, explosions and effects.
- Post-processing: ambient occlusion, glow, fog matched to the sky colors, higher view distance.
- Proper effects for special materials (reflective mirrors, glass, animated water).
