
/+ SPDX-LICENSE-IDENTIFIER: 0BSD +/

module bnkf2.exports;

import core.bitop : bswap;
import core.simd;
import std.meta : AliasSeq;
import std.system : Endian, endian;
import std.traits : Unqual;

import zlib;

/+ Anything that isn't an honest-to-God export lives in `bnkf2.core`.
   The exports are here.
   This separation is to make dynamic linking easier. +/
import bnkf2.core;


extern(System)
export BNKF2Status bnkf2_bnkToZip (
	scope void* context,
	scope const(ubyte)[]* inputBuffer,
	scope ContiguousOutputBufferFlusher outputFlusher,
	scope BNKToZipState* state
)
{
	alias V = __vector(byte[16]);

	static struct UncompressedSpan
	{
		uint offset;
		uint length;
	}

	static assert(UncompressedSpan.sizeof == BNK.UncompressedFileTableEntry.DataSpan.sizeof);

	static struct PerFileData
	{
		uint uncompressedSize;
		uint crc32;
	}

	if (state.version_ != 0)
	{
		return BNKF2Status.status(BNKF2StatusCode.unrecognisedStructureVersion);
	}

	state.extendedReturnChannel.v0.packedState = 0;
	state.extendedReturnChannel.v0.bnkVersion = 0;

	const(ubyte)* input = inputBuffer.ptr;
	size_t inputLength = inputBuffer.length;
	size_t remaining = inputLength;

	if (remaining > uint.max)
	{
		return BNKF2Status.status(BNKF2StatusCode.inputIsTooLong);
	}

	BNKF2Status ultimateStatus = void;

	ubyte* output = null;
	size_t outputOffset = 0;
	size_t outputSpace = outputFlusher(context, &output, output, outputOffset);

	if (output == null)
	{
		return BNKF2Status.caller(cast(uint) outputSpace);
	}

	/+ BNK files are limited to 4GB, but a zip file has larger metadata
	   than its equivalent BNK file, so we may need to emit a Zip64™ file.
	   And, much more likely than the zip ending up larger than 4GB,
	   a BNK file can contain more than 65,536 files.
	   (Though for us it's more of a Zip40 file.) +/
	ulong zipOffset = 0;

	/+ Boy, I really love D's `Error: `goto` skips declaration of variable`.
	   For, I really yearn for the ergonomics of C-fucking-89. +/
	bool asVersion3BNK = void;
	Unaligned!(const(BNK.FileHeader))* bnkFileHeader = void;
	Unaligned!(const(BNK.FileHeaderV2))* bnkFileHeaderV2 = void;
	Unaligned!(const(BNK.FileHeaderV3))* bnkFileHeaderV3 = void;
	uint bnkVersion = void;
	uint bnkDataOffset = void;
	uint compressedHeaderSize = void;
	uint uncompressedHeaderSize = void;
	uint totalUncompressedHeaderSize = void;
	uint fileTableChunkCount = void;
	uint remainingFileTableChunks = void;
	bool bnkIsCompressed = void;
	uint fileCount = void;
	uint emittedFileCount = void;
	ubyte* fileTableBuffer = void;
	size_t initialContinuationOffset = void;
	size_t continuationOffset = void;
	uint continuationCompressedSize = void;
	uint continuationUncompressedSize = void;
	Unaligned!(const(BNK.FileTableContinuationHeader))* continuationHeader = void;
	void* fileMetadataBuffer = void;
	PerFileData* perFileDataBuffer = void;
	ubyte* fileEmissionBitMap = void;
	ubyte* fileNameHashTable = void;
	uint fileNameHashTableSize = void;
	z_stream zlibStream = void;
	typeof(zlibStream.avail_in) previousAvailIn = void;
	int zlibStatus = void;
	uint fileTableBufferSize = void;
	ubyte* fileTable = void;
	size_t fileTableSize = void;
	size_t remainingInFileTable = void;
	uint crc32Seed = void;
	uint runningCRC32 = void;
	uint bnkf2MetadataCRC32 = void;
	V backSlashVector = void;
	V forwardSlashVector = void;
	V slashSwapDeltaVector = void;
	const(ubyte)* bnkData = void;
	size_t bnkDataLength = void;
	uint remainingFileCount = void;
	uint fileIndex = void;
	uint nameLength = void;
	uint remainingNameLength = void;
	bool nameIsNullTerminated = void;
	ulong hashOfName = void;
	const(char)[] nameSlice = void;
	Unaligned!(BNK.UncompressedFileTableEntry.DataSpan)* dataSpan = void;
	UncompressedSpan span = void;
	uint compressedFileSize = void;
	uint compressedFileChunkCount = void;
	const(Unaligned!(BigEndian!uint))* compressedChunkCountPointer = void;
	uint compressedChunkUncompressedSizesCopiedToExtraFieldSize = void;
	uint extraFieldLength = void;
	ubyte* namePointer = void;
	Unaligned!uint* nameLengthPointer = void;
	size_t splitOffset = void;
	size_t splitLength = void;
	ubyte* decompressionBuffer = void;
	size_t decompressionBufferSize = void;
	Zip.LocalFileHeader localFileHeader = void;
	ulong offsetOfZipCentralDirectory = void;
	uint adornedNameLength = void;
	ubyte zipOffsetHighByte = void;
	bool has32BitOffset = void;
	Zip.CentralDirectoryRecord64 centralDirectoryRecord = void;
	size_t centralDirectoryRecordSize = void;
	ulong sizeOfCentralDirectory = void;
	bool has32BitFooter = void;
	Zip.EndOfCentralDirectoryRecord endOfCentralDirectoryRecord = void;

	enum string fail (string failureStatus) =
	`
		*inputBuffer = input[inputBuffer.length - remaining .. inputBuffer.length];
		ultimateStatus = (` ~ failureStatus ~ `);
	`;

	enum string consume (string length, string failureTarget, string remainingBytes = q{remaining}) =
	`
		if ((` ~ length ~ `) > (` ~ remainingBytes ~ `))
		{
			mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.inputIsTruncated)});
			goto ` ~ failureTarget ~ `;
		}

		` ~ remainingBytes ~ ` -= (` ~ length ~ `);
	`;

	enum string reportProgress (string opcode, string operand0, string operand1) =
	`
		if (state.progressObserver !is null)
		{
			state.progressObserver(
				state.progressObserver.context,
				BNKToZipProgressOpcode.` ~ opcode ~ `,
				` ~ operand0 ~ `,
				` ~ operand1 ~ `
			);
		}
	`;

	mixin(consume!(q{BNK.FileHeader.sizeof}, q{failedWithOutputBuffer}));

	bnkFileHeader = unaligned(cast(const(BNK.FileHeader)*) input);
	bnkVersion = bnkFileHeader.version_;

	state.extendedReturnChannel.v0.packedState |= state.extendedReturnChannel.v0.packedState.Flags.bnkVersionIsKnown;
	state.extendedReturnChannel.v0.bnkVersion = bnkVersion;

	if (bnkVersion == 2)
	{
		mixin(consume!(q{BNK.FileHeaderV2.sizeof - BNK.FileHeader.sizeof}, q{failedWithOutputBuffer}));

		asVersion3BNK = false;
		bnkFileHeaderV2 = unaligned(cast(const(BNK.FileHeaderV2)*) input);

		bnkIsCompressed = bnkFileHeaderV2.filesAreCompressed != 0;
	}
	else
	{
		mixin(consume!(q{BNK.FileHeaderV3.sizeof - BNK.FileHeader.sizeof}, q{failedWithOutputBuffer}));

		asVersion3BNK = true;
		bnkFileHeaderV3 = unaligned(cast(const(BNK.FileHeaderV3)*) input);

		bnkIsCompressed = bnkFileHeaderV3.filesAreCompressed != 0;
	}

	state.extendedReturnChannel.v0.packedState |= state.extendedReturnChannel.v0.packedState.Flags.bnkCompressionStatusIsKnown;
	state.extendedReturnChannel.v0.packedState |= (
		bnkIsCompressed ? state.extendedReturnChannel.v0.packedState.Flags.bnkWasCompressed : 0
	);

	bnkDataOffset = bnkFileHeader.offset;

	if (bnkDataOffset > inputLength)
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.outOfBoundsDataOffsetInBNK)});
		goto failedWithOutputBuffer;
	}

	if (asVersion3BNK)
	{
		initialContinuationOffset = BNK.FileHeaderV3.compressedHeaderSize.offsetof;
		bnkDataLength = inputLength - bnkDataOffset;
	}
	else
	{
		mixin(consume!(q{BNK.FileTableContinuationHeader.sizeof}, q{failedWithOutputBuffer}));
		mixin(consume!(q{bnkDataOffset}, q{failedWithOutputBuffer}));
		initialContinuationOffset = bnkDataOffset;
		bnkDataOffset = BNK.FileHeaderV2.fileData.offsetof;
		bnkDataLength = initialContinuationOffset - bnkDataOffset;
	}

	continuationOffset = initialContinuationOffset;

	continuationHeader = cast(Unaligned!(const(BNK.FileTableContinuationHeader))*) (input + continuationOffset);

	compressedHeaderSize = continuationHeader.compressedSize;

	mixin(consume!(q{compressedHeaderSize}, q{failedWithOutputBuffer}));

	decompressionBuffer = null;
	decompressionBufferSize = 0;

	if (compressedHeaderSize == 0)
	{
		fileCount = 0;
		emittedFileCount = 0;
		fileTableBuffer = null;
		fileMetadataBuffer = null;
		offsetOfZipCentralDirectory = 0;
		goto beginWritingZipFooter;
	}

	mixin(reportProgress!(q{decompressingFileTable}, q{null}, q{0}));

	/+ A BNK file's file-table is a singly-linked-list of compressed chunks.
	   So, we'll scan ahead to get the complete size. +/

	fileTableChunkCount = 1;
	uncompressedHeaderSize = continuationHeader.uncompressedSize;
	totalUncompressedHeaderSize = uncompressedHeaderSize;

	if (compressedHeaderSize != 0)
	{
		bool shouldContinue = true;

		continuationCompressedSize = compressedHeaderSize;
		continuationOffset += BNK.FileTableContinuationHeader.sizeof;
	windThroughCompressedHeaders:
		if (ulong(continuationOffset) + continuationCompressedSize + BNK.FileTableContinuationHeader.sizeof > inputLength)
		{
			if (asVersion3BNK | (ulong(continuationOffset) + continuationCompressedSize > inputLength))
			{
				mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.inputIsTruncated)});
				goto failedWithOutputBuffer;
			}

			/+ V2 BNK file-tables are implicitly terminated by the end-of-the-file. +/
			shouldContinue = false;
		}

		continuationOffset += continuationCompressedSize;
		continuationHeader = cast(Unaligned!(const(BNK.FileTableContinuationHeader))*) (input + continuationOffset);
		continuationOffset += BNK.FileTableContinuationHeader.sizeof;

		continuationCompressedSize = continuationHeader.compressedSize;
		continuationUncompressedSize = continuationHeader.uncompressedSize;

		if (totalUncompressedHeaderSize > uint.max - continuationUncompressedSize)
		{
			mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.impossiblyLargeFileTableInBNK)});
			goto failedWithOutputBuffer;
		}

		totalUncompressedHeaderSize += continuationUncompressedSize;

		if ((continuationCompressedSize != 0) & shouldContinue)
		{
			++fileTableChunkCount;
			goto windThroughCompressedHeaders;
		}
	}

	fileTableBufferSize = greaterOf(totalUncompressedHeaderSize.alignUpTo(minimumPageSize), cast(uint) minimumPageSize);

	previousAvailIn = 0;

	zlibStream.zalloc = null;
	zlibStream.zfree = null;
	zlibStream.opaque = null;

	if (state.packedState & state.packedState.Flags.forwardAllocatorToZLib)
	{
		zlibStream.zalloc = &state.memoryAllocators.zlibAllocate;
		zlibStream.zfree = &state.memoryAllocators.zlibFree;
		zlibStream.opaque = &state.memoryAllocators;
	}

	/+ We have to do two passes of the file-table to write the zip-file's
	   central directory records, so we read the file-table in full
	   rather than streaming it.
	   We'll allocate only once so long as the header isn't lying about its size. +/
beginDecompressingFileTable:
	remainingFileTableChunks = fileTableChunkCount;

	continuationOffset = initialContinuationOffset + BNK.FileTableContinuationHeader.sizeof;
	continuationCompressedSize = compressedHeaderSize;

	zlibStream.next_in = input + continuationOffset;
	zlibStream.avail_in = compressedHeaderSize;

	if ((zlibStatus = state.zlib.inflateInit_(&zlibStream, ZLIB_VERSION, z_stream.sizeof)) != Z_OK)
	{
		mixin(fail!q{BNKF2Status.zlib(zlibStatus)});
		goto failedWithOutputBuffer;
	}

	fileTableBuffer = cast(ubyte*) state.memoryAllocators.allocate(fileTableBufferSize, 16);

	if (fileTableBuffer == null)
	{
		state.zlib.inflateEnd(&zlibStream);
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.memoryAllocationFailed)});
		goto failedWithOutputBuffer;
	}

	zlibStream.next_out = fileTableBuffer;
	zlibStream.avail_out = fileTableBufferSize;
decompressFileTableFully:
	/+ BNK files don't actually terminate their DEFLATE streams,
	   so we can't use Z_FINISH for this, instead we use Z_SYNC_FLUSH
	   and check the value of `avail_in` and the number of remaining chunks. +/

	zlibStatus = state.zlib.inflate(&zlibStream, Z_SYNC_FLUSH);

	if ((zlibStatus == Z_OK) | (zlibStatus == Z_STREAM_END))
	{
		if ((zlibStatus == Z_OK) & (zlibStream.avail_in != 0))
		{
			/+ If we've already doubled the buffer size and `avail_in` hasn't budged
			   since the previous attempt, we'll assume that we're finished
			   so as to avoid failure. +/
			if ((previousAvailIn == 0) | (zlibStream.avail_in != previousAvailIn))
			{
				previousAvailIn = zlibStream.avail_in;

				state.memoryAllocators.free(fileTableBuffer, fileTableBufferSize);

				fileTableBufferSize <<= 1;
				fileTableBufferSize = fileTableBufferSize != 0 ? fileTableBufferSize : uint.max;

				goto beginDecompressingFileTable;
			}
		}

		if (--remainingFileTableChunks == 0)
		{
			goto decompressedFileTable;
		}

		/+ We've already validated the file-table continuations, so we needn't do so again. +/
		continuationOffset += continuationCompressedSize;
		continuationHeader = cast(Unaligned!(const(BNK.FileTableContinuationHeader))*) (input + continuationOffset);
		continuationOffset += BNK.FileTableContinuationHeader.sizeof;

		continuationCompressedSize = continuationHeader.compressedSize;

		zlibStream.next_in = continuationHeader.continuationData.ptr;
		zlibStream.avail_in = continuationCompressedSize;

		goto decompressFileTableFully;
	}
	else
	{
		state.zlib.inflateEnd(&zlibStream);

		if (zlibStatus != Z_STREAM_END)
		{
			mixin(fail!q{BNKF2Status.zlib(zlibStatus)});
			goto failedWithFileTableBuffer;
		}
	}
