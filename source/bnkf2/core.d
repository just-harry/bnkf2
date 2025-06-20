
/+ SPDX-LICENSE-IDENTIFIER: 0BSD +/

module bnkf2.core;

import core.bitop : bswap;
import core.simd;
import std.meta : AliasSeq;
import std.system : Endian, endian;
import std.traits : Unqual;

import zlib;


version (BigEndian)
{
	static assert(false, "Here's a nickel kid, get yourself a better computer.");
}


version (X86)
{
	version = X86_64_Or_X86;
}
else version (X86_64)
{
	version = X86_64_Or_X86;
}


enum size_t minimumPageSize = 4096;


/+ These archive definitions are based on the definitions
   provided at http://fable2mod.com/forums/post/1.
   Cheers, Keshire. +/
struct BNK
{
	align(1)
	struct FileHeader
	{
		BigEndian!uint offset;
		BigEndian!uint version_;

		static assert(FileHeader.sizeof == 8);
	}

	align(1)
	struct FileHeaderV2
	{
		alias header this;
		FileHeader header;
		/+ This is tentative--I've yet to encounter a compressed V2 BNK file. +/
		ubyte filesAreCompressed;
		ubyte[7] padding;
		ubyte[0] fileData;

		static assert(FileHeaderV2.sizeof == 16);
	}

	align(1)
	struct FileHeaderV3
	{
		alias header this;
		FileHeader header;
		ubyte filesAreCompressed;
	align(1)
		BigEndian!uint compressedHeaderSize;
	align(1)
		BigEndian!uint uncompressedHeaderSize;
		ubyte[0] compressedFileTable;

		static assert(FileHeaderV3.sizeof == 17);
	}

	struct FileTable
	{
		BigEndian!uint fileCount;
		ubyte[0] fileEntries;

		static assert(FileTable.sizeof == 4);
	}

	struct FileTableContinuationHeader
	{
		BigEndian!uint compressedSize;
		BigEndian!uint uncompressedSize;
		ubyte[0] continuationData;

		static assert(FileTableContinuationHeader.sizeof == 8);
	}

	struct UncompressedFileTableEntry
	{
		BigEndian!uint nameLength;
		char[0] path;
		/+ Offsets after the variably-sized path? A curious choice. +/
		DataSpan data;

		struct DataSpan
		{
			BigEndian!uint offset;
			BigEndian!uint uncompressedFileSize;

			static assert(DataSpan.sizeof == 8);
		}

		static assert(UncompressedFileTableEntry.sizeof == 12);
	}

	struct CompressedFileTableEntry
	{
		alias uncompressed this;

		UncompressedFileTableEntry uncompressed;
		BigEndian!uint compressedFileSize;
		BigEndian!uint chunkCount;
		BigEndian!uint[0] uncompressedChunkSizes;

		static assert(CompressedFileTableEntry.sizeof == 20);

		enum uint completeChunkSize = 32 << 10;
		enum uint completeChunkSizeLog2 = 15;
		enum uint completeChunkSizeMask = (1 << completeChunkSizeLog2) - 1;
	}

	union FileTableEntry
	{
		UncompressedFileTableEntry uncompressed;
		CompressedFileTableEntry compressed;
	}
}


extern(System)
{
	alias ContiguousOutputBufferFlusher = size_t function (
		scope void* context,
		ubyte** freshBuffer,
		ubyte* flushBuffer,
		size_t flushSize
	);

	alias DiscontiguousOutputBufferFlusher = size_t function (
		scope void* context,
		ubyte** freshBuffer,
		ubyte* flushBuffer,
		size_t flushSize,
		uint bufferIndex
	);

	alias CStyleMemoryAllocate = void* function (void* context, size_t size) nothrow @nogc;
	alias CStyleMemoryFree = void function (void* context, void* memory) nothrow @nogc;

	alias MemoryAllocate = void* function (void* context, size_t size, size_t alignment) nothrow @nogc;
	alias MemoryFree = void function (void* context, void* memory, size_t size) nothrow @nogc;

	alias ProgressObserver = void function (
		void* context,
		size_t progressOpcode,
		scope const(void)* operand0,
		size_t operand1
	);
}


struct BNKF2DynamicallyLinkedZLib
{
	enum ProvisionVersion : size_t
	{
		latest = _0,
		_0 = 0
	}

	ProvisionVersion provisionVersion;

	typeof(&zlib.deflateInit_) deflateInit_;
	typeof(&zlib.deflateInit2_) deflateInit2_;
	typeof(&zlib.deflate) deflate;
	typeof(&zlib.deflateEnd) deflateEnd;
	typeof(&zlib.deflateReset) deflateReset;
	typeof(&zlib.deflatePrime) deflatePrime;
	typeof(&zlib.deflateTune) deflateTune;
	typeof(&zlib.inflateInit_) inflateInit_;
	typeof(&zlib.inflateInit2_) inflateInit2_;
	typeof(&zlib.inflate) inflate;
	typeof(&zlib.inflateEnd) inflateEnd;
	typeof(&zlib.inflateReset) inflateReset;
	typeof(&zlib.inflateReset2) inflateReset2;
	typeof(&zlib.inflatePrime) inflatePrime;
	typeof(&zlib.crc32) crc32;
}


struct BNKF2MemoryAllocatorProvision
{
	enum fundamentalAlignment = void*.sizeof << 1;

	PackedState packedState;

	void* memoryContext;
	MemoryAllocate memoryAllocate;
	MemoryFree memoryFree;

	void* cStyleMemoryContext;
	CStyleMemoryAllocate cStyleMemoryAllocate;
	CStyleMemoryFree cStyleMemoryFree;

	struct PackedState
	{
		alias value this;

		size_t value;

		enum Flags : size_t
		{
			none = 0,
			allocatesZeroedMemory = 1 << 0,
			cStyleAllocatesZeroedMemory = 1 << 1
		}
	}

	pragma(inline, false)
	void* allocate (size_t size, size_t alignment, bool zeroed = false) scope nothrow @nogc
	in (alignment <= fundamentalAlignment)
	{
		void* memory = void;

		if (this.memoryAllocate !is null)
		{
			memory = this.memoryAllocate(this.memoryContext, size, alignment);

			if (!(this.packedState & this.packedState.Flags.allocatesZeroedMemory))
			{
				goto zeroIfNeeded;
			}

			return memory;
		}
		else
		{
			memory = this.cStyleMemoryAllocate(this.memoryContext, size);

			if (!(this.packedState & this.packedState.Flags.cStyleAllocatesZeroedMemory))
			{
				goto zeroIfNeeded;
			}

			return memory;
		}
	zeroIfNeeded:
		if (zeroed)
		{
			zeroOut(memory, size);
		}

		return memory;
	}

	pragma(inline, false)
	void free (void* memory, size_t size) scope nothrow @nogc
	{
		if (this.memoryAllocate !is null)
		{
			return this.memoryFree(this.memoryContext, memory, size);
		}
		else
		{
			return this.cStyleMemoryFree(this.memoryContext, memory);
		}
	}

	pragma(inline, false)
	void* cStyleAllocate (size_t size, bool zeroed = false) scope nothrow @nogc
	{
		void* memory = void;

		if (this.cStyleMemoryAllocate !is null)
		{
			memory = this.cStyleMemoryAllocate(this.memoryContext, size);

			if (!(this.packedState & this.packedState.Flags.cStyleAllocatesZeroedMemory))
			{
				goto zeroIfNeeded;
			}

			return memory;
		}
		else
		{
			void* base = this.memoryAllocate(this.memoryContext, fundamentalAlignment + size, fundamentalAlignment);

			if (base is null)
			{
				return null;
			}

			*cast(size_t*) base = size;

			memory = base + fundamentalAlignment;

			if (!(this.packedState & this.packedState.Flags.allocatesZeroedMemory))
			{
				goto zeroIfNeeded;
			}

			return memory;
		}
	zeroIfNeeded:
		if (zeroed)
		{
			zeroOut(memory, size);
		}

		return memory;
	}

	pragma(inline, false)
	void cStyleFree (void* memory) scope nothrow @nogc
	{
		if (this.cStyleMemoryAllocate !is null)
		{
			this.cStyleMemoryFree(this.memoryContext, memory);
		}
		else
		{
			if (memory is null)
			{
				return;
			}

			void* base = memory - fundamentalAlignment;
			size_t size = *cast(size_t*) base;

			this.memoryFree(this.memoryContext, base, size);
		}
	}

	extern(C)
	static void* zlibAllocate (scope void* opaque, uint items, uint size) nothrow @nogc
	{
		return (cast(BNKF2MemoryAllocatorProvision*) opaque).cStyleAllocate(size_t(items) * size);
	}

	extern(C)
	static void zlibFree (scope void* opaque, scope void* address) nothrow @nogc
	{
		return (cast(BNKF2MemoryAllocatorProvision*) opaque).cStyleFree(address);
	}

}


struct ContextualisedProgressObserver
{
	alias observer this;

	void* context;
	ProgressObserver observer;
}


enum BNKToZipProgressOpcode : size_t
{
	decompressingFileTable = 0,
	decompressedFileTable = 1,
	decompressingFile = 2,
	copyingFile = 3,
	skippedDuplicateFileName = 4,
	checksummingFile = 5,
	checksummedFile = 6,
	writingFileMetadata = 7
}


