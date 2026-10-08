#!/bin/sh
# Bug test: triangles flagged 0x2 (material NONE) are made not drawn and not solid when the original
# activates an arena (0x40d46c(a,1)). LEVEL8 GUNT_2's one cuts the floor diagonally: walking west
# from (-259, 488) Kurt must get past it.
# Run from the project folder: sh tests/hidden_wall_test.sh <godot executable>
GODOT=${1:-godot}
OUT=$(timeout 60 "$GODOT" --headless --audio-driver Dummy --path . -- --level=8 --at=-258.96,488.37,7.51,166 --walk=1.5 --profile=0.5 2>&1 | grep "^Kurt at")
echo "$OUT"
X=$(echo "$OUT" | sed -n 's/^Kurt at (\(-*[0-9]*\).*/\1/p')
[ -n "$X" ] && [ "$X" -lt -265 ] && echo PASSED && exit 0
echo FAILED
exit 1
