// Creates functions that auto-analysis missed: Watcom-compiled functions start with
// `push ebp; mov ebp, esp` (55 89 E5), usually after a `ret` or alignment padding.
// Large functions with jump tables Ghidra couldn't resolve often end up not being functions.
// Usage (headless): -postScript FindMissedFunctions.java
// @category MDK

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.mem.MemoryBlock;

public class FindMissedFunctions extends GhidraScript {

	@Override
	public void run() throws Exception {
		MemoryBlock code = currentProgram.getMemory().getBlock("AUTO");
		byte[] bytes = new byte[(int) code.getSize()];
		code.getBytes(code.getStart(), bytes);
		int created = 0;
		for (int i = 1; i + 2 < bytes.length; i++) {
			if (bytes[i] != 0x55 || bytes[i + 1] != (byte) 0x89 || bytes[i + 2] != (byte) 0xE5) {
				continue;
			}
			int previous = bytes[i - 1] & 0xFF;
			// After `ret`, `ret n` (checked loosely via its last byte being 0), `nop` padding or `int3`.
			if (previous != 0xC3 && previous != 0x90 && previous != 0xCC && previous != 0x00) {
				continue;
			}
			Address addr = code.getStart().add(i);
			Function containing = getFunctionContaining(addr);
			if (containing != null) {
				continue;
			}
			disassemble(addr);
			Function f = createFunction(addr, null);
			if (f != null) {
				created++;
				println("Created " + f.getName() + " size=" + f.getBody().getNumAddresses());
			}
		}
		println("Created " + created + " missed functions");
	}
}