struct BNKToZipResult
{
	struct V0
	{
		PackedState packedState;
		uint bnkVersion;

		struct PackedState
		{
			alias value this;

			size_t value;

			enum Flags : size_t
			{
				none = 0,
				bnkCompressionStatusIsKnown = 1 << 0,
				bnkWasCompressed = 1 << 1,
				bnkVersionIsKnown = 1 << 2
			}
		}
	}

	union
	{
		V0 v0;
	}
}


struct BNKToZipState
{
	PackedState packedState;

	struct PackedState
	{
		alias value this;

		enum Flags : uint
		{
			none = 0,
			forwardAllocatorToZLib = 1 << 0,
			omitBNKF2Metadata = 1 << 3,
			emitDuplicateFiles = 1 << 4
		}

		size_t value;
	}

	BNKF2MemoryAllocatorProvision* memoryAllocators;
	const(BNKF2DynamicallyLinkedZLib)* zlib;
	ContextualisedProgressObserver progressObserver;

	BNKToZipResult* extendedReturnChannel;

	uint version_;
}


enum DEFLATECompressionLevel : ubyte
{
	default_ = 0,
	/+ *Fastest decompression of the output
	    whilst still performing _some_ compression of the input. +/
	fastestDecompresion = 1,
	strongestCompression = 2,
	_0 = 3,
	_1 = 4,
	_2 = 5,
	_3 = 6,
	_4 = 7,
	_5 = 8,
	_6 = 9,
	_7 = 10,
	_8 = 11,
	_9 = 12
}


enum ZLibMemoryLevel : ubyte
{
	default_ = 0,
	_0 = 1,
	_1 = 2,
	_2 = 3,
	_3 = 4,
	_4 = 5,
	_5 = 6,
	_6 = 7,
	_7 = 8,
	_8 = 9,
	_9 = 10
}


ubyte asZLibCompressionLevel (DEFLATECompressionLevel level) @safe pure nothrow @nogc
{
	switch (level)
	{
	default:
	case DEFLATECompressionLevel.default_: return 8;
	case DEFLATECompressionLevel.fastestDecompresion: return 1;
	case DEFLATECompressionLevel.strongestCompression: return 9;
	case DEFLATECompressionLevel._0: return 0;
	case DEFLATECompressionLevel._1: return 1;
	case DEFLATECompressionLevel._2: return 2;
	case DEFLATECompressionLevel._3: return 3;
	case DEFLATECompressionLevel._4: return 4;
	case DEFLATECompressionLevel._5: return 5;
	case DEFLATECompressionLevel._6: return 6;
	case DEFLATECompressionLevel._7: return 7;
	case DEFLATECompressionLevel._8: return 8;
	case DEFLATECompressionLevel._9: return 9;
	}
}


ubyte asZLibMemoryLevel (ZLibMemoryLevel level) @safe pure nothrow @nogc
{
	switch (level)
	{
	default:
	case ZLibMemoryLevel.default_: return 8;
	case ZLibMemoryLevel._0: return 0;
	case ZLibMemoryLevel._1: return 1;
	case ZLibMemoryLevel._2: return 2;
	case ZLibMemoryLevel._3: return 3;
	case ZLibMemoryLevel._4: return 4;
	case ZLibMemoryLevel._5: return 5;
	case ZLibMemoryLevel._6: return 6;
	case ZLibMemoryLevel._7: return 7;
	case ZLibMemoryLevel._8: return 8;
	case ZLibMemoryLevel._9: return 9;
	}
}


enum ZipToBNKProgressOpcode : size_t
{
	searchingForCentralDirectory = 0,
	foundCentralDirectory = 1,
	copyingFile = 2,
	compressingFile = 3,
	compressingFileChunk = 4,
	compressedFileChunk = 5,
	decompressingFile = 6
}


struct ZipToBNKResult
{
	struct V0
	{
		PackedState packedState;
		uint bnkVersion;

		struct PackedState
		{
			alias value this;

			size_t value;

			enum Flags : size_t
			{
				none = 0,
				bnkCompressionStatusIsKnown = 1 << 0,
				bnkIsCompressed = 1 << 1,
				bnkVersionIsKnown = 1 << 2
			}
		}
	}

	union
	{
		V0 v0;
	}
}


struct ZipToBNKState
{
	PackedState packedState;

	struct PackedState
	{
		alias value this;

		enum Flags : uint
		{
			none = 0,
			forwardAllocatorToZLib = 1 << 0,
			ignoreBNKF2MetadataForCompressionSetting = 1 << 5,
			outputCompressedBNK = 1 << 6,
			ignoreBNKF2MetadataForBNKVersion = 1 << 7
		}

		size_t value;
	}

	BNKF2MemoryAllocatorProvision* memoryAllocators;
	const(BNKF2DynamicallyLinkedZLib)* zlib;
	ContextualisedProgressObserver progressObserver;

	ZipToBNKResult* extendedReturnChannel;

	uint version_;

	uint bnkVersion;

	DEFLATECompressionLevel fileTableCompressionLevel;
	ZLibMemoryLevel fileTableMemoryLevel;
	DEFLATECompressionLevel fileDataCompressionLevel;
	ZLibMemoryLevel fileDataMemoryLevel;

	uint fileTableUncompressedChunkThreshold;
}


struct BNKF2Status
{
	uint code;
	ubyte[3] padding;
	CodeSource source;

	enum CodeSource : ubyte
	{
		bnkf2 = 0,
		caller = 1,
		system = 2,
		zlib = 3
	}

	pragma(inline, true)
	bool successful () const scope @safe pure nothrow @nogc
	{
		return this.code == 0;
	}

	pragma(inline, true)
	bool failed () const scope @safe pure nothrow @nogc
	{
		return this.code != 0;
	}

	static BNKF2Status status () (BNKF2StatusCode code) @safe pure nothrow @nogc
	{
		return BNKF2Status(cast(uint) code, [0, 0, 0], CodeSource.bnkf2);
	}

	static BNKF2Status caller () (uint code) @safe pure nothrow @nogc
	{
		return BNKF2Status(code, [0, 0, 0], CodeSource.caller);
	}

	static BNKF2Status system (uint code) @safe pure nothrow @nogc
	{
		return BNKF2Status(code, [0, 0, 0], CodeSource.system);
	}

	version (Windows)
	{
		static BNKF2Status lastError () () @safe nothrow @nogc
		{
			return lastError(GetLastError);
		}

		static BNKF2Status lastError () (uint lastError) @safe pure nothrow @nogc
		{
			return BNKF2Status(0x80070000 | cast(ushort) lastError, [0, 0, 0], CodeSource.system);
		}
	}

	static BNKF2Status zlib (uint code) @safe pure nothrow @nogc
	{
		return BNKF2Status(code, [0, 0, 0], CodeSource.zlib);
	}
}


enum BNKF2StatusCode : uint
{
	success = 0,
	unrecognisedStructureVersion = 1,
	memoryAllocationFailed = 2,
	inputIsTooLong = 3,
	inputIsTruncated = 4,
	inputIsInvalid = 5,
	fileTableUncompressedChunkThresholdIsTooBig = 6,
	impossiblyLargeFileTableInBNK = 7,
	impossiblyLongFilePathInBNK = 8,
	outOfBoundsDataOffsetInBNK = 9,
	outOfBoundsDataSpanInBNK = 10,
	mismatchingCompressedChunkCountInBNK = 11,
	invalidZLibHeaderForFileInBNK = 12,
	presetDictionaryRequiredByFileInBNK = 13,
	couldNotFindEndOfCentralDirectoryRecordInZip = 14,
	invalidSignatureForEndOfCentralDirectoryLocator64InZip = 15,
	invalidSignatureForEndOfCentralDirectoryRecord64InZip = 16,
	invalidSignatureForCentralDirectoryRecordInZip = 17,
	invalidSignatureForLocalFileHeaderInZip = 18,
	invalidOffsetForCentralDirectoryInZip = 19,
	invalidSizeForCentralDirectoryInZip = 20,
	invalidOffsetForEndOfCentralDirectoryRecord64InZip = 21,
	invalidSizeForEndOfCentralDirectoryRecord64InZip = 22,
	invalidOffsetForCentralDirectoryRecordInZip = 23,
	unsupportedVersionRequiredForExtractionInZip = 24,
	unsupportedEncryptedFileInZip = 25,
	unsupportedCompressedPatchedDataInZip = 26,
	unsupportedEnhancedCompressionInZip = 27,
	unsupportedCompressionMethodInZip = 28,
	invalidFooterSizeForCentralDirectoryRecordInZip = 29,
	invalidFooterSizeForLocalFileHeaderInZip = 30,
	excessivelyLongFileNameForCentralDirectoryRecordInZip = 31,
	tooMuchFileNameInZip = 32,
	invalidExtraFieldLengthForCentralDirectoryRecordInZip = 33,
	invalidExtraFieldSizeForCentralDirectoryRecordInZip = 34,
	failedToFindExtendedInformationExtraField64ForCentralDirectoryRecordInZip = 35,
	invalidOffsetForLocalFileHeaderInZip = 36,
	invalidCompressedSizeForFileInZip = 37,
	invalidUncompressedSizeForFileInZip = 38,
	zipFileIsTooBigForBNKFile = 39,
	invalidSizeForFileInZip = 40,
}


