// Exports decompiled C code, strings (with referencing functions), imports and a function list
// of the current program, for grep-based analysis outside of the Ghidra UI.
// Usage (headless): -postScript ExportAll.java <output directory>
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
		outDir.mkdirs();

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
				Function ext = getFunctionAt(s.getAddress());
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

		DecompInterface decomp = new DecompInterface();
		DecompileOptions options = new DecompileOptions();
		decomp.setOptions(options);
		decomp.openProgram(currentProgram);

		try (PrintWriter code = new PrintWriter(new FileWriter(new File(outDir, "decomp.c")));
				PrintWriter list = new PrintWriter(new FileWriter(new File(outDir, "functions.txt")))) {
			FunctionIterator functions = currentProgram.getFunctionManager().getFunctions(true);
			while (functions.hasNext() && !monitor.isCancelled()) {
				Function f = functions.next();
				int callers = f.getCallingFunctions(monitor).size();
				int callees = f.getCalledFunctions(monitor).size();
				list.println(f.getEntryPoint() + "\t" + f.getName() + "\tsize=" + f.getBody().getNumAddresses()
						+ "\tcallers=" + callers + "\tcallees=" + callees);
				if (f.isExternal() || f.isThunk()) {
					continue;
				}
				DecompileResults r = decomp.decompileFunction(f, 120, monitor);
				code.println("// ==== FUNCTION " + f.getName() + " @ " + f.getEntryPoint() + " size="
						+ f.getBody().getNumAddresses() + " callers=" + callers);
				if (r.decompileCompleted()) {
					code.println(r.getDecompiledFunction().getC());
				} else {
					code.println("// decompile failed: " + r.getErrorMessage());
				}
			}
		}
		decomp.dispose();
		println("Export done: " + outDir.getAbsolutePath());
	}
}
