// Exports decompiled C code, strings (with referencing functions), imports and a function list
// of the current program, for grep-based analysis outside of the Ghidra UI.
// Usage (headless): -postScript ExportAll.java <output directory> [name prefix or "all"] [timeout seconds]
// With a name prefix, only the matching functions are decompiled, into `decomp_<prefix>.c`.
// @category MDK

import java.io.File;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.util.Set;
import java.util.TreeSet;

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileOptions;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.DataIterator;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.Symbol;

public class ExportAll extends GhidraScript {

	private String referencingFunctions(Address address) {
		Set<String> names = new TreeSet<>();
		for (Reference ref : getReferencesTo(address)) {
			Function f = getFunctionContaining(ref.getFromAddress());
			names.add(f != null ? f.getName() : ref.getFromAddress().toString());
		}
		return String.join(",", names);
	}

	@Override
	public void run() throws Exception {
		String[] args = getScriptArgs();
		File outDir = new File(args.length > 0 ? args[0] : ".");
		String prefix = args.length > 1 && !args[1].equals("all") ? args[1] : "";
		int timeout = args.length > 2 ? Integer.parseInt(args[2]) : 120;
		outDir.mkdirs();
		if (!prefix.isEmpty()) {
			exportDecompiled(new File(outDir, "decomp_" + prefix + ".c"), null, prefix, timeout);
			println("Export done: " + prefix);
			return;
		}

		try (PrintWriter pw = new PrintWriter(new FileWriter(new File(outDir, "strings.txt")))) {
			DataIterator it = currentProgram.getListing().getDefinedData(true);
			while (it.hasNext()) {
				Data d = it.next();
				if (!d.hasStringValue()) {
					continue;
				}
				String value = String.valueOf(d.getValue()).replace("\n", "\\n").replace("\r", "\\r");
				pw.println(d.getAddress() + "\t" + value + "\t" + referencingFunctions(d.getAddress()));
			}
		}

		try (PrintWriter pw = new PrintWriter(new FileWriter(new File(outDir, "imports.txt")))) {
			for (Symbol s : currentProgram.getSymbolTable().getExternalSymbols()) {
				Set<String> callers = new TreeSet<>();
				for (Reference ref : getReferencesTo(s.getAddress())) {
					callers.add(ref.getFromAddress().toString());
				}
				// Imports are usually called through thunks or IAT pointers.
				for (Symbol thunkSym : currentProgram.getSymbolTable().getSymbols(s.getName())) {
					for (Reference ref : getReferencesTo(thunkSym.getAddress())) {
						Function f = getFunctionContaining(ref.getFromAddress());
						callers.add(f != null ? f.getName() : ref.getFromAddress().toString());
					}
				}
				pw.println(s.getParentNamespace().getName() + "::" + s.getName() + "\t" + String.join(",", callers));
			}
		}

		exportDecompiled(new File(outDir, "decomp.c"), new File(outDir, "functions.txt"), "", timeout);
		println("Export done: " + outDir.getAbsolutePath());
	}

	private void exportDecompiled(File codeFile, File listFile, String prefix, int timeout) throws Exception {
		DecompInterface decomp = new DecompInterface();
		decomp.setOptions(new DecompileOptions());
		decomp.openProgram(currentProgram);
		try (PrintWriter code = new PrintWriter(new FileWriter(codeFile));
				PrintWriter list = listFile != null ? new PrintWriter(new FileWriter(listFile)) : null) {
			FunctionIterator functions = currentProgram.getFunctionManager().getFunctions(true);
			while (functions.hasNext() && !monitor.isCancelled()) {
				Function f = functions.next();
				if (!f.getName().startsWith(prefix)) {
					continue;
				}
				// Script opcode handlers are exported separately (prefix `op_`): they use their parent's stack
				// frame and are slow to decompile.
				if (prefix.isEmpty() && f.getName().startsWith("op_")) {
					continue;
				}
				int callers = f.getCallingFunctions(monitor).size();
				int callees = f.getCalledFunctions(monitor).size();
				if (list != null) {
					list.println(f.getEntryPoint() + "\t" + f.getName() + "\tsize=" + f.getBody().getNumAddresses()
							+ "\tcallers=" + callers + "\tcallees=" + callees);
				}
				if (f.isExternal() || f.isThunk()) {
					continue;
				}
				DecompileResults r = decomp.decompileFunction(f, timeout, monitor);
				code.println("// ==== FUNCTION " + f.getName() + " @ " + f.getEntryPoint() + " size="
						+ f.getBody().getNumAddresses() + " callers=" + callers);
				if (r.decompileCompleted()) {
					code.println(r.getDecompiledFunction().getC());
				} else {
					code.println("// decompile failed: " + r.getErrorMessage());
				}
				code.flush();
			}
		}
		decomp.dispose();
	}
}
