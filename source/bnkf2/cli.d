
/+ SPDX-LICENSE-IDENTIFIER: 0BSD +/

module bnkf2.cli;

import bnkf2;
import zlib;

import std.traits : Unqual;
import std.typecons : Flag, No, Yes;


version (X86)
{
	version = X86_64_Or_X86;
}
else version (X86_64)
{
	version = X86_64_Or_X86;
}


version (Windows)
{
	alias OSChar = wchar;
	alias IOHandle = HANDLE;
}
else
{
	alias OSChar = char;
	alias IOHandle = int;
}


enum immutable(OSChar)[] versionString = "v0.9.1";


static immutable(OSChar[]) commandLineUsage = (
	  "bnkf2 | Converter of BNK files from Fable II " ~ versionString ~ "\r\n"
	~ "Usage:\r\n"
	~ "    bnkf2 [<switches>] [--] <input-file-path> [[--] <output-file-path>]\r\n"
	~ "        | Converts a BNK file to a zip file or a zip file to a BNK file, depending on the file extension.\r\n"
	~ "          The output file will be placed beside the input file with a different file extension.\r\n"
	~ "          Existing output files will be overwritten.\r\n"
	~ "          A file-path argument may be prefixed with '--' to prevent it from\r\n"
	~ "          being interpreted as a switch if it happens to begin with a dash.\r\n\r\n"
	~ "        | Switches:\r\n"
	~ "          | -i|-in|-input bnk|zip: This switch instructs BNKF2 to ignore the file extension of the input file\r\n"
	~ "                                   and to instead treat it as the type of file specified just after the switch.\r\n"
	~ "          | -o|-out|-output bnk|zip: This switch instructs BNKF2 to ignore the file extension of the input/output file\r\n"
	~ "                                     and to instead output the type of file specified just after the switch.\r\n"
	~ "          | -q|-quiet: This switch inhibits the output of progress messages and other non-essential messages.\r\n\r\n"
	~ "          | -d|-emitDuplicateFiles: When converting a BNK file to a zip file, this switch will\r\n"
	~ "                                    this switch will cause files duplicated in the BNK file to also\r\n"
	~ "                                    be duplicated in the zip file.\r\n"
	~ "          | -t|-omitBNKF2Metadata: When converting a BNK file to a zip file, this switch will\r\n"
	~ "                                   prevent BNKF2 from including a '.__bnkf2' metadata file in the zip file.\r\n"
	~ "          | -n|-ignoreBNKF2Metadata: When converting a zip file to a BNK file, this switch will\r\n"
	~ "                                     instruct BNKF2 to ignore any '.__bnkf2' metadata file in the zip file.\r\n"
	~ "          | -m|-outputCompressedBNK: When converting a zip file to a BNK file, this switch will\r\n"
	~ "                                     instruct BNKF2 to create a compressed BNK file.\r\n"
	~ "                                     The compression-status stored within a '.__bnkf2' metadata file\r\n"
	~ "                                     takes precedence over this switch\r\n"
	~ "                                     unless the '-ignoreBNKF2Metadata' is also provided.\r\n"
	~ "          | -f(t/d)(c/m)l|-file(Table/Data)(Compression/Memory)Level <level>:\r\n"
	~ "                                     When converting a zip file to a BNK file,\r\n"
	~ "                                     these switches control the aggressiveness of the compression\r\n"
	~ "                                     used for the BNK file-table or file-data. The valid values are 0-to-9.\r\n"
	~ "                                     0 being uncompressed, 1 being minimal compression, 9 being maximal compression.\r\n"
	~ "          | -ftuct|-fileTableUncompressedChunkThreshold <threshold>:\r\n"
	~ "                                     When converting a zip file to a BNK file, this switch\r\n"
	~ "                                     specifies the maximum uncompressed size of an individual\r\n"
	~ "                                     compressed chunk of the BNK's file-table.\r\n\r\n"
	~ "    bnkf2 -c|-command <command-name> [...]\r\n"
	~ "        | Inhibits the usual file conversion routine and instead causes BNKF2\r\n"
	~ "          to enact the command specified just after the switch.\r\n\r\n"
	~ "        | Commands:\r\n"
	~ "          | isCompressedBnk? [--] <input-file-path>\r\n"
	~ "            | Prints 0 or 1 representing whether the input file is an uncompressed or compressed BNK file.\r\n"
	~ "              Fails with a non-zero status-code if the input file is too small to be a BNK file.\r\n\r\n"
	~ "    bnkf2 [-help|h]\r\n"
	~ "        | Prints this help information.\r\n\r\n"
	~ "    bnkf2 -version\r\n"
	~ "        | Prints the version of bnkf2.\r\n"
);


version (Windows)
{
	__gshared typeof(&NtCopyFileChunk) ntCopyFileChunk;

	extern(System)
	void entrypoint ()
	{
		auto ntdll = GetModuleHandleW("ntdll");
		ntCopyFileChunk = cast(typeof(&NtCopyFileChunk)) GetProcAddress(ntdll, "NtCopyFileChunk");

		auto shell32 = LoadLibraryW("shell32");
		auto commandLineToArgvW = cast(typeof(&CommandLineToArgvW)) GetProcAddress(shell32, "CommandLineToArgvW");

		int argumentCount = void;
		wchar** arguments = commandLineToArgvW(GetCommandLineW, &argumentCount);

		int statusCode = void;

		if (arguments != null)
		{
			StandardIOHandles io = StandardIOHandles.get;
			InvocationDictates dictates = void;
			statusCode = parseCommandLineArguments(arguments[0 .. argumentCount], &dictates, &io);

			if (statusCode == 0)
			{
				statusCode = invokeWithDictates(&dictates, &io);
			}
		}
		else
		{
			statusCode = -1;
		}

		ExitProcess(statusCode);
	}
}


struct StandardIOHandles
{
	ConsoleOrIOHandle stdout;
	ConsoleOrIOHandle stderr;
	ConsoleOrIOHandle stdin;

	static StandardIOHandles get () nothrow @nogc
	{
		return StandardIOHandles(
			ConsoleOrIOHandle.fromHandle(GetStdHandle(STD_OUTPUT_HANDLE)),
			ConsoleOrIOHandle.fromHandle(GetStdHandle(STD_ERROR_HANDLE)),
			ConsoleOrIOHandle.fromHandle(GetStdHandle(STD_INPUT_HANDLE))
		);
	}
}


struct InvocationDictates
{
	enum Archetype : ubyte
	{
		unknown = 0,
		help = 1,
		version_ = 2,
		fileConversion = 3,
		isCompressedBNK = 4
	}

	struct Help
	{}

	struct Version
	{}

	struct FileConversion
	{
		Switches switches;

		union
		{
			struct
			{
				const(OSChar)* inputPath;
				const(OSChar)* outputPath;
			}

			const(OSChar)*[2] ioPaths;
		}

		enum Switches : uint
		{
			none = 0,
			quiet = 1 << 0,
			input = 1 << 1,
			output = 1 << 2,
			fileTableCompressionLevel = 1 << 3,
			fileTableMemoryLevel = 1 << 4,
			fileDataCompressionLevel = 1 << 5,
			fileDataMemoryLevel = 1 << 6,
			emitDuplicateFiles = 1 << 7,
			omitBNKF2Metadata = 1 << 8,
			ignoreBNKF2Metadata = 1 << 9,
			outputCompressedBNK = 1 << 10,
			fileTableUncompressedChunkThreshold = 1 << 11
		}

		enum FileType : ubyte
		{
			bnk = 0,
			zip = 1
		}

		enum InputFileType : FileType
		{
			bnk = FileType.bnk,
			zip = FileType.zip
		}

		enum OutputFileType : FileType
		{
			bnk = FileType.bnk,
			zip = FileType.zip
		}

		InputFileType inputFileType;
		OutputFileType outputFileType;

		DEFLATECompressionLevel fileTableCompressionLevel;
		ZLibMemoryLevel fileTableMemoryLevel;
		DEFLATECompressionLevel fileDataCompressionLevel;
		ZLibMemoryLevel fileDataMemoryLevel;

		uint fileTableUncompressedChunkThreshold;
	}

	struct IsCompressedBNK
	{
		const(OSChar)* inputPath;
	}

	Archetype archetype;

	union
	{
		Help help;
		Version version_;
		FileConversion fileConversion;
		IsCompressedBNK isCompressedBNK;
	}
}