decompressedFileTable:
	fileTable = fileTableBuffer;
	fileTableSize = zlibStream.next_out - fileTable;
	remainingInFileTable = fileTableSize;

	mixin(consume!(q{BNK.FileTable.sizeof}, q{failedWithFileTableBuffer}, q{remainingInFileTable}));

	fileCount = (cast(Unaligned!(const(BNK.FileTable))*) fileTable).fileCount;
	emittedFileCount = 0;

	mixin(reportProgress!(q{decompressedFileTable}, q{null}, q{fileCount}));

	fileTable += BNK.FileTable.sizeof;

	if (fileCount == 0)
	{
		offsetOfZipCentralDirectory = 0;
		fileMetadataBuffer = null;
		goto beginWritingZipFooter;
	}

	if (state.packedState & state.packedState.Flags.emitDuplicateFiles)
	{
		fileNameHashTableSize = 0;
	}
	else
	{
		fileNameHashTableSize = (fileCount + (fileCount >> 1)).alignUpTo(16);
	}

	enum string fileMetadataBufferSize =
	q{
		  ((fileCount * PerFileData.sizeof) + fileCount).alignUpTo(16)
		+ (fileNameHashTableSize + (fileNameHashTableSize << 2))
	};

	fileMetadataBuffer = cast(ubyte*) state.memoryAllocators.allocate(mixin(fileMetadataBufferSize), 16);

	if (fileMetadataBuffer == null)
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.memoryAllocationFailed)});
		goto failedWithFileTableBuffer;
	}

	enum string flushSplitOutput (string length, string data, string failureTarget = q{failedWithFileMetadataBuffer}) =
	`
		splitOffset = 0;

		for (;;)
		{
			splitLength = lesserOf((` ~ length ~ `) - splitOffset, outputSpace);

			blit(output + outputOffset, (` ~ data ~ `) + splitOffset, splitLength);

			outputOffset += splitLength;
			splitOffset += splitLength;
			outputSpace -= splitLength;

			if (outputSpace == 0)
			{
				outputSpace = outputFlusher(context, &output, output, outputOffset);

				if (output == null)
				{
					mixin(fail!q{BNKF2Status.caller(cast(uint) outputSpace)});
					goto ` ~ failureTarget ~ `;
				}

				outputOffset = 0;

				if (splitOffset != (` ~ length ~ `))
				{
					continue;
				}
			}

			assert(splitOffset == (` ~ length ~ `));

			break;
		}
	`;

	crc32Seed = cast(uint) state.zlib.crc32(0, null, 0);

	if (!(state.packedState & state.packedState.Flags.omitBNKF2Metadata))
	{
		/+ Unless the caller has asked us not to, we omit a special metadata file
		   into the zip which details some information about the source BNK file.
		   Namely, whether or not it was compressed, so that we can roundtrip
		   a BNK file from a zip without requiring the user to keep track of
		   and specify whether the BNK file is compressed or not.
		   And also which version of the BNK format the BNK file uses. +/

		BNKF2MetadataFileContents.V1 metadata;
		metadata.signature = BNKF2MetadataFileContents.V_.magic;
		metadata.version_ = 1;
		metadata.packedState = 0;
		metadata.packedState |= bnkIsCompressed ? metadata.packedState.Flags.bnkWasCompressed : 0;
		metadata.bnkVersion = bnkVersion;

		/+ The 11th bit indicates that the file-name is UTF-8 encoded. +/
		localFileHeader.bitFlags = 1 << 11;
		localFileHeader.signature = localFileHeader.magic;
		localFileHeader.versionRequiredForExtraction = 10;
		localFileHeader.compressionMethod = 0;
		localFileHeader.lastModificationTime = 0;
		localFileHeader.lastModificationDate = 0;
		localFileHeader.fileNameLength = BNKF2MetadataFileContents.fileName.length;
		localFileHeader.extraFieldLength = 0;

		localFileHeader.compressedSize = metadata.sizeof;
		localFileHeader.uncompressedSize = metadata.sizeof;

		zipOffset += localFileHeader.sizeof + BNKF2MetadataFileContents.fileName.length + metadata.sizeof;

		bnkf2MetadataCRC32 = state.zlib.crc32(crc32Seed, cast(const(ubyte)*) &metadata, metadata.sizeof);
		localFileHeader.crc32 = bnkf2MetadataCRC32;

		mixin(flushSplitOutput!(q{localFileHeader.sizeof}, q{cast(const(ubyte)*) &localFileHeader}));

		const(char)[BNKF2MetadataFileContents.fileName.length] metadataName = BNKF2MetadataFileContents.fileName;
		mixin(flushSplitOutput!(q{metadataName.length}, q{cast(const(ubyte)*) metadataName.ptr}));

		mixin(flushSplitOutput!(q{metadata.sizeof}, q{cast(const(ubyte)*) &metadata}));

		++emittedFileCount;
	}

	perFileDataBuffer = cast(PerFileData*) fileMetadataBuffer;
	fileEmissionBitMap = cast(ubyte*) (fileMetadataBuffer + (fileCount * PerFileData.sizeof));
	fileNameHashTable = cast(ubyte*) (fileEmissionBitMap + fileCount).alignUpTo(16);

	backSlashVector = '\\';
	forwardSlashVector = '/';
	slashSwapDeltaVector = forwardSlashVector - backSlashVector;

	bnkData = input + bnkDataOffset;

	remainingFileCount = fileCount;
	fileIndex = 0;

	goto writeDataForFirstFile;
writeDataForNextFile:
	++fileIndex;
writeDataForFirstFile:
	mixin(consume!(q{BNK.UncompressedFileTableEntry.nameLength.sizeof}, q{failedWithFileMetadataBuffer}, q{remainingInFileTable}));

	nameLength = *unaligned(cast(const(typeof(BNK.UncompressedFileTableEntry.nameLength))*) fileTable);

	if (nameLength > ushort.max)
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.impossiblyLongFilePathInBNK)});
		goto failedWithFileMetadataBuffer;
	}

	mixin(
		consume!(
			q{nameLength + (BNK.UncompressedFileTableEntry.sizeof - BNK.UncompressedFileTableEntry.nameLength.sizeof)},
			q{failedWithFileMetadataBuffer},
			q{remainingInFileTable}
		)
	);

	fileTable += BNK.UncompressedFileTableEntry.nameLength.sizeof;

	remainingNameLength = nameLength;

	/+ BNK files use a backslash to separate directories, whereas zip files use a forward-slash.
	   We swap the two slash types accordingly so that we can roundtrip paths. +/

	for (; remainingNameLength >= 16; remainingNameLength -= 16)
	{
		V nameVector = loadVector!V(cast(byte*) fileTable);

		V backSlashMask = nameVector == backSlashVector;
		V forwardSlashMask = nameVector == forwardSlashVector;

		/+ Back-slashes to forward-slashes. +/
		V backSlashDelta = slashSwapDeltaVector & backSlashMask;
		nameVector += backSlashDelta;

		/+ Forward-slashes to back-slashes. +/
		V forwardSlashDelta = slashSwapDeltaVector & forwardSlashMask;
		nameVector -= forwardSlashDelta;

		storeVector(cast(byte*) fileTable, nameVector);

		fileTable += 16;
	}

	for (; remainingNameLength != 0; --remainingNameLength)
	{
		char codeUnit = *fileTable;
		*fileTable = codeUnit == '\\' ? '/' : (codeUnit != '/' ? codeUnit : '\\');
		++fileTable;
	}

	dataSpan = unaligned(cast(BNK.UncompressedFileTableEntry.DataSpan*) fileTable);

	span = UncompressedSpan(dataSpan.offset, dataSpan.uncompressedFileSize);

	fileTable += span.sizeof;

	/+ We won't need this file's BNK offset again, so we reuse the space
	   to keep track of its place in the zip-file, which saves us from having
	   to allocate extra memory.
	   Likewise, we've rejected names larger than 64KB, so we can reuse a byte
	   from within the name-length field. +/

	namePointer = fileTable - span.sizeof - nameLength;
	nameLengthPointer = cast(Unaligned!uint*) (namePointer - BNK.UncompressedFileTableEntry.nameLength.sizeof);

	assert(*cast(ubyte*) nameLengthPointer == 0);
	assert(*(cast(ubyte*) nameLengthPointer + 1) == 0);

	*cast(Unaligned!uint*) &dataSpan.offset = cast(uint) zipOffset;
	*cast(ubyte*) nameLengthPointer = cast(ubyte) (zipOffset >> 32);

	if (bnkIsCompressed)
	{
		compressedFileSize = *unaligned(cast(const(typeof(BNK.CompressedFileTableEntry.compressedFileSize))*) fileTable);
		fileTable += BNK.CompressedFileTableEntry.compressedFileSize.sizeof;

		compressedChunkCountPointer = cast(const(Unaligned!(typeof(BNK.CompressedFileTableEntry.chunkCount)))*) fileTable;
		uint chunkCount = *compressedChunkCountPointer;

		fileTable += BNK.CompressedFileTableEntry.chunkCount.sizeof;
		fileTable += chunkCount * typeof(BNK.CompressedFileTableEntry.uncompressedChunkSizes.init[0]).sizeof;

		compressedFileChunkCount = (
			  (compressedFileSize >> BNK.CompressedFileTableEntry.completeChunkSizeLog2)
			+ ((compressedFileSize & BNK.CompressedFileTableEntry.completeChunkSizeMask) != 0)
		);

		/+ Non-terminal compressed chunks are supposed to be 32KB each--
		   if they aren't either the chunk-count or the compressed-file-size is wrong. +/
		if (chunkCount != compressedFileChunkCount)
		{
			mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.mismatchingCompressedChunkCountInBNK)});
			goto failedWithFileMetadataBuffer;
		}
	}
	else
	{
		compressedFileSize = span.length;
	}

	if (ulong(span.offset) + compressedFileSize > bnkDataLength)
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.outOfBoundsDataSpanInBNK)});
		goto failedWithFileMetadataBuffer;
	}

	nameIsNullTerminated = nameLength != 0 && namePointer[nameLength - 1] == '\0';

	nameLength -= nameIsNullTerminated;

	if (!(state.packedState & state.packedState.Flags.emitDuplicateFiles))
	{
		hashOfName = wathash!asciiLowerCase(namePointer[0 .. nameLength]);

		uint slot = distributeIntoRange(cast(uint) hashOfName, fileNameHashTableSize);
		ubyte reducedHash = cast(ubyte) (distributeIntoRange(cast(uint) hashOfName, 255) + 1);
	probeFileNameHashTable:
		if (fileNameHashTable[slot] == 0)
		{
		assignFileNameInHashTable:
			fileNameHashTable[slot] = reducedHash;

			(cast(uint*) (fileNameHashTable + fileNameHashTableSize))[slot] = cast(uint) (
				cast(size_t) nameLengthPointer - cast(size_t) fileTableBuffer
			);
		}
		else
		{
			if (fileNameHashTable[slot] == reducedHash)
			{
				uint offsetOfOtherName = (cast(const(uint)*) (fileNameHashTable + fileNameHashTableSize))[slot];
				/+ Masked by 0xFFFF because we may be reusing the upper 2 bytes for storage. +/
				uint lengthOfOtherName = *cast(Unaligned!(BigEndian!uint)*) (fileTableBuffer + offsetOfOtherName) & 0xFFFF;

				const(ubyte)* otherName = fileTableBuffer + offsetOfOtherName + 4;

				bool otherNameIsNullTerminated = lengthOfOtherName != 0 && otherName[lengthOfOtherName - 1] == '\0';

				lengthOfOtherName -= otherNameIsNullTerminated;

				if (nameLength == lengthOfOtherName)
				{
					if (bitEqual!asciiLowerCase(namePointer, otherName, nameLength))
					{
						/+ This is a duplicate file, so we'll skip it. +/

						nameSlice = (cast(const(char)*) namePointer)[0 .. nameLength];
						mixin(reportProgress!(q{skippedDuplicateFileName}, q{&nameSlice}, q{0}));

						if (--remainingFileCount != 0)
						{
							goto writeDataForNextFile;
						}

						goto secondPassOfFileTable;
					}
				}
			}

			++slot;
			slot = slot != fileNameHashTableSize ? slot : 0;

			goto probeFileNameHashTable;
		}
	}

	fileEmissionBitMap[fileIndex >> 3] |= 1 << (fileIndex & 7);

	/+ The 11th bit indicates that the file-name is UTF-8 encoded. +/
	localFileHeader.bitFlags = 1 << 11;
	localFileHeader.signature = localFileHeader.magic;
	localFileHeader.versionRequiredForExtraction = 10;
	localFileHeader.compressionMethod = 0;
	localFileHeader.lastModificationTime = 0;
	localFileHeader.lastModificationDate = 0;
	localFileHeader.fileNameLength = cast(ushort) nameLength;
	localFileHeader.extraFieldLength = 0;

	if (bnkIsCompressed)
	{
		/+ In an ideal world we would just copy the DEFLATE stream from the BNK to the zip.
		   Alas, the DEFLATE streams in a BNK file are all malformed.
		   SO WE CAN'T. +/

		nameSlice = (cast(const(char)*) namePointer)[0 .. nameLength];
		mixin(reportProgress!(q{decompressingFile}, q{&nameSlice}, q{compressedFileSize}));

		if (compressedFileSize < 2)
		{
			if (compressedFileSize == 0)
			{
				/+ We'll be lax and permit empty files. +/
				span.length = 0;
				goto writeLocalFileHeaderForUncompressedFile;
			}

			mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidZLibHeaderForFileInBNK)});
			goto failedWithFileMetadataBuffer;
		}

		if (decompressionBuffer == null)
		{
			/+ Our decompression buffer should be at-least one byte more than
			   the size of the decompressed data, so that we don't end up with
			   `avail_out` being zero. +/
			decompressionBufferSize = (span.length + 1).alignUpTo(64 << 10);
			decompressionBufferSize = lesserOf(decompressionBufferSize, uint.max);

			decompressionBuffer = cast(ubyte*) state.memoryAllocators.allocate(decompressionBufferSize, 16);

			if (decompressionBuffer == null)
			{
				mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.memoryAllocationFailed)});
				goto failedWithFileMetadataBuffer;
			}

			if ((zlibStatus = state.zlib.inflateInit2_(&zlibStream, -15, ZLIB_VERSION, z_stream.sizeof)) != Z_OK)
			{
				state.memoryAllocators.free(decompressionBuffer, decompressionBufferSize);
				decompressionBuffer = null;
				mixin(fail!q{BNKF2Status.zlib(zlibStatus)});
				goto failedWithFileMetadataBuffer;
			}
		}

		assert(compressedFileChunkCount != 0);

		if (decompressionBufferSize <= compressedFileSize)
		{
			state.memoryAllocators.free(decompressionBuffer, decompressionBufferSize);

			decompressionBufferSize = (compressedFileSize + 1).alignUpTo(64 << 10);
			decompressionBufferSize = lesserOf(decompressionBufferSize, uint.max);

			decompressionBuffer = cast(ubyte*) state.memoryAllocators.allocate(decompressionBufferSize, 16);

			if (decompressionBuffer == null)
			{
				mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.memoryAllocationFailed)});
				goto failedWithFileMetadataBuffer;
			}
		}

		previousAvailIn = 0;
	beginDecompressingFileData:
		uint uncompressedSize = 0;
		uint chunkOffset = 0;
		uint remainingChunkCount = compressedFileChunkCount;
		uint remainingChunkData = compressedFileSize;
		const(ubyte*) chunkDataBase = bnkData + span.offset;

		zlibStream.next_out = decompressionBuffer;
		zlibStream.avail_out = cast(uint) decompressionBufferSize;
	decompressNextChunkOfFileData:
		if (remainingChunkData < 2)
		{
			mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidZLibHeaderForFileInBNK)});
			goto failedWithFileMetadataBuffer;
		}

		uint chunkLength = lesserOf(BNK.CompressedFileTableEntry.completeChunkSize, remainingChunkData);
		const(ubyte*) chunkData = chunkDataBase + chunkOffset;

		/+ Refer to section 2.2 of RFC 1950. (https://www.rfc-editor.org/rfc/rfc1950.txt) +/

		ubyte zlibCMF = chunkData[0];
		ubyte zlibFLG = chunkData[1];

		if ((zlibCMF != 0x78) | (((uint(zlibCMF) << 8) | zlibFLG) % 31 != 0))
		{
			mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidZLibHeaderForFileInBNK)});
			goto failedWithFileMetadataBuffer;
		}

		if (zlibFLG & (1 << 5))
		{
			mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.presetDictionaryRequiredByFileInBNK)});
			goto failedWithFileMetadataBuffer;
		}

		/+ Plus/minus two to account for the zlib header. +/
		zlibStream.next_in = chunkData + 2;
		zlibStream.avail_in = chunkLength - 2;

		/+ As with the file-table, these DEFLATE streams are malformed
		   and don't actually terminate, so we can't use Z_FINISH for them,
		   instead we use Z_SYNC_FLUSH. +/

		zlibStatus = state.zlib.inflate(&zlibStream, Z_SYNC_FLUSH);

		if ((zlibStatus == Z_STREAM_END) | (zlibStatus == Z_OK))
		{
			if ((zlibStatus == Z_OK) & (zlibStream.avail_in != 0))
			{
				/+ If we've already doubled the buffer size and `avail_in` hasn't budged
				   since the previous attempt, we'll assume that we're finished
				   so as to avoid failure. +/
				if ((previousAvailIn == 0) | (zlibStream.avail_in != previousAvailIn))
				{
					previousAvailIn = zlibStream.avail_in;

					state.memoryAllocators.free(decompressionBuffer, decompressionBufferSize);

					decompressionBufferSize <<= 1;
					decompressionBufferSize = lesserOf(decompressionBufferSize, uint.max);

					decompressionBuffer = cast(ubyte*) state.memoryAllocators.allocate(decompressionBufferSize, 16);

					if (decompressionBuffer == null)
					{
						mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.memoryAllocationFailed)});
						goto failedWithFileMetadataBuffer;
					}

					state.zlib.inflateReset(&zlibStream);

					goto beginDecompressingFileData;
				}
			}

			if (--remainingChunkCount == 0)
			{
				goto decompressedFileData;
			}

			assert(remainingChunkData >= BNK.CompressedFileTableEntry.completeChunkSize);


			chunkOffset += BNK.CompressedFileTableEntry.completeChunkSize;
			remainingChunkData -= BNK.CompressedFileTableEntry.completeChunkSize;

			state.zlib.inflateReset(&zlibStream);

			goto decompressNextChunkOfFileData;
		}
		else
		{
			mixin(fail!q{BNKF2Status.zlib(zlibStatus)});
			goto failedWithFileMetadataBuffer;
		}
	decompressedFileData:
		state.zlib.inflateReset(&zlibStream);

		uncompressedSize += cast(uint) (decompressionBufferSize - zlibStream.avail_out);

		localFileHeader.compressedSize = uncompressedSize;
		localFileHeader.uncompressedSize = uncompressedSize;

		perFileDataBuffer[fileIndex].uncompressedSize = uncompressedSize;

		zipOffset += localFileHeader.sizeof + nameLength + uncompressedSize;

		nameSlice = (cast(const(char)*) namePointer)[0 .. nameLength];
		mixin(reportProgress!(q{checksummingFile}, q{&nameSlice}, q{uncompressedSize}));

		runningCRC32 = state.zlib.crc32(crc32Seed, decompressionBuffer, uncompressedSize);
		perFileDataBuffer[fileIndex].crc32 = runningCRC32;
		localFileHeader.crc32 = runningCRC32;

		mixin(reportProgress!(q{checksummedFile}, q{&nameSlice}, q{runningCRC32}));

		mixin(flushSplitOutput!(q{localFileHeader.sizeof}, q{cast(const(ubyte)*) &localFileHeader}));
		mixin(flushSplitOutput!(q{nameLength}, q{namePointer}));

		mixin(flushSplitOutput!(q{uncompressedSize}, q{decompressionBuffer}));
	}
	else
	{
		nameSlice = (cast(const(char)*) namePointer)[0 .. nameLength];
		mixin(reportProgress!(q{copyingFile}, q{&nameSlice}, q{compressedFileSize}));
	writeLocalFileHeaderForUncompressedFile:
		localFileHeader.compressedSize = compressedFileSize;
		localFileHeader.uncompressedSize = span.length;

		perFileDataBuffer[fileIndex].uncompressedSize = span.length;

		zipOffset += localFileHeader.sizeof + nameLength + compressedFileSize;

		nameSlice = (cast(const(char)*) namePointer)[0 .. nameLength];
		mixin(reportProgress!(q{checksummingFile}, q{&nameSlice}, q{compressedFileSize}));

		runningCRC32 = state.zlib.crc32(crc32Seed, bnkData + span.offset, compressedFileSize);
		perFileDataBuffer[fileIndex].crc32 = runningCRC32;
		localFileHeader.crc32 = runningCRC32;

		mixin(reportProgress!(q{checksummedFile}, q{&nameSlice}, q{runningCRC32}));

		mixin(flushSplitOutput!(q{localFileHeader.sizeof}, q{cast(const(ubyte)*) &localFileHeader}));
		mixin(flushSplitOutput!(q{nameLength}, q{namePointer}));

		mixin(flushSplitOutput!(q{compressedFileSize}, q{bnkData + span.offset}));
	}

	if (--remainingFileCount != 0)
	{
		goto writeDataForNextFile;
	}
