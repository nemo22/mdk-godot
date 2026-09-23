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
- Scripts: bytecode decoder (every script of the game) and VM with 235 of the 236 opcodes the levels
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
- Fans (updrafts) with their particles, the wind zones and Kurt sliding on his back (level 6),
  chains of objects and waypoints.
- Swinging objects and their ropes, `spawn_box` flames, animated wall speeds, the cutscenes (states
  and camera shots) and the end of a level.
- Effects: slime wounds, drops and bubbles, shattered triangle groups, rolling boulders, leaping
  aliens, level 6's shooting galleries, the camera tilting up at bosses.
- The order of play (LEVEL7, 6, 3, 4, 8, 5), loading screens, the end of level (the arena torn
  apart around Kurt as he rises), dying back to the menu with "Continue", saved games.
- The screens between levels: intermission, debriefing by the towns' fate, the Score-O-matic
  (shots, accuracy, sniper rounds, kills, spinning head shots) and the briefing.
- Kurt grabs ledges and climbs up them; the end of a level turns him and tilts the view up.
- Aliens plan detours around walls (`plan_move`), replan when stuck, and bank into their turns.
- Sniper mode: the scope screen, zoom, target lock, the clip and rounds (bullets, homing bullets,
  grenades, homing grenades, the mortar and its guidance by `bomb_follow_path`), Bones' air strike,
  the round cameras, bullet holes.
- Options in the main and pause menus (volumes, music filter, mouse, fullscreen, difficulty, keys),
  saved in
  `user://settings.cfg`; music and effects on their own buses with a limiter.

## Next

1. **Aliens and scripts**: sparks and explosions' debris, the full-screen strike of Bones, the
   second arena seen through open doors.
2. **Sniper mode**: the 3D clip on the screen and the air strike's iris.
3. **Sound**: SNI sounds, arena sounds, music, footsteps.
4. **Movement details**: slippery floors, camera roll, pushing Kurt
   away from walls instead of moving the camera closer, stopping on walls hit head-on.
5. **Level flow**: the falling sequence (`FALL3D`, documented), the stream between levels
   (`STREAM`), F2 snapshots and the save prompt after a level.

## Menu

- Main menu (new game, load game, options, quit), pause menu, level select (partly done).
- Options: sound volumes, music filter, mouse, fullscreen, difficulty and key bindings (one key or
  mouse button per action) are done; still to do: the enhanced mode below. The pause menu (Esc) has
  resume, options, main menu, quit.
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