int parseCommandLineArguments (scope const(OSChar*)[] arguments, scope InvocationDictates* dictates, scope StandardIOHandles* io)
{
	if (arguments.length <= 1)
	{
		dictates.archetype = dictates.archetype.help;
		return 0;
	}

	alias whyIsThisStillAnIssueIn2025 = __traits(getOverloads, bnkf2, "wathash", true)[0];
	alias hashFor = whyIsThisStillAnIssueIn2025!(asciiLowerCase, OSChar);

	static if (OSChar.sizeof == 1)
	{
		alias h = hashFor;
	}
	else
	{
		enum h (const(OSChar)[] target) = ()
		{
			ubyte[target.length << 1] asBytes;
			foreach (index, codeUnit; target) asBytes[index << 1] = cast(ubyte) codeUnit;
			return wathash!asciiLowerCase(asBytes[]);
		}();
	}

	arguments = arguments[1 .. $];

	const(OSChar)[] e = void;
	uint pathCount = 0;

	const(OSChar)* arg = arguments[0];
	ubyte dashCount = eatSwitchPrefix(arg);
	size_t length = strlen(arg);
	ulong hash = void;

	enum string advance =
	q{
		arguments = arguments[1 .. $];
		arg = arguments[0];
	};

	enum string advanceAndHash =
	q{
		mixin(advance);
		length = strlen(arg);
		hash = hashFor(arg[0 .. length]);
	};

	enum string match (string target, string unrecognised = q{unrecognisedSwitch}, string length = q{length}) =
	`
		case h!"` ~ target ~ `":
			if ((` ~ length ~ `) != ` ~ target.length.asDecimal ~ `)
			{
				goto ` ~ unrecognised ~ `;
			}

			if (`
				~ (
					  target.length == 1
					? (`arg[0].asciiLowerCase != '` ~ target[0] ~ `'`)
					: (`!bitEqual!asciiLowerCase(arg, "` ~ target ~ `"` ~ (OSChar.sizeof == 1 ? `` : `w`) ~ `.ptr, (` ~ length ~ `))`)
				)
			~ `)
			{
				goto ` ~ unrecognised ~ `;
			}
	`;

	if (dashCount != 0)
	{
		hash = hashFor(arg[0 .. length]);

		switch (hash)
		{
		mixin(match!("c", q{handleNonInitialFileConversionSwitch})); goto command;
		mixin(match!("command", q{handleNonInitialFileConversionSwitch})); command:
			if (arguments.length == 1) goto missingArgumentAfterSwitch;
			mixin(advanceAndHash);

			switch (hash)
			{
			mixin(match!"isCompressedBNK?"); goto handleIsCompressedBNKArguments;
			default: goto unrecognisedCommandName;
			}

			break;
		mixin(match!("h", q{handleNonInitialFileConversionSwitch})); goto help;
		mixin(match!("hlep", q{handleNonInitialFileConversionSwitch})); goto help;
		mixin(match!("halp", q{handleNonInitialFileConversionSwitch})); goto help;
		mixin(match!("hlp", q{handleNonInitialFileConversionSwitch})); goto help;
		mixin(match!("help", q{handleNonInitialFileConversionSwitch})); help:
			dictates.archetype = dictates.archetype.help;
			return 0;
		mixin(match!("v", q{handleNonInitialFileConversionSwitch})); goto version_;
		mixin(match!("version", q{handleNonInitialFileConversionSwitch})); version_:
			dictates.archetype = dictates.archetype.version_;
			return 0;
		default:
			goto handleNonInitialFileConversionSwitch;
		}
	}

	assert(dashCount == 0);

	dictates.archetype = dictates.archetype.fileConversion;
	dictates.fileConversion.switches = dictates.fileConversion.switches.none;
	dictates.fileConversion.ioPaths = null;

	goto handleFileConversionPath;
handleFileConversionArgument:
	dashCount = eatSwitchPrefix(arg);

	if (dashCount != 0)
	{
		length = strlen(arg);
		hash = hashFor(arg[0 .. length]);
		goto handleFileConversionSwitch;
	handleNonInitialFileConversionSwitch:
		dictates.archetype = dictates.archetype.fileConversion;
		dictates.fileConversion.switches = dictates.fileConversion.switches.none;
		dictates.fileConversion.ioPaths = null;
	handleFileConversionSwitch:
		if (length == 0)
		{
			if (dashCount == 1)
			{
				goto singleSolitaryDash;
			}
			else
			{
				assert(dashCount == 2);

				if (arguments.length == 1)
				{
					goto missingPathAfterDoubleDash;
				}

				mixin(advance);
				goto handleFileConversionPath;
			}
		}

		InvocationDictates.FileConversion.FileType* fileType = void;
		ubyte zlibLevelBase = void;
		ubyte* zlibLevel = void;
		typeof(parseAsUnsignedBaseTenInteger!uint(arg)) threshold = void;

		switch (hash)
		{
		mixin(match!"i"); goto input;
		mixin(match!"in"); goto input;
		mixin(match!"input"); input:
			dictates.fileConversion.switches |= dictates.fileConversion.switches.input;
			fileType = cast(typeof(fileType)) &dictates.fileConversion.inputFileType;
			goto setFileType;
		mixin(match!"o"); goto output;
		mixin(match!"out"); goto output;
		mixin(match!"output"); output:
			dictates.fileConversion.switches |= dictates.fileConversion.switches.output;
			fileType = cast(typeof(fileType)) &dictates.fileConversion.outputFileType;
		setFileType:
			if (arguments.length == 1) goto missingArgumentAfterSwitch;
			mixin(advanceAndHash);

			switch (hash)
			{
			mixin(match!"bnk"); *fileType = dictates.fileConversion.FileType.bnk; break;
			mixin(match!"zip"); *fileType = dictates.fileConversion.FileType.zip; break;
			default: goto unrecognisedFileType;
			}

			break;
		mixin(match!"q"); goto quiet;
		mixin(match!"quiet"); quiet:
			dictates.fileConversion.switches |= dictates.fileConversion.switches.quiet;
			break;
		mixin(match!"d"); goto emitDuplicateFiles;
		mixin(match!"emitDuplicateFiles"); emitDuplicateFiles:
			dictates.fileConversion.switches |= dictates.fileConversion.switches.emitDuplicateFiles;
			break;
		mixin(match!"t"); goto omitBNKF2Metadata;
		mixin(match!"omitBNKF2Metadata"); omitBNKF2Metadata:
			dictates.fileConversion.switches |= dictates.fileConversion.switches.omitBNKF2Metadata;
			break;
		mixin(match!"n"); goto ignoreBNKF2Metadata;
		mixin(match!"ignoreBNKF2Metadata"); ignoreBNKF2Metadata:
			dictates.fileConversion.switches |= dictates.fileConversion.switches.ignoreBNKF2Metadata;
			break;
		mixin(match!"m"); goto outputCompressedBNK;
		mixin(match!"outputCompressedBNK"); outputCompressedBNK:
			dictates.fileConversion.switches |= dictates.fileConversion.switches.outputCompressedBNK;
			break;
		mixin(match!"ftcl"); goto fileTableCompressionLevel;
		mixin(match!"fileTableCompressionLevel"); fileTableCompressionLevel:
			dictates.fileConversion.switches |= dictates.fileConversion.switches.fileTableCompressionLevel;
			zlibLevel = cast(ubyte*) &dictates.fileConversion.fileTableCompressionLevel;
			zlibLevelBase = dictates.fileConversion.fileTableCompressionLevel._0;
			goto setZlibLevel;
		mixin(match!"fdcl"); goto fileDataCompressionLevel;
		mixin(match!"fileDataCompressionLevel"); fileDataCompressionLevel:
			dictates.fileConversion.switches |= dictates.fileConversion.switches.fileDataCompressionLevel;
			zlibLevel = cast(ubyte*) &dictates.fileConversion.fileDataCompressionLevel;
			zlibLevelBase = dictates.fileConversion.fileDataCompressionLevel._0;
			goto setZlibLevel;
		mixin(match!"ftml"); goto fileTableMemoryLevel;
		mixin(match!"fileTableMemoryLevel"); fileTableMemoryLevel:
			dictates.fileConversion.switches |= dictates.fileConversion.switches.fileTableMemoryLevel;
			zlibLevel = cast(ubyte*) &dictates.fileConversion.fileTableMemoryLevel;
			zlibLevelBase = dictates.fileConversion.fileTableMemoryLevel._0;
			goto setZlibLevel;
		mixin(match!"fdml"); goto fileDataMemoryLevel;
		mixin(match!"fileDataMemoryLevel"); fileDataMemoryLevel:
			dictates.fileConversion.switches |= dictates.fileConversion.switches.fileDataMemoryLevel;
			zlibLevel = cast(ubyte*) &dictates.fileConversion.fileDataMemoryLevel;
			zlibLevelBase = dictates.fileConversion.fileDataMemoryLevel._0;
			goto setZlibLevel;
		setZlibLevel:
			if (arguments.length == 1) goto missingArgumentAfterSwitch;
			mixin(advanceAndHash);

			if ((*arg < '0') | (*arg > '9'))
			{
				goto invalidZlibLevel;
			}

			*zlibLevel = cast(ubyte) (zlibLevelBase + (*arg - '0'));

			break;
		mixin(match!"ftuct"); goto fileTableUncompressedChunkThreshold;
		mixin(match!"fileTableUncompressedChunkThreshold"); fileTableUncompressedChunkThreshold:
			dictates.fileConversion.switches |= dictates.fileConversion.switches.fileTableUncompressedChunkThreshold;

			threshold = parseAsUnsignedBaseTenInteger!uint(arg);

			if (threshold.overflowed)
			{
				goto overflowedUInt;
			}

			dictates.fileConversion.fileTableUncompressedChunkThreshold = threshold.value;

			break;
		default:
			goto unrecognisedSwitch;
		}
	}
	else
	{
	handleFileConversionPath:
		if (pathCount >= 2)
		{
			goto tooManyPaths;
		}

		dictates.fileConversion.ioPaths[pathCount++] = arg;
	}

	if (arguments.length != 1)
	{
		mixin(advance);
		goto handleFileConversionArgument;
	}

	return 0;
handleIsCompressedBNKArguments:
	dictates.archetype = dictates.archetype.isCompressedBNK;
	dictates.isCompressedBNK.inputPath = null;
handleIsCompressedBNKArgument:
	if (arguments.length == 1)
	{
		return 0;
	}

	mixin(advance);

	dashCount = eatSwitchPrefix(arg);

	if (dashCount != 0)
	{
		length = strlen(arg);
		hash = hashFor(arg[0 .. length]);

		if (length == 0)
		{
			if (dashCount == 1)
			{
				goto singleSolitaryDash;
			}
			else
			{
				assert(dashCount == 2);

				if (arguments.length == 1)
				{
					goto missingPathAfterDoubleDash;
				}

				mixin(advance);
				goto handleIsCompressedBNKPath;
			}
		}

		goto unrecognisedSwitch;
	}
	else
	{
	handleIsCompressedBNKPath:
		if (pathCount++  >= 1)
		{
			goto tooManyPaths;
		}

		dictates.isCompressedBNK.inputPath = arg;
	}

	goto handleIsCompressedBNKArgument;
missingArgumentAfterSwitch: e = "No argument was supplied after a switch.\r\n"; goto printErrorMessage;
unrecognisedSwitch: e = "An unrecognised switch was supplied.\r\n"; goto printErrorMessage;
unrecognisedCommandName: e = "An unrecognised command was specified.\r\n"; goto printErrorMessage;
singleSolitaryDash: e = "BNKF2 cannot read from or write to the standard-input.\r\n"; goto printErrorMessage;
tooManyPaths: e = "Too many paths were supplied.\r\n"; goto printErrorMessage;
missingPathAfterDoubleDash: e = "No path was supplied after a '--'.\r\n"; goto printErrorMessage;
overflowedUInt: e = "A number was too big for a 32-bit integer.\r\n"; goto printErrorMessage;
unrecognisedFileType: e = "An unrecognised file-type was supplied. Only 'bnk' and 'zip' are supported.\r\n"; goto printErrorMessage;
invalidZlibLevel: e = "An invalid zlib level was provided; the valid levels are 0-to-9.\r\n"; goto printErrorMessage;
printErrorMessage:
	e.writeToConsoleOrFile(io.stderr);
	return 1;
}


int invokeWithDictates (scope InvocationDictates* dictates, scope StandardIOHandles* io)
{
	final switch (dictates.archetype)
	{
	case dictates.archetype.unknown: return invokeUnknownCommand(dictates, io);
	case dictates.archetype.help: return invokeHelpCommand(&dictates.help, io);
	case dictates.archetype.version_: return invokeVersionCommand(&dictates.version_, io);
	case dictates.archetype.fileConversion: return invokeFileConversionCommand(&dictates.fileConversion, io);
	case dictates.archetype.isCompressedBNK: return invokeIsCompressedBNKCommand(&dictates.isCompressedBNK, io);
	}
}


int invokeUnknownCommand (scope InvocationDictates* dictates, scope StandardIOHandles* io)
{
	commandLineUsage.writeToConsoleOrFile(io.stdout);
	return 1;
}


int invokeHelpCommand (scope InvocationDictates.Help* help, scope StandardIOHandles* io)
{
	commandLineUsage.writeToConsoleOrFile(io.stdout);
	return 0;
}


