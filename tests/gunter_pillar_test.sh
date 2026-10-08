#!/bin/sh
# Bug test: LEVEL5 MUSE_4's Gunter (XGUNTAM, flag 0x80000000) sank into his pillar with each taunt
# (XGU_BLDM). Flag 0x80000000 skips the animation's root motion (anim_step_frames 0x43ab70): after
# a minute he still stands at z -1563.
# Run from the project folder: sh tests/gunter_pillar_test.sh <godot executable>
GODOT=${1:-godot}
OUT=$(timeout 180 "$GODOT" --headless --audio-driver Dummy --path . -- --level=5 --at=398.21,211.26,-1622,265 --god --profile=60 2>&1 | grep "^  XGUNTAM")
echo "$OUT"
echo "$OUT" | grep -q -- "-1563.0)" && echo PASSED && exit 0
echo FAILED
exit 1