package enum errorMessageTableDefiner = ()
{
	immutable(char)[][BNKF2StatusCode.max + 1] messageFor;
	uint[BNKF2StatusCode.max + 1] endOfMessageOffsets;
	uint totalLength = 0;
	uint longestLength = 0;

	messageFor[BNKF2StatusCode.success] = "Success!";
	messageFor[BNKF2StatusCode.memoryAllocationFailed] = "Memory allocation failed.";
	messageFor[BNKF2StatusCode.inputIsTooLong] = "The input is too large.";
	messageFor[BNKF2StatusCode.inputIsTruncated] = "The input is truncated. (Or lying about its size).";
	messageFor[BNKF2StatusCode.inputIsInvalid] = "The input is invalid in some unexpected way.";
	messageFor[BNKF2StatusCode.fileTableUncompressedChunkThresholdIsTooBig] = "fileTableUncompressedChunkThresholdIsTooBig";
	messageFor[BNKF2StatusCode.impossiblyLargeFileTableInBNK] = "The BNK file's file-table purports to be impossibly large.";
	messageFor[BNKF2StatusCode.impossiblyLongFilePathInBNK] = "A file-path in the BNK's file-table is larger than 64KB.";
	messageFor[BNKF2StatusCode.outOfBoundsDataOffsetInBNK] = "An offset for file-data in the BNK's file-table is out of bounds.";
	messageFor[BNKF2StatusCode.outOfBoundsDataSpanInBNK] = "A length for file-data in the BNK's file-table is out of bounds.";
	messageFor[BNKF2StatusCode.mismatchingCompressedChunkCountInBNK] = "The compressed-chunk-count and the compressed-file-size for an entry in the BNK's file-table mismatch.";
	messageFor[BNKF2StatusCode.invalidZLibHeaderForFileInBNK] = "A compressed-file-chunk in the BNK file has an invalid zlib header.";
	messageFor[BNKF2StatusCode.presetDictionaryRequiredByFileInBNK] = "A compressed-file-chunk in the BNK file requires a preset dictionary. (There is no means by which to supply such a dictionary).";
	messageFor[BNKF2StatusCode.couldNotFindEndOfCentralDirectoryRecordInZip] = "The end-of-central-directory-record could not be found in the zip file.";
	messageFor[BNKF2StatusCode.invalidSignatureForEndOfCentralDirectoryLocator64InZip] = "The 64-bit end-of-central-directory-locator in the zip file has an invalid signature.";
	messageFor[BNKF2StatusCode.invalidSignatureForEndOfCentralDirectoryRecord64InZip] = "The 64-bit end-of-central-directory-record in the zip file has an invalid signature.";
	messageFor[BNKF2StatusCode.invalidSignatureForCentralDirectoryRecordInZip] = "The end-of-central-directory-record in the zip file has an invalid signature.";
	messageFor[BNKF2StatusCode.invalidSignatureForLocalFileHeaderInZip] = "A local-file-header in the zip file has an invalid signature.";
	messageFor[BNKF2StatusCode.invalidOffsetForCentralDirectoryInZip] = "The offset for the central-directory in the zip file is out of bounds.";
	messageFor[BNKF2StatusCode.invalidSizeForCentralDirectoryInZip] = "The size for the central-directory in the zip file is out of bounds.";
	messageFor[BNKF2StatusCode.invalidOffsetForEndOfCentralDirectoryRecord64InZip] = "The offset for the 64-bit end-of-central-directory-record in the zip file is out of bounds.";
	messageFor[BNKF2StatusCode.invalidSizeForEndOfCentralDirectoryRecord64InZip] = "The size for the 64-bit end-of-central-directory-record in the zip file is out of bounds.";
	messageFor[BNKF2StatusCode.invalidOffsetForCentralDirectoryRecordInZip] = "An offset for a central-directory-record in the zip file is out of bounds, or the zip file is truncated.";
	messageFor[BNKF2StatusCode.unsupportedVersionRequiredForExtractionInZip] = "An entry in the zip file requires an unsupported version for extraction.";
	messageFor[BNKF2StatusCode.unsupportedEncryptedFileInZip] = "An entry in the zip file is encrypted.";
	messageFor[BNKF2StatusCode.unsupportedCompressedPatchedDataInZip] = "An entry in the zip file consists of unsupported compressed patched data.";
	messageFor[BNKF2StatusCode.unsupportedEnhancedCompressionInZip] = "An entry in the zip file uses unsupported enhanced compression.";
	messageFor[BNKF2StatusCode.unsupportedCompressionMethodInZip] = "An entry in the zip file uses an unsupported compression method. (Only the \"Store\" and \"DEFLATE\" compression methods are supported).";
	messageFor[BNKF2StatusCode.invalidFooterSizeForCentralDirectoryRecordInZip] = "A central-directory-record in the zip file has invalid footer size, or the zip file is truncated.";
	messageFor[BNKF2StatusCode.invalidFooterSizeForLocalFileHeaderInZip] = "A local-file-header in the zip file has invalid footer size, or the zip file is truncated.";
	messageFor[BNKF2StatusCode.excessivelyLongFileNameForCentralDirectoryRecordInZip] = "An entry in the zip file has a file-path larger than 65,535 bytes.";
	messageFor[BNKF2StatusCode.tooMuchFileNameInZip] = "The total size of the file-paths in the zip file are too large to be stored in a BNK file.";
	messageFor[BNKF2StatusCode.invalidExtraFieldLengthForCentralDirectoryRecordInZip] = "A central-directory-record in the zip file has invalid extra-field length, or the zip file is truncated.";
	messageFor[BNKF2StatusCode.invalidExtraFieldSizeForCentralDirectoryRecordInZip] = "An extra-field for a central-directory-record in the zip file has invalid field-size, or the zip file is truncated.";
	messageFor[BNKF2StatusCode.failedToFindExtendedInformationExtraField64ForCentralDirectoryRecordInZip] = "The 64-bit-extended-information extra-field for a 64-bit central-directory-record in the zip file could not be found.";
	messageFor[BNKF2StatusCode.invalidOffsetForLocalFileHeaderInZip] = "An offset for a local-file-header in the zip file is out of bounds, or the zip file is truncated.";
	messageFor[BNKF2StatusCode.invalidCompressedSizeForFileInZip] = "The compressed-size for an entry in the zip file is out of bounds, or the zip file is truncated.";
	messageFor[BNKF2StatusCode.invalidUncompressedSizeForFileInZip] = "The uncompressed-size for an uncompressed entry in the zip file does not the entry's compressed-size.";
	messageFor[BNKF2StatusCode.zipFileIsTooBigForBNKFile] = "The contents of the zip file are too large, in aggregate, to be stored in a BNK file.";
	messageFor[BNKF2StatusCode.invalidSizeForFileInZip] = "The size for an entry in the zip file is out of bounds, or the zip file is truncated.";

	foreach (index, message; messageFor)
	{
		totalLength += message.length + 1;
		longestLength = greaterOf(cast(uint) message.length, longestLength);
		endOfMessageOffsets[index] = totalLength;
	}

	static struct Result
	{
		immutable(char)[][BNKF2StatusCode.max + 1] messageFor;
		uint[BNKF2StatusCode.max + 1] endOfMessageOffsets;
		uint longestLength;
	}

	return Result(messageFor, endOfMessageOffsets, longestLength);
}();


package struct ErrorMessageTable
{
	enum uint longestMessageLength = errorMessageTableDefiner.longestLength;

	package static shared immutable(uint[BNKF2StatusCode.max + 1]) endOfMessageOffsets = errorMessageTableDefiner.endOfMessageOffsets;
	package static shared immutable messageTable = ()
	{
		char[endOfMessageOffsets[endOfMessageOffsets.length - 1]] table;

		foreach (index, message; errorMessageTableDefiner.messageFor)
		{
			size_t start = index != 0 ? endOfMessageOffsets[index - 1] : 0;
			size_t end = endOfMessageOffsets[index];
			table[start .. end - 1] = message[];
			table[end - 1] = '\0';
		}

		return table;
	}();

	pragma(inline, true)
	static shared(immutable(char))[] get (BNKF2StatusCode statusCode) @safe pure nothrow @nogc
	{
		size_t start = statusCode != 0 ? endOfMessageOffsets[statusCode - 1] : 0;
		size_t end = endOfMessageOffsets[statusCode];
		return messageTable[start .. end - 1];
	}
}


enum ubyte bnkF2ZipFileHostOS = 0xF2;


struct BNKF2MetadataFileContents
{
	enum string fileName = ".__bnkf2";

	struct V_
	{
		enum uint magic = 0x1BE1B1FA;

		uint signature;
		ubyte version_;
		ubyte[3] reserved;
	}

	struct V0
	{
		uint signature;
		ubyte version_;
		PackedState packedState;
		ubyte[2] reserved;

		struct PackedState
		{
			alias value this;

			ubyte value;

			enum Flags : ubyte
			{
				none = 0,
				bnkWasCompressed = 1 << 0
			}
		}
	}

	struct V1
	{
		alias v0 this;
		V0 v0;
		uint bnkVersion;
	}