int invokeVersionCommand (scope InvocationDictates.Version* version_, scope StandardIOHandles* io)
{
	versionString.writeToConsoleOrFile(io.stdout);
	return 0;
}


int invokeFileConversionCommand (scope InvocationDictates.FileConversion* fileConversion, scope StandardIOHandles* io)
{
	alias S = InvocationDictates.FileConversion.Switches;
	alias FileType = InvocationDictates.FileConversion.FileType;

	if (fileConversion.inputPath == null)
	{
		assert(fileConversion.outputPath == null);
		"A path to an input BNK or zip file must be supplied.\r\n".writeToConsoleOrFile(io.stderr);
		return 1;
	}

	InvocationDictates.FileConversion.InputFileType inputType = void;
	InvocationDictates.FileConversion.OutputFileType outputType = void;

	if (fileConversion.switches & S.input)
	{
		inputType = fileConversion.inputFileType;
	}
	else
	{
		assert(fileConversion.inputPath != null);

		if (
			!fileConversionFileTypeFromFilePath(
				fileConversion.inputPath[0 .. strlen(fileConversion.inputPath)],
				cast(FileType*) &inputType
			)
		)
		{
			"The type of the input file could not be detected from its file extension.\r\nPlease specify its type via the '-input' switch.\r\n".writeToConsoleOrFile(io.stderr);
			return 1;
		}
	}

	if (fileConversion.switches & S.output)
	{
		outputType = fileConversion.outputFileType;

		if (cast(FileType) inputType == cast(FileType) outputType)
		{
			"Only BNK-to-zip or zip-to-BNK conversions are supported.\r\n".writeToConsoleOrFile(io.stderr);
			return 1;
		}
	}
	else
	{
		static assert(FileType.bnk == 0);
		static assert(FileType.zip == 1);

		outputType = cast(typeof(outputType)) (inputType ^ 1);
	}

	assert(cast(FileType) inputType != cast(FileType) outputType);

	OSChar[MAX_PATH] outputPathBuffer = void;
	const(OSChar)* outputPath = void;

	if (fileConversion.outputPath != null)
	{
		outputPath = fileConversion.outputPath;
	}
	else
	{
		const(OSChar)* start = fileConversion.inputPath;
		const(OSChar)* end = strend(start);
		OSChar* dot = cast(OSChar*) end;

		if (end - start > MAX_PATH)
		{
		inputPathIsTooLongForOutputPath:
			"The input path is too long for an output path to be synthesised from it.\r\n".writeToConsoleOrFile(io.stderr);
			return 1;
		}

		for (; (*dot != '.') & (dot != start); --dot) {}

		assert((dot == start) | (*dot == '.'));

		dot = dot != start ? dot : cast(OSChar*) end;

		if (dot - start > MAX_PATH - 5)
		{
			goto inputPathIsTooLongForOutputPath;
		}

		blit(outputPathBuffer.ptr, start, dot - start);
		dot = outputPathBuffer.ptr + (dot - start);

		*dot++ = '.';

		final switch (outputType)
		{
		case outputType.bnk: *dot++ = 'b'; *dot++ = 'n'; *dot++ = 'k'; break;
		case outputType.zip: *dot++ = 'z'; *dot++ = 'i'; *dot++ = 'p'; break;
		}

		*dot = '\0';

		outputPath = outputPathBuffer.ptr;
	}

	BNKF2MemoryAllocatorProvision memoryAllocators;
	memoryAllocators.packedState |= memoryAllocators.packedState.Flags.allocatesZeroedMemory;
	memoryAllocators.packedState |= memoryAllocators.packedState.Flags.cStyleAllocatesZeroedMemory;
	memoryAllocators.memoryAllocate = &memoryAllocate;
	memoryAllocators.memoryFree = &memoryFree;
	memoryAllocators.cStyleMemoryAllocate = &cStyleMemoryAllocate;
	memoryAllocators.cStyleMemoryFree = &cStyleMemoryFree;

	BNKF2DynamicallyLinkedZLib zlib;
	zlib.deflateInit_ = &deflateInit_;
	zlib.deflateInit2_ = &deflateInit2_;
	zlib.deflate = &deflate;
	zlib.deflateEnd = &deflateEnd;
	zlib.deflateReset = &deflateReset;
	zlib.deflatePrime = &deflatePrime;
	zlib.deflateTune = &deflateTune;
	zlib.inflateInit_ = &inflateInit_;
	zlib.inflateInit2_ = &inflateInit2_;
	zlib.inflate = &inflate;
	zlib.inflateEnd = &inflateEnd;
	zlib.inflateReset = &inflateReset;
	zlib.inflateReset2 = &inflateReset2;
	zlib.inflatePrime = &inflatePrime;
	zlib.crc32 = &crc32;

	int ultimateStatus = void;
	BNKF2Status status = void;

	if (inputType == inputType.bnk)
	{
		IOHandle bnkFile = void;
		ulong bnkSize = void;
		const(ubyte)* bnkView = void;

		if ((status = openAndMapFile(fileConversion.inputPath, &bnkFile, &bnkSize, &bnkView)).failed)
		{
			printErrorMessageForStatus(status, io.stderr);
			return status.code;
		}

		IOHandle zipFile = void;

		if ((status = createFile(outputPath, &zipFile)).failed)
		{
			closeAndUnmapFile(bnkFile, bnkView);
			return status.code;
		}

		const(ubyte)[] inputBuffer = bnkView[0 .. bnkSize];

		BNKToZipResult result;
		BNKToZipState state;

		state.version_ = 0;

		state.memoryAllocators = &memoryAllocators;
		state.zlib = &zlib;
		state.extendedReturnChannel = &result;
		state.progressObserver.context = *cast(void**) &io.stderr;
		state.progressObserver.observer = (fileConversion.switches & S.quiet) ? null : &bnkToZipProgressReporter;

		state.packedState |= (fileConversion.switches & S.emitDuplicateFiles) ? state.packedState.Flags.emitDuplicateFiles : 0;
		state.packedState |= (fileConversion.switches & S.omitBNKF2Metadata) ? state.packedState.Flags.omitBNKF2Metadata : 0;

		BNKF2Status bnkToZipStatus = bnkf2_bnkToZip(zipFile, &inputBuffer, &zipFileFlusher!(), &state);

		if (bnkToZipStatus.failed)
		{
			printErrorMessageForStatus(bnkToZipStatus, io.stderr);
		}

		closeFile(zipFile);
		closeAndUnmapFile(bnkFile, bnkView);

		return bnkToZipStatus.code;
	}
	else
	{
		IOHandle zipFile = void;
		ulong zipSize = void;
		const(ubyte)* zipView = void;

		if ((status = openAndMapFile(fileConversion.inputPath, &zipFile, &zipSize, &zipView)).failed)
		{
			printErrorMessageForStatus(status, io.stderr);
			return status.code;
		}

		IOHandle bnkFile = void;

		if ((status = createFile(outputPath, &bnkFile)).failed)
		{
			closeAndUnmapFile(zipFile, zipView);
			return status.code;
		}

		uint bytesWritten = void;

		FILE_SET_SPARSE_BUFFER sparsity = {SetSparse: true};
		if (DeviceIoControl(bnkFile, FSCTL_SET_SPARSE, &sparsity, sparsity.sizeof, null, 0, &bytesWritten, null))
		{
			FILE_ZERO_DATA_INFORMATION sparseRange = void;
			sparseRange.FileOffset.QuadPart = 0;
			sparseRange.BeyondFinalZero.QuadPart = ulong(4) << 30;
			DeviceIoControl(bnkFile, FSCTL_SET_ZERO_DATA, &sparseRange, sparseRange.sizeof, null, 0, &bytesWritten, null);
		}

		BNKFileFlusherContext context = void;
		context.sparseFile = bnkFile;

		const(ubyte)[] inputBuffer = zipView[0 .. zipSize];

		ZipToBNKResult result;
		ZipToBNKState state;

		state.version_ = 0;

		state.memoryAllocators = &memoryAllocators;
		state.zlib = &zlib;
		state.extendedReturnChannel = &result;
		state.progressObserver.context = *cast(void**) &io.stderr;
		state.progressObserver.observer = (fileConversion.switches & S.quiet) ? null : &zipToBNKProgressReporter;

		state.packedState |= (fileConversion.switches & S.ignoreBNKF2Metadata) ? state.packedState.Flags.ignoreBNKF2MetadataForCompressionSetting : 0;
		state.packedState |= (fileConversion.switches & S.outputCompressedBNK) ? state.packedState.Flags.outputCompressedBNK : 0;

		state.bnkVersion = 3;

		state.fileTableCompressionLevel = (fileConversion.switches & S.fileTableCompressionLevel) ? fileConversion.fileTableCompressionLevel : state.fileTableCompressionLevel.default_;
		state.fileTableMemoryLevel = (fileConversion.switches & S.fileTableMemoryLevel) ? fileConversion.fileTableMemoryLevel : state.fileTableMemoryLevel.default_;
		state.fileDataCompressionLevel = (fileConversion.switches & S.fileDataCompressionLevel) ? fileConversion.fileDataCompressionLevel : state.fileDataCompressionLevel.default_;
		state.fileDataMemoryLevel = (fileConversion.switches & S.fileDataMemoryLevel) ? fileConversion.fileDataMemoryLevel : state.fileDataMemoryLevel.default_;

		state.fileTableUncompressedChunkThreshold = (fileConversion.switches & S.fileTableUncompressedChunkThreshold) ? fileConversion.fileTableUncompressedChunkThreshold : 0;

		context.bnkVersion = &result.v0.bnkVersion;

		BNKF2Status zipToBNKStatus = bnkf2_zipToBNK(&context, &inputBuffer, &bnkFileFlusher!(), &state);

		if (zipToBNKStatus.failed)
		{
			printErrorMessageForStatus(zipToBNKStatus, io.stderr);
		}

		closeFile(bnkFile);
		closeAndUnmapFile(zipFile, zipView);

		return zipToBNKStatus.code;
	}

	return 0;
}