secondPassOfFileTable:
	/+ We now know that the file-table is valid, so we needn't validate it during this second pass. +/

	offsetOfZipCentralDirectory = zipOffset;

	if (!(state.packedState & state.packedState.Flags.omitBNKF2Metadata))
	{
		alias Metadata = BNKF2MetadataFileContents.V1;

		centralDirectoryRecord.signature = centralDirectoryRecord.magic;
		centralDirectoryRecord.versionMadeBy = (bnkF2ZipFileHostOS << 8) |10;
		centralDirectoryRecord.versionRequiredForExtraction = 10;
		centralDirectoryRecord.compressionMethod = 0;
		centralDirectoryRecord.bitFlags = 1 << 11;
		centralDirectoryRecord.lastModificationTime = 0;
		centralDirectoryRecord.lastModificationDate = 0;
		centralDirectoryRecord.crc32 = bnkf2MetadataCRC32;
		centralDirectoryRecord.fileNameLength = BNKF2MetadataFileContents.fileName.length;
		centralDirectoryRecord.comentLength = 0;
		centralDirectoryRecord.internalFileAttributes = 0;
		/+ Refer to https://learn.microsoft.com/windows/win32/fileio/file-attribute-constants +/
		centralDirectoryRecord.externalFileAttributes = FILE_ATTRIBUTE_NORMAL;

		centralDirectoryRecord.compressedSize = Metadata.sizeof;
		centralDirectoryRecord.uncompressedSize = Metadata.sizeof;
		centralDirectoryRecord.diskNumber = 0;
		/+ The metadata is the very first thing we write to the zip file. +/
		centralDirectoryRecord.offsetOfLocalHeaderRelativeToDisk = 0;
		centralDirectoryRecord.extraFieldLength = 0;

		mixin(flushSplitOutput!(q{centralDirectoryRecord.record.sizeof}, q{cast(const(ubyte)*) &centralDirectoryRecord}));

		const(char)[BNKF2MetadataFileContents.fileName.length] metadataName = BNKF2MetadataFileContents.fileName;
		mixin(flushSplitOutput!(q{metadataName.length}, q{cast(const(ubyte)*) metadataName.ptr}));

		zipOffset += centralDirectoryRecord.record.sizeof + BNKF2MetadataFileContents.fileName.length;
	}

	fileTable = fileTableBuffer + BNK.FileTable.sizeof;
	remainingInFileTable = fileTableSize;

	remainingFileCount = fileCount;
	fileIndex = 0;

	goto writeFooterForFirstFile;
writeFooterForNextFile:
	++fileIndex;
writeFooterForFirstFile:
	adornedNameLength = (cast(Unaligned!uint*) fileTable).value;

	zipOffsetHighByte = cast(ubyte) adornedNameLength;

	nameLength = BigEndian!uint(adornedNameLength & 0xFFFF0000).value;
	fileTable += BNK.UncompressedFileTableEntry.nameLength.sizeof;
	fileTable += nameLength;

	dataSpan = unaligned(cast(BNK.UncompressedFileTableEntry.DataSpan*) fileTable);
	/+ We overwrote the offset, earlier, with its little-endian offset within the zip. +/
	span = UncompressedSpan(dataSpan.offset.rawValue, dataSpan.uncompressedFileSize);
	fileTable += span.sizeof;

	namePointer = fileTable - span.sizeof - nameLength;
	nameIsNullTerminated = nameLength != 0 && namePointer[nameLength - 1] == '\0';
	nameLength -= nameIsNullTerminated;

	nameSlice = (cast(const(char)*) namePointer)[0 .. nameLength];
	mixin(reportProgress!(q{writingFileMetadata}, q{&nameSlice}, q{0}));

	if (bnkIsCompressed)
	{
		fileTable += BNK.CompressedFileTableEntry.compressedFileSize.sizeof;

		uint chunkCount = *unaligned(cast(const(typeof(BNK.CompressedFileTableEntry.chunkCount))*) fileTable);
		fileTable += BNK.CompressedFileTableEntry.chunkCount.sizeof;
		fileTable += chunkCount << 2;

		compressedFileSize = perFileDataBuffer[fileIndex].uncompressedSize;
		span.length = compressedFileSize;
	}
	else
	{
		compressedFileSize = span.length;
	}

	if (!(fileEmissionBitMap[fileIndex >> 3] & 1 << (fileIndex & 7)))
	{
		/+ We're to skip this file--likely because it's a duplicate.
		   (But not before we advance past its entry in the file-table,
		    that's very important!) +/

		if (--remainingFileCount == 0)
		{
			goto beginWritingZipFooter;
		}

		goto writeFooterForNextFile;
	}

	++emittedFileCount;

	has32BitOffset = zipOffsetHighByte == 0;

	centralDirectoryRecord.signature = centralDirectoryRecord.magic;
	centralDirectoryRecord.versionMadeBy = (bnkF2ZipFileHostOS << 8) | (has32BitOffset ? 10 : 45);
	centralDirectoryRecord.versionRequiredForExtraction = has32BitOffset ? 10 : 45;
	centralDirectoryRecord.compressionMethod = 0;
	centralDirectoryRecord.bitFlags = 1 << 11;
	centralDirectoryRecord.lastModificationTime = 0;
	centralDirectoryRecord.lastModificationDate = 0;
	centralDirectoryRecord.crc32 = perFileDataBuffer[fileIndex].crc32;
	centralDirectoryRecord.fileNameLength = cast(ushort) nameLength;
	centralDirectoryRecord.comentLength = 0;
	centralDirectoryRecord.internalFileAttributes = 0;
	/+ Refer to https://learn.microsoft.com/windows/win32/fileio/file-attribute-constants +/
	centralDirectoryRecord.externalFileAttributes = FILE_ATTRIBUTE_NORMAL;

	if (has32BitOffset)
	{
		centralDirectoryRecord.compressedSize = compressedFileSize;
		centralDirectoryRecord.uncompressedSize = span.length;
		centralDirectoryRecord.diskNumber = 0;
		centralDirectoryRecord.offsetOfLocalHeaderRelativeToDisk = span.offset;
		centralDirectoryRecord.extraFieldLength = 0;
	}
	else
	{
		centralDirectoryRecord.compressedSize = -1;
		centralDirectoryRecord.uncompressedSize = -1;
		centralDirectoryRecord.diskNumber = cast(ushort) -1;
		centralDirectoryRecord.offsetOfLocalHeaderRelativeToDisk = -1;
		centralDirectoryRecord.extraFieldLength = centralDirectoryRecord._64.sizeof;

		centralDirectoryRecord._64.signature = centralDirectoryRecord._64.magic;
		centralDirectoryRecord._64.fieldSize = centralDirectoryRecord._64.sizeof - Zip.ExtraFieldHeader.sizeof;
		centralDirectoryRecord._64.uncompressedFileSize = span.length;
		centralDirectoryRecord._64.compressedFileSize = compressedFileSize;
		centralDirectoryRecord._64.offsetOfLocalHeaderRelativeToDisk = (ulong(zipOffsetHighByte) << 32) | ulong(span.offset);
		centralDirectoryRecord._64.numberOfDiskThatContainsTheStartOfTheFile = 0;
	}

	mixin(flushSplitOutput!(q{centralDirectoryRecord.record.sizeof}, q{cast(const(ubyte)*) &centralDirectoryRecord}));
	mixin(flushSplitOutput!(q{nameLength}, q{namePointer}));

	if (!has32BitOffset)
	{
		mixin(flushSplitOutput!(q{centralDirectoryRecord._64.sizeof}, q{cast(const(ubyte)*) &centralDirectoryRecord._64}));
	}

	zipOffset += centralDirectoryRecord.record.sizeof + nameLength + (has32BitOffset ? 0 : centralDirectoryRecord._64.sizeof);

	if (--remainingFileCount != 0)
	{
		goto writeFooterForNextFile;
	}
beginWritingZipFooter:
	sizeOfCentralDirectory = zipOffset - offsetOfZipCentralDirectory;

	has32BitFooter = (emittedFileCount <= ushort.max) & (cast(uint) zipOffset == zipOffset);

	assert(sizeOfCentralDirectory <= uint.max || !has32BitFooter);

	if (has32BitFooter)
	{
		endOfCentralDirectoryRecord.entryCountOfDisk = cast(ushort) emittedFileCount;
		endOfCentralDirectoryRecord.entryCountOfCentralDirectory = cast(ushort) emittedFileCount;
		endOfCentralDirectoryRecord.sizeOfCentralDirectory = cast(uint) sizeOfCentralDirectory;
		endOfCentralDirectoryRecord.offsetOfCentralDirectoryRelativeToDiskThatContainsIt = cast(uint) offsetOfZipCentralDirectory;
	}
	else
	{
		Zip.EndOfCentralDirectoryRecord64 endOfCentralDirectoryRecord64 = void;
		endOfCentralDirectoryRecord64.signature = endOfCentralDirectoryRecord64.magic;
		endOfCentralDirectoryRecord64.sizeOfEndOfCentralDirectory64 = endOfCentralDirectoryRecord64.sizeof - 12;
		endOfCentralDirectoryRecord64.versionMadeBy = (bnkF2ZipFileHostOS << 8) | 45;
		endOfCentralDirectoryRecord64.versionRequiredForExtraction = 45;
		endOfCentralDirectoryRecord64.diskNumber = 0;
		endOfCentralDirectoryRecord64.numberOfDiskThatContainsTheStartOfTheCentralDirectory64 = 0;
		endOfCentralDirectoryRecord64.entryCountOfDisk = emittedFileCount;
		endOfCentralDirectoryRecord64.entryCountOfCentralDirectory64 = emittedFileCount;
		endOfCentralDirectoryRecord64.sizeOfCentralDirectory64 = sizeOfCentralDirectory;
		endOfCentralDirectoryRecord64.offsetOfCentralDirectory64RelativeToDiskThatContainsIt = offsetOfZipCentralDirectory;

		mixin(flushSplitOutput!(q{endOfCentralDirectoryRecord64.sizeof}, q{cast(const(ubyte)*) &endOfCentralDirectoryRecord64}));
		zipOffset += endOfCentralDirectoryRecord64.sizeof;

		Zip.EndOfCentralDirectoryLocator64 endOfCentralDirectoryLocator64 = void;
		endOfCentralDirectoryLocator64.signature = endOfCentralDirectoryLocator64.magic;
		endOfCentralDirectoryLocator64.numberOfDiskThatContainsTheStartOfTheEndOfCentralDirectoryRecord64 = 0;
		endOfCentralDirectoryLocator64.offsetOfEndOfCentralDirectoryRecord64RelativeToDiskThatContainsIt = zipOffset;
		endOfCentralDirectoryLocator64.diskCount = 1;

		mixin(flushSplitOutput!(q{endOfCentralDirectoryLocator64.sizeof}, q{cast(const(ubyte)*) &endOfCentralDirectoryLocator64}));
		zipOffset += endOfCentralDirectoryLocator64.sizeof;

		endOfCentralDirectoryRecord.entryCountOfDisk = cast(ushort) -1;
		endOfCentralDirectoryRecord.entryCountOfCentralDirectory = cast(ushort) -1;
		endOfCentralDirectoryRecord.sizeOfCentralDirectory = -1;
		endOfCentralDirectoryRecord.offsetOfCentralDirectoryRelativeToDiskThatContainsIt = -1;
	}

	endOfCentralDirectoryRecord.signature = endOfCentralDirectoryRecord.magic;
	endOfCentralDirectoryRecord.diskNumber = 0;
	endOfCentralDirectoryRecord.numberOfDiskThatContainsTheStartOfTheCentralDirectory = 0;
	endOfCentralDirectoryRecord.commentLength = 0;

	mixin(flushSplitOutput!(q{endOfCentralDirectoryRecord.sizeof}, q{cast(const(ubyte)*) &endOfCentralDirectoryRecord}));
	zipOffset += endOfCentralDirectoryRecord.sizeof;

	if (outputOffset != 0)
	{
		outputSpace = outputFlusher(context, &output, output, outputOffset);

		if (output == null)
		{
			mixin(fail!q{BNKF2Status.caller(cast(uint) outputSpace)});
			goto failedWithFileMetadataBuffer;
		}
	}
successful:
	ultimateStatus = BNKF2Status.status(BNKF2StatusCode.success);
failedWithFileMetadataBuffer:
	if (decompressionBuffer != null)
	{
		state.memoryAllocators.free(decompressionBuffer, decompressionBufferSize);
		state.zlib.inflateEnd(&zlibStream);
	}

	state.memoryAllocators.free(fileMetadataBuffer, mixin(fileMetadataBufferSize));
failedWithFileTableBuffer:
	state.memoryAllocators.free(fileTableBuffer, fileTableBufferSize);
failedWithOutputBuffer:
	size_t flusherStatus = outputFlusher(context, &output, output, 0);

	if (flusherStatus != 0)
	{
		mixin(fail!q{BNKF2Status.caller(cast(uint) flusherStatus)});
	}

	return ultimateStatus;
}