	union
	{
		V_ v_;
		V0 v0;
		V1 v1;
	}
}


/+ Refer to https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT +/
struct Zip
{
	align(2)
	struct EndOfCentralDirectoryRecord
	{
		enum uint magic = 0x06054b50;
		uint signature;
		ushort diskNumber;
		ushort numberOfDiskThatContainsTheStartOfTheCentralDirectory;
		ushort entryCountOfDisk;
		ushort entryCountOfCentralDirectory;
		uint sizeOfCentralDirectory;
		uint offsetOfCentralDirectoryRelativeToDiskThatContainsIt;
		ushort commentLength;
		char[0] comment;

		static assert(EndOfCentralDirectoryRecord.sizeof == 22);
	}

	struct EndOfCentralDirectoryLocator64
	{
		enum uint magic = 0x07064b50;

		uint signature;
		uint numberOfDiskThatContainsTheStartOfTheEndOfCentralDirectoryRecord64;
	align(4)
		ulong offsetOfEndOfCentralDirectoryRecord64RelativeToDiskThatContainsIt;
		uint diskCount;

		static assert(EndOfCentralDirectoryLocator64.sizeof == 20);
	}

	struct EndOfCentralDirectoryRecord64
	{
		enum uint magic = 0x06064b50;

		uint signature;
	align(4)
		ulong sizeOfEndOfCentralDirectory64;
		ushort versionMadeBy;
		ushort versionRequiredForExtraction;
		uint diskNumber;
		uint numberOfDiskThatContainsTheStartOfTheCentralDirectory64;
		ulong entryCountOfDisk;
		ulong entryCountOfCentralDirectory64;
		ulong sizeOfCentralDirectory64;
		ulong offsetOfCentralDirectory64RelativeToDiskThatContainsIt;
		ubyte[0] extensibleDataSector;

		static assert(EndOfCentralDirectoryRecord64.sizeof == 56);
	}

	align(2)
	struct CentralDirectoryRecord
	{
		enum uint magic = 0x02014b50;

		uint signature;
		ushort versionMadeBy;
		ushort versionRequiredForExtraction;
		ushort bitFlags;
		ushort compressionMethod;
		ushort lastModificationTime;
		ushort lastModificationDate;
		uint crc32;
		uint compressedSize;
		uint uncompressedSize;
		ushort fileNameLength;
		ushort extraFieldLength;
		ushort comentLength;
		ushort diskNumber;
		ushort internalFileAttributes;
	align(2)
		uint externalFileAttributes;
	align(2)
		uint offsetOfLocalHeaderRelativeToDisk;
		char[0] fileName;
		ubyte[0] extraField;
		char[0] comment;

		static assert(CentralDirectoryRecord.sizeof == 46);
	}

	struct CentralDirectoryRecord64
	{
		alias record this;
		CentralDirectoryRecord record;
	align(2)
		ExtendedInformationExtraField64 _64;

		static assert(CentralDirectoryRecord64.sizeof == 78);
	}

	align(2)
	struct LocalFileHeader
	{
		enum uint magic = 0x04034b50;

		uint signature;
		ushort versionRequiredForExtraction;
		ushort bitFlags;
		ushort compressionMethod;
		ushort lastModificationTime;
		ushort lastModificationDate;
	align(2)
		uint crc32;
	align(2)
		uint compressedSize;
	align(2)
		uint uncompressedSize;
		ushort fileNameLength;
		ushort extraFieldLength;
		char[0] fileName;
		ubyte[0] extraField;

		static assert(LocalFileHeader.sizeof == 30);
	}

	struct LocalFileHeader64
	{
		alias header this;
		LocalFileHeader header;
	align(2)
		ExtendedInformationExtraField64 _64;

		static assert(LocalFileHeader64.sizeof == 62);
	}

	struct DataDescriptor
	{
		uint crc32;
		uint compressedSize;
		uint uncompressedSize;

		static assert(DataDescriptor.sizeof == 12);
	}

	struct DataDescriptor64
	{
		uint crc32;
	align(4)
		ulong compressedSize;
	align(4)
		ulong uncompressedSize;

		static assert(DataDescriptor64.sizeof == 20);
	}

	struct DataDescriptorWithSignature
	{
		enum uint magic = 0x08074b50;

		uint signature;
		DataDescriptor dataDescriptor;

		static assert(DataDescriptorWithSignature.sizeof == 16);
	}

	struct DataDescriptorWithSignature64
	{
		enum uint magic = 0x08074b50;

		uint signature;
		DataDescriptor64 dataDescriptor;

		static assert(DataDescriptorWithSignature64.sizeof == 24);
	}

	struct ExtraFieldHeader
	{
		ushort signature;
		ushort fieldSize;

		static assert(ExtraFieldHeader.sizeof == 4);
	}

	struct ExtendedInformationExtraField64
	{
		enum ushort magic = 0x0001;

		alias header this;

		ExtraFieldHeader header;
	align(4)
		ulong uncompressedFileSize;
	align(4)
		ulong compressedFileSize;
	align(4)
		ulong offsetOfLocalHeaderRelativeToDisk;
		uint numberOfDiskThatContainsTheStartOfTheFile;

		static assert(ExtendedInformationExtraField64.sizeof == 32);
	}
}


struct Unaligned (T)
{
	alias value this;
	align(1) T value;
}


Unaligned!T* unaligned (T) (scope T* address) @trusted pure nothrow @nogc
{
	return cast(typeof(return)) address;
}


struct BigEndian (T)
if (T.sizeof <= 8)
{
	T rawValue;

	static if (T.sizeof == 0)
	{
		alias rawValue this;
		alias value = rawValue;
	}
	else
	{
		version (BigEndian)
		{
			alias rawValue this;
			alias value = rawValue;
		}
		else
		{
			inout(T) value () inout return scope
			{
				auto swapped = endianSwap(*cast(const(UIntsFittingSizeOf[T.sizeof])*) &this.rawValue);
				return *cast(typeof(return)*) &swapped;
			}

			T value (return scope T newValue) return scope
			{
				this.rawValue = endianSwap(*cast(const(UIntsFittingSizeOf[T.sizeof])*) &newValue);
				return newValue;
			}

			alias value this;
		}
	}

	pragma(inline, true)
	static BigEndian fromLittleEndian (T value)
	{
		typeof(return) bigEndian;
		bigEndian.value = value;
		return bigEndian;
	}
}


alias UIntsFittingSizeOf = AliasSeq!(ubyte, ubyte, ushort, uint, uint, ulong, ulong, ulong, ulong);
alias IntsFittingSizeOf = AliasSeq!(byte, byte, short, int, int, long, long, long, long);


pragma(inline, true)
package ubyte swapByte () (ubyte value)
{
	return value;
}

/+ core.bitop.byteswap won't work for BetterC. +/
pragma(inline, true)
package Short swapShort (Short) (Short value)
if (is(Unqual!Short == ushort) || is(Unqual!Short == short))
{
	return cast(Short) (((value >> 8) & 0xFF) | ((value << 8) & 0xFF00));
}


alias endianSwap = swapByte!();
alias endianSwap = swapShort!ushort;
alias endianSwap = swapShort!short;
alias endianSwap = bswap;


pragma(inline, true)
auto ref lesserOf (A, B) (return scope auto ref A a, return scope auto ref B b)
{
	return a <= b ? a : b;
}


pragma(inline, true)
auto ref greaterOf (A, B) (return scope auto ref A a, return scope auto ref B b)
{
	return a >= b ? a : b;
}


pragma(inline, true)
ulong distributeIntoRange (uint bitCount = 64) (ulong value, ulong range)
if (bitCount <= 64)
in
{
	static if (bitCount < 64)
	{
		assert(value < (ulong(1) << bitCount));
		assert(range < (ulong(1) << bitCount));
	}
}
out (result; result < range)
{
	static if (bitCount == 64)
	{
		return multiplyWithHighHalfOf128BitProduct(value, range);
	}
	else static if (bitCount <= 32)
	{
		return distributeIntoRange!bitCount(cast(uint) value, cast(uint) range);
	}
	else
	{
		ulong hi;
		ulong lo = multiplyWith128BitProduct(value, range, &hi);

		enum uint lowHighBitsToTopShift = 64 - bitCount;

		return (hi << lowHighBitsToTopShift) | (lo >> bitCount);
	}
}


pragma(inline, true)
uint distributeIntoRange (uint bitCount = 32) (uint value, uint range)
if (bitCount <= 32)
in
{
	static if (bitCount < 32)
	{
		assert(value < (uint(1) << bitCount));
		assert(range < (uint(1) << bitCount));
	}
}
out (result; result < range)
{
	static if (bitCount <= 16)
	{
		return distributeIntoRange!bitCount(cast(ushort) value, cast(ushort) range);
	}
	else
	{
		return cast(uint) ((ulong(value) * range) >> bitCount);
	}
}


pragma(inline, true)
ushort distributeIntoRange (uint bitCount = 16) (ushort value, ushort range)
if (bitCount <= 16)
in
{
	static if (bitCount < 16)
	{
		assert(value < (ushort(1) << bitCount));
		assert(range < (ushort(1) << bitCount));
	}
}
out (result; result < range)
{
	static if (bitCount <= 8)
	{
		return distributeIntoRange!bitCount(cast(ubyte) value, cast(ubyte) range);
	}
	else
	{
		return cast(ushort) ((uint(value) * range) >> bitCount);
	}
}


