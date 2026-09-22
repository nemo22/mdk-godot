# Ghidra setup for MDK

MDK (`MDKD3D.EXE`, `MDK95.EXE`, `MDK3DFX.EXE`) was compiled with Watcom C/C++ using the
*register* calling convention (`-5r`): the first four integer arguments are passed in
EAX, EDX, EBX and ECX, and the callee preserves every register it didn't receive an argument in.
Ghidra's bundled Watcom compiler spec defaults to the *stack* convention, so the decompiler output
is full of `unaff_EAX` values unless the register convention is the default.

## Install the compiler spec

1. Copy `x86watcomreg.cspec` to `<ghidra>/Ghidra/Processors/x86/data/languages/`.
2. In `<ghidra>/Ghidra/Processors/x86/data/languages/x86.ldefs`, add this line to the
   `x86:LE:32:default` language, next to the existing Watcom compiler:

   ```xml
   <compiler name="Watcom C (register convention)" spec="x86watcomreg.cspec" id="watcomreg"/>
   ```

## Analyze and export

```sh
analyzeHeadless <project dir> MDK -import MDKD3D.EXE -processor x86:LE:32:default -cspec watcomreg \
    -scriptPath tools/ghidra -postScript ExportAll.java <export dir>
```

`ExportAll.java` writes `decomp.c` (all functions), `functions.txt`, `strings.txt` (with referencing
functions) and `imports.txt` for grep-based analysis. `ApplyNames.java` applies the function names
and comments collected in `names.txt` (so they survive re-analysis).