extern(System)
void bnkToZipProgressReporter (scope void* context, size_t opcode, scope const(void)* operand0, size_t operand1)
{
	OSChar[512] buffer = void;
	const(OSChar)[] message = void;
	size_t offset = 0;

	dchar pendingCodePoint = void;
	const(OSChar)[] m0 = void;
	const(OSChar)[] m1 = void;
	const(OSChar)[] m2 = void;

	alias S = const(OSChar)[];

	switch (cast(BNKToZipProgressOpcode) opcode)
	{
	case BNKToZipProgressOpcode.decompressingFileTable:
		message = "Reading file-table\r\n";
		break;
	case BNKToZipProgressOpcode.decompressedFileTable:
		offset += blit(buffer.ptr + offset, (cast(S) "Read ").ptr, 5);
		auto entryCount = operand1.asDecimal!(OSChar, '\0');
		offset += blit(buffer.ptr + offset, entryCount.unpadded.ptr, entryCount.unpadded.length);
		offset += blit(buffer.ptr + offset, (operand1 != 1 ? cast(S) " entries from the file-table\r\n" : cast(S) " entry from the file-table\r\n").ptr, operand1 != 1 ? 30 : 28);
		message = buffer[0 .. offset];
		break;
	case BNKToZipProgressOpcode.copyingFile:
		m0 = "Copying \""; m1 = "\" ("; m2 = " bytes)\r\n"; goto fileNameWithByteCount;
	case BNKToZipProgressOpcode.decompressingFile:
		m0 = "Decompressing \""; m1 = "\" (from "; m2 = " bytes)\r\n"; goto fileNameWithByteCount;
	fileNameWithByteCount:
		offset += blit(buffer.ptr + offset, m0.ptr, m0.length);
		const(char)[] utf8Name = *cast(const(char)[]*) operand0;
		size_t truncated = lesserOf(utf8Name.length, 260 - 3);
		utf8Name = utf8Name[$ - truncated .. $];
		if (truncated != utf8Name.length) offset += blit(buffer.ptr + offset, (cast(S) "...").ptr, 3);
		pendingCodePoint = cast(dchar) -1;
		wchar[] utf16Name = buffer[offset .. $];
		utf8ToUTF16(utf8Name, utf16Name, &pendingCodePoint);
		offset = utf16Name.ptr - buffer.ptr;
		offset += blit(buffer.ptr + offset, m1.ptr, m1.length);
		auto byteCount = operand1.asDecimal!(OSChar, '\0');
		offset += blit(buffer.ptr + offset, byteCount.unpadded.ptr, byteCount.unpadded.length);
		offset += blit(buffer.ptr + offset, m2.ptr, m2.length);
		message = buffer[0 .. offset];
		break;
	case BNKToZipProgressOpcode.skippedDuplicateFileName:
		offset += blit(buffer.ptr + offset, (cast(S) "Skipped duplicate file for \"").ptr, 28);
		const(char)[] utf8Name = *cast(const(char)[]*) operand0;
		size_t truncated = lesserOf(utf8Name.length, 260 - 3);
		utf8Name = utf8Name[$ - truncated .. $];
		if (truncated != utf8Name.length) offset += blit(buffer.ptr + offset, (cast(S) "...").ptr, 3);
		pendingCodePoint = cast(dchar) -1;
		wchar[] utf16Name = buffer[offset .. $];
		utf8ToUTF16(utf8Name, utf16Name, &pendingCodePoint);
		offset = utf16Name.ptr - buffer.ptr;
		offset += blit(buffer.ptr + offset, (cast(S) "\"\r\n").ptr, 3);
		message = buffer[0 .. offset];
		break;
	default:
		return;
	}

	message.writeToConsoleOrFile(*cast(const(ConsoleOrIOHandle)*) &context);
}


extern(System)
void zipToBNKProgressReporter (scope void* context, size_t opcode, scope const(void)* operand0, size_t operand1)
{
	OSChar[512] buffer = void;
	const(OSChar)[] message = void;
	size_t offset = 0;

	dchar pendingCodePoint = void;
	const(OSChar)[] m0 = void;
	const(OSChar)[] m1 = void;
	const(OSChar)[] m2 = void;

	alias S = const(OSChar)[];

	switch (cast(ZipToBNKProgressOpcode) opcode)
	{
	case ZipToBNKProgressOpcode.searchingForCentralDirectory:
		message = "Searching for central-directory\r\n";
		break;
	case ZipToBNKProgressOpcode.foundCentralDirectory:
		offset += blit(buffer.ptr + offset, (cast(S) "Found the central-directory with ").ptr, 33);
		auto entryCount = operand1.asDecimal!(OSChar, '\0');
		offset += blit(buffer.ptr + offset, entryCount.unpadded.ptr, entryCount.unpadded.length);
		offset += blit(buffer.ptr + offset, (operand1 != 1 ? cast(S) " entries\r\n" : cast(S) " entry\r\n").ptr, operand1 != 1 ? 10 : 8);
		message = buffer[0 .. offset];
		break;
	case ZipToBNKProgressOpcode.copyingFile:
		m0 = "Copying \""; m1 = "\" ("; m2 = " bytes)\r\n"; goto fileNameWithByteCount;
	case ZipToBNKProgressOpcode.compressingFile:
		m0 = "Compressing \""; m1 = "\" (from "; m2 = " bytes)\r\n"; goto fileNameWithByteCount;
	case ZipToBNKProgressOpcode.compressingFileChunk:
		m0 = "Compressing \""; m1 = "\" into a chunk ("; m2 = " bytes remaining)\r\n"; goto fileNameWithByteCount;
	case ZipToBNKProgressOpcode.compressedFileChunk:
		m0 = "Compressed \""; m1 = "\" into a chunk ("; m2 = " bytes)\r\n"; goto fileNameWithByteCount;
	case ZipToBNKProgressOpcode.decompressingFile:
		m0 = "Decompressing \""; m1 = "\" (from "; m2 = " bytes)\r\n"; goto fileNameWithByteCount;
	fileNameWithByteCount:
		offset += blit(buffer.ptr + offset, m0.ptr, m0.length);
		const(char)[] utf8Name = *cast(const(char)[]*) operand0;
		size_t truncated = lesserOf(utf8Name.length, 260 - 3);
		utf8Name = utf8Name[$ - truncated .. $];
		if (truncated != utf8Name.length) offset += blit(buffer.ptr + offset, (cast(S) "...").ptr, 3);
		pendingCodePoint = cast(dchar) -1;
		wchar[] utf16Name = buffer[offset .. $];
		utf8ToUTF16(utf8Name, utf16Name, &pendingCodePoint);
		offset = utf16Name.ptr - buffer.ptr;
		offset += blit(buffer.ptr + offset, m1.ptr, m1.length);
		auto byteCount = operand1.asDecimal!(OSChar, '\0');
		offset += blit(buffer.ptr + offset, byteCount.unpadded.ptr, byteCount.unpadded.length);
		offset += blit(buffer.ptr + offset, m2.ptr, m2.length);
		message = buffer[0 .. offset];
		break;
	default:
		return;
	}

	message.writeToConsoleOrFile(*cast(const(ConsoleOrIOHandle)*) &context);
}


