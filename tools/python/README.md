# Python reverse engineering tools

Reference decoders used to validate the file formats before implementing them in GDScript.
They need Python 3 with numpy and Pillow.

- `mdk_models.py`: models and animations of an arena's models section (and CMI models).
- `render_model.py`: renders flat-shaded contact sheets of animation frames, for validation.
- `mdk_stats.py`: `STATS.BNI` / `MDKFONT.FTI` texts; PNG previews of the intermission, debriefing,
  briefing and Score-O-matic pages (state 6).
- `fall3d_dump.py`: lists the fall's files (`FALL3D.BNI`, `FALL3D_n.MTI`, `FALL3D.SNI`), decodes
  `FALLPU_n` and the `ZOOMnnnn` haze masks, and exports PNGs (`--png <dir>`).