pragma(inline, true)
ubyte distributeIntoRange (uint bitCount = 8) (ubyte value, ubyte range)
if (bitCount <= 8)
in
{
	static if (bitCount < 8)
	{
		assert(value < (ubyte(1) << bitCount));
		assert(range < (ubyte(1) << bitCount));
	}
}
out (result; result < range)
{
	return cast(ubyte) ((ushort(value) * range) >> bitCount);
}


pragma(inline, true)
Char asciiLowerCase (Char) (Char character) @safe pure nothrow @nogc
if (__traits(isScalar, Char) && !is(Char == __vector(C[size]), C, size_t size))
{
	Char isUpperCase = (character > '@') & (character <= 'Z');
	return cast(Char) (character | (isUpperCase << 5));
}

@safe pure nothrow @nogc unittest
{
	static void test (Char) ()
	{
		alias l = asciiLowerCase!Char;

		for (char character = '\0'; character < 'A'; ++character) assert(l(character) == character);
		for (char character = 'Z'; character++ < 255;) assert(l(character) == character);

		assert(l('A') == 'a'); assert(l('B') == 'b'); assert(l('C') == 'c');
		assert(l('D') == 'd'); assert(l('E') == 'e'); assert(l('F') == 'f');
		assert(l('G') == 'g'); assert(l('H') == 'h'); assert(l('I') == 'i');
		assert(l('J') == 'j'); assert(l('K') == 'k'); assert(l('L') == 'l');
		assert(l('M') == 'm'); assert(l('N') == 'n'); assert(l('O') == 'o');
		assert(l('P') == 'p'); assert(l('Q') == 'q'); assert(l('R') == 'r');
		assert(l('S') == 's'); assert(l('T') == 't'); assert(l('U') == 'u');
		assert(l('V') == 'v'); assert(l('W') == 'w'); assert(l('X') == 'x');
		assert(l('Y') == 'y'); assert(l('Z') == 'z');
	}

	test!char;
	test!wchar;
	test!dchar;
}


pragma(inline, true)
__vector(Char[vectorSize]) asciiLowerCase (Char, size_t vectorSize) (__vector(Char[vectorSize]) text) @trusted pure nothrow @nogc
if (__traits(isScalar, Char))
{

	enum uint byteWidth = 16;

	static assert(byteWidth % Char.sizeof == 0);

	alias Int = IntsFittingSizeOf[Char.sizeof];
	alias V = __vector(Int[byteWidth / Int.sizeof]);

	V lowerBound = '@';
	V upperBound = 'Z';
	V bitMask = 0b00100000;

	V chunk = cast(V) text;
	V lowerCaseBits = (bitMask & (chunk > lowerBound)) & (chunk <= upperBound);
	V lowerCase = chunk | lowerCaseBits;

	return cast(typeof(return)) lowerCase;
}


void asciiLowerCase (size_t alignment = 0, Char) (scope Char[] text) @trusted pure nothrow @nogc
{
	return asciiLowerCase!alignment(text, text);
}


void asciiLowerCase (size_t alignment = 0, SourceChar, DestinationChar) (
	scope SourceChar[] text,
	scope DestinationChar[] destination
) @trusted pure nothrow @nogc
if (is(SourceChar : DestinationChar))
in (destination.length >= text.length)
{
	if (__ctfe)
	{
		size_t remaining = text.length;
		SourceChar* from = text.ptr;
		DestinationChar* to = destination.ptr;

		while (remaining--)
		{
			*to++ = (*from++).asciiLowerCase;
		}
	}
	else
	{
		enum uint byteWidth = 16;

		static assert(byteWidth % SourceChar.sizeof == 0);

		size_t remaining = text.length;
		SourceChar* from = text.ptr;
		DestinationChar* to = destination.ptr;

		alias Int = IntsFittingSizeOf[SourceChar.sizeof];
		alias V = __vector(Int[byteWidth / Int.sizeof]);
	nextChunk:
		if (remaining < V.length)
		{
			goto scalarLoop;
		}

		to.storeVector(asciiLowerCase(loadVector!(V, alignment)(from)));

		from += V.length;
		to += V.length;
		remaining -= V.length;

		goto nextChunk;
	scalarLoop:
		while (remaining--)
		{
			*to++ = (*from++).asciiLowerCase;
		}
	}
}


@safe pure nothrow @nogc unittest
{
	char[34] text = "THIS IS SOME very VERY ANGRY TEXT.";

	asciiLowerCase(text[]);

	assert(text[] == "this is some very very angry text.");
}


package template defaultWatHashSecrets ()
{
	enum WatHashSecrets defaultWatHashSecrets = WatHashSecrets(
		[0x2d358dccaa6c78a5, 0x8bb84b93962eacc9, 0x4b33a62ed433d4a3, 0x4d5a2da51de1aa47]
	);
}


pragma(inline, true)
package ulong wathash (alias transform = void, Scalar) (
	scope const(Scalar)[] input
)
{
	return .wathash!(transform, Scalar)(input, 0);
}


pragma(inline, true)
package ulong wathash (alias transform = void, Scalar) (
	scope const(Scalar)[] input,
	ulong seed
)
{
	immutable secrets = defaultWatHashSecrets!();
	return .wathash!(transform, Scalar)(input, seed, secrets);
}


/++ wathash is a derivation of 王一 (Wang Yi)'s wyhash (final version 4.2, specifically).
    The name wathash is an obvious play on words, and is also a reference to Horrible Histories' Wat Tylor sketch.

    wathash differs from wyhash in that wathash fully passes SMHasher3's battery of tests.
    This is achieved by xoring the seed against the length of the input during the finalisation of the hash.
    An additional change is that one of the secrets used during the finalisation of the hash is selected according
    to the lowest 2-bits of the input's length, to eke out a smidgen more of entropy.

    Moreover, wathash's main loop processes the input in 64-byte chunks instead of 48-byte chunks,
    simplifying the logic needed to implement an incremental variant of wathash.
    To further that goal, the handling of the final 16-bytes of the input is the same regardless of what
    the input's length is, such that an incremental hasher doesn't need to handle the possibility of a torn
    read across the ends of a circular buffer to finalise its hash.

    Additionally, the order in which the input is read in the main loop is permuted to make the hashing
    theoretically more amenable to vectorisation; in practice, the need to load-and-store vectors from-and-to
    memory constantly causes vectorisation to be a loss rather than a gain.
    (So, like wyhash, wathash is not vectorised).

    Lastly, wathash prefetches the next cache-line at the beginning of its main loop, resulting in a
    minor yet measurable performance boost. +/
package ulong wathash (alias transform = void, Scalar) (
	scope const(Scalar)[] input,
	ulong seed,
	scope ref const(WatHashSecrets) secrets
) @trusted
if (__traits(isScalar, Scalar) && Scalar.sizeof <= 8)
{
	import core.bitop : bsr;

	enum s = Scalar.sizeof.bsr;

	pragma(inline, true)
	static ulong chunk (in const(ubyte)[8] data)
	{
		if (__ctfe)
		{
			return (
				  (ulong(data[0])      ) | (ulong(data[1]) <<  8) | (ulong(data[2]) << 16) | (ulong(data[3]) << 24)
				| (ulong(data[4]) << 32) | (ulong(data[5]) << 40) | (ulong(data[6]) << 48) | (ulong(data[7]) << 56)
			);
		}
		else
		{
			return *cast(const(Unaligned!ulong)*) data.ptr;
		}
	}

	pragma(inline, true)
	static uint quarter (in const(ubyte)[4] data)
	{
		if (__ctfe)
		{
			return uint(data[0]) | (uint(data[1]) << 8) | (uint(data[2]) << 16) | (uint(data[3]) << 24);
		}
		else
		{
			return *cast(const(Unaligned!uint)*) data.ptr;
		}
	}

	enum bool transforming = !is(transform == void);

	const(ubyte)[] data = (cast(const(ubyte)*) input.ptr)[0 .. input.length << s];

	static if (transforming)
	{
		align(64) ubyte[64] transformationBuffer;
		alias buffer = transformationBuffer;
	}
	else
	{
		alias buffer = data;
	}

	seed ^= mumxor(seed ^ secrets[0], secrets[1]);

	size_t totalLength = data.length;

	if (data.length >= 64)
	{
		ulong seed0 = seed;
		ulong seed1 = seed;
		ulong seed2 = seed;
		ulong seed3 = seed;

		do
		{
			prefetchData(data.ptr + 64);

			static if (transforming)
			{
				transform(
					(cast(const(Scalar)*) data.ptr)[0 .. 64 >> s],
					(cast(Scalar*) transformationBuffer.ptr)[0 .. 64 >> s]
				);
			}

			seed0 = mumxor(chunk(buffer[ 0 ..  8]) ^ secrets[0], chunk(buffer[32 .. 40]) ^ seed0);
			seed1 = mumxor(chunk(buffer[ 8 .. 16]) ^ secrets[1], chunk(buffer[40 .. 48]) ^ seed1);
			seed2 = mumxor(chunk(buffer[16 .. 24]) ^ secrets[2], chunk(buffer[48 .. 56]) ^ seed2);
			seed3 = mumxor(chunk(buffer[24 .. 32]) ^ secrets[3], chunk(buffer[56 .. 64]) ^ seed3);

			data = data[64 .. $];
		}
		while (data.length >= 64);

		seed = seed0 ^ seed1 ^ seed2 ^ seed3;
	}

	while (data.length > 16)
	{
		static if (transforming)
		{
			transform(
				(cast(const(Scalar)*) data.ptr)[0 .. 16 >> s],
				(cast(Scalar*) transformationBuffer.ptr)[0 .. 16 >> s]
			);
		}

		seed = mumxor(chunk(buffer[0 .. 8]) ^ secrets[1], chunk(buffer[8 .. 16]) ^ seed);

		data = data[16 .. $];
	}

	static if (transforming)
	{
		transform(
			(cast(const(Scalar)*) data.ptr)[0 .. data.length >> s],
			(cast(Scalar*) transformationBuffer.ptr)[0 .. data.length >> s]
		);
	}

	ulong a = 0;
	ulong b = 0;

	if (data.length >= 4)
	{
		size_t _0 = 0;
		size_t _1 = (data.length >> 3) << 2;
		size_t _2 = data.length - 4;
		size_t _3 = _2 - _1;

		a = (ulong(quarter(buffer[_0 .. _0 + 4][0 .. 4])) << 32) | quarter(buffer[_1 .. _1 + 4][0 .. 4]);
		b = (ulong(quarter(buffer[_2 .. _2 + 4][0 .. 4])) << 32) | quarter(buffer[_3 .. _3 + 4][0 .. 4]);
	}
	else if (data.length > 0)
	{
		a = ((ulong(buffer[0])) << 16) | ((ulong(buffer[$ >> 1])) << 8) | buffer[$ - 1];
	}

	a ^= secrets[totalLength & 0b11];
	b ^= seed ^ totalLength;
	mip(a, b);

	return mumxor(a ^ secrets[0] ^ totalLength, b ^ secrets[1]);
}