extern(System)
size_t zipFileFlusher () (
	scope void* context,
	scope ubyte** freshBuffer,
	scope ubyte* flushBuffer,
	size_t flushSize
)
{
	enum uint bufferSize = 4 << 20;

	enum string freeState =
	q{
		VirtualFree(flushBuffer, 0, MEM_RELEASE);
	};

	if (flushBuffer == null)
	{
		ubyte* allocated = cast(ubyte*) VirtualAlloc(null, bufferSize, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
		*freshBuffer = allocated;
		return allocated ? bufferSize : 0;
	}
	else if (flushSize == 0)
	{
		mixin(freeState);
		return 0;
	}

	HANDLE file = cast(HANDLE) context;
	uint bytesWritten = void;

	if (!WriteFile(file, flushBuffer, cast(uint) flushSize, &bytesWritten, null))
	{
		*freshBuffer = null;
		mixin(freeState);
		return GetLastError;
	}

	return bufferSize;
}


struct BNKFileFlusherContext
{
	HANDLE sparseFile;
	ulong[3] fileOffsetsByBuffer;
	ubyte* allocatedMemory;
	uint[2] variableBufferSizes;
	uint* bnkVersion;
	UltimateFileHeader ultimateFileHeader;

	union UltimateFileHeader
	{
		BNK.FileHeaderV3 v3;
		BNK.FileHeaderV2 v2;
	}
}


extern(System)
size_t bnkFileFlusher () (
	scope void* context,
	scope ubyte** freshBuffer,
	scope ubyte* flushBuffer,
	size_t flushSize,
	uint bufferIndex
)
{
	enum uint fileTableBufferSize = 128 << 10;
	enum uint fileDataBufferSize = 4 << 20;
	enum uint completeBufferSize = fileTableBufferSize + fileDataBufferSize;

	enum string freeState =
	q{
		VirtualFree(state.allocatedMemory, 0, MEM_RELEASE);
	};

	scope BNKFileFlusherContext* state = cast(BNKFileFlusherContext*) context;

	if (bufferIndex == -1)
	{
		if ((flushSize & (1 << 16)) == 0)
		{
			state.allocatedMemory = cast(ubyte*) VirtualAlloc(
				null,
				completeBufferSize,
				MEM_RESERVE | MEM_COMMIT,
				PAGE_READWRITE
			);

			if (state.allocatedMemory == null)
			{
				return GetLastError;
			}

			state.fileOffsetsByBuffer[0] = 0;
			state.fileOffsetsByBuffer[1] = *state.bnkVersion != 2 ? BNK.FileHeaderV3.sizeof : BNK.FileHeaderV2.sizeof;
			state.fileOffsetsByBuffer[2] = ulong(4) << 30;

			if (*state.bnkVersion != 2)
			{
				state.variableBufferSizes[0] = fileTableBufferSize;
				state.variableBufferSizes[1] = fileDataBufferSize;
			}
			else
			{
				state.variableBufferSizes[0] = fileDataBufferSize;
				state.variableBufferSizes[1] = fileTableBufferSize;
			}

			return 0;
		}
		else
		{
			ulong sourceOffset = ulong(4) << 30;
			ulong destinationOffset = state.fileOffsetsByBuffer[1];

			ulong copyLength = state.fileOffsetsByBuffer[2] - sourceOffset;
			ulong remainingCopyLength = copyLength;

			if (ntCopyFileChunk !is null)
			{
				uint chunkLength = cast(uint) lesserOf(remainingCopyLength, uint.max);

				while (chunkLength != 0)
				{
					IO_STATUS_BLOCK ioStatusBlock = void;

					NTSTATUS error = ntCopyFileChunk(
						state.sparseFile,
						state.sparseFile,
						null,
						&ioStatusBlock,
						chunkLength,
						cast(LARGE_INTEGER*) &sourceOffset,
						cast(LARGE_INTEGER*) &destinationOffset,
						null,
						null,
						0
					);

					if (error)
					{
						mixin(freeState);
						return error;
					}

					sourceOffset += chunkLength;
					destinationOffset += chunkLength;
					remainingCopyLength -= chunkLength;

					chunkLength = cast(uint) lesserOf(remainingCopyLength, uint.max);
				}
			}
			else
			{
				/+ We can't get the kernel to do it, a buffer-by-buffer copy will have to do. +/
				HANDLE file = state.sparseFile;
				ubyte* buffer = state.allocatedMemory;

				uint chunkLength = cast(uint) lesserOf(remainingCopyLength, completeBufferSize);

				while (chunkLength != 0)
				{
					uint bytesRead = void;
					OVERLAPPED readOffset;
					readOffset.Offset = cast(uint) sourceOffset;
					readOffset.OffsetHigh = cast(uint) (sourceOffset >> 32);

					if (!ReadFile(file, buffer, chunkLength, &bytesRead, &readOffset))
					{
						mixin(freeState);
						return GetLastError;
					}

					uint bytesWritten = void;
					OVERLAPPED writeOffset;
					writeOffset.Offset = cast(uint) destinationOffset;
					writeOffset.OffsetHigh = cast(uint) (destinationOffset >> 32);

					if (!WriteFile(file, buffer, chunkLength, &bytesWritten, &writeOffset))
					{
						mixin(freeState);
						return GetLastError;
					}

					sourceOffset += chunkLength;
					destinationOffset += chunkLength;
					remainingCopyLength -= chunkLength;

					chunkLength = cast(uint) lesserOf(remainingCopyLength, completeBufferSize);
				}
			}

			LARGE_INTEGER endOfFile = {QuadPart: destinationOffset};
			SetFilePointerEx(state.sparseFile, endOfFile, null, FILE_BEGIN);
			SetEndOfFile(state.sparseFile);

			mixin(freeState);

			return 0;
		}
	}

	if (flushBuffer == null)
	{
		if (bufferIndex == 0)
		{
			*freshBuffer = cast(ubyte*) &state.ultimateFileHeader;
			return state.ultimateFileHeader.sizeof;
		}
		else if (bufferIndex == 1)
		{
			*freshBuffer = state.allocatedMemory;
			return state.variableBufferSizes[0];
		}
		else
		{
			*freshBuffer = state.allocatedMemory + state.variableBufferSizes[0];
			return state.variableBufferSizes[1];
		}
	}
	else if (flushSize == 0)
	{
		return 0;
	}

	ulong offsetForBuffer = state.fileOffsetsByBuffer[bufferIndex];
	state.fileOffsetsByBuffer[bufferIndex] += flushSize;

	HANDLE file = state.sparseFile;
	uint bytesWritten = void;

	OVERLAPPED fileOffset;
	fileOffset.Offset = cast(uint) offsetForBuffer;
	fileOffset.OffsetHigh = cast(uint) (offsetForBuffer >> 32);

	if (!WriteFile(file, flushBuffer, cast(uint) flushSize, &bytesWritten, &fileOffset))
	{
		*freshBuffer = null;
		mixin(freeState);
		return GetLastError;
	}

	if (bufferIndex == 2)
	{
		return state.variableBufferSizes[1];
	}
	else if (bufferIndex == 1)
	{
		return state.variableBufferSizes[0];
	}
	else
	{
		return state.ultimateFileHeader.sizeof;
	}
}


pragma(inline, true)
bool fileConversionFileTypeFromFilePath (
	scope const(OSChar)[] path,
	scope InvocationDictates.FileConversion.FileType* fileType
)
{
	if (path.length < 4)
	{
		return false;
	}

	static if (OSChar.sizeof == 2)
	{
		alias Int = ulong;
	}
	else static if (OSChar.sizeof == 1)
	{
		alias Int = uint;
	}

	align(Int.alignof) OSChar[4] bnk = ".bnk";
	align(Int.alignof) OSChar[4] zip = ".zip";
	align(Int.alignof) OSChar[4] extension = void;

	path[$ - 4 .. $].asciiLowerCase(extension[]);

	Int extensionAsInt = *cast(const(Int)*) extension.ptr;
	Int bnkAsInt = *cast(const(Int)*) bnk.ptr;
	Int zipAsInt = *cast(const(Int)*) zip.ptr;

	if (extensionAsInt == bnkAsInt)
	{
		*fileType = fileType.bnk;
		return true;
	}
	else if (extensionAsInt == zipAsInt)
	{
		*fileType = fileType.zip;
		return true;
	}

	return false;
}


int invokeIsCompressedBNKCommand (scope InvocationDictates.IsCompressedBNK* isCompressedBNK, scope StandardIOHandles* io)
{
	if (isCompressedBNK.inputPath == null)
	{
		"A path to a BNK file must be supplied.\r\n".writeToConsoleOrFile(io.stderr);
		return 1;
	}

	int ultimateStatus = void;

	BNKF2Status status = void;
	IOHandle bnkFile = void;
	ulong bnkSize = void;
	const(ubyte)* bnkView = void;

	OSChar consoleText = void;
	ubyte fileData = void;

	if ((status = openAndMapFile(isCompressedBNK.inputPath, &bnkFile, &bnkSize, &bnkView)).failed)
	{
		printErrorMessageForStatus(status, io.stderr);
		return status.code;
	}

	bool isCompressed = void;

	if ((status = bnkf2_bnkIsCompressed(bnkView, bnkSize, &isCompressed)).failed)
	{
		printErrorMessageForStatus(status, io.stderr);
		ultimateStatus = status.code;
		goto finish;
	}

	consoleText = OSChar('0') + isCompressed;
	fileData = char('0') + isCompressed;

	writeToConsoleOrFile((&consoleText)[0 .. 1], (&fileData)[0 .. 1], io.stdout);

	ultimateStatus = 0;
finish:
	closeAndUnmapFile(bnkFile, bnkView);
	return ultimateStatus;
}


void printErrorMessageForStatus (BNKF2Status status, scope ConsoleOrIOHandle ioHandle)
{
	if (status.source == BNKF2Status.CodeSource.bnkf2)
	{
		uint length = void;
		immutable(char)* message = bnkf2_messageForStatusCodeWithLength(cast(BNKF2StatusCode) status.code, &length);

		if (message == null)
		{
			auto hex = status.code.asHex!(OSChar, true);
			"Unexpected BNKF2 error: 0x".writeToConsoleOrFile(ioHandle);
			hex[].writeToConsoleOrFile(ioHandle);
			".\r\n".writeToConsoleOrFile(ioHandle);
		}

		version (Windows)
		{
			wchar[512] asUTF16 = void;
			length = lesserOf(length, cast(uint) asUTF16.length);
			const(char)[] truncatedMessage = message[0 .. length];
			wchar[] utf16Message = asUTF16[];

			dchar pendingCodePoint = cast(dchar) -1;
			utf8ToUTF16(truncatedMessage, utf16Message, &pendingCodePoint);

			"BNKF2 error: ".writeToConsoleOrFile(ioHandle);
			asUTF16[0 .. utf16Message.ptr - asUTF16.ptr].writeToConsoleOrFile(ioHandle);
			"\r\n".writeToConsoleOrFile(ioHandle);
		}
		else
		{
			"BNKF2 error: ".writeToConsoleOrFile(ioHandle);
			message[0 .. length].writeToConsoleOrFile(ioHandle);
			"\r\n".writeToConsoleOrFile(ioHandle);
		}
	}
	else
	{
		const(OSChar)[] e0 = void;
		const(OSChar)[] e1 = void;
		typeof(status.code.asHex!(OSChar, true)) hex = void;

		if (status.source != BNKF2Status.CodeSource.zlib)
		{
			hex = status.code.asHex!(OSChar, true);
			e1 = hex[];
			e0 = "System error: 0x";
		}
		else
		{
			e0 = "zlib error: ";

			switch (status.code)
			{
			case Z_NEED_DICT: e1 = "Z_NEED_DICT"; break;
			case Z_ERRNO: e1 = "Z_ERRNO"; break;
			case Z_STREAM_ERROR: e1 = "Z_STREAM_ERROR"; break;
			case Z_DATA_ERROR: e1 = "Z_DATA_ERROR"; break;
			case Z_MEM_ERROR: e1 = "Z_MEM_ERROR"; break;
			case Z_BUF_ERROR: e1 = "Z_BUF_ERROR"; break;
			case Z_VERSION_ERROR: e1 = "Z_VERSION_ERROR"; break;
			default:
				hex = status.code.asHex!(OSChar, true);
				e1 = hex[];
				e0 = "Unexpected zlib error: 0x";
			}
		}

		e0.writeToConsoleOrFile(ioHandle);
		e1.writeToConsoleOrFile(ioHandle);
		".\r\n".writeToConsoleOrFile(ioHandle);
	}
}


BNKF2Status openAndMapFile (
	scope const(OSChar)* path,
	scope IOHandle* fileHandle,
	scope ulong* fileSize,
	scope const(ubyte)** fileView
)
{
	LARGE_INTEGER size = void;
	HANDLE fileMapping = void;
	const(ubyte)* view = void;

	HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, null, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, null);

	if (file == INVALID_HANDLE_VALUE) goto failed;

	GetFileSizeEx(file, &size);

	if (!GetFileSizeEx(file, &size)) goto failedWithOpenFile;

	fileMapping = CreateFileMappingW(file, null, PAGE_READONLY, size.HighPart, size.LowPart, null);

	if (fileMapping == null) goto failedWithOpenFile;

	view = cast(const(ubyte)*) MapViewOfFile(fileMapping, FILE_MAP_READ, 0, 0, size.QuadPart);

	CloseHandle(fileMapping);

	if (view == null) goto failedWithOpenFile;

	*fileHandle = file;
	*fileSize = size.QuadPart;
	*fileView = view;

	return BNKF2Status.status(BNKF2StatusCode.success);
failedWithOpenFile:
	CloseHandle(file);
failed:
	return BNKF2Status.lastError;
}


BNKF2Status createFile (
	scope const(OSChar)* path,
	scope IOHandle* fileHandle
)
{
	HANDLE file = CreateFileW(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);

	if (file == INVALID_HANDLE_VALUE)
	{
		return BNKF2Status.lastError;
	}

	*fileHandle = file;

	return BNKF2Status.status(BNKF2StatusCode.success);
}


void closeAndUnmapFile (scope IOHandle fileHandle, scope const(ubyte)* fileView)
{
	unmapFile(fileView);
	closeFile(fileHandle);
}


void closeFile (scope IOHandle fileHandle)
{
	CloseHandle(fileHandle);
}


void unmapFile (scope const(ubyte)* fileView)
{
	UnmapViewOfFile(fileView);
}


BNKF2Status writeToConsoleOrFile (
	scope const(OSChar)[] text,
	return scope ConsoleOrIOHandle handle
) nothrow @nogc
in (text.length <= (uint.max >> 1))
{
	final switch (handle.type)
	{
	case handle.Type.console:
		static assert(handle.Type.console == 0);

		if (!WriteConsoleW(handle.taggedHandle, text.ptr, cast(uint) text.length, null, null))
		{
			return BNKF2Status.lastError;
		}

		return BNKF2Status.status(BNKF2StatusCode.success);
	case handle.Type.file:
		uint bytesWritten = void;

		if (!WriteFile(handle.handle, text.ptr, cast(uint) (text.length << 1), &bytesWritten, null))
		{
			return BNKF2Status.lastError;
		}

		return BNKF2Status.status(BNKF2StatusCode.success);
	}
}


