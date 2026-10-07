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
  Kurt colliding with objects and carried by platforms, and with only his and the active second
  arena.
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
- The fall before each level (`FALL3D`): the intro in space, the ground with the minecrawler and
  its track, the haze, steering, radars, homing missiles, pickups with chutes, Bones, the palette
  effects, death; the health and pickups carried into the level.
- The stream after each level (`STREAM`): the generated tube, Kurt's steering and the walls, the
  lights, the `SWH150` bonus, Bones' rescue, Gunter and the planet after LEVEL8, the fades.
- The save prompt after a level ("Save Game?", the name typed in the original fonts); F2 full
  saves of the level's state.
- The original's sound mixer (volume in dB, distance law, Doppler, the scope listening, loops and
  volumes from the SNI files) and its music fades, `CORRIDOR` in corridors.
- Sparks (chain gun, rounds, explosions) and objects breaking up into their `<model>D` pieces
  with smoke trails and gore.
- The full-screen strike before Bones' air strike and Kurt's final strike.
- The second arena (behind an open door, the one just left): its objects and script run, its
  aliens appear as the door opens; `arena_show`, `arena_set_neighbour` and the trigger records;
  only Kurt's and the second arena are drawn, arenas put away stop their loop sounds; Kurt only
  goes into connected arenas (teleports stay put); type 4 DTI objects; rays only in Kurt's and
  the second arena; thrown items go with their arena.
- `SW_H150` running away from Kurt, the holy cow of `SW_EWJ`.
- Rides: the snowboard of level 4, the `XD2` and the `XE` bomber of level 7 (`MDKRides`, `MDKBomber`); Kurt breaks triangle
  groups he runs into (the ice walls).
- Kurt grabs ledges and climbs up them; the end of a level turns him and tilts the view up.
- The camera roll (running and turning, sliding, the board), walls hit head-on stop Kurt, and the
  camera pushes Kurt away from walls instead of getting closer.
- Aliens plan detours around walls (`plan_move`), replan when stuck, and bank into their turns.
- Sniper mode: the scope screen, zoom, target lock, the clip and rounds (bullets, homing bullets,
  grenades, homing grenades, the mortar and its guidance by `bomb_follow_path`), Bones' air strike,
  the round cameras, bullet holes, the 3D clip on the screen, the air strike's iris.
- Options in the main and pause menus (volumes, music filter, mouse, fullscreen, difficulty, keys),
  saved in
  `user://settings.cfg`; music and effects on their own buses with a limiter; `OPTSONG` and `OPTBUTT`.

## Next

2. **Menu**: the original's options sub-pages (the port keeps its own options page).

## Menu

- Main menu (new game, load game, options, quit), pause menu, level select, drawn in the original's
  font and layout (`MenuItems`); "Really Quit?" on Esc; gore as an option, switch and cheat.
- Options: sound volumes, music filter, mouse, fullscreen, difficulty, gore, graphics (original or
  enhanced, below) and key bindings (one key or mouse button per action). The pause menu (Esc) has
  resume, options, main menu, quit.
- Original assets where possible (`MISC/OPTIONS.BNI`, `MISC/MDKFONT.FTI`, menu video `MDK12.FLC` and
  the `MDKS_*.GIF` slideshow, the end movies `MDKEND.FLC` and `MDKBZK.MVE`).

## Enhanced graphics mode

A toggle between the original look and an enhanced one ("Graphics" in the options, from the next
level; `--enhanced` / `--original` for tests).

Done (first pass):

- **Texture filtering**: bilinear by hand in the palette shader (`palette_filtered.gdshaderinc`:
  four texels through the palette, then blended; index 0 stays transparent, animated textures
  keep to their frame). No mipmaps yet.
- **Lighting**: flat normals on arena and model meshes (`MDKMeshBuilder.flat_normals`), lit
  palette and colour materials (`MDKMeshBuilder.Look`), one sun with shadows (`Level._enhance`,
  the same direction in every level), white ambient light so shaded faces keep about the
  texture's brightness.
- **Post-processing**: SSAO, glow only above the HDR threshold (no bloom: it lifted the blacks), a
  light haze (0.0002 per unit; 0.0007 veiled whole rooms) in the colour of the sky's horizon
  (`tests/enhanced_haze_test.gd`).
- **Sky, sprites and screens**: the sky is filtered the same way (`sky.gdshader` `filtered`),
  Kurt's and the muzzle's sprites too (alpha-scissored edges, `sprite.gdshader`), and the HUD,
  menus and other 2D screens sample their images linearly (`Settings.canvas_filter`). Flat
  sprites throw no shadows (`tests/sprite_shadow_test.gd`).

Still to do: mipmaps or anisotropic filtering, a sun per level matched to its sky, lights for
muzzle flashes, explosions and effects, smooth normals where faces meet at small angles.