extern(System)
export BNKF2Status bnkf2_zipToBNK (
	scope void* context,
	scope const(ubyte)[]* inputBuffer,
	scope DiscontiguousOutputBufferFlusher outputFlusher,
	scope ZipToBNKState* state
)
{
	/+ We're not handling encryption here,
	   nor are we respecting or even examining disk numbers. +/

	alias V = __vector(byte[16]);

	/+ One for the file-header, one for the file-table, one for the file-data. +/
	enum uint outputBufferCount = 3;

	/+ A complete compressed chunk... and a little bit over. +/
	enum size_t compressionBufferOverflow = 64;
	enum size_t compressionBufferSize = (32 << 10);
	/+ 4GB / 32KB * 4 gives 512KB. +/
	enum size_t uncompressedChunkSizesBufferSize = 512 << 10;
	enum size_t compressionStateMemorySize = compressionBufferSize + compressionBufferOverflow + uncompressedChunkSizesBufferSize;

	BNKF2Status ultimateStatus = void;

	if (state.version_ != 0)
	{
		return BNKF2Status.status(BNKF2StatusCode.unrecognisedStructureVersion);
	}

	state.extendedReturnChannel.v0.packedState = 0;

	if (state.packedState & state.packedState.Flags.ignoreBNKF2MetadataForCompressionSetting)
	{
		state.extendedReturnChannel.v0.packedState |= state.extendedReturnChannel.v0.packedState.Flags.bnkCompressionStatusIsKnown;
		state.extendedReturnChannel.v0.packedState |= (
			  (state.packedState & state.packedState.Flags.outputCompressedBNK)
			? state.extendedReturnChannel.v0.packedState.Flags.bnkIsCompressed
			: 0
		);
	}

	if (state.packedState & state.packedState.Flags.ignoreBNKF2MetadataForBNKVersion)
	{
		state.extendedReturnChannel.v0.packedState |= state.extendedReturnChannel.v0.packedState.Flags.bnkVersionIsKnown;
		state.extendedReturnChannel.v0.bnkVersion = state.bnkVersion;
	}

	size_t inputLength = inputBuffer.length;
	const(ubyte)* inputBase = inputBuffer.ptr;
	const(ubyte)* endOfInput = inputBase + inputLength;
	const(ubyte)* input = endOfInput;
	size_t remaining = inputLength;

	uint uncompressedFileTableBufferSize = state.fileTableUncompressedChunkThreshold == 0 ? 64 << 10 : state.fileTableUncompressedChunkThreshold;

	if (uncompressedFileTableBufferSize > uint.max - (64 << 10))
	{
		return BNKF2Status.status(BNKF2StatusCode.fileTableUncompressedChunkThresholdIsTooBig);
	}

	uint compressedFileTableBufferSize = uncompressedFileTableBufferSize + (64 << 10);

	enum string fileTableBuffersSize = q{size_t(uncompressedFileTableBufferSize) + compressedFileTableBufferSize};

	ubyte* uncompressedFileTableBuffer = cast(ubyte*) state.memoryAllocators.allocate(mixin(fileTableBuffersSize), 16);

	if (uncompressedFileTableBuffer == null)
	{
		return BNKF2Status.status(BNKF2StatusCode.memoryAllocationFailed);
	}

	ubyte* compressedFileTableBuffer = uncompressedFileTableBuffer + uncompressedFileTableBufferSize;

	static struct OutputBuffer
	{
		ubyte* buffer;
		size_t offset;
		size_t space;
	}

	OutputBuffer[outputBufferCount] output;
	size_t flusherStatus = void;

	enum string fail (string failureStatus) =
	`
		*inputBuffer = input[inputBuffer.length - remaining .. inputBuffer.length];
		ultimateStatus = (` ~ failureStatus ~ `);
	`;

	enum string consume (string length, string failureTarget, string remainingBytes = q{remaining}) =
	`
		if ((` ~ length ~ `) > (` ~ remainingBytes ~ `))
		{
			mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.inputIsTruncated)});
			goto ` ~ failureTarget ~ `;
		}

		` ~ remainingBytes ~ ` -= (` ~ length ~ `);
	`;

	enum string reportProgress (string opcode, string operand0, string operand1) =
	`
		if (state.progressObserver !is null)
		{
			state.progressObserver(
				state.progressObserver.context,
				ZipToBNKProgressOpcode.` ~ opcode ~ `,
				` ~ operand0 ~ `,
				` ~ operand1 ~ `
			);
		}
	`;

	Unaligned!(const(Zip.EndOfCentralDirectoryRecord))* endOfCentralDirectoryRecord = void;
	Unaligned!(const(Zip.EndOfCentralDirectoryLocator64))* endOfCentralDirectoryLocator64 = void;
	Unaligned!(const(Zip.EndOfCentralDirectoryRecord64))* endOfCentralDirectoryRecord64 = void;
	Unaligned!(const(Zip.CentralDirectoryRecord64))* centralDirectoryBase = void;
	Unaligned!(const(Zip.CentralDirectoryRecord64))* centralDirectoryRecord = void;
	Unaligned!(const(Zip.ExtraFieldHeader))* extraFieldHeader = void;
	Unaligned!(const(Zip.LocalFileHeader64))* localFileHeader = void;
	const(ubyte)* localFileData = void;
	ulong entryCountOfCentralDirectory = void;
	ulong sizeOfCentralDirectory = void;
	ulong offsetOfCentralDirectory = void;
	ulong compressedSizeOfFile = void;
	ulong uncompressedSizeOfFile = void;
	ulong offsetOfLocalHeaderOfFile = void;
	const(ubyte)* endOfCentralDirectory = void;
	size_t remainingEntriesOfCentralDirectory = void;
	uint centralDirectoryFooterSize = void;
	uint localFileHeaderFooterSize = void;
	bool nameIsNullTerminated = void;
	const(char)[] nameSlice = void;
	uint bytesLeftForFindingEndOfCentralDirectoryRecord = void;
	bool is64BitZip = void;
	bool centralDirectoryRecordIs64Bit = void;
	/+ 0 for no compression; 8 for DEFLATE; -1 for not yet set. +/
	uint compressionMethod = -1;
	uint zipEntryDirectoryAttributeMask = void;
	ulong fileCountOfCentralDirectory = void;
	size_t remainingfileEntriesOfCentralDirectory = void;
	uint bytesUsedByFileData = void;
	uint uncompressedFileNameLength = void;
	uint initialUncompressedFileTableChunkSize = void;
	uint initialCompressedFileTableChunkSize = void;
	uint uncompressedFileTableChunkSize = void;
	uint totalCompressedFileTableSize = void;
	uint uncompressedFileTableOffset = void;
	uint uncompressedFileTableEntrySize = void;
	uint accumulatedCompressedFileOffset = void;
	uint initialFileDataOffset = void;
	uint paddingNeededBeforeData = void;
	bool foundBNKF2Metadata = void;
	bool originalBNKWasCompressed = void;
	bool outputtingCompressedBNKFile = void;
	uint originalBNKVersion = void;
	uint outputBNKVersion = void;
	ubyte fileTableBufferIndex = void;
	ubyte fileDataBufferIndex = void;
	ubyte filePaddingLength = void;
	ubyte filePaddingMask = void;
	V backSlashVector = void;
	V forwardSlashVector = void;
	V slashSwapDeltaVector = void;
	uint ultimateFileHeaderSize = void;

	static union UltimateFileHeader
	{
		BNK.FileHeaderV3 v3;
		BNK.FileHeaderV2 v2;
	}

	UltimateFileHeader ultimateFileHeader = void;
	BNK.FileTableContinuationHeader terminalContinuationHeader = void;
	BigEndian!uint bigEndianUInt = void;
	z_stream fileTableZLibStream = void;
	z_stream compressionZLibStream = void;
	z_stream decompressionZLibStream = void;
	ubyte* compressionBuffer = void;
	ubyte* decompressionBuffer = void;
	size_t decompressionBufferSize = void;
	ubyte fileCompressionLevel = void;
	ubyte fileCompressionMemoryLevel = void;
	BigEndian!uint* uncompressedChunkSizesBuffer = void;
	uint uncompressedChunkSizesOffset = void;
	bool compressionStateInitialised = void;
	bool decompressionStateInitialised = void;
	int zlibStatus = void;

	static struct SplitSpan
	{
		size_t offset;
		size_t length;
	}

	SplitSpan[outputBufferCount] split;
	size_t compressedSplitOffset = void;
	size_t compressedSplitLength = void;

	enum string flushSplitOutput (string buffer, string length, string data, string failureTarget = q{failedWithZlibStreams}) =
	`
		split[` ~ buffer ~ `].offset = 0;

		for (;;)
		{
			split[` ~ buffer ~ `].length = lesserOf(
				(` ~ length ~ `) - split[` ~ buffer ~ `].offset,
				output[` ~ buffer ~ `].space
			);

			blit(
				output[` ~ buffer ~ `].buffer + output[` ~ buffer ~ `].offset,
				(` ~ data ~ `) + split[` ~ buffer ~ `].offset,
				split[` ~ buffer ~ `].length
			);

			output[` ~ buffer ~ `].offset += split[` ~ buffer ~ `].length;
			split[` ~ buffer ~ `].offset += split[` ~ buffer ~ `].length;
			output[` ~ buffer ~ `].space -= split[` ~ buffer ~ `].length;

			if (output[` ~ buffer ~ `].space == 0)
			{
				output[` ~ buffer ~ `].space = outputFlusher(
					context,
					&output[` ~ buffer ~ `].buffer,
					output[` ~ buffer ~ `].buffer,
					output[` ~ buffer ~ `].offset,
					(` ~ buffer ~ `)
				);

				if (output[` ~ buffer ~ `].buffer == null)
				{
					mixin(fail!q{BNKF2Status.caller(cast(uint) output[` ~ buffer ~ `].space)});
					goto ` ~ failureTarget ~ `;
				}

				output[` ~ buffer ~ `].offset = 0;

				if (split[` ~ buffer ~ `].offset != (` ~ length ~ `))
				{
					continue;
				}
			}

			assert(split[` ~ buffer ~ `].offset == (` ~ length ~ `));

			break;
		}
	`;

	enum string compressAndFlushFileTableData (
		string length,
		string data,
		string failureTarget = q{failedWithZlibStreams},
		string mungeData = q{}
	) =
	`
		compressedSplitOffset = 0;

		for (;;)
		{
			compressedSplitLength = lesserOf((` ~ length ~ `) - compressedSplitOffset, uncompressedFileTableBufferSize - uncompressedFileTableOffset);

			blit(uncompressedFileTableBuffer + uncompressedFileTableOffset, (` ~ data ~ `) + compressedSplitOffset, compressedSplitLength);

			do {` ~ mungeData ~ `} while (false);

			uncompressedFileTableChunkSize += compressedSplitLength;
			uncompressedFileTableOffset += compressedSplitLength;
			compressedSplitOffset += compressedSplitLength;

			if (uncompressedFileTableOffset == uncompressedFileTableBufferSize)
			{
				fileTableZLibStream.next_in = uncompressedFileTableBuffer;
				fileTableZLibStream.avail_in = uncompressedFileTableBufferSize;

				/+ We can't stream the compressed output because zlib will emit
				   more than one DEFLATE block if we do so, hence why we allocated
				   this big ol' buffer beforehand. +/
				fileTableZLibStream.next_out = compressedFileTableBuffer;
				fileTableZLibStream.avail_out = compressedFileTableBufferSize;

				zlibStatus = state.zlib.deflate(&fileTableZLibStream, Z_SYNC_FLUSH);

				if (zlibStatus != Z_OK)
				{
					mixin(fail!q{BNKF2Status.zlib(zlibStatus)});
					goto ` ~ failureTarget ~ `;
				}

				assert(fileTableZLibStream.avail_out != 0);

				uint deflatedSize = cast(uint) (compressedFileTableBufferSize - fileTableZLibStream.avail_out);

				if (deflatedSize > uint.max - totalCompressedFileTableSize)
				{
					mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.tooMuchFileNameInZip)});
					goto ` ~ failureTarget ~ `;
				}

				totalCompressedFileTableSize += deflatedSize;

				if ((outputBNKVersion != 2) & (initialUncompressedFileTableChunkSize == -1))
				{
					initialUncompressedFileTableChunkSize = uncompressedFileTableBufferSize;
					initialCompressedFileTableChunkSize = deflatedSize;
				}
				else
				{
					totalCompressedFileTableSize += BNK.FileTableContinuationHeader.sizeof;

					BNK.FileTableContinuationHeader continuationHeader = void;
					continuationHeader.compressedSize = deflatedSize;
					continuationHeader.uncompressedSize = uncompressedFileTableBufferSize;

					mixin(
						flushSplitOutput!(
							q{fileTableBufferIndex},
							q{continuationHeader.sizeof},
							q{cast(const(ubyte)*) &continuationHeader},
							q{` ~ failureTarget ~ `}
						)
					);
				}

				mixin(flushSplitOutput!(q{fileTableBufferIndex}, q{deflatedSize}, q{compressedFileTableBuffer}, q{` ~ failureTarget ~ `}));

				uncompressedFileTableOffset = 0;

				if (compressedSplitOffset != (` ~ length ~ `))
				{
					continue;
				}
			}

			assert(compressedSplitOffset == (` ~ length ~ `));

			break;
		}
	`;

	/+ It's time to play the "What the fuck was Phil Katz thinking?" game. +/

	mixin(reportProgress!(q{searchingForCentralDirectory}, q{null}, q{0}));

	mixin(consume!(q{Zip.EndOfCentralDirectoryRecord.sizeof}, q{failedWithUncompressedFileTableBuffer}));

	input -= Zip.EndOfCentralDirectoryRecord.sizeof;
	bytesLeftForFindingEndOfCentralDirectoryRecord = ushort.max;
findTheEndOfCentralDirectoryRecord:
	if (
		   (cast(Unaligned!(const(Zip.EndOfCentralDirectoryRecord))*) input).signature
		!= Zip.EndOfCentralDirectoryRecord.magic
	)
	{
		if (bytesLeftForFindingEndOfCentralDirectoryRecord == 0)
		{
			mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.couldNotFindEndOfCentralDirectoryRecordInZip)});
			goto failedWithUncompressedFileTableBuffer;
		}
	goBackToFindTheEndOfCentralDirectoryRecord:
		mixin(consume!(q{1}, q{failedWithUncompressedFileTableBuffer}));
		--input;

		goto findTheEndOfCentralDirectoryRecord;
	}

	endOfCentralDirectoryRecord = cast(Unaligned!(const(Zip.EndOfCentralDirectoryRecord))*) input;

	if (remaining + Zip.EndOfCentralDirectoryRecord.sizeof + endOfCentralDirectoryRecord.commentLength != inputLength)
	{
		/+ If the comment-length of the end-of-central-directory-record
		   doesn't point to the end of the file then either the file is truncated,
		   or the signature we've found is actually part of a comment.
		   We'll continue searching because what else can we do? +/
		goto goBackToFindTheEndOfCentralDirectoryRecord;
	}

	is64BitZip = (
		  (endOfCentralDirectoryRecord.diskNumber == -1)
		| (endOfCentralDirectoryRecord.numberOfDiskThatContainsTheStartOfTheCentralDirectory == -1)
		| (endOfCentralDirectoryRecord.entryCountOfDisk == -1)
		| (endOfCentralDirectoryRecord.entryCountOfCentralDirectory == -1)
		| (endOfCentralDirectoryRecord.sizeOfCentralDirectory == -1)
		| (endOfCentralDirectoryRecord.offsetOfCentralDirectoryRelativeToDiskThatContainsIt == -1)
	);

	if (is64BitZip)
	{
		mixin(consume!(q{Zip.EndOfCentralDirectoryLocator64.sizeof}, q{failedWithUncompressedFileTableBuffer}));
		input -= Zip.EndOfCentralDirectoryLocator64.sizeof;
		endOfCentralDirectoryLocator64 = cast(typeof(endOfCentralDirectoryLocator64)) input;

		if (endOfCentralDirectoryLocator64.signature != endOfCentralDirectoryLocator64.magic)
		{
			mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidSignatureForEndOfCentralDirectoryLocator64InZip)});
			goto failedWithUncompressedFileTableBuffer;
		}

		ulong endOfCentralDirectoryRecord64Offset = endOfCentralDirectoryLocator64.offsetOfEndOfCentralDirectoryRecord64RelativeToDiskThatContainsIt;

		if (
			/+ Two checks to guard against overflow. +/
			  (endOfCentralDirectoryRecord64Offset >= remaining)
			| (endOfCentralDirectoryRecord64Offset + 12 >= remaining)
		)
		{
			mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidOffsetForEndOfCentralDirectoryRecord64InZip)});
			goto failedWithUncompressedFileTableBuffer;
		}

		remaining = cast(size_t) endOfCentralDirectoryRecord64Offset;
		input = inputBase + remaining;

		endOfCentralDirectoryRecord64 = cast(typeof(endOfCentralDirectoryRecord64)) input;

		if (endOfCentralDirectoryRecord64.signature != endOfCentralDirectoryRecord64.magic)
		{
			mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidSignatureForEndOfCentralDirectoryRecord64InZip)});
			goto failedWithUncompressedFileTableBuffer;
		}

		ulong sizeOfEndOfCentralDirectory64 = endOfCentralDirectoryRecord64.sizeOfEndOfCentralDirectory64;

		if (sizeOfEndOfCentralDirectory64 > ulong.max - 12 - endOfCentralDirectoryRecord64Offset)
		{
			mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidSizeForEndOfCentralDirectoryRecord64InZip)});
			goto failedWithUncompressedFileTableBuffer;
		}

		if (
			   endOfCentralDirectoryRecord64Offset + sizeOfEndOfCentralDirectory64
			>= cast(size_t) endOfCentralDirectoryLocator64 - cast(size_t) inputBase
		)
		{
			mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidSizeForEndOfCentralDirectoryRecord64InZip)});
			goto failedWithUncompressedFileTableBuffer;
		}

		/+ I'm going to assume that the fields of the 64-bit end-of-central-directory-record
		   are physically mandatory. +/

		if (endOfCentralDirectoryRecord.entryCountOfCentralDirectory == -1)
		{
			if (sizeOfEndOfCentralDirectory64 < Zip.EndOfCentralDirectoryRecord64.entryCountOfCentralDirectory64.offsetof - 12)
			{
				mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidSizeForEndOfCentralDirectoryRecord64InZip)});
				goto failedWithUncompressedFileTableBuffer;
			}

			entryCountOfCentralDirectory = endOfCentralDirectoryRecord64.entryCountOfCentralDirectory64;
		}
		else
		{
			entryCountOfCentralDirectory = endOfCentralDirectoryRecord.entryCountOfCentralDirectory;
		}

		if (endOfCentralDirectoryRecord.offsetOfCentralDirectoryRelativeToDiskThatContainsIt == -1)
		{
			if (sizeOfEndOfCentralDirectory64 < Zip.EndOfCentralDirectoryRecord64.offsetOfCentralDirectory64RelativeToDiskThatContainsIt.offsetof - 12)
			{
				mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidSizeForEndOfCentralDirectoryRecord64InZip)});
				goto failedWithUncompressedFileTableBuffer;
			}

			offsetOfCentralDirectory = endOfCentralDirectoryRecord64.offsetOfCentralDirectory64RelativeToDiskThatContainsIt;
		}
		else
		{
			offsetOfCentralDirectory = endOfCentralDirectoryRecord.offsetOfCentralDirectoryRelativeToDiskThatContainsIt;
		}
	}
	else
	{
		entryCountOfCentralDirectory = endOfCentralDirectoryRecord.entryCountOfCentralDirectory;
		sizeOfCentralDirectory = endOfCentralDirectoryRecord.sizeOfCentralDirectory;
		offsetOfCentralDirectory = endOfCentralDirectoryRecord.offsetOfCentralDirectoryRelativeToDiskThatContainsIt;
	}

	if (offsetOfCentralDirectory >= remaining)
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidOffsetForCentralDirectoryInZip)});
		goto failedWithUncompressedFileTableBuffer;
	}

	if (
		  (sizeOfCentralDirectory > ulong.max - offsetOfCentralDirectory)
		| (offsetOfCentralDirectory + sizeOfCentralDirectory > remaining)
	)
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidSizeForCentralDirectoryInZip)});
		goto failedWithUncompressedFileTableBuffer;
	}

	remaining = offsetOfCentralDirectory;
	input = inputBase + remaining;

	centralDirectoryBase = cast(typeof(centralDirectoryBase)) input;
	endOfCentralDirectory = input + sizeOfCentralDirectory;
	remainingEntriesOfCentralDirectory = cast(size_t) entryCountOfCentralDirectory;
	fileCountOfCentralDirectory = 0;

	mixin(reportProgress!(q{foundCentralDirectory}, q{null}, q{entryCountOfCentralDirectory}));

	foundBNKF2Metadata = false;

	if (remainingEntriesOfCentralDirectory == 0)
	{
		/+ The zip has no entries, so we'll just write out an emptyish BNK file.  +/
		outputBNKVersion = state.bnkVersion;

		state.extendedReturnChannel.v0.packedState |= state.extendedReturnChannel.v0.packedState.Flags.bnkVersionIsKnown;
		state.extendedReturnChannel.v0.bnkVersion = outputBNKVersion;

		fileCountOfCentralDirectory = 0;
		goto maybeWriteOutEmptyishBNKFile;
	}

	centralDirectoryRecord = centralDirectoryBase;

	/+ This first pass is mainly validation and counting the number of file entries
	   (as opposed to directory entries, as BNK files can't directly represent directories).
	   We'll also use it as am opportunity to scan for any BNKF2 metadata. +/
nextCentralDirectoryFirstPass:
	/+ This can't overflow, the last page of the address-space will never be mapped. +/
	if (cast(const(ubyte)*) centralDirectoryRecord + Zip.CentralDirectoryRecord.sizeof >= endOfInput)
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidOffsetForCentralDirectoryRecordInZip)});
		goto failedWithUncompressedFileTableBuffer;
	}

	if (centralDirectoryRecord.signature != centralDirectoryRecord.magic)
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidSignatureForCentralDirectoryRecordInZip)});
		goto failedWithUncompressedFileTableBuffer;
	}

	if (centralDirectoryRecord.versionRequiredForExtraction > 45)
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.unsupportedVersionRequiredForExtractionInZip)});
		goto failedWithUncompressedFileTableBuffer;
	}

	if (centralDirectoryRecord.bitFlags & ((1 << 0) | (1 << 6) | (1 << 13)))
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.unsupportedEncryptedFileInZip)});
		goto failedWithUncompressedFileTableBuffer;
	}

	if (centralDirectoryRecord.bitFlags & (1 << 5))
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.unsupportedCompressedPatchedDataInZip)});
		goto failedWithUncompressedFileTableBuffer;
	}

	if (centralDirectoryRecord.bitFlags & ((1 << 4) | (1 << 12)))
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.unsupportedEnhancedCompressionInZip)});
		goto failedWithUncompressedFileTableBuffer;
	}

	/+ To follow the specification strictly, we should check bit 11 to see if
	   the file-name is to be treated as UTF-8 or as code-page 437, but I suspect
	   that most writers don't bother to set it and also expect readers to just
	   assume that they're UTF-8 anyway. So we'll do just that. +/

	if ((centralDirectoryRecord.compressionMethod != 0) & (centralDirectoryRecord.compressionMethod != 8))
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.unsupportedCompressionMethodInZip)});
		goto failedWithUncompressedFileTableBuffer;
	}

	compressionMethod = centralDirectoryRecord.compressionMethod;

	centralDirectoryFooterSize = (
		  uint(centralDirectoryRecord.fileNameLength)
		+ uint(centralDirectoryRecord.extraFieldLength)
		+ uint(centralDirectoryRecord.comentLength)
	);

	if (
		  (cast(size_t) endOfCentralDirectory < centralDirectoryFooterSize)
		| (cast(const(ubyte)*) centralDirectoryRecord + centralDirectoryFooterSize > endOfCentralDirectory)
	)
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidFooterSizeForCentralDirectoryRecordInZip)});
		goto failedWithUncompressedFileTableBuffer;
	}

	nameIsNullTerminated = (
		   centralDirectoryRecord.fileNameLength != 0
		&& centralDirectoryRecord.fileName.ptr[centralDirectoryRecord.fileNameLength - 1] == '\0'
	);

	uncompressedFileNameLength = centralDirectoryRecord.fileNameLength + !nameIsNullTerminated;

	if (cast(ushort) uncompressedFileNameLength == 0)
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.excessivelyLongFileNameForCentralDirectoryRecordInZip)});
		goto failedWithUncompressedFileTableBuffer;
	}

	centralDirectoryRecordIs64Bit = (
		  (centralDirectoryRecord.compressedSize == -1)
		| (centralDirectoryRecord.uncompressedSize == -1)
		| (centralDirectoryRecord.diskNumber == -1)
		| (centralDirectoryRecord.offsetOfLocalHeaderRelativeToDisk == -1)
	);

	if (centralDirectoryRecordIs64Bit)
	{
		uint requiredExtraFieldSize = 4;
		requiredExtraFieldSize += centralDirectoryRecord.compressedSize == -1 ? 8 : 0;
		requiredExtraFieldSize += centralDirectoryRecord.uncompressedSize == -1 ? 8 : 0;
		requiredExtraFieldSize += centralDirectoryRecord.diskNumber == -1 ? 4 : 0;
		requiredExtraFieldSize += centralDirectoryRecord.offsetOfLocalHeaderRelativeToDisk == -1 ? 8 : 0;

		if (centralDirectoryRecord.extraFieldLength < requiredExtraFieldSize)
		{
			mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidExtraFieldLengthForCentralDirectoryRecordInZip)});
			goto failedWithUncompressedFileTableBuffer;
		}

		uint extraFieldOffset = 0;
		const(ubyte)* extraFieldBase = (
			cast(const(ubyte)*) centralDirectoryRecord + Zip.CentralDirectoryRecord.sizeof + centralDirectoryRecord.fileNameLength
		);
	findExtendedInformationExtraField64DuringFirstPass:
		extraFieldHeader = cast(Unaligned!(const(Zip.ExtraFieldHeader))*) (extraFieldBase + extraFieldOffset);

		if (extraFieldHeader.signature != Zip.ExtendedInformationExtraField64.magic)
		{
			if (extraFieldOffset > ushort.max - Zip.ExtraFieldHeader.sizeof - extraFieldHeader.fieldSize)
			{
				mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidExtraFieldSizeForCentralDirectoryRecordInZip)});
				goto failedWithUncompressedFileTableBuffer;
			}

			extraFieldOffset += extraFieldHeader.fieldSize + Zip.ExtraFieldHeader.sizeof;

			if (extraFieldOffset > centralDirectoryRecord.extraFieldLength)
			{
				mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidExtraFieldSizeForCentralDirectoryRecordInZip)});
				goto failedWithUncompressedFileTableBuffer;
			}

			if (extraFieldOffset > ushort.max - requiredExtraFieldSize)
			{
				mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.failedToFindExtendedInformationExtraField64ForCentralDirectoryRecordInZip)});
				goto failedWithUncompressedFileTableBuffer;
			}

			goto findExtendedInformationExtraField64DuringFirstPass;
		}

		extraFieldOffset += Zip.ExtraFieldHeader.sizeof;

		if (centralDirectoryRecord.uncompressedSize == -1)
		{
			uncompressedSizeOfFile = *cast(const(Unaligned!ulong)*) (extraFieldBase + extraFieldOffset);
			extraFieldOffset += 8;
		}
		else
		{
			uncompressedSizeOfFile = centralDirectoryRecord.uncompressedSize;
		}

		if (centralDirectoryRecord.compressedSize == -1)
		{
			compressedSizeOfFile = *cast(const(Unaligned!ulong)*) (extraFieldBase + extraFieldOffset);
			extraFieldOffset += 8;
		}
		else
		{
			compressedSizeOfFile = centralDirectoryRecord.compressedSize;
		}

		if (centralDirectoryRecord.offsetOfLocalHeaderRelativeToDisk == -1)
		{
			offsetOfLocalHeaderOfFile = *cast(const(Unaligned!ulong)*) (extraFieldBase + extraFieldOffset);
			extraFieldOffset += 8;
		}
		else
		{
			offsetOfLocalHeaderOfFile = centralDirectoryRecord.offsetOfLocalHeaderRelativeToDisk;
		}
	}
	else
	{
		compressedSizeOfFile = centralDirectoryRecord.compressedSize;
		uncompressedSizeOfFile = centralDirectoryRecord.uncompressedSize;
		offsetOfLocalHeaderOfFile = centralDirectoryRecord.offsetOfLocalHeaderRelativeToDisk;
	}

	/+ We'll be extra helpful and skip over directory entries,
	   because zip archivers like to create them. +/
	switch (centralDirectoryRecord.versionMadeBy >> 8)
	{
	case  0: /+ MS-DOS +/
	case 11: /+ NTFS +/
		zipEntryDirectoryAttributeMask = FILE_ATTRIBUTE_DIRECTORY;
		break;
	case  3: /+ UNIX +/
	case  7: /+ Classic MacOS +/
	case 19: /+ macOS +/
		zipEntryDirectoryAttributeMask = S_IFDIR << 16;
		break;
	default:
		zipEntryDirectoryAttributeMask = 0;
	}

	if (centralDirectoryRecord.externalFileAttributes & zipEntryDirectoryAttributeMask)
	{
		goto skippingEntryDuringFirstPass;
	}

	if (offsetOfLocalHeaderOfFile > cast(size_t) centralDirectoryBase - cast(size_t) inputBase)
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidOffsetForLocalFileHeaderInZip)});
		goto failedWithUncompressedFileTableBuffer;
	}

	if (
		  (compressedSizeOfFile > cast(size_t) centralDirectoryBase - cast(size_t) inputBase)
		| (offsetOfLocalHeaderOfFile > (cast(size_t) centralDirectoryBase - cast(size_t) inputBase) - compressedSizeOfFile)
	)
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidCompressedSizeForFileInZip)});
		goto failedWithUncompressedFileTableBuffer;
	}

	if ((compressionMethod == 0) & (uncompressedSizeOfFile != compressedSizeOfFile))
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidUncompressedSizeForFileInZip)});
		goto failedWithUncompressedFileTableBuffer;
	}

	if (accumulatedCompressedFileOffset > uint.max - cast(uint) compressedSizeOfFile)
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.zipFileIsTooBigForBNKFile)});
		goto failedWithUncompressedFileTableBuffer;
	}

	localFileHeader = cast(typeof(localFileHeader)) (inputBase + offsetOfLocalHeaderOfFile);

	if (localFileHeader.signature != localFileHeader.magic)
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidSignatureForLocalFileHeaderInZip)});
		goto failedWithUncompressedFileTableBuffer;
	}

	localFileHeaderFooterSize = uint(localFileHeader.fileNameLength) + uint(localFileHeader.extraFieldLength);

	if (
		  (cast(size_t) centralDirectoryBase < Zip.LocalFileHeader.sizeof + localFileHeaderFooterSize)
		| (cast(size_t) localFileHeader + Zip.LocalFileHeader.sizeof + localFileHeaderFooterSize > cast(size_t) centralDirectoryBase)
	)
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidFooterSizeForCentralDirectoryRecordInZip)});
		goto failedWithUncompressedFileTableBuffer;
	}

	localFileData = cast(const(ubyte)*) localFileHeader + Zip.LocalFileHeader.sizeof + localFileHeaderFooterSize;

	if (compressedSizeOfFile > cast(size_t) centralDirectoryBase - cast(size_t) localFileData)
	{
		mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.invalidSizeForFileInZip)});
		goto failedWithUncompressedFileTableBuffer;
	}

	if (centralDirectoryRecord.fileNameLength == BNKF2MetadataFileContents.fileName.length)
	{
		static assert(BNKF2MetadataFileContents.fileName.length == 8);

		const(char)[8] metadataName = BNKF2MetadataFileContents.fileName;

		if (
			   *cast(const(Unaligned!ulong)*) centralDirectoryRecord.fileName.ptr
			== *cast(const(Unaligned!ulong)*) &metadataName
		)
		{
			/+ We can just ignore any errors with regards to the BNKF2 metadata,
			   they're irrelevant for the actual BNK data. +/

			static assert(BNKF2MetadataFileContents.sizeof == 12);
			ubyte[16] buffer = void;
			const(ubyte)* metadataData = void;
			uint metadataSize = void;

			if (compressionMethod == 0)
			{
				metadataData = localFileData;
				metadataSize = cast(uint) uncompressedSizeOfFile;
			}
			else
			{
				assert(!decompressionStateInitialised);

				decompressionZLibStream.zalloc = null;
				decompressionZLibStream.zfree = null;
				decompressionZLibStream.opaque = null;

				if (state.packedState & state.packedState.Flags.forwardAllocatorToZLib)
				{
					decompressionZLibStream.zalloc = &state.memoryAllocators.zlibAllocate;
					decompressionZLibStream.zfree = &state.memoryAllocators.zlibFree;
					decompressionZLibStream.opaque = &state.memoryAllocators;
				}

				if ((zlibStatus = state.zlib.inflateInit2_(&decompressionZLibStream, -15, ZLIB_VERSION, z_stream.sizeof)) != Z_OK)
				{
					goto skippingEntryDuringFirstPass;
				}

				decompressionZLibStream.next_out = buffer.ptr;
				decompressionZLibStream.avail_out = buffer.length;

				decompressionZLibStream.next_in = localFileData;
				decompressionZLibStream.avail_in = cast(uint) compressedSizeOfFile;

				zlibStatus = state.zlib.inflate(&decompressionZLibStream, Z_SYNC_FLUSH);

				metadataSize = cast(uint) buffer.length - decompressionZLibStream.avail_out;
				metadataData = buffer.ptr;

				state.zlib.inflateEnd(&decompressionZLibStream);

				if ((zlibStatus != Z_STREAM_END) & (zlibStatus != Z_OK))
				{
					goto skippingEntryDuringFirstPass;
				}
			}

			if (metadataSize < BNKF2MetadataFileContents.V_.sizeof)
			{
				goto skippingEntryDuringFirstPass;
			}

			Unaligned!(const(BNKF2MetadataFileContents.V_))* metadata = (
				cast(Unaligned!(const(BNKF2MetadataFileContents.V_))*) metadataData
			);

			if (metadata.signature != metadata.magic)
			{
				goto skippingEntryDuringFirstPass;
			}

			switch (metadata.version_)
			{
			case 0:
				if (metadataSize < BNKF2MetadataFileContents.V0.sizeof)
				{
					goto skippingEntryDuringFirstPass;
				}

				originalBNKVersion = 3;
			metadataV0:
				Unaligned!(const(BNKF2MetadataFileContents.V0))* v0 = (
					cast(Unaligned!(const(BNKF2MetadataFileContents.V0))*) metadataData
				);

				originalBNKWasCompressed = !!(v0.packedState & v0.packedState.Flags.bnkWasCompressed);

				break;
			case 1:
				if (metadataSize < BNKF2MetadataFileContents.V1.sizeof)
				{
					goto skippingEntryDuringFirstPass;
				}

				Unaligned!(const(BNKF2MetadataFileContents.V1))* v1 = (
					cast(Unaligned!(const(BNKF2MetadataFileContents.V1))*) metadataData
				);

				originalBNKVersion = v1.bnkVersion;

				goto metadataV0;
			default:
				goto skippingEntryDuringFirstPass;
			}

			foundBNKF2Metadata = true;

			goto skippingEntryDuringFirstPass;
		}
	}

	++fileCountOfCentralDirectory;