BNKF2Status writeToConsoleOrFile (
	scope const(OSChar)[] consoleText,
	scope const(ubyte)[] fileData,
	return scope ConsoleOrIOHandle handle
) nothrow @nogc
in (consoleText.length <= uint.max)
in (fileData.length <= uint.max)
{
	final switch (handle.type)
	{
	case handle.Type.console:
		static assert(handle.Type.console == 0);

		if (!WriteConsoleW(handle.taggedHandle, consoleText.ptr, cast(uint) consoleText.length, null, null))
		{
			return BNKF2Status.lastError;
		}

		return BNKF2Status.status(BNKF2StatusCode.success);
	case handle.Type.file:
		uint bytesWritten = void;

		if (!WriteFile(handle.handle, fileData.ptr, cast(uint) fileData.length, &bytesWritten, null))
		{
			return BNKF2Status.lastError;
		}

		return BNKF2Status.status(BNKF2StatusCode.success);
	}
}


struct ConsoleOrIOHandle
{
	version (Windows)
	{
		alias handle this;

		enum TaggedHandle : HANDLE
		{
			init = null
		}

		enum Type : size_t
		{
			console = 0b00,
			file = 0b01
		}

		TaggedHandle taggedHandle;

		pragma(inline, true)
		inout(HANDLE) handle () inout return scope @trusted pure nothrow @nogc
		{
			return cast(HANDLE) (cast(size_t) this.taggedHandle & ~size_t(0b11));
		}

		pragma(inline, true)
		inout(Type) type () inout return scope @trusted pure nothrow @nogc
		{
			return cast(Type) (cast(size_t) this.taggedHandle & 0b11);
		}

		pragma(inline, true)
		static ConsoleOrIOHandle fromConsoleHandle (return scope HANDLE handle) @trusted pure nothrow @nogc
		in (handle)
		{
			return ConsoleOrIOHandle(cast(TaggedHandle) (cast(size_t) handle | Type.console));
		}

		pragma(inline, true)
		static ConsoleOrIOHandle fromFileHandle (return scope HANDLE handle) @trusted pure nothrow @nogc
		{
			return ConsoleOrIOHandle(cast(TaggedHandle) (cast(size_t) handle | Type.file));
		}

		pragma(inline, true)
		static ConsoleOrIOHandle fromHandle (return scope HANDLE handle) @safe nothrow @nogc
		{
			uint mode = void;
			return GetConsoleMode(handle, &mode) ? fromConsoleHandle(handle) : fromFileHandle(handle);
		}
	}
	else
	{
		IOHandle handle;
	}
}


pragma(inline, true)
ubyte eatSwitchPrefix (Char) (scope ref Char* text)
{
	ubyte oneDash = 0;
	ubyte twoDash = 0;

	text += oneDash = *text == '-';
	text += twoDash = *text == '-';

	return cast(ubyte) (oneDash + twoDash);
}


void utf8ToUTF16 (scope ref const(char)[] utf8, ref scope wchar[] utf16, scope dchar* pendingCodePoint)
in (*pendingCodePoint > 0x10FFFF)
{
	version (X86_64_Or_X86)
	{
		import ldc.gccbuiltins_x86 : __builtin_ia32_pmovmskb128;
		import ldc.llvmasm : __ir_pure;

		enum size_t byteWidth = 16;
		alias movmsk = __builtin_ia32_pmovmskb128;
		alias Mask = ushort;

		enum bool usingSIMD = true;
	}
	else
	{
		enum bool usingSIMD = false;
	}

	const(char)* endOfUTF8 = utf8.ptr + utf8.length;
	const(wchar)* endOfUTF16 = utf16.ptr + utf16.length;
	const(char)* utf8SIMDLimit = endOfUTF8 - 16;
	const(wchar)* utf16SIMDLimit = endOfUTF16 - 16;

	const(char)* c = utf8.ptr;
	wchar* w = utf16.ptr;

	static if (usingSIMD)
	{
		alias V = __vector(byte[16]);
	next:
		if ((c <= utf8SIMDLimit) & (w <= utf16SIMDLimit))
		{
			V cc = loadVector!V(cast(const(byte)*) c);
			Mask nonASCIIMask = cast(Mask) __builtin_ia32_pmovmskb128(cc);

			if (nonASCIIMask == 0)
			{
				/+ If it's just ASCII (spoiler alert--it is), then we'll just
				   blit the ASCII to UTF-16 via a PUNPCKLBW and a PUNPCKHBW. +/

				V zero = 0;

				V firstHalf = __ir_pure!(
					`%v = shufflevector <16 x i8> %0, <16 x i8> %1, <16 x i32> <i32 0, i32 16, i32 1, i32 17, i32 2, i32 18, i32 3, i32 19, i32 4, i32 20, i32 5, i32 21, i32 6, i32 22, i32 7, i32 23>
					 ret <16 x i8> %v`,
					V
				)(cc, zero);

				storeVector!V(cast(byte*) w, firstHalf);

				V secondHalf = __ir_pure!(
					`%v = shufflevector <16 x i8> %0, <16 x i8> %1, <16 x i32> <i32 8, i32 24, i32 9, i32 25, i32 10, i32 26, i32 11, i32 27, i32 12, i32 28, i32 13, i32 29, i32 14, i32 30, i32 15, i32 31>
					 ret <16 x i8> %v`,
					V
				)(cc, zero);

				storeVector!V(cast(byte*) (w + 8), secondHalf);

				c += 16;
				w += 16;

				goto next;
			}

			/+ Otherwise if it's not just ASCII we'll blit whatever ASCII we can
			   and then proceed with the usual scalar logic. +/

			uint bix = nonASCIIMask.leastSetBitIndex!(No.definedForZero);

			while (bix--)
			{
				*w++ = *c++;
			}

			assert((c < endOfUTF8) & (w < endOfUTF16));

			goto handleScalarLead;
		}
	}
	else
	{
	next:
	}

	if ((c >= endOfUTF8) | (w >= endOfUTF16))
	{
	finish:
		utf8 = c[0 .. endOfUTF8 - c];
		utf16 = w[0 .. endOfUTF16 - w];
		return;
	}
handleScalarLead:
	if (*c < 128)
	{
		*w++ = *c++;
		goto next;
	}

	uint lead = endianSwap(uint(*c));
	uint codeUnitCount = leadingZeroCount!(No.definedForZero)(~lead | 1);

	if (endOfUTF8 - c < codeUnitCount)
	{
		*w++ = 0xFFFD;
		goto finish;
	}

	if (codeUnitCount < 4)
	{
		assert(codeUnitCount == 2 || codeUnitCount == 3);

		uint leadBits = 7 - codeUnitCount;

		uint codePoint = *c++ & ((1 << (7 - codeUnitCount)) - 1);
		//uint codePoint = *c & ((cast(ubyte) -1) >> (codeUnitCount + 1));
		codePoint |= uint(*c & 0b00111111) << leadBits;

		if ((*c & 0b10000000) != 0b10)
		{
			goto replacementCharacter;
		}

		/+ If we have 3 code-units we'll eat the third code-unit here,
		   otherwise if we have 2, we'll eat the second code-unit again. +/
		c += codeUnitCount == 3;
		uint lastBits = leadBits + (codeUnitCount == 3 ? 6 : 0);
		uint overlongThreshold = codeUnitCount == 3 ? 0x0800 : 0x0080;

		codePoint |= uint(*c++ & 0b00111111) << lastBits;

		if ((*c & 0b10000000) != 0b10)
		{
			goto replacementCharacter;
		}

		if (codePoint < overlongThreshold)
		{
			goto replacementCharacter;
		}

		*w++ = cast(ushort) codePoint;

		goto next;
	}
	else if (codeUnitCount == 4)
	{
		uint codePoint = *c++ & 0b00000111;

		for (uint bits = 3; bits < 21; bits += 6)
		{
			codePoint |= uint(*c & 0b00111111) << bits;

			if ((*c & 0b10000000) != 0b10)
			{
				goto replacementCharacter;
			}
		}

		if (codePoint < 0x10000)
		{
			goto replacementCharacter;
		}

		if (endOfUTF16 - w < 2)
		{
			*pendingCodePoint = codePoint;
			goto finish;
		}

		codePoint -= 0x10000;

		*w++ = 0xD800 | cast(ushort) (codePoint >> 10);
		*w++ = 0xDC00 | (codePoint & 0b0000001111111111);

		goto next;
	}
	else
	{
		*w++ = 0xFFFD;

		if (w >= endOfUTF16)
		{
			goto finish;
		}
	windThroughOverlong:
		++c;

		assert (++c < endOfUTF8);

		if ((*c >> 6) == 0b10)
		{
			goto windThroughOverlong;
		}

		goto handleScalarLead;
	}
replacementCharacter:
	*w++ = 0xFFFD;
	goto next;
}


pragma(inline, true)
auto parseAsUnsignedBaseTenInteger (Int, Char) (scope const(Char)* text) @trusted pure nothrow @nogc
{
	enum Int overflowThreshold = cast(Int) Int.max / 10;

	static struct Result
	{
		Int value;
		ubyte length;
		ubyte overflowed;
	}

	Int value;

	for (ubyte index = 0;; ++index)
	{
		Char c;

		if (((c = text[index]) >= '0') & (c <= '9'))
		{
			if (value > overflowThreshold)
			{
				return Result(value, cast(ubyte) (index + 1), true);
			}

			value *= 10;
			value += c - '0';
		}
		else
		{
			return Result(value, index, false);
		}
	}
}


Char[Value.sizeof * 2] asHex (Char = char, bool uppercase = false, Value) (Value value)
{
	enum uint letterNibble = 10;
	enum uint letterNibbleToLetter = Char(uppercase ? 'A' : 'a') - Char('0') - letterNibble;

	Unqual!Char[Value.sizeof * 2] hex = '0';
	Unqual!Value theValue = value;

	foreach_reverse (index; 0 .. hex.length)
	{
		uint nibble = theValue & 0x0f;
		theValue >>= 4;
		uint adjustment = nibble < letterNibble ? 0 : letterNibbleToLetter;
		hex[index] += nibble + adjustment;
	}

	return hex;
}

@safe pure nothrow @nogc unittest
{
	static bool test ()
	{
		assert((0xabcdef24).asHex == "abcdef24");
		assert((0x01356789).asHex == "01356789");
		assert((0xabcdef24).asHex!(char, true) == "ABCDEF24");

		return true;
	}

	assert(test);
	static assert(test);
}


