// The script interpreter (`script_run`, 0x440bc8) dispatches opcodes 1–253 through a jump table at
// 0x440d4c. Its cases span ~100 KiB, too much for the decompiler to handle as one function, so this
// creates a function per case, named `op_NNN` after the (first) opcode handled there.
// Usage (headless): -postScript SplitScriptOpcodes.java
// @category MDK

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.SourceType;

public class SplitScriptOpcodes extends GhidraScript {

	private static final long TABLE = 0x440d4c;
	private static final int COUNT = 253;
	private static final long DEFAULT_CASE = 0x45a0f7;

	@Override
	public void run() throws Exception {
		Map<Long, List<Integer>> targets = new TreeMap<>();
		for (int i = 0; i < COUNT; i++) {
			long target = getInt(toAddr(TABLE + i * 4L)) & 0xffffffffL;
			if (target == DEFAULT_CASE) {
				continue;
			}
			targets.computeIfAbsent(target, k -> new ArrayList<>()).add(i + 1);
		}
		// Mark the table as data so it isn't disassembled as code.
		for (int i = 0; i < COUNT; i++) {
			Address a = toAddr(TABLE + i * 4L);
			clearListing(a, a.add(3));
			createDWord(a);
		}
		int created = 0;
		for (Map.Entry<Long, List<Integer>> e : targets.entrySet()) {
			Address addr = toAddr(e.getKey());
			String name = String.format("op_%03d", e.getValue().get(0));
			disassemble(addr);
			Function f = getFunctionAt(addr);
			if (f == null) {
				f = createFunction(addr, name);
			}
			if (f == null) {
				printerr("Couldn't create " + name + " at " + addr);
				continue;
			}
			f.setName(name, SourceType.USER_DEFINED);
			setPlateComment(addr, "Script opcodes " + e.getValue());
			created++;
		}
		println("Created " + created + " opcode functions for " + targets.size() + " targets");
	}
}