skippingEntryDuringFirstPass:
	if (--remainingEntriesOfCentralDirectory != 0)
	{
		centralDirectoryRecord = cast(typeof(centralDirectoryRecord)) (
			cast(const(ubyte)*) centralDirectoryRecord + Zip.CentralDirectoryRecord.sizeof + centralDirectoryFooterSize
		);

		goto nextCentralDirectoryFirstPass;
	}

	if (state.packedState & state.packedState.Flags.ignoreBNKF2MetadataForBNKVersion)
	{
		outputBNKVersion = state.bnkVersion;
	}
	else
	{
		if (foundBNKF2Metadata)
		{
			outputBNKVersion = originalBNKVersion;
		}
		else
		{
			outputBNKVersion = state.bnkVersion;
		}

		state.extendedReturnChannel.v0.packedState |= state.extendedReturnChannel.v0.packedState.Flags.bnkVersionIsKnown;
		state.extendedReturnChannel.v0.bnkVersion = outputBNKVersion;
	}

maybeWriteOutEmptyishBNKFile:
	/+ We initialise the output-flushers here so that they can inspect the output BNK version. +/

	if ((flusherStatus = outputFlusher(context, null, null, outputBufferCount, -1)) != 0)
	{
		state.memoryAllocators.free(uncompressedFileTableBuffer, mixin(fileTableBuffersSize));
		return BNKF2Status.caller(cast(uint) flusherStatus);
	}

	foreach (bufferIndex; 0 .. outputBufferCount)
	{
		output[bufferIndex].space = outputFlusher(
			context,
			&output[bufferIndex].buffer,
			output[bufferIndex].buffer,
			output[bufferIndex].offset,
			bufferIndex
		);

		if (output[bufferIndex].buffer == null)
		{
			state.memoryAllocators.free(uncompressedFileTableBuffer, mixin(fileTableBuffersSize));
			return BNKF2Status.caller(cast(uint) output[bufferIndex].space);
		}
	}

	if (fileCountOfCentralDirectory == 0)
	{
		/+ The zip has no files, so we'll just write out an emptyish BNK file.  +/
		if (outputBNKVersion != 2)
		{
			ultimateFileHeader.v3.offset = 0;
			ultimateFileHeader.v3.version_ = outputBNKVersion;
			ultimateFileHeader.v3.filesAreCompressed = false;
			ultimateFileHeader.v3.compressedHeaderSize = 0;
			ultimateFileHeader.v3.uncompressedHeaderSize = 0;
		}
		else
		{
			ultimateFileHeader.v2.offset = BNK.FileHeaderV2.fileData.offsetof;
			ultimateFileHeader.v2.version_ = 2;
			ultimateFileHeader.v2.filesAreCompressed = false;
			ultimateFileHeader.v2.padding = 0;
		}

		state.extendedReturnChannel.v0.packedState |= state.extendedReturnChannel.v0.packedState.Flags.bnkCompressionStatusIsKnown;
		state.extendedReturnChannel.v0.packedState &= ~state.extendedReturnChannel.v0.packedState.Flags.bnkIsCompressed;

		goto successful;
	}

	if (state.packedState & state.packedState.Flags.ignoreBNKF2MetadataForCompressionSetting)
	{
		outputtingCompressedBNKFile = !!(state.packedState & state.packedState.Flags.outputCompressedBNK);
	}
	else
	{
		if (foundBNKF2Metadata)
		{
			outputtingCompressedBNKFile = originalBNKWasCompressed;
		}
		else
		{
			outputtingCompressedBNKFile = !!(state.packedState & state.packedState.Flags.outputCompressedBNK);
		}

		state.extendedReturnChannel.v0.packedState |= state.extendedReturnChannel.v0.packedState.Flags.bnkCompressionStatusIsKnown;
		state.extendedReturnChannel.v0.packedState |= (
			outputtingCompressedBNKFile ? state.extendedReturnChannel.v0.packedState.Flags.bnkIsCompressed : 0
		);
	}

	if (outputBNKVersion != 2)
	{
		fileTableBufferIndex = 1;
		fileDataBufferIndex = 2;

		filePaddingLength = 2;
		filePaddingMask = 1;
	}
	else
	{
		fileTableBufferIndex = 2;
		fileDataBufferIndex = 1;

		filePaddingLength = 8;
		filePaddingMask = 7;
	}

	backSlashVector = '\\';
	forwardSlashVector = '/';
	slashSwapDeltaVector = forwardSlashVector - backSlashVector;

	initialUncompressedFileTableChunkSize = -1;
	initialCompressedFileTableChunkSize = -1;
	uncompressedFileTableOffset = 0;
	uncompressedFileTableChunkSize = 0;
	totalCompressedFileTableSize = 0;
	accumulatedCompressedFileOffset = 0;
	bytesUsedByFileData = 0;
	compressionStateInitialised = false;
	decompressionStateInitialised = false;

	fileTableZLibStream.zalloc = null;
	fileTableZLibStream.zfree = null;
	fileTableZLibStream.opaque = null;

	if (state.packedState & state.packedState.Flags.forwardAllocatorToZLib)
	{
		fileTableZLibStream.zalloc = &state.memoryAllocators.zlibAllocate;
		fileTableZLibStream.zfree = &state.memoryAllocators.zlibFree;
		fileTableZLibStream.opaque = &state.memoryAllocators;
	}

	zlibStatus = state.zlib.deflateInit2_(
		&fileTableZLibStream,
		state.fileTableCompressionLevel.asZLibCompressionLevel,
		Z_DEFLATED,
		15,
		state.fileTableMemoryLevel.asZLibMemoryLevel,
		Z_DEFAULT_STRATEGY,
		ZLIB_VERSION,
		z_stream.sizeof
	);

	if (zlibStatus != Z_OK)
	{
		mixin(fail!q{BNKF2Status.zlib(zlibStatus)});
		goto failedWithOutputBuffer;
	}

	*cast(BigEndian!uint*) uncompressedFileTableBuffer = BigEndian!uint.fromLittleEndian(cast(uint) fileCountOfCentralDirectory);
	uncompressedFileTableOffset += 4;
	uncompressedFileTableChunkSize += 4;

	remainingfileEntriesOfCentralDirectory = cast(size_t) fileCountOfCentralDirectory;
	centralDirectoryRecord = centralDirectoryBase;