auto asDecimal (Char = char, alias padding = Char(' '), Value) (Value value)
{
	enum uint[] maximumBase10DigitsBySizeOf = [0, 3, 5, 8, 10, 13, 15, 17, 20];
	enum uint digitCount = maximumBase10DigitsBySizeOf[Value.sizeof];

	static if (Value.sizeof <= 4)
	{
		enum Value reciprocal = cast(Value) 0xCCCCCCCCCCCCCCCD;
		enum uint shift = ((Value.sizeof << 3) & 63) + 3;
	}

	Unqual!Char[digitCount] decimal = padding;
	ulong theValue = value;
	size_t index = decimal.length;

	do
	{
		ulong previousValue = theValue;

		static if (Value.sizeof <= 4)
		{
			theValue *= reciprocal;
			theValue >>>= shift;
		}
		else
		{
			theValue /= 10;
		}

		--index;
		decimal[index] = cast(Char) ('0' + cast(uint) (previousValue - theValue * 10));
	}
	while (theValue != 0);

	static struct AsDecimal
	{
		alias digits this;

		typeof(decimal) digits;
		ubyte firstSignificantDigitIndex;

		inout(Unqual!Char)[] unpadded () inout @property return scope
		{
			return this.digits[firstSignificantDigitIndex .. $];
		}
	}

	return AsDecimal(decimal, cast(ubyte) index);
}

@safe pure nothrow @nogc unittest
{
	static bool test (Char) ()
	{
		assert(ubyte(0).asDecimal!Char == "  0");
		assert(ushort(0).asDecimal!Char == "    0");
		assert(uint(0).asDecimal!Char == "         0");
		assert(ulong(0).asDecimal!Char == "                   0");
		assert(ubyte(1).asDecimal!Char == "  1");
		assert(ushort(1).asDecimal!Char == "    1");
		assert(uint(1).asDecimal!Char == "         1");
		assert(ulong(1).asDecimal!Char == "                   1");
		assert(ubyte(9).asDecimal!Char == "  9");
		assert(ushort(9).asDecimal!Char == "    9");
		assert(uint(9).asDecimal!Char == "         9");
		assert(ulong(9).asDecimal!Char == "                   9");

		assert(ubyte(10).asDecimal!Char == " 10");
		assert(ushort(10).asDecimal!Char == "   10");
		assert(uint(10).asDecimal!Char == "        10");
		assert(ulong(10).asDecimal!Char == "                  10");

		assert(ubyte(255).asDecimal!Char == "255");
		assert(ushort(65535).asDecimal!Char == "65535");
		assert(uint(4294967295).asDecimal!Char == "4294967295");
		assert(ulong(18446744073709551615).asDecimal!Char == "18446744073709551615");

		assert(ubyte(0).asDecimal!Char.unpadded == "0");
		assert(ushort(0).asDecimal!Char.unpadded == "0");
		assert(uint(0).asDecimal!Char.unpadded == "0");
		assert(ulong(0).asDecimal!Char.unpadded == "0");
		assert(ubyte(1).asDecimal!Char.unpadded == "1");
		assert(ushort(1).asDecimal!Char.unpadded == "1");
		assert(uint(1).asDecimal!Char.unpadded == "1");
		assert(ulong(1).asDecimal!Char.unpadded == "1");
		assert(ubyte(9).asDecimal!Char.unpadded == "9");
		assert(ushort(9).asDecimal!Char.unpadded == "9");
		assert(uint(9).asDecimal!Char.unpadded == "9");
		assert(ulong(9).asDecimal!Char.unpadded == "9");

		assert(ubyte(10).asDecimal!Char.unpadded == "10");
		assert(ushort(10).asDecimal!Char.unpadded == "10");
		assert(uint(10).asDecimal!Char.unpadded == "10");
		assert(ulong(10).asDecimal!Char.unpadded == "10");

		assert(ubyte(255).asDecimal!Char.unpadded == "255");
		assert(ushort(65535).asDecimal!Char.unpadded == "65535");
		assert(uint(4294967295).asDecimal!Char.unpadded == "4294967295");
		assert(ulong(18446744073709551615).asDecimal!Char.unpadded == "18446744073709551615");

		return true;
	}

	assert(test!char);
	static assert(test!char);
	assert(test!wchar);
	static assert(test!wchar);
	assert(test!dchar);
	static assert(test!dchar);
}


pragma(inline, true)
size_t strlen (Char = char, size_t alignment = 0, Char sentinel = '\0') (return scope Char* str)
{
	return findSentinel!(sentinel, alignment, Char)(str) - str;
}


pragma(inline, true)
Char* strend (Char = char, size_t alignment = 0, Char sentinel = '\0') (return scope Char* str)
{
	return findSentinel!(sentinel, alignment, Char)(str);
}


pragma(inline, true)
T* findSentinel (alias sentinel, size_t alignment = 0, T) (return scope T* data)
if (is(typeof(sentinel) : T) && (alignment == 0 || alignment.isPowerOfTwo))
in
{
	static if (alignment > 0)
	{
		assert(__ctfe || (cast(size_t) data.ptr & (alignment - 1)) == 0);
	}
}
do
{
	/+ This implementation optimises for code size, with the logic being that
	   most sentinel-terminated arrays are short, and thus the overhead of a function call
	   outweighs the benefit of a longer implementation; thus we keep the implementation short,
	   so that it's more amenable to inlining. +/

	version (X86_64_Or_X86)
	{
		import ldc.gccbuiltins_x86 : __builtin_ia32_pmovmskb128;

		enum size_t byteWidth = 16;
		alias movmsk = __builtin_ia32_pmovmskb128;
		alias Mask = ushort;
	}
	else
	{
		alias Mask = void;
	}

	static if (is(Mask == void))
	{
		enum bool usingSIMD = false;
	}
	else
	{
		enum bool usingSIMD = T.sizeof <= 8 && byteWidth % T.sizeof == 0 && byteWidth / T.sizeof >= 4;
	}

	static if (!usingSIMD)
	{
	next:
		if (*data == sentinel)
		{
			return data;
		}

		++data;

		goto next;
	}
	else
	{
		enum size_t chunkScale = T.sizeof.leastSetBitIndex >= 3 ? 3 : T.sizeof.leastSetBitIndex;
		enum size_t chunkSize = size_t(1) << chunkScale;

		enum size_t chunksInVector = byteWidth >>> chunkScale;

		alias Chunk = IntsFittingSizeOf[chunkSize];

		alias V = __vector(Chunk[chunksInVector]);
		alias ByteV = __vector(byte[byteWidth]);

		enum size_t pageMask = minimumPageSize - 1;
		enum size_t vectorMask = byteWidth - 1;
		enum size_t pageThreshold = pageMask - vectorMask;

		V sentinelVector = cast(Chunk) sentinel;
		Chunk* chunk = cast(Chunk*) data;
		size_t offsetInPage;
		size_t underread;
		size_t bytesLeftInPage;
	nextChunk:
		offsetInPage = cast(size_t) chunk & pageMask;
		bytesLeftInPage = pageMask - offsetInPage;

		underread = offsetInPage < pageThreshold ? 0 : (vectorMask ^ bytesLeftInPage);

		chunk = cast(Chunk*) (cast(void*) chunk - underread);

		V vector = loadVector!(V, alignment)(chunk);
		V equality = vector == sentinelVector;
		Mask mask = cast(Mask) movmsk(cast(ByteV) equality);

		mask >>= underread;

		uint bix = mask.leastSetBitIndex!(No.definedForZero);

		if (mask != 0)
		{
			return cast(T*) cast(Chunk*) (cast(void*) chunk + bix + underread);
		}

		chunk = cast(Chunk*) (cast(void*) chunk + byteWidth);

		goto nextChunk;
	}
}


pure nothrow @nogc unittest
{
	align(minimumPageSize) ubyte[minimumPageSize] page;
	assert((cast(size_t) page.ptr & (minimumPageSize - 1)) == 0);

	(cast(char[]) page)[0 .. 72] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-\0\0\0\0\0\0\0\0";

	assert((cast( char*) page.ptr).findSentinel!'\0' == cast( char*) &page[64]);
	assert((cast(wchar*) page.ptr).findSentinel!'\0' == cast(wchar*) &page[64]);
	assert((cast(dchar*) page.ptr).findSentinel!'\0' == cast(dchar*) &page[64]);
	assert((cast(ulong*) page.ptr).findSentinel!'\0' == cast(ulong*) &page[64]);

	assert((cast( char*) &page[64]).findSentinel!'\0' == cast( char*) &page[64]);
	assert((cast(wchar*) &page[64]).findSentinel!'\0' == cast(wchar*) &page[64]);
	assert((cast(dchar*) &page[64]).findSentinel!'\0' == cast(dchar*) &page[64]);
	assert((cast(ulong*) &page[64]).findSentinel!'\0' == cast(ulong*) &page[64]);

	(cast(char[]) page)[minimumPageSize - 8 .. minimumPageSize] = "\r\r\r\r\r\r\r\0";
	assert((cast( char*) &page[minimumPageSize - 8]).findSentinel!'\0' == cast( char*) &page[minimumPageSize - 1]);
	(cast(char[]) page)[minimumPageSize - 8 .. minimumPageSize] = "\r\r\r\r\r\r\0\0";
	assert((cast(wchar*) &page[minimumPageSize - 8]).findSentinel!'\0' == cast(wchar*) &page[minimumPageSize - 2]);
	(cast(char[]) page)[minimumPageSize - 8 .. minimumPageSize] = "\r\r\r\r\0\0\0\0";
	assert((cast(dchar*) &page[minimumPageSize - 8]).findSentinel!'\0' == cast(dchar*) &page[minimumPageSize - 4]);
	(cast(char[]) page)[minimumPageSize - 8 .. minimumPageSize] = "\0\0\0\0\0\0\0\0";
	assert((cast(ulong*) &page[minimumPageSize - 8]).findSentinel!'\0' == cast(ulong*) &page[minimumPageSize - 8]);

	(cast(char[]) page)[32 .. 48] = "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0";

	assert((cast(void[]*) page.ptr).findSentinel!null == cast(void[]*) &page[32]);
}


pragma(inline, true)
uint leastSetBitIndex (Flag!"definedForZero" definedForZero = Yes.definedForZero, T) (T value)
{
	import core.bitop : bsf;

	if (__ctfe)
	{
		enum uint operandSize = T.sizeof << 3;

		return value == 0 ? operandSize : cast(uint) bsf(value);
	}

	version (LDC)
	{
		import ldc.intrinsics : llvm_cttz;
		return cast(uint) llvm_cttz(value, !cast(bool) definedForZero);
	}
	else version (GNU)
	{
		static if (T.sizeof <= 4)
		{
			import gcc.builtins : __builtin_ctz;
			auto index = cast(uint) __builtin_ctz(value) ^ operandSizeLessOne;
		}
		else
		{
			import gcc.builtins : __builtin_ctzll;
			auto index = cast(uint) __builtin_ctzll(value) ^ operandSizeLessOne;
		}

		static if (definedForZero)
		{
			enum uint operandSize = T.sizeof << 3;
			return value == 0 ? operandSize : index;
		}
		else
		{
			return index;
		}
	}
	else
	{
		auto index = cast(uint) bsf(value);

		static if (definedForZero)
		{
			enum uint operandSize = T.sizeof << 3;
			return value == 0 ? operandSize : index;
		}
		else
		{
			return index;
		}
	}
}


