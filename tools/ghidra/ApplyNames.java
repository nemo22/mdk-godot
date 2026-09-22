// Applies reverse engineered names from a text file, so that they can be kept under version control
// and re-applied after re-importing the executable.
//
// File format (one entry per line, `#` starts a comment):
//   func <address> <name> [signature]   Names a function (creating it if needed). The optional signature
//                                       is a C prototype such as `void f(int a, char *b)`.
//   data <address> <name>               Names a global variable (a label).
//   note <address> <text...>            Sets a plate comment.
//
// Usage (headless): -postScript ApplyNames.java <names.txt>
// @category MDK

import java.io.File;
import java.nio.file.Files;
import java.util.List;

import ghidra.app.cmd.function.ApplyFunctionSignatureCmd;
import ghidra.app.script.GhidraScript;
import ghidra.app.util.parser.FunctionSignatureParser;
import ghidra.program.model.address.Address;
import ghidra.program.model.data.FunctionDefinitionDataType;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.SourceType;

public class ApplyNames extends GhidraScript {

	@Override
	public void run() throws Exception {
		String[] args = getScriptArgs();
		List<String> lines = Files.readAllLines(new File(args[0]).toPath());
		FunctionSignatureParser parser = new FunctionSignatureParser(currentProgram.getDataTypeManager(), null);
		int applied = 0;
		for (String raw : lines) {
			String line = raw.strip();
			int hash = line.indexOf(" #");
			if (line.isEmpty() || line.startsWith("#")) {
				continue;
			}
			if (hash >= 0) {
				line = line.substring(0, hash).strip();
			}
			String[] parts = line.split("\\s+", 4);
			Address addr = toAddr(parts[1]);
			switch (parts[0]) {
				case "func": {
					Function f = getFunctionAt(addr);
					if (f == null) {
						disassemble(addr);
						f = createFunction(addr, parts[2]);
					}
					if (f == null) {
						printerr("Couldn't create function at " + addr);
						continue;
					}
					f.setName(parts[2], SourceType.USER_DEFINED);
					if (parts.length > 3) {
						try {
							FunctionDefinitionDataType sig = parser.parse(f.getSignature(), parts[3]);
							new ApplyFunctionSignatureCmd(addr, sig, SourceType.USER_DEFINED).applyTo(currentProgram, monitor);
						} catch (Exception e) {
							printerr("Bad signature for " + parts[2] + ": " + e.getMessage());
						}
					}
					break;
				}
				case "data":
					createLabel(addr, parts[2], true, SourceType.USER_DEFINED);
					break;
				case "note":
					setPlateComment(addr, line.split("\\s+", 3)[2]);
					break;
				default:
					printerr("Unknown entry: " + raw);
					continue;
			}
			applied++;
		}
		println("Applied " + applied + " names");
	}
}