nextCentralDirectorySecondPass:
	compressionMethod = centralDirectoryRecord.compressionMethod;

	centralDirectoryFooterSize = (
		  uint(centralDirectoryRecord.fileNameLength)
		+ uint(centralDirectoryRecord.extraFieldLength)
		+ uint(centralDirectoryRecord.comentLength)
	);

	switch (centralDirectoryRecord.versionMadeBy >> 8)
	{
	case  0: /+ MS-DOS +/
	case 11: /+ NTFS +/
		zipEntryDirectoryAttributeMask = FILE_ATTRIBUTE_DIRECTORY;
		break;
	case  3: /+ UNIX +/
	case  7: /+ Classic MacOS +/
	case 19: /+ macOS +/
		zipEntryDirectoryAttributeMask = S_IFDIR << 16;
		break;
	default:
		zipEntryDirectoryAttributeMask = 0;
	}

	if (centralDirectoryRecord.externalFileAttributes & zipEntryDirectoryAttributeMask)
	{
		goto skippingEntryDuringSecondPass;
	}

	nameIsNullTerminated = (
		   centralDirectoryRecord.fileNameLength != 0
		&& centralDirectoryRecord.fileName.ptr[centralDirectoryRecord.fileNameLength - 1] == '\0'
	);

	uncompressedFileNameLength = centralDirectoryRecord.fileNameLength + !nameIsNullTerminated;

	if (centralDirectoryRecord.fileNameLength == BNKF2MetadataFileContents.fileName.length)
	{
		static assert(BNKF2MetadataFileContents.fileName.length == 8);

		const(char)[8] metadataName = BNKF2MetadataFileContents.fileName;

		if (
			   *cast(const(Unaligned!ulong)*) centralDirectoryRecord.fileName.ptr
			== *cast(const(Unaligned!ulong)*) &metadataName
		)
		{
			goto skippingEntryDuringSecondPass;
		}
	}

	centralDirectoryRecordIs64Bit = (
		  (centralDirectoryRecord.compressedSize == -1)
		| (centralDirectoryRecord.uncompressedSize == -1)
		| (centralDirectoryRecord.diskNumber == -1)
		| (centralDirectoryRecord.offsetOfLocalHeaderRelativeToDisk == -1)
	);

	if (centralDirectoryRecordIs64Bit)
	{
		uint requiredExtraFieldSize = 4;
		requiredExtraFieldSize += centralDirectoryRecord.compressedSize == -1 ? 8 : 0;
		requiredExtraFieldSize += centralDirectoryRecord.uncompressedSize == -1 ? 8 : 0;
		requiredExtraFieldSize += centralDirectoryRecord.diskNumber == -1 ? 4 : 0;
		requiredExtraFieldSize += centralDirectoryRecord.offsetOfLocalHeaderRelativeToDisk == -1 ? 8 : 0;

		uint extraFieldOffset = 0;
		const(ubyte)* extraFieldBase = (
			cast(const(ubyte)*) centralDirectoryRecord + Zip.CentralDirectoryRecord.sizeof + centralDirectoryRecord.fileNameLength
		);
	findExtendedInformationExtraField64DuringSecondPass:
		extraFieldHeader = cast(Unaligned!(const(Zip.ExtraFieldHeader))*) (extraFieldBase + extraFieldOffset);

		if (extraFieldHeader.signature != Zip.ExtendedInformationExtraField64.magic)
		{
			extraFieldOffset += extraFieldHeader.fieldSize + Zip.ExtraFieldHeader.sizeof;

			goto findExtendedInformationExtraField64DuringSecondPass;
		}

		extraFieldOffset += Zip.ExtraFieldHeader.sizeof;

		if (centralDirectoryRecord.uncompressedSize == -1)
		{
			uncompressedSizeOfFile = *cast(const(Unaligned!ulong)*) (extraFieldBase + extraFieldOffset);
			extraFieldOffset += 8;
		}
		else
		{
			uncompressedSizeOfFile = centralDirectoryRecord.uncompressedSize;
		}

		if (centralDirectoryRecord.compressedSize == -1)
		{
			compressedSizeOfFile = *cast(const(Unaligned!ulong)*) (extraFieldBase + extraFieldOffset);
			extraFieldOffset += 8;
		}
		else
		{
			compressedSizeOfFile = centralDirectoryRecord.compressedSize;
		}

		if (centralDirectoryRecord.offsetOfLocalHeaderRelativeToDisk == -1)
		{
			offsetOfLocalHeaderOfFile = *cast(const(Unaligned!ulong)*) (extraFieldBase + extraFieldOffset);
			extraFieldOffset += 8;
		}
		else
		{
			offsetOfLocalHeaderOfFile = centralDirectoryRecord.offsetOfLocalHeaderRelativeToDisk;
		}
	}
	else
	{
		compressedSizeOfFile = centralDirectoryRecord.compressedSize;
		uncompressedSizeOfFile = centralDirectoryRecord.uncompressedSize;
		offsetOfLocalHeaderOfFile = centralDirectoryRecord.offsetOfLocalHeaderRelativeToDisk;
	}

	localFileHeader = cast(typeof(localFileHeader)) (inputBase + offsetOfLocalHeaderOfFile);

	localFileHeaderFooterSize = uint(localFileHeader.fileNameLength) + uint(localFileHeader.extraFieldLength);

	localFileData = cast(const(ubyte)*) localFileHeader + Zip.LocalFileHeader.sizeof + localFileHeaderFooterSize;

	static assert(BNK.UncompressedFileTableEntry.nameLength.offsetof == 0);

	bigEndianUInt = uncompressedFileNameLength;
	mixin(compressAndFlushFileTableData!(q{4}, q{cast(const(ubyte)*) &bigEndianUInt}));

	mixin(
		compressAndFlushFileTableData!(
			q{centralDirectoryRecord.fileNameLength},
			q{cast(const(ubyte)*) centralDirectoryRecord.fileName.ptr},
			q{failedWithZlibStreams},
			q{
				byte* fileTable = cast(byte*) (uncompressedFileTableBuffer + uncompressedFileTableOffset);
				size_t remainingNameLength = cast(size_t) compressedSplitLength;

				/+ BNK files use a backslash to separate directories, whereas zip files use a forward-slash.
				   We swap the two slash types accordingly so that we can roundtrip paths. +/

				for (; remainingNameLength >= 16; remainingNameLength -= 16)
				{
					V nameVector = loadVector!V(cast(byte*) fileTable);

					V backSlashMask = nameVector == backSlashVector;
					V forwardSlashMask = nameVector == forwardSlashVector;

					/+ Back-slashes to forward-slashes. +/
					V backSlashDelta = slashSwapDeltaVector & backSlashMask;
					nameVector += backSlashDelta;

					/+ Forward-slashes to back-slashes. +/
					V forwardSlashDelta = slashSwapDeltaVector & forwardSlashMask;
					nameVector -= forwardSlashDelta;

					storeVector(cast(byte*) fileTable, nameVector);

					fileTable += 16;
				}

				for (; remainingNameLength != 0; --remainingNameLength)
				{
					char codeUnit = *fileTable;
					*fileTable = codeUnit == '\\' ? '/' : (codeUnit != '/' ? codeUnit : '\\');
					++fileTable;
				}
			}
		)
	);

	if (!nameIsNullTerminated)
	{
		char nullTerminator = '\0';
		mixin(compressAndFlushFileTableData!(q{1}, q{cast(const(ubyte)*) &nullTerminator}));
	}

	if (compressionMethod == 0)
	{
	emitDataForUncompressedFile:
		if (!outputtingCompressedBNKFile)
		{
			nameSlice = centralDirectoryRecord.fileName.ptr[0 .. centralDirectoryRecord.fileNameLength];
			mixin(reportProgress!(q{copyingFile}, q{&nameSlice}, q{uncompressedSizeOfFile}));

			/+ The file is uncompressed, we can simply copy it as is. +/

			uint trailingPaddingInBNKFile = (
				  outputBNKVersion != 2
				? 0
				: (
					  (filePaddingLength - (uncompressedSizeOfFile & filePaddingMask))
					& (remainingfileEntriesOfCentralDirectory != 1 ? filePaddingMask : 0)
				)
			);

			uint bytesLeftForFile = void;

			if (outputBNKVersion != 2)
			{
				initialFileDataOffset = (uint(BNK.FileHeaderV3.sizeof) + totalCompressedFileTableSize).alignUpTo(32 << 10);
				bytesLeftForFile = uint.max - bytesUsedByFileData - initialFileDataOffset;
			}
			else
			{
				initialFileDataOffset = (uint(BNK.FileHeaderV2.sizeof) + bytesUsedByFileData).alignUpTo(64);
				bytesLeftForFile = uint.max - totalCompressedFileTableSize - initialFileDataOffset;
			}

			if ((bytesLeftForFile < trailingPaddingInBNKFile) | (cast(uint) uncompressedSizeOfFile > bytesLeftForFile))
			{
				mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.zipFileIsTooBigForBNKFile)});
				goto failedWithZlibStreams;
			}

			bytesUsedByFileData += uncompressedSizeOfFile + trailingPaddingInBNKFile;

			mixin(flushSplitOutput!(q{fileDataBufferIndex}, q{uncompressedSizeOfFile}, q{localFileData}, q{failedWithZlibStreams}));

			ulong padding = 0;
			mixin(flushSplitOutput!(q{fileDataBufferIndex}, q{trailingPaddingInBNKFile}, q{cast(const(ubyte)*) &padding}, q{failedWithZlibStreams}));

			uncompressedFileTableEntrySize = BNK.UncompressedFileTableEntry.sizeof;

			uncompressedFileTableChunkSize += uncompressedFileNameLength + uncompressedFileTableEntrySize;

			static assert(BNK.UncompressedFileTableEntry.data.offsetof == 4);
			static assert(BNK.UncompressedFileTableEntry.data.offset.offsetof == 0);
			static assert(BNK.UncompressedFileTableEntry.data.uncompressedFileSize.offsetof == 4);

			BigEndian!uint[2] fileTableEntryValues = void;
			fileTableEntryValues[0] = accumulatedCompressedFileOffset;
			fileTableEntryValues[1] = cast(uint) uncompressedSizeOfFile;

			accumulatedCompressedFileOffset += cast(uint) uncompressedSizeOfFile + trailingPaddingInBNKFile;

			mixin(compressAndFlushFileTableData!(q{fileTableEntryValues.sizeof}, q{cast(const(ubyte)*) fileTableEntryValues.ptr}));

			goto handledZipEntry;
		}
		else
		{
			nameSlice = centralDirectoryRecord.fileName.ptr[0 .. centralDirectoryRecord.fileNameLength];
			mixin(reportProgress!(q{compressingFile}, q{&nameSlice}, q{uncompressedSizeOfFile}));

			/+ No bytes? +/
			if ((uncompressedSizeOfFile == 0) | (compressedSizeOfFile == 0))
			{
				/+ Plus a padding byte if there's another file after this one. +/
				uint trailingPaddingInBNKFile = remainingfileEntriesOfCentralDirectory != 1;

				uint sizeInBNKFile = 7;

				uint spaceLeftForFileData = void;

				if (outputBNKVersion != 2)
				{
					initialFileDataOffset = (uint(BNK.FileHeaderV3.sizeof) + totalCompressedFileTableSize).alignUpTo(32 << 10);
					spaceLeftForFileData = uint.max - bytesUsedByFileData - initialFileDataOffset;
				}
				else
				{
					initialFileDataOffset = (uint(BNK.FileHeaderV2.sizeof) + bytesUsedByFileData).alignUpTo(64);
					spaceLeftForFileData = uint.max - totalCompressedFileTableSize - initialFileDataOffset;
				}

				if ((spaceLeftForFileData < trailingPaddingInBNKFile) | (sizeInBNKFile > spaceLeftForFileData - trailingPaddingInBNKFile))
				{
					mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.zipFileIsTooBigForBNKFile)});
					goto failedWithZlibStreams;
				}

				bytesUsedByFileData += sizeInBNKFile + trailingPaddingInBNKFile;

				/+ A zlib header followed by an empty DEFLATE block with the BFINAL bit set,
				   and lastly a padding byte, if needed, to maintain an alignment of 2. +/
				ubyte[8] emptyStream = [0x78, 0xDA, 0x01, 0x00, 0x00, 0xFF, 0xFF, 0x00];

				mixin(flushSplitOutput!(q{fileDataBufferIndex}, q{sizeInBNKFile + trailingPaddingInBNKFile}, q{emptyStream.ptr}, q{failedWithZlibStreams}));

				uncompressedFileTableEntrySize = BNK.CompressedFileTableEntry.sizeof;

				uncompressedFileTableChunkSize += uncompressedFileNameLength + uncompressedFileTableEntrySize;

				static assert(BNK.UncompressedFileTableEntry.data.offsetof == 4);
				static assert(BNK.UncompressedFileTableEntry.data.offset.offsetof == 0);
				static assert(BNK.UncompressedFileTableEntry.data.uncompressedFileSize.offsetof == 4);
				static assert(BNK.CompressedFileTableEntry.compressedFileSize.offsetof == 12);
				static assert(BNK.CompressedFileTableEntry.chunkCount.offsetof == 16);

				BigEndian!uint[4] fileTableEntryValues = void;
				fileTableEntryValues[0] = accumulatedCompressedFileOffset;
				fileTableEntryValues[1] = 0;
				fileTableEntryValues[2] = sizeInBNKFile;
				fileTableEntryValues[3] = 0;

				accumulatedCompressedFileOffset += sizeInBNKFile + trailingPaddingInBNKFile;

				mixin(compressAndFlushFileTableData!(q{fileTableEntryValues.sizeof}, q{cast(const(ubyte)*) fileTableEntryValues.ptr}));

				goto handledZipEntry;
			}

			/+ We need to compress the file into chunks of no-more-than 32KB.
			   I don't know how the Fable II developers wrangled zlib into compressing
			   the data into chunks of exactly 32KB, including the zlib header,
			   perhaps they used a similar approach to zlib's "fitblk.c" example?
			   (https://github.com/madler/zlib/blob/master/examples/fitblk.c)
			   I'm going with a binary search of the length of the input. +/

			if (!compressionStateInitialised)
			{
				compressionBuffer = cast(ubyte*) state.memoryAllocators.allocate(compressionStateMemorySize, 16);

				if (compressionBuffer == null)
				{
					mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.memoryAllocationFailed)});
					goto failedWithZlibStreams;
				}

				uncompressedChunkSizesBuffer = cast(BigEndian!uint*) (
					compressionBuffer + compressionBufferSize + compressionBufferOverflow
				);

				compressionZLibStream.zalloc = null;
				compressionZLibStream.zfree = null;
				compressionZLibStream.opaque = null;

				if (state.packedState & state.packedState.Flags.forwardAllocatorToZLib)
				{
					compressionZLibStream.zalloc = &state.memoryAllocators.zlibAllocate;
					compressionZLibStream.zfree = &state.memoryAllocators.zlibFree;
					compressionZLibStream.opaque = &state.memoryAllocators;
				}

				fileCompressionLevel = state.fileDataCompressionLevel.asZLibCompressionLevel;
				fileCompressionMemoryLevel = state.fileDataMemoryLevel.asZLibMemoryLevel;

				zlibStatus = state.zlib.deflateInit2_(
					&compressionZLibStream,
					fileCompressionLevel,
					Z_DEFLATED,
					-15,
					fileCompressionMemoryLevel,
					Z_DEFAULT_STRATEGY,
					ZLIB_VERSION,
					z_stream.sizeof
				);

				if (zlibStatus != Z_OK)
				{
					mixin(fail!q{BNKF2Status.zlib(zlibStatus)});
					goto failedWithZlibStreams;
				}

				compressionStateInitialised = true;
			}

			enum uint completeChunkSize = BNK.CompressedFileTableEntry.completeChunkSize;
			/+ Plus 1 so that `avail_out` isn't 0 when we have a perfect fit for a chunk. +/
			enum uint zlibChunkSize = completeChunkSize + 1;

			static assert(compressionBufferSize + compressionBufferOverflow >= zlibChunkSize);

			uncompressedChunkSizesOffset = 0;

			/+ Refer to section 2.2 of RFC 1950. (https://www.rfc-editor.org/rfc/rfc1950.txt) +/

			ubyte zlibCMF = 0x78;
			ubyte zlibFLG = (
				fileCompressionLevel > 6 ? 3 : (fileCompressionLevel == 6 ? 2 : fileCompressionLevel >= 2)
			) << 6;
			/+ This is setting FCHECK. +/
			zlibFLG |= 31 - (((uint(zlibCMF) << 8) | zlibFLG) % 31);

			compressionBuffer[0] = zlibCMF;
			compressionBuffer[1] = zlibFLG;

			uint uncompressedOffset = 0;
			uint remainingUncompressedLength = cast(uint) uncompressedSizeOfFile;
			uint overallCompressedLength = 0;
			uint overallUncompressedLength = 0;
			uint compressedLength = void;

			const(ubyte)* uncompressedData = void;
			uint uncompressedLength = void;
			uint halfWindow = void;
			uint previousUncompressedLengthThatFit = 0;

			goto beginCompressionIntoFirstChunk;
		beginCompressionIntoNextChunk:
			state.zlib.deflateReset(&compressionZLibStream);
			//remainingUncompressedLength -= uncompressedOffset;
			assert(uncompressedLength < remainingUncompressedLength);
			remainingUncompressedLength -= uncompressedLength;
			uncompressedOffset += uncompressedLength;
		beginCompressionIntoFirstChunk:
			mixin(reportProgress!(q{compressingFileChunk}, q{&nameSlice}, q{remainingUncompressedLength}));

			uncompressedData = localFileData + uncompressedOffset;
			uncompressedLength = remainingUncompressedLength;
			halfWindow = uncompressedLength;

			goto tryCompressionIntoFirstChunk;
		retryCompressionIntoChunk:
			state.zlib.deflateReset(&compressionZLibStream);
		tryCompressionIntoFirstChunk:
			/+ Plus/minus 2 to account for the zlib header. +/
			compressionZLibStream.next_out = compressionBuffer + 2;
			compressionZLibStream.avail_out = zlibChunkSize - 2;

			compressionZLibStream.next_in = uncompressedData;
			compressionZLibStream.avail_in = uncompressedLength;

			zlibStatus = state.zlib.deflate(&compressionZLibStream, Z_FINISH);

			if (((zlibStatus == Z_STREAM_END) | (zlibStatus == Z_OK)) & (compressionZLibStream.avail_out != 0))
			{
				if (uncompressedLength == remainingUncompressedLength)
				{
					/+ We've compressed all there is to compress. +/
					compressedLength = zlibChunkSize - compressionZLibStream.avail_out;

					assert(compressedLength <= completeChunkSize);

					uncompressedChunkSizesBuffer[uncompressedChunkSizesOffset++] = uncompressedLength;

					overallUncompressedLength += uncompressedLength;

					uint trailingPaddingInBNKFile = (
						  (filePaddingLength - (compressedLength & filePaddingMask))
						& (remainingfileEntriesOfCentralDirectory != 1 ? filePaddingMask : 0)
					);

					uint spaceLeftForFileData = void;

					if (outputBNKVersion != 2)
					{
						initialFileDataOffset = (uint(BNK.FileHeaderV3.sizeof) + totalCompressedFileTableSize).alignUpTo(32 << 10);
						spaceLeftForFileData = uint.max - bytesUsedByFileData - initialFileDataOffset;
					}
					else
					{
						initialFileDataOffset = (uint(BNK.FileHeaderV2.sizeof) + bytesUsedByFileData).alignUpTo(64);
						spaceLeftForFileData = uint.max - totalCompressedFileTableSize - initialFileDataOffset;
					}

					if ((spaceLeftForFileData < trailingPaddingInBNKFile) | (compressedLength > spaceLeftForFileData - trailingPaddingInBNKFile))
					{
						mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.zipFileIsTooBigForBNKFile)});
						goto failedWithZlibStreams;
					}

					bytesUsedByFileData += compressedLength + trailingPaddingInBNKFile;

					mixin(flushSplitOutput!(q{fileDataBufferIndex}, q{compressedLength}, q{compressionBuffer}, q{failedWithZlibStreams}));

					ulong padding = 0;
					mixin(flushSplitOutput!(q{fileDataBufferIndex}, q{trailingPaddingInBNKFile}, q{cast(const(ubyte)*) &padding}, q{failedWithZlibStreams}));

					uncompressedFileTableEntrySize = (
						cast(uint) BNK.CompressedFileTableEntry.sizeof + (uncompressedChunkSizesOffset << 2)
					);

					uncompressedFileTableChunkSize += uncompressedFileNameLength + uncompressedFileTableEntrySize;

					overallCompressedLength += compressedLength;

					static assert(BNK.UncompressedFileTableEntry.data.offsetof == 4);
					static assert(BNK.UncompressedFileTableEntry.data.offset.offsetof == 0);
					static assert(BNK.UncompressedFileTableEntry.data.uncompressedFileSize.offsetof == 4);
					static assert(BNK.CompressedFileTableEntry.compressedFileSize.offsetof == 12);
					static assert(BNK.CompressedFileTableEntry.chunkCount.offsetof == 16);

					BigEndian!uint[4] fileTableEntryValues = void;
					fileTableEntryValues[0] = accumulatedCompressedFileOffset;
					fileTableEntryValues[1] = overallUncompressedLength;
					fileTableEntryValues[2] = overallCompressedLength;
					fileTableEntryValues[3] = uncompressedChunkSizesOffset;

					accumulatedCompressedFileOffset += overallCompressedLength + trailingPaddingInBNKFile;

					mixin(compressAndFlushFileTableData!(q{fileTableEntryValues.sizeof}, q{cast(const(ubyte)*) fileTableEntryValues.ptr}));

					mixin(
						compressAndFlushFileTableData!(
							q{uncompressedChunkSizesOffset << 2},
							q{cast(const(ubyte)*) uncompressedChunkSizesBuffer}
						)
					);

					mixin(reportProgress!(q{compressedFileChunk}, q{&nameSlice}, q{compressedLength}));
				}
				else
				{
					if (compressionZLibStream.avail_out == 1)
					{
						/+ We have a perfect fit. +/
						compressedLength = zlibChunkSize - 1;
					flushNonTerminalCompressionChunk:
						assert(compressedLength <= completeChunkSize);

						repStos(compressionBuffer + compressedLength, 0, completeChunkSize - compressedLength);

						uncompressedChunkSizesBuffer[uncompressedChunkSizesOffset++] = uncompressedLength;

						overallUncompressedLength += uncompressedLength;

						uint spaceLeftForFileData = void;

						if (outputBNKVersion != 2)
						{
							initialFileDataOffset = (uint(BNK.FileHeaderV3.sizeof) + totalCompressedFileTableSize).alignUpTo(32 << 10);
							spaceLeftForFileData = uint.max - bytesUsedByFileData - initialFileDataOffset;
						}
						else
						{
							initialFileDataOffset = (uint(BNK.FileHeaderV2.sizeof) + bytesUsedByFileData).alignUpTo(64);
							spaceLeftForFileData = uint.max - totalCompressedFileTableSize - initialFileDataOffset;
						}

						if (completeChunkSize > spaceLeftForFileData)
						{
							mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.zipFileIsTooBigForBNKFile)});
							goto failedWithZlibStreams;
						}

						bytesUsedByFileData += completeChunkSize;

						mixin(flushSplitOutput!(q{fileDataBufferIndex}, q{completeChunkSize}, q{compressionBuffer}, q{failedWithZlibStreams}));

						overallCompressedLength += completeChunkSize;

						mixin(reportProgress!(q{compressedFileChunk}, q{&nameSlice}, q{compressedLength}));

						goto beginCompressionIntoNextChunk;
					}
					else
					{
						/+ Maybe we could fit a bit more in. +/
						previousUncompressedLengthThatFit = uncompressedLength;

						halfWindow >>= 1;

						if (halfWindow == 0)
						{
							/+ Scratch that. This is the best fit we'll get. +/
							assert(uncompressedLength != remainingUncompressedLength);
							assert(compressionZLibStream.avail_out != 0);

							compressedLength = zlibChunkSize - compressionZLibStream.avail_out;

							goto flushNonTerminalCompressionChunk;
						}
						else
						{
							uncompressedLength += halfWindow;

							goto retryCompressionIntoChunk;
						}
					}
				}
			}
			else
			{
				/+ Let's try again with a little less. +/
				halfWindow >>= 1;

				if (halfWindow != 0)
				{
					uncompressedLength -= halfWindow;
				}
				else
				{
					uncompressedLength = previousUncompressedLengthThatFit;
				}

				goto retryCompressionIntoChunk;
			}

			state.zlib.deflateReset(&compressionZLibStream);

			goto handledZipEntry;
		}
	}
	else
	{
		mixin(reportProgress!(q{decompressingFile}, q{&nameSlice}, q{uncompressedSizeOfFile}));

		if (!decompressionStateInitialised)
		{
			decompressionBufferSize = (
				uncompressedSizeOfFile < uint.max ? (uncompressedSizeOfFile + 1).alignUpTo(64 << 10) : uint.max
			);

			decompressionBuffer = cast(ubyte*) state.memoryAllocators.allocate(decompressionBufferSize, 16);

			if (decompressionBuffer == null)
			{
				mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.memoryAllocationFailed)});
				goto failedWithZlibStreams;
			}

			decompressionZLibStream.zalloc = null;
			decompressionZLibStream.zfree = null;
			decompressionZLibStream.opaque = null;

			if (state.packedState & state.packedState.Flags.forwardAllocatorToZLib)
			{
				decompressionZLibStream.zalloc = &state.memoryAllocators.zlibAllocate;
				decompressionZLibStream.zfree = &state.memoryAllocators.zlibFree;
				decompressionZLibStream.opaque = &state.memoryAllocators;
			}

			if ((zlibStatus = state.zlib.inflateInit2_(&decompressionZLibStream, -15, ZLIB_VERSION, z_stream.sizeof)) != Z_OK)
			{
				mixin(fail!q{BNKF2Status.zlib(zlibStatus)});
				goto failedWithZlibStreams;
			}

			decompressionStateInitialised = true;
		}

		size_t previousAvailIn = 0;
	decompressFileData:
		decompressionZLibStream.next_out = decompressionBuffer;
		decompressionZLibStream.avail_out = cast(uint) decompressionBufferSize;

		decompressionZLibStream.next_in = localFileData;
		decompressionZLibStream.avail_in = cast(uint) compressedSizeOfFile;

		zlibStatus = state.zlib.inflate(&decompressionZLibStream, Z_FINISH);

		if (zlibStatus == Z_STREAM_END)
		{
			uncompressedSizeOfFile = decompressionBufferSize - decompressionZLibStream.avail_out;
			localFileData = decompressionBuffer;

			state.zlib.inflateReset(&decompressionZLibStream);

			goto emitDataForUncompressedFile;
		}
		else
		{
			if (zlibStatus == Z_BUF_ERROR)
			{
				/+ If we've already doubled the buffer size and `avail_in` hasn't budged
				   since the previous attempt, we'll assume that we're finished
				   so as to avoid failure. +/
				if ((previousAvailIn == 0) | (decompressionZLibStream.avail_in != previousAvailIn))
				{
					previousAvailIn = decompressionZLibStream.avail_in;

					state.memoryAllocators.free(decompressionBuffer, decompressionBufferSize);

					decompressionBufferSize <<= 1;
					decompressionBufferSize = lesserOf(decompressionBufferSize, uint.max);

					decompressionBuffer = cast(ubyte*) state.memoryAllocators.allocate(decompressionBufferSize, 16);

					if (decompressionBuffer == null)
					{
						mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.memoryAllocationFailed)});
						goto failedWithZlibStreams;
					}

					state.zlib.inflateReset(&decompressionZLibStream);

					goto decompressFileData;
				}
			}

			mixin(fail!q{BNKF2Status.zlib(zlibStatus)});
			goto failedWithZlibStreams;
		}
	}
