# Roadmap

## Done

- Level loading: all 6 levels (arenas, textures, animated textures, palettes, special materials,
  sky), collision with the arena geometry.
- Kurt: sprite animations, animation states, movement with the original constants (acceleration,
  turbo, turning, jumping, falling, chute), third person camera following the original formula.
- Main menu with the original background, texts, music and sound (drawn in a Godot font, not yet
  in the original ones).
- Model and animation formats (models section and CMI models), model viewer.
- Level viewer (`--viewer`) and model viewer (`--models`).
- Scripts: bytecode decoder (every script of the game) and VM with 204 of the 236 opcodes the levels
  use; arena scripts, DTI aliens, spawned objects, commands between objects, partners, group hit
  scripts.
- Object movement like the original: spline paths, walking, flying, chasing, formations,
  projectiles, gravity, friction and collisions with the arena.
- Doors (connectors), pickups falling with chutes, arena triangle groups (hidden/non-solid parts),
  Kurt colliding with objects and carried by platforms.
- Kurt's chain gun: firing animations and sound, auto-aimed hits, weak parts, hit events, deaths
  and explosions; the super chain gun.
- Pickups and the inventory, health, damage and death, the HUD (health and inventory).
- Items: throwing, grenades, the decoy, the World's Most Interesting Bomb, the tornado, the mortar,
  the nuke, the seal and the bone, blasts (also on triangle groups).
- Kurt knocked down by hits and pushes, screen shake and white flash.
- HUD messages in the original fonts (pickups, script hints), the health bar, the minecrawler's
  timer.

## Next

1. **Aliens and scripts**: the last 32 opcodes (effects, lights, fans and wind, chains, cutscene
   events), effects (sparks, particles, debris), path planning around walls (`plan_move`),
   automatic banking, the second arena seen through open doors.
2. **Weapons and sniper mode**: sniper mode and its ammo (Bones' air strike), saving and loading.
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