package struct WatHashSecrets
{
	alias values this;
	align(32) ulong[4] values;
}


/+ mip being short for "multiply in place". +/
pragma(inline, true)
package void mip (scope ref ulong a, scope ref ulong b)
{
	a = multiplyWith128BitProduct(a, b, &b);
}


/+ mum being short for "multiply mixup". +/
pragma(inline, true)
package ulong mumxor (ulong a, ulong b)
{
	mip(a, b);
	return a ^ b;
}


package alias multiplyWith128BitProduct = _multiplyWith128BitProduct!false;
package alias multiplyWithHighHalfOf128BitProduct = _multiplyWith128BitProduct!true;


pragma(inline, true)
package ulong _multiplyWith128BitProduct (bool returnOnlyHighHalf = false) (
	ulong low,
	ulong high,
	scope AliasSeq!(ulong*)[0 .. !returnOnlyHighHalf] highProduct
) @safe pure nothrow @nogc
{
	static if (__traits(compiles, _multiplyWith128BitProductViaHardware!returnOnlyHighHalf(low, high, highProduct)))
	{
		return _multiplyWith128BitProductViaHardware!returnOnlyHighHalf(low, high, highProduct);
	}
	else
	{
		return multiplyWithDoubleWidthProductViaSoftware!(ulong, returnOnlyHighHalf)(low, high, highProduct);
	}
}


package alias multiplyWith128BitProductViaSoftware = multiplyWithDoubleWidthProductViaSoftware!(ulong, false);
package alias multiplyWithHighHalfOf128BitProductViaSoftware = multiplyWithDoubleWidthProductViaSoftware!(ulong, true);


pragma(inline, true)
package I multiplyWithDoubleWidthProductViaSoftware (I, bool returnOnlyHighHalf = false) (
	I low,
	I high,
	scope AliasSeq!(I*)[0 .. !returnOnlyHighHalf] highProduct
) @safe pure nothrow @nogc
{
	enum uint halfWidth = I.sizeof << 2;
	enum I lowerHalf = (cast(I) ~I(0)) >>> halfWidth;

	auto first = low & lowerHalf;
	auto second = low >>> halfWidth;
	auto third = high & lowerHalf;
	auto fourth = high >>> halfWidth;

	I lowest = cast(I) (cast(I) first * cast(I) third);
	I lower = cast(I) (cast(I) first * cast(I) fourth);
	I higher = cast(I) (cast(I) second * cast(I) third);
	I highest = cast(I) (cast(I) second * cast(I) fourth);

	/+ A diagram of how this works (vaguely) for a 128-bit product from two 64-bit operands:

	   These 64-bit thirds get accumulated together from the 64-bit quarters.
	   ┌─────────top──────────┐
	              ┌─────────middle─────────┐
	                           ┌─────────bottom────────┐
	   ┌───────────────────────┐
	   │       highest         │
	   └───────────┬───────────┴───────────┐
	               │        higher         │
	               ├───────────────────────┤ <- These two get split between the resulting halves.
	               │         lower         │
	               └───────────┬───────────┴───────────┐
	                           │        lowest         │
	                           └───────────────────────┘
	   ├───────────┼───────────┼───────────┼───────────┤ bits
	    128         96          64          32          0
	   ┌───────────────────────┬───────────────────────┐
	   │          hi           │           lo          │
	   └───────────────────────┴───────────────────────┘ +/

	I middle = cast(I) ((higher & lowerHalf) + lower + (lowest >>> halfWidth));
	static if (!returnOnlyHighHalf) I bottom = cast(I) ((middle << halfWidth) + (lowest & lowerHalf));
	I top = cast(I) (highest + (higher >>> halfWidth) + (middle >>> halfWidth));

	static if (returnOnlyHighHalf)
	{
		return top;
	}
	else
	{
		*highProduct[0] = top;
		return bottom;
	}
}

@safe pure nothrow @nogc unittest
{
	/+ The mechanics used to get a double-width product from two operands are the same regardless
	   of the width.
	   So, if this works for 8x8->16-bit multiplication, it'll work for 64x64->128-bit multiplication. +/

	ubyte left = 0;
	ubyte right = 0;

	do
	{
		do
		{
			ushort expectedResult = left * right;

			ubyte hi = left;
			ubyte lo = right;
			lo = multiplyWithDoubleWidthProductViaSoftware!ubyte(lo, hi, &hi);

			assert(((ushort(hi) << 8) | lo) == expectedResult);

			assert(multiplyWithDoubleWidthProductViaSoftware!(ubyte, true)(left, right) == hi);

			++right;
		}
		while (right != 0);

		++left;
	}
	while (left != 0);
}


pragma(inline, true)
package ulong _multiplyWith128BitProductViaHardware (bool returnOnlyHighHalf = false) (
	ulong low,
	ulong high,
	scope AliasSeq!(ulong*)[0 .. !returnOnlyHighHalf] highProduct
) @safe pure nothrow @nogc
{
	if (__ctfe)
	{
		return multiplyWithDoubleWidthProductViaSoftware!(ulong, returnOnlyHighHalf)(low, high, highProduct);
	}
	else
	{
		version (LDC)
		{
			version (LDC_LLVM_OpaquePointers) enum ptr = "ptr "; else enum ptr = "i64*";

			ulong lo = low;
			ulong hi = high;

			__ir_pure!(
				"%a = load i64, " ~ ptr ~ " %0
				 %b = load i64, " ~ ptr ~ " %1

				 %aa = zext i64 %a to i128
				 %bb = zext i64 %b to i128

				 %product = mul i128 %aa, %bb

				" ~ (returnOnlyHighHalf ? "" : "%lo = trunc i128 %product to i64\n")

				~ "%hi128 = lshr i128 %product, 64
				 %hi = trunc i128 %hi128 to i64

				" ~ (returnOnlyHighHalf ? "" : "store i64 %lo, " ~ ptr ~ " %0\n")
				~ "store i64 %hi, " ~ ptr ~ " %1",
				void
			)(&lo, &hi);

			static if (returnOnlyHighHalf)
			{
				return hi;
			}
			else
			{
				*highProduct[0] = hi;
				return lo;
			}
		}
		else version (GNU)
		{
			version (X86_64_Or_AArch64)
			{
				ulong lo = void;
				ulong hi = void;

				version (X86_64)
				{
					enum p = ".intel_syntax noprefix\n\t";
					enum s = "\n\t.att_syntax prefix";

					/+ If we have PEXT, then the target has BMI2, ergo we can use MULX. +/
					static if (__traits(compiles, () {import gcc.builtins : __builtin_ia32_pext_si;}))
					{
						asm @trusted pure nothrow @nogc
						{
							  p ~ "mulx %1, %0, %3" ~ s
							: "=r" (lo), "=r" (hi)
							: "%d" (low), "rm" (high);
						}
					}
					else
					{
						asm @trusted pure nothrow @nogc
						{
							  p ~ "mul %3" ~ s
							: "=a" (lo), "=d" (hi)
							: "%0" (low), "rm" (high)
							: "cc";
						}
					}
				}
				else version (AArch64)
				{
					static if (!returnOnlyHighHalf)
					{
						asm @trusted pure nothrow @nogc
						{
							  "mul %0, %1, %2"
							: "=r" (lo)
							: "%r" (low), "r" (high);
						}
					}

					asm @trusted pure nothrow @nogc
					{
						  "umulh %0, %1, %2"
						: "=r" (hi)
						: "%r" (low), "r" (high);
					}
				}
				else
				{
					static assert(false);
				}

				static if (returnOnlyHighHalf)
				{
					return hi;
				}
				else
				{
					*highProduct[0] = hi;
					return lo;
				}
			}
			else
			{
				static assert(false, "multiplyWith128BitProductViaHardware has not been implemented for this target.");
			}
		}
		else version (D_InlineAsm_X86_64)
		{
			version (Win64)
			{
				static if (returnOnlyHighHalf)
				{
					enum string lowOperand = "RDX";
					enum string highOperand = "RCX";
					enum string highHalfDestination = "RAX";
				}
				else
				{
					enum string lowOperand = "R8";
					enum string highOperand = "RDX";
					enum string highHalfDestination = "[RCX]";
				}
			}
			else
			{
				static if (returnOnlyHighHalf)
				{
					enum string lowOperand = "RSI";
					enum string highOperand = "RDI";
					enum string highProductOperand = "RAX";
				}
				else
				{
					enum string lowOperand = "RDX";
					enum string highOperand = "RSI";
					enum string highProductOperand = "[RDI]";
				}
			}

			mixin(
				"asm @trusted pure nothrow @nogc
				 {
				 	naked;
				 	mov RAX, " ~ lowOperand ~ ";
				 	mul " ~ highOperand ~ ";
				 	mov " ~ highHalfDestination ~ ", RDX;
				 	ret;
				 }"
			);
		}
		else
		{
			static assert(false, "multiplyWith128BitProductViaHardware has not been implemented for this target.");
		}
	}
}