handledZipEntry:
	if (--remainingfileEntriesOfCentralDirectory != 0)
	{
	skippingEntryDuringSecondPass:
		centralDirectoryRecord = cast(typeof(centralDirectoryRecord)) (
			cast(const(ubyte)*) centralDirectoryRecord + Zip.CentralDirectoryRecord.sizeof + centralDirectoryFooterSize
		);

		goto nextCentralDirectorySecondPass;
	}

	if (compressionStateInitialised)
	{
		state.zlib.deflateEnd(&compressionZLibStream);
		state.memoryAllocators.free(compressionBuffer, compressionStateMemorySize);
	}

	if (decompressionStateInitialised)
	{
		state.zlib.deflateEnd(&decompressionZLibStream);
		state.memoryAllocators.free(decompressionBuffer, decompressionBufferSize);
	}

	if (uncompressedFileTableOffset != 0)
	{
		fileTableZLibStream.next_in = uncompressedFileTableBuffer;
		fileTableZLibStream.avail_in = uncompressedFileTableOffset;

		fileTableZLibStream.next_out = compressedFileTableBuffer;
		fileTableZLibStream.avail_out = compressedFileTableBufferSize;

		zlibStatus = state.zlib.deflate(&fileTableZLibStream, Z_SYNC_FLUSH);

		if (zlibStatus != Z_OK)
		{
			mixin(fail!q{BNKF2Status.zlib(zlibStatus)});
			goto failedWithZlibStreams;
		}

		assert(fileTableZLibStream.avail_out != 0);

		uint deflatedSize = cast(uint) (compressedFileTableBufferSize - fileTableZLibStream.avail_out);

		if (deflatedSize > uint.max - totalCompressedFileTableSize)
		{
			mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.tooMuchFileNameInZip)});
			goto failedWithZlibStreams;
		}

		totalCompressedFileTableSize += deflatedSize;

		if ((outputBNKVersion != 2) & (initialUncompressedFileTableChunkSize == -1))
		{
			initialUncompressedFileTableChunkSize = uncompressedFileTableOffset;
			initialCompressedFileTableChunkSize = deflatedSize;
		}
		else
		{
			totalCompressedFileTableSize += BNK.FileTableContinuationHeader.sizeof;

			BNK.FileTableContinuationHeader continuationHeader = void;
			continuationHeader.compressedSize = deflatedSize;
			continuationHeader.uncompressedSize = uncompressedFileTableOffset;

			mixin(
				flushSplitOutput!(
					q{fileTableBufferIndex},
					q{continuationHeader.sizeof},
					q{cast(const(ubyte)*) &continuationHeader},
					q{failedWithZlibStreams}
				)
			);
		}

		state.zlib.deflateEnd(&fileTableZLibStream);

		mixin(flushSplitOutput!(q{fileTableBufferIndex}, q{deflatedSize}, q{compressedFileTableBuffer}, q{failedWithOutputBuffer}));
	}

	if (outputBNKVersion != 2)
	{
		/+ We terminate the file-table. +/
		terminalContinuationHeader.compressedSize = 0;
		terminalContinuationHeader.uncompressedSize = 0;

		totalCompressedFileTableSize += BNK.FileTableContinuationHeader.sizeof;

		mixin(
			flushSplitOutput!(
				q{fileTableBufferIndex},
				q{terminalContinuationHeader.sizeof},
				q{cast(const(ubyte)*) &terminalContinuationHeader},
				q{failedWithZlibStreams}
			)
		);

		if (BNK.FileHeaderV3.sizeof > uint.max - totalCompressedFileTableSize)
		{
			mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.tooMuchFileNameInZip)});
			goto failedWithOutputBuffer;
		}
	}
	else
	{
		if (BNK.FileHeaderV2.sizeof > uint.max - totalCompressedFileTableSize)
		{
			mixin(fail!q{BNKF2Status.status(BNKF2StatusCode.tooMuchFileNameInZip)});
			goto failedWithOutputBuffer;
		}
	}

	if (outputBNKVersion != 2)
	{
		initialFileDataOffset = (uint(BNK.FileHeaderV3.sizeof) + totalCompressedFileTableSize).alignUpTo(32 << 10);
		paddingNeededBeforeData = initialFileDataOffset - (uint(BNK.FileHeaderV3.sizeof) + totalCompressedFileTableSize);

		assert(paddingNeededBeforeData < (32 << 10));
		static assert(minimumPageSize <= (32 << 10));

		zeroOut(uncompressedFileTableBuffer.alignUpTo(minimumPageSize), paddingNeededBeforeData.alignUpTo(64));
		mixin(
			flushSplitOutput!(
				q{fileTableBufferIndex},
				q{paddingNeededBeforeData},
				q{uncompressedFileTableBuffer.alignUpTo(minimumPageSize)},
				q{failedWithZlibStreams}
			)
		);

		ultimateFileHeader.v3.offset = initialFileDataOffset;
		ultimateFileHeader.v3.version_ = outputBNKVersion;
		ultimateFileHeader.v3.filesAreCompressed = outputtingCompressedBNKFile;
		ultimateFileHeader.v3.compressedHeaderSize = initialCompressedFileTableChunkSize;
		ultimateFileHeader.v3.uncompressedHeaderSize = initialUncompressedFileTableChunkSize;
	}
	else
	{
		uint endOfFileData = uint(BNK.FileHeaderV2.sizeof) + bytesUsedByFileData;
		uint fileTableOffset = endOfFileData.alignUpTo(64);
		uint paddingNeededBeforeFileTable = fileTableOffset - endOfFileData;

		assert(paddingNeededBeforeFileTable < 64);

		zeroOut(uncompressedFileTableBuffer.alignUpTo(minimumPageSize), paddingNeededBeforeFileTable.alignUpTo(64));
		mixin(
			flushSplitOutput!(
				q{fileDataBufferIndex},
				q{paddingNeededBeforeFileTable},
				q{uncompressedFileTableBuffer.alignUpTo(minimumPageSize)},
				q{failedWithZlibStreams}
			)
		);

		ultimateFileHeader.v2.offset = fileTableOffset;
		ultimateFileHeader.v2.version_ = 2;
		ultimateFileHeader.v2.filesAreCompressed = outputtingCompressedBNKFile;
		ultimateFileHeader.v2.padding = 0;
	}