pragma(inline, true)
uint leadingZeroCount (Flag!"definedForZero" definedForZero = Yes.definedForZero, T) (T value)
{
	import core.bitop : bsr;

	if (__ctfe)
	{
		enum uint operandSize = T.sizeof << 3;
		enum uint operandSizeLessOne = operandSize - 1;

		return value == 0 ? operandSize : (cast(uint) bsr(value) ^ operandSizeLessOne);
	}

	version (LDC)
	{
		import ldc.intrinsics : llvm_ctlz;
		return cast(uint) llvm_ctlz(value, !cast(bool) definedForZero);
	}
	else version (GNU)
	{
		static if (T.sizeof <= 4)
		{
			import gcc.builtins : __builtin_clz;
			auto count = cast(uint) __builtin_clz(value);
		}
		else
		{
			import gcc.builtins : __builtin_clzll;
			auto count = cast(uint) __builtin_clzll(value);
		}

		static if (definedForZero)
		{
			enum uint operandSize = T.sizeof << 3;
			return value == 0 ? operandSize : count;
		}
		else
		{
			return count;
		}
	}
	else
	{
		enum uint operandSize = T.sizeof << 3;
		enum uint operandSizeLessOne = operandSize - 1;

		auto count = cast(uint) bsr(value) ^ operandSizeLessOne;

		static if (definedForZero)
		{
			return value == 0 ? operandSize : count;
		}
		else
		{
			return count;
		}
	}
}


extern(System)
void* cStyleMemoryAllocate (scope void* context, size_t size) nothrow @nogc
{
	return VirtualAlloc(null, size, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
}


extern(System)
void cStyleMemoryFree (scope void* context, void* memory) nothrow @nogc
{
	VirtualFree(memory, 0, MEM_RELEASE);
}


extern(System)
void* memoryAllocate (scope void* context, size_t size, size_t alignment) nothrow @nogc
in (alignment <= (64 << 10))
{
	return VirtualAlloc(null, size, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
}


extern(System)
void memoryFree (scope void* context, void* memory, size_t size) nothrow @nogc
{
	VirtualFree(memory, 0, MEM_RELEASE);
}



version (Windows)
{
	alias HANDLE = void*;
	alias HMODULE = void*;
	alias HLOCAL = void*;
	alias BOOL = uint;
	alias BOOLEAN = ubyte;
	alias NTSTATUS = uint;

	enum HANDLE INVALID_HANDLE_VALUE = cast(HANDLE) -1;

	enum uint GENERIC_READ = 0x80000000;
	enum uint GENERIC_WRITE = 0x40000000;
	enum uint GENERIC_EXECUTE = 0x20000000;
	enum uint GENERIC_ALL = 0x10000000;

	enum uint FILE_SHARE_READ = 0x00000001;
	enum uint FILE_SHARE_WRITE = 0x00000002;
	enum uint FILE_SHARE_DELETE = 0x00000004;

	enum uint CREATE_ALWAYS = 2;
	enum uint CREATE_NEW = 1;
	enum uint OPEN_ALWAYS = 4;
	enum uint OPEN_EXISTING = 3;
	enum uint TRUNCATE_EXISTING = 5;

	enum uint FILE_ATTRIBUTE_NORMAL = 0x80;

	enum uint PAGE_READONLY = 0x02;
	enum uint PAGE_READWRITE = 0x04;

	enum uint FILE_MAP_READ = 0x0004;

	enum uint MEM_COMMIT = 0x00001000;
	enum uint MEM_RESERVE = 0x00002000;
	enum uint MEM_DECOMMIT = 0x00004000;
	enum uint MEM_RELEASE = 0x00008000;

	enum uint FILE_BEGIN = 0;
	enum uint FILE_CURRENT = 1;
	enum uint FILE_END = 2;

	enum uint STD_INPUT_HANDLE = cast(uint) -10;
	enum uint STD_OUTPUT_HANDLE = cast(uint) -11;
	enum uint STD_ERROR_HANDLE = cast(uint) -12;

	enum uint MAX_PATH = 260;

	union LARGE_INTEGER
	{
		alias QuadPart this;

		struct
		{
			uint LowPart;
			int HighPart;
		}

		long QuadPart;
	}

	struct OVERLAPPED
	{
		size_t Internal;
		size_t InternalHigh;

		union
		{
			struct
			{
				uint Offset;
				uint OffsetHigh;
			}

			void* Pointer;
		}

		HANDLE hEvent;
	}

	struct IO_STATUS_BLOCK
	{
		union
		{
			NTSTATUS Status;
			void* Pointer;
		}

		size_t Information;
	}

	extern(Windows) HMODULE GetModuleHandleW (scope const(wchar)* lpModuleName) nothrow @nogc;
	extern(Windows) void* GetProcAddress (scope HMODULE hModule, scope const(char)* lpProcName) nothrow @nogc;

	extern(Windows) HMODULE LoadLibraryW (scope const(wchar)* lpLibFileName) nothrow @nogc;
	extern(Windows) BOOL FreeLibrary (scope HMODULE hLibModule) nothrow @nogc;

	extern(Windows) uint WaitForSingleObject (HANDLE hHandle, uint dwMilliseconds) @safe nothrow @nogc;

	extern(Windows) BOOL CloseHandle (scope HANDLE hObject) @safe nothrow @nogc;
	extern(Windows) HANDLE CreateFileW (scope const(wchar)* lpFileName, uint dwDesiredAccess, uint dwShareMode, scope void* lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, HANDLE hTemplateFile) nothrow @nogc;
	extern(Windows) HANDLE CreateFileMappingW (scope HANDLE hFile, scope void* lpSecurityAttributes, uint flProtect, uint dwMaximumSizeHigh, uint dwMaximumSizeLow, scope const(wchar)* lpName) nothrow @nogc;
	extern(Windows) void* MapViewOfFile (scope HANDLE hFileMappingObject, uint dwDesiredAccess, uint dwFileOffsetHigh, uint dwFileOffsetLow, size_t dwNumberOfBytesToMap) nothrow @nogc;
	extern(Windows) BOOL UnmapViewOfFile (scope const(void)* lpBaseAddress) nothrow @nogc;
	extern(Windows) BOOL GetFileSizeEx (scope HANDLE hFile, scope LARGE_INTEGER* lpFileSize) @safe nothrow @nogc;

	extern(Windows) BOOL WriteFile (HANDLE hFile, scope const(void)* lpBuffer, uint nNumberOfBytesToWrite, scope uint* lpNumberOfBytesWritten, OVERLAPPED* lpOverlapped) @system nothrow @nogc;
	extern(Windows) BOOL ReadFile (HANDLE hFile, scope void* lpBuffer, uint nNumberOfBytesToRead, scope uint* lpNumberOfBytesRead, OVERLAPPED* lpOverlapped) @system nothrow @nogc;

	extern(Windows) BOOL SetFilePointerEx (scope HANDLE hFile, LARGE_INTEGER liDistanceToMove, scope LARGE_INTEGER* lpNewFilePointer, uint dwMoveMethod) @safe nothrow @nogc;
	extern(Windows) BOOL SetEndOfFile (scope HANDLE hFile) @safe nothrow @nogc;

	extern(Windows) void* VirtualAlloc (scope void* lpAddress, size_t dwSize, uint flAllocationType, uint flProtect) nothrow @nogc;
	extern(Windows) BOOL VirtualFree (scope void* lpAddress, size_t dwSize, uint dwFreeType) nothrow @nogc;

	extern(Windows) HLOCAL LocalFree (scope HLOCAL hMem) nothrow @nogc;

	extern(Windows) uint GetLastError () @safe nothrow @nogc;

	extern(Windows) wchar* GetCommandLineW () nothrow @nogc;
	extern(Windows) wchar** CommandLineToArgvW (scope const(wchar)* lpCmdLine, scope int* pNumArgs) nothrow @nogc;

	extern(Windows) HANDLE GetStdHandle (uint nStdHandle) @safe nothrow @nogc;
	extern(Windows) BOOL GetConsoleMode (scope HANDLE hConsoleHandle, scope uint* lpMode) @safe nothrow @nogc;

	extern(Windows) BOOL WriteConsoleW (scope HANDLE hConsoleOutput, scope const(void)* lpBuffer, uint nNumberOfCharsToWrite, scope uint* lpNumberOfCharsWritten, scope void* lpReserved) nothrow @nogc;

	extern(Windows) noreturn ExitProcess (uint uExitCode) @safe nothrow @nogc;

	extern(Windows) NTSTATUS NtCopyFileChunk (HANDLE SourceHandle, HANDLE DestHandle, HANDLE Event, IO_STATUS_BLOCK* IoStatusBlock, uint Length, scope LARGE_INTEGER* SourceOffset, scope LARGE_INTEGER* DestOffset, scope uint* SourceKey, scope uint* DestKey, uint Flags) @system nothrow @nogc;

	extern(Windows) BOOL DeviceIoControl (scope HANDLE hDevice, uint dwIoControlCode, scope void* lpInBuffer, uint nInBufferSize, scope void* lpOutBuffer, uint nOutBufferSize, scope uint* lpBytesReturned, scope OVERLAPPED* lpOverlapped) @system nothrow @nogc;

	enum uint CTL_CODE (uint deviceType, uint function_, uint method, uint access) = (
		(deviceType << 16) | (access << 14) | (function_ << 2) | method
	);

	enum uint METHOD_BUFFERED = 0;
	enum uint METHOD_IN_DIRECT = 1;
	enum uint METHOD_OUT_DIRECT = 2;
	enum uint METHOD_NEITHER = 3;

	enum uint FILE_ANY_ACCESS = 0;
	enum uint FILE_SPECIAL_ACCESS = FILE_ANY_ACCESS;
	enum uint FILE_READ_ACCESS = 0x0001;
	enum uint FILE_WRITE_ACCESS = 0x0002;
	enum uint FILE_WRITE_DATA = 0x0002;

	enum uint FILE_DEVICE_FILE_SYSTEM = 0x00000009;
	enum uint FILE_DEVICE_NETWORK_FILE_SYSTEM = 0x00000014;

	enum uint FSCTL_SET_SPARSE = CTL_CODE!(FILE_DEVICE_FILE_SYSTEM, 49, METHOD_BUFFERED, FILE_SPECIAL_ACCESS);
	enum uint FSCTL_SET_ZERO_DATA = CTL_CODE!(FILE_DEVICE_FILE_SYSTEM, 50, METHOD_BUFFERED, FILE_WRITE_DATA);

	struct FILE_SET_SPARSE_BUFFER
	{
		BOOLEAN SetSparse;
	}

	struct FILE_ZERO_DATA_INFORMATION
	{
		LARGE_INTEGER FileOffset;
		LARGE_INTEGER BeyondFinalZero;
	}
}