pragma(inline, true)
void prefetchData (uint distance = 0) (scope const(void)* address) @safe pure nothrow @nogc
if (distance <= 3)
{
	if (__ctfe)
	{}
	else
	{
		version (LDC)
		{
			import ldc.intrinsics : llvm_prefetch;

			llvm_prefetch(address, 0, distance ^ 3, 1);
		}
	}
}


pragma(inline, true)
I alignUpTo (I, A) (I offset, A alignment)
if (!is(I : P*, P))
in (alignment > 0)
in (alignment <= I.max)
{
	return offset.roundUpToMultipleOfPowerOfTwo(cast(I) alignment);
}


pragma(inline, true)
T* alignUpTo (T) (T* pointer, size_t alignment = T.alignof) @trusted
in (alignment > 0)
{
	return cast(T*) alignUpTo(cast(size_t) pointer, alignment);
}


pragma(inline, true)
I roundUpToMultipleOfPowerOfTwo (I) (I value, I factor)
in (factor > 0)
out (result; result >= value)
{
	return cast(I) ((value + factor - 1) & ~(factor - 1));
}


struct RawSlice (Slice)
{
	alias slice this;

	union
	{
		Slice slice;
		Raw raw;
	}

	struct Raw
	{
		size_t length;
		typeof(Slice.ptr) ptr;
	}
}


pragma(inline, true)
bool bitEqual (alias transform = void, T) (scope const(T)* a, scope const(T)* b, size_t length) @system pure nothrow @nogc
if (__traits(isScalar, T))
in ((cast(size_t) a & (T.alignof - 1)) == 0)
in ((cast(size_t) b & (T.alignof - 1)) == 0)
{
	enum bool transforming = !is(transform == void);

	static if (transforming)
	{
		enum string examine (string expression) = `transform(` ~ expression ~ `)`;
	}
	else
	{
		enum string examine (string expression) = `(` ~ expression ~ `)`;
	}

	if (__ctfe)
	{
		foreach (index; 0 .. length)
		{
			if (mixin(examine!q{a[index]}) !is mixin(examine!q{b[index]}))
			{
				return false;
			}
		}

		return true;
	}
	else
	{
		version (X86_64_Or_X86)
		{
			alias V = __vector(byte[16]);

			V allEqual = -1;

			size_t offset = 0;
			size_t remaining = length;

			for (; remaining >= 16; remaining -= 16)
			{
				V aa = loadVector!V(cast(const(byte)*) a + offset);
				V bb = loadVector!V(cast(const(byte)*) b + offset);

				if (mixin(examine!q{aa}) !is mixin(examine!q{bb}))
				{
					return false;
				}

				offset += 16;
			}

			for (; remaining != 0; --remaining)
			{
				if (mixin(examine!q{a[offset]}) !is mixin(examine!q{b[offset]}))
				{
					return false;
				}

				++offset;
			}

			return true;
		}
		else
		{
			foreach (index; 0 .. length)
			{
				if (mixin(examine!q{a[index]}) !is mixin(examine!q{b[index]}))
				{
					return false;
				}
			}

			return true;
		}
	}
}


pragma(inline, true)
size_t blit (T) (scope T* destination, scope const(T)* source, size_t length) @system pure nothrow @nogc
in ((cast(size_t) destination & (T.alignof - 1)) == 0)
in ((cast(size_t) source & (T.alignof - 1)) == 0)
{
	version (X86_64_Or_X86)
	{
		static if (T.alignof >= 4)
		{
			repMovs(cast(uint*) destination, cast(const(uint)*) source, length * (T.sizeof >> 2));
		}
		else
		{
			repMovs(cast(ubyte*) destination, cast(const(ubyte)*) source, length * T.sizeof);
		}
	}
	else
	{
		static if (T.alignof >= 8)
		{
			enum uint shift = 3;
			alias Chunk = ulong;
		}
		else static if (T.alignof >= 4)
		{
			enum uint shift = 2;
			alias Chunk = uint;
		}
		else
		{
			enum uint shift = 0;
			alias Chunk = ubyte;
		}

		foreach (index; 0 .. length * (T.sizeof >> shift))
		{
			(cast(Chunk*) destination)[index] = (cast(const(Chunk)*) source)[index];
		}
	}

	return length;
}


pragma(inline, true)
size_t blit (T) (scope T* destination, scope const(T)* source) @trusted pure nothrow @nogc
in ((cast(size_t) destination & (T.alignof - 1)) == 0)
in ((cast(size_t) source & (T.alignof - 1)) == 0)
{
	version (X86_64_Or_X86)
	{
		static if (T.alignof >= 4)
		{
			repMovs(cast(uint*) destination, cast(const(uint)*) source, T.sizeof >> 2);
		}
		else
		{
			repMovs(cast(ubyte*) destination, cast(const(ubyte)*) source, T.sizeof);
		}
	}
	else
	{
		static if (T.alignof >= 8)
		{
			enum uint shift = 3;
			alias Chunk = ulong;
		}
		else static if (T.alignof >= 4)
		{
			enum uint shift = 2;
			alias Chunk = uint;
		}
		else
		{
			enum uint shift = 0;
			alias Chunk = ubyte;
		}

		foreach (index; 0 .. T.sizeof >> shift)
		{
			(cast(Chunk*) destination)[index] = (cast(const(Chunk)*) source)[index];
		}
	}

	return T.sizeof;
}


pragma(inline, true)
void zeroOut (T) (scope T* values, size_t length) @system pure nothrow @nogc
in ((cast(size_t) values & (T.alignof - 1)) == 0)
{
	version (X86_64_Or_X86)
	{
		static if (T.alignof >= 4)
		{
			repStos(cast(uint*) values, 0, length * (T.sizeof >> 2));
		}
		else
		{
			repStos(cast(ubyte*) values, 0, length * T.sizeof);
		}
	}
	else
	{
		static if (T.alignof >= 8)
		{
			enum uint shift = 3;
			alias Chunk = ulong;
		}
		else static if (T.alignof >= 4)
		{
			enum uint shift = 2;
			alias Chunk = uint;
		}
		else
		{
			enum uint shift = 0;
			alias Chunk = ubyte;
		}

		foreach (index; 0 .. length * (T.sizeof >> shift))
		{
			(cast(Chunk*) values)[index] = 0;
		}
	}
}


pragma(inline, true)
void zeroOut (T) (scope T* value) @trusted pure nothrow @nogc
in ((cast(size_t) value & (T.alignof - 1)) == 0)
{
	version (X86_64_Or_X86)
	{
		static if (T.alignof >= 4)
		{
			repStos(cast(uint*) value, 0, T.sizeof >> 2);
		}
		else
		{
			repStos(cast(ubyte*) value, 0, T.sizeof);
		}
	}
	else
	{
		static if (T.alignof >= 8)
		{
			enum uint shift = 3;
			alias Chunk = ulong;
		}
		else static if (T.alignof >= 4)
		{
			enum uint shift = 2;
			alias Chunk = uint;
		}
		else
		{
			enum uint shift = 0;
			alias Chunk = ubyte;
		}

		foreach (index; 0 .. T.sizeof >> shift)
		{
			(cast(Chunk*) value)[index] = 0;
		}
	}
}


V loadVector (V, size_t alignment = 0, E) (scope const(E)* address)
if (alignment == 0)
{
	if (__ctfe)
	{
		return *cast(const(V)*) address;
	}

	static if ((alignment != 0 ? alignment : E.alignof) >= V.alignof)
	{
		return *cast(const(V)*) address;
	}
	else
	{
		version (LDC)
		{
			return loadUnaligned!V(cast(const(typeof(V.array[0]))*) address);
		}
		else
		{
			return loadUnaligned(cast(const(V)*) address);
		}
	}
}