successful:
	mixin(
		flushSplitOutput!(
			q{0},
			q{outputBNKVersion != 2 ? BNK.FileHeaderV3.sizeof : BNK.FileHeaderV2.sizeof},
			q{cast(const(ubyte)*) &ultimateFileHeader},
			q{failedWithZlibStreams}
		)
	);

	foreach (bufferIndex; 0 .. outputBufferCount)
	{
		if (output[bufferIndex].offset != 0)
		{
			flusherStatus = outputFlusher(
				context,
				&output[bufferIndex].buffer,
				output[bufferIndex].buffer,
				output[bufferIndex].offset,
				bufferIndex
			);

			if (output[bufferIndex].buffer == null)
			{
				mixin(fail!q{BNKF2Status.caller(cast(uint) flusherStatus)});
				goto failedWithZlibStreams;
			}
		}
	}

	ultimateStatus = BNKF2Status.status(BNKF2StatusCode.success);
failedWithZlibStreams:
	if (compressionStateInitialised)
	{
		state.zlib.deflateEnd(&compressionZLibStream);
		state.memoryAllocators.free(compressionBuffer, compressionStateMemorySize);
	}

	if (decompressionStateInitialised)
	{
		state.zlib.deflateEnd(&decompressionZLibStream);
		state.memoryAllocators.free(decompressionBuffer, decompressionBufferSize);
	}
failedWithFileTableZlibStream:
	state.zlib.deflateEnd(&fileTableZLibStream);
failedWithOutputBuffer:
	foreach (bufferIndex; 0 .. outputBufferCount)
	{
		flusherStatus = outputFlusher(context, &output[bufferIndex].buffer, output[bufferIndex].buffer, 0, bufferIndex);

		if (flusherStatus != 0)
		{
			mixin(fail!q{BNKF2Status.caller(cast(uint) flusherStatus)});
			goto failedWithUncompressedFileTableBuffer;
		}
	}

	if ((flusherStatus = outputFlusher(context, null, null, (1 << 16) | outputBufferCount, -1)) != 0)
	{
		mixin(fail!q{BNKF2Status.caller(cast(uint) flusherStatus)});
		goto failedWithUncompressedFileTableBuffer;
	}
failedWithUncompressedFileTableBuffer:
	state.memoryAllocators.free(uncompressedFileTableBuffer, mixin(fileTableBuffersSize));

	return ultimateStatus;
}


extern(System)
export BNKF2Status bnkf2_bnkIsCompressed (
	scope const(ubyte)* inputBuffer,
	scope size_t inputLength,
	scope bool* bnkIsCompressed
)
{
	static assert(BNK.FileHeaderV3.filesAreCompressed.offsetof == BNK.FileHeaderV2.filesAreCompressed.offsetof);
	static assert(BNK.FileHeaderV3.filesAreCompressed.sizeof == BNK.FileHeaderV2.filesAreCompressed.sizeof);

	if (inputLength < BNK.FileHeaderV3.filesAreCompressed.offsetof + BNK.FileHeaderV3.filesAreCompressed.sizeof)
	{
		return BNKF2Status.status(BNKF2StatusCode.inputIsTruncated);
	}

	*bnkIsCompressed = *(inputBuffer + BNK.FileHeaderV3.filesAreCompressed.offsetof) != 0;

	return BNKF2Status.status(BNKF2StatusCode.success);
}


extern(System)
export immutable(char)* bnkf2_messageForStatusCode (BNKF2StatusCode code)
{
	return code <= BNKF2StatusCode.max ? ErrorMessageTable.get(code).ptr : null;
}


extern(System)
export immutable(char)* bnkf2_messageForStatusCodeWithLength (BNKF2StatusCode code, scope uint* length)
{
	auto message = code <= BNKF2StatusCode.max ? ErrorMessageTable.get(code) : null;
	*length = cast(uint) message.length;
	return message.ptr;
}


extern(System)
export shared immutable(uint) bnkf2_longestStatusCodeMessageLength = ErrorMessageTable.longestMessageLength;


/+ Provided for the benefit of deficient language runtimes. +/
extern(System)
export uint bnkf2_getLongestStatusCodeMessageLength ()
{
	return bnkf2_longestStatusCodeMessageLength;
}