void storeVector (V, size_t alignment = 0, E) (scope E* address, V value)
if (is(Unqual!E == E) && alignment == 0)
{
	if (__ctfe)
	{
		*cast(Unqual!V*) address = value;
	}

	static if ((alignment != 0 ? alignment : E.alignof) >= V.alignof)
	{
		*cast(Unqual!V*) address = value;
	}
	else
	{
		version (LDC)
		{
			storeUnaligned!V(value, cast(Unqual!(typeof(V.array[0]))*) address);
		}
		else
		{
			storeUnaligned(cast(Unqual!V*) address, value);
		}
	}
}


version (X86_64_Or_X86)
{
	extern(C)
	pragma(inline, true)
	void repMovs (T) (scope T* destination, scope const(T)* source, size_t length) @system pure nothrow @nogc
	{
		import core.bitop : bsr;

		if (__ctfe)
		{
			foreach (index; 0 .. length)
			{
				destination[index] = source[index];
			}
		}
		else
		{
			enum size = T.sizeof.bsr;

			version (LDC)
			{
				import ldc.llvmasm : __ir_pure;

				enum char suffix = "bwlq"[size];
				enum dataType = ["i8", "i16", "i32", "i64"][size];
				enum ptr = llvmIRPtr!dataType;
				enum lengthType = ["i8", "i16", "i32", "i64"][size_t.sizeof.bsr];

				version (X86)
				{
					enum indexPrefix = 'e';
				}
				else version (X86_64)
				{
					enum indexPrefix = 'r';
				}

				__ir_pure!(
					`call {` ~ ptr ~ `, ` ~ ptr ~ `, ` ~ lengthType ~ `} asm
					 "rep movs` ~ suffix ~ `",
					 "=&{` ~ indexPrefix ~ `di},=&{` ~ indexPrefix ~ `si},=&{ecx},0,1,2,~{memory}"
					 (` ~ ptr ~ ` %0, ` ~ ptr ~ ` %1, ` ~ lengthType ~ ` %2)`,
					void
				)(destination, source, length);
			}
			else version (GNU)
			{
				enum char suffix = "bwlq"[size];

				asm @system pure nothrow @nogc
				 {
				 	  "rep movs" ~ suffix
				 	: "+&D" (destination), "+&S" (source), "+&c" (length)
				 	: "0" (destination), "1" (source), "2" (length)
				 	: "memory";
				 }
			}
			else version (InlineAsm_X86_64_Or_X86)
			{
				enum char suffix = "bwdq"[size];

				version (D_InlineAsm_X86_64)
				{
					mixin(
						"asm @system pure nothrow @nogc
						 {
						 	/* RCX is destination; RDX is source; R8 is length. */
						 	naked;
						 	mov R9, RDI; /* RDI is non-volatile, so we save it in R9. */
						 	mov RAX, RSI; /* RSI is non-volatile, so we save it in RAX. */
						 	mov RDI, RCX;
						 	mov RCX, R8;
						 	mov RSI, RDX;
						 	rep; movs" ~ suffix ~ ";
						 	mov RSI, RAX;
						 	mov RDI, R9;
						 	ret;
						 }"
					);
				}
				else version (D_InlineAsm_X86)
				{
					mixin(
						"asm @system pure nothrow @nogc
						 {
						 	naked;
						 	mov EAX, EDI; /* EDI is non-volatile, so we save it in EAX. */
						 	mov EDX, ESI; /* ESI is non-volatile, so we save it in EDX. */
						 	mov EDI, [ESP +  4]; /* destination. */
						 	mov ESI, [ESP +  8]; /* source. */
						 	mov ECX, [ESP + 12]; /* length. */
						 	rep; movs" ~ suffix ~ ";
						 	mov ESI, EDX;
						 	mov EDI, EAX;
						 	ret;
						 }"
					);
				}
			}
		}
	}

	@safe pure nothrow @nogc unittest
	{
		static bool test (alias I, alias movs)()
		{
			I[8] memory = [I.max, I.max - 1, 2, 3, 4, 5, 6, 7];

			((d, s) @trusted => movs(d, s, 4))(&memory[3], &memory[2]);
			assert(memory == [I.max, I.max - 1, 2, 2, 2, 2, 2, 7]);

			((d, s) @trusted => movs(d, s, 2))(&memory[0], &memory[6]);
			assert(memory == [2, 7, 2, 2, 2, 2, 2, 7]);

			return true;
		}

		assert(test!(ubyte, repMovs));
		static assert(test!(ubyte, repMovs));
		assert(test!(ushort, repMovs));
		static assert(test!(ushort, repMovs));
		assert(test!(uint, repMovs));
		static assert(test!(uint, repMovs));

		version (X86_64)
		{
			assert(test!(ulong, repMovs));
			static assert(test!(ulong, repMovs));
		}
	}


	extern(C)
	pragma(inline, true)
	void repStos (I) (scope I* destination, I data, size_t length) @system pure nothrow @nogc
	{
		if (__ctfe)
		{
			foreach (index; 0 .. length)
			{
				destination[index] = data;
			}
		}
		else
		{
			import core.bitop : bsr;

			enum size = I.sizeof.bsr;

			version (LDC)
			{
				import ldc.llvmasm : __ir_pure;

				enum char suffix = "bwlq"[size];
				enum type = ["i8", "i16", "i32", "i64"][size];

				version (X86)
				{
					enum string lengthType = "i32";
					enum a = "eax";
					enum c = "ecx";
					enum di = "edi";
				}
				else version (X86_64)
				{
					enum string lengthType = "i64";
					enum a = "rax";
					enum c = "rcx";
					enum di = "rdi";
				}

				__ir_pure!(
					`call {` ~ llvmIRPtr!type ~ `, ` ~ lengthType ~ `} asm
					 "rep stos` ~ suffix ~ `",
					 "=&{` ~ di ~ `},=&{` ~ c ~ `},0,{` ~ a ~ `},1,~{memory}"
					 (` ~ llvmIRPtr!type ~ ` %0, ` ~ type ~ ` %1, ` ~ lengthType ~ ` %2)`,
					void
				)(
					destination,
					data,
					length
				);
			}
			else version (GNU)
			{
				enum char suffix = "bwlq"[size];

				asm pure nothrow @nogc
				{
					  "rep stos" ~ suffix
					: "+&D" (destination), "+&c" (length)
					: "0" (destination), "1" (length), "a" (data)
					: "memory";
				}
			}
			else version (InlineAsm_X86_64_Or_X86)
			{
				enum char suffix = "bwdq"[size];

				version (D_InlineAsm_X86_64)
				{
					mixin(
						"asm pure nothrow @nogc
						 {
						 	/* RCX is destination; *D* is data; R8 is length. */
						 	naked;
						 	mov R9, RDI; /* RDI is non-volatile, so we save it in R9. */
						 	mov RDI, RCX;
						 	mov RAX, RDX;
						 	mov RCX, R8;
						 	rep; stos" ~ suffix ~ ";
						 	mov RDI, R9;
						 	ret;
						 }"
					);
				}
				else version (D_InlineAsm_X86)
				{
					mixin(
						"asm pure nothrow @nogc
						 {
						 	naked;
						 	mov EDX, EDI; /* EDI is non-volatile, so we save it in EDX. */
						 	mov EDI, [ESP +  4]; /* destination. */
						 	mov EAX, [ESP +  8]; /* data. */
						 	mov ECX, [ESP + 12]; /* length. */
						 	rep; stos" ~ suffix ~ ";
						 	mov EDI, EDX;
						 	ret;
						 }"
					);
				}
			}
		}
	}

	@safe pure nothrow @nogc unittest
	{
		static bool test(alias I, alias stos)()
		{
			I[8] memory = [I.max, I.max - 1, 2, 3, 4, 5, 6, 7];
			((m) @trusted => stos(m, 8, 4))(&memory[1]);

			assert(memory == [I.max, 8, 8, 8, 8, 5, 6, 7]);

			return true;
		}

		assert(test!(ubyte, repStos!ubyte));
		static assert(test!(ubyte, repStos!ubyte));
		assert(test!(ushort, repStos!ushort));
		static assert(test!(ushort, repStos!ushort));
		assert(test!(uint, repStos!uint));
		static assert(test!(uint, repStos!uint));

		version (X86_64)
		{
			assert(test!(ulong, repStos!ulong));
			static assert(test!(ulong, repStos!ulong));
		}
	}
}


version (LDC)
{
	template llvmIRPtr (string type, string postfix = null)
	{
		version (LDC_LLVM_OpaquePointers)
		{
			enum llvmIRPtr = postfix is null ? "ptr" : "ptr " ~ postfix;
		}
		else
		{
			enum llvmIRPtr = postfix is null ? type ~ "*" : type ~ " " ~ postfix ~ "*";
		}
	}
}


enum uint FILE_ATTRIBUTE_NORMAL = 0x80;
enum uint FILE_ATTRIBUTE_DIRECTORY = 0x10;


enum uint S_IFDIR = 0x4000;


version (Windows)
{
	extern(Windows) uint GetLastError () @safe nothrow @nogc;
}

