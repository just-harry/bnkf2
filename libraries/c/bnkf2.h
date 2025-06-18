
#pragma once

#include "stdint.h"

#ifdef __cplusplus
extern "C"
{
#endif

#ifdef _WIN32
#	define BNKF2_D_SYSTEM_CONVENTION(returnType) returnType __stdcall

#	ifdef BNKF2_SHOULD_DLLIMPORT
#		define BNKF2_IMPORT __declspec(dllimport)
#	else
#		define BNKF2_IMPORT
#	endif
#else
#	define BNKF2_D_SYSTEM_CONVENTION(returnType) returnType __cdecl
#	define BNKF2_IMPORT
#endif


typedef enum
{
	bnkf2_StatusCode_success = 0,
	bnkf2_StatusCode_memoryAllocationFailed = 1,
	bnkf2_StatusCode_inputIsTooLong = 2,
	bnkf2_StatusCode_inputIsTruncated = 3,
	bnkf2_StatusCode_inputIsInvalid = 4,
	bnkf2_StatusCode_fileTableUncompressedChunkThresholdIsTooBig = 5,
	bnkf2_StatusCode_impossiblyLargeFileTableInBNK = 6,
	bnkf2_StatusCode_impossiblyLongFilePathInBNK = 7,
	bnkf2_StatusCode_outOfBoundsDataOffsetInBNK = 8,
	bnkf2_StatusCode_outOfBoundsDataSpanInBNK = 9,
	bnkf2_StatusCode_mismatchingCompressedChunkCountInBNK = 10,
	bnkf2_StatusCode_invalidZLibHeaderForFileInBNK = 11,
	bnkf2_StatusCode_presetDictionaryRequiredByFileInBNK = 12,
	bnkf2_StatusCode_couldNotFindEndOfCentralDirectoryRecordInZip = 13,
	bnkf2_StatusCode_invalidSignatureForEndOfCentralDirectoryLocator64InZip = 14,
	bnkf2_StatusCode_invalidSignatureForEndOfCentralDirectoryRecord64InZip = 15,
	bnkf2_StatusCode_invalidSignatureForCentralDirectoryRecordInZip = 16,
	bnkf2_StatusCode_invalidSignatureForLocalFileHeaderInZip = 17,
	bnkf2_StatusCode_invalidOffsetForCentralDirectoryInZip = 18,
	bnkf2_StatusCode_invalidSizeForCentralDirectoryInZip = 19,
	bnkf2_StatusCode_invalidOffsetForEndOfCentralDirectoryRecord64InZip = 20,
	bnkf2_StatusCode_invalidSizeForEndOfCentralDirectoryRecord64InZip = 21,
	bnkf2_StatusCode_invalidOffsetForCentralDirectoryRecordInZip = 22,
	bnkf2_StatusCode_unsupportedVersionRequiredForExtractionInZip = 23,
	bnkf2_StatusCode_unsupportedEncryptedFileInZip = 24,
	bnkf2_StatusCode_unsupportedCompressedPatchedDataInZip = 25,
	bnkf2_StatusCode_unsupportedEnhancedCompressionInZip = 26,
	bnkf2_StatusCode_unsupportedCompressionMethodInZip = 27,
	bnkf2_StatusCode_invalidFooterSizeForCentralDirectoryRecordInZip = 28,
	bnkf2_StatusCode_invalidFooterSizeForLocalFileHeaderInZip = 29,
	bnkf2_StatusCode_excessivelyLongFileNameForCentralDirectoryRecordInZip = 30,
	bnkf2_StatusCode_tooMuchFileNameInZip = 31,
	bnkf2_StatusCode_invalidExtraFieldLengthForCentralDirectoryRecordInZip = 32,
	bnkf2_StatusCode_invalidExtraFieldSizeForCentralDirectoryRecordInZip = 33,
	bnkf2_StatusCode_failedToFindExtendedInformationExtraField64ForCentralDirectoryRecordInZip = 34,
	bnkf2_StatusCode_invalidOffsetForLocalFileHeaderInZip = 35,
	bnkf2_StatusCode_invalidCompressedSizeForFileInZip = 36,
	bnkf2_StatusCode_invalidUncompressedSizeForFileInZip = 37,
	bnkf2_StatusCode_zipFileIsTooBigForBNKFile = 38,
	bnkf2_StatusCode_invalidSizeForFileInZip = 39
} bnkf2_StatusCode;


typedef enum
{
	bnkf2_StatusCodeSource_bnkf2 = 0,
	bnkf2_StatusCodeSource_caller = 1,
	bnkf2_StatusCodeSource_system = 2,
	bnkf2_StatusCodeSource_zlib = 3
} bnkf2_StatusCodeSource;


typedef struct
{
	uint32_t code;
	uint8_t padding[3];
	uint8_t source; /* bnkf2_StatusCodeSource */
} bnkf2_Status;


typedef enum
{
	bnkf2_DEFLATECompressionLevel_default_ = 0,
	/* *Fastest decompression of the output
	    whilst still performing _some_ compression of the input. */
	bnkf2_DEFLATECompressionLevel_fastestDecompresion = 1,
	bnkf2_DEFLATECompressionLevel_strongestCompression = 2,
	bnkf2_DEFLATECompressionLevel_0 = 3,
	bnkf2_DEFLATECompressionLevel_1 = 4,
	bnkf2_DEFLATECompressionLevel_2 = 5,
	bnkf2_DEFLATECompressionLevel_3 = 6,
	bnkf2_DEFLATECompressionLevel_4 = 7,
	bnkf2_DEFLATECompressionLevel_5 = 8,
	bnkf2_DEFLATECompressionLevel_6 = 9,
	bnkf2_DEFLATECompressionLevel_7 = 10,
	bnkf2_DEFLATECompressionLevel_8 = 11,
	bnkf2_DEFLATECompressionLevel_9 = 12
} bnkf2_DEFLATECompressionLevel;


typedef enum
{
	bnkf2_ZLibMemoryLevel_default_ = 0,
	bnkf2_ZLibMemoryLevel_0 = 1,
	bnkf2_ZLibMemoryLevel_1 = 2,
	bnkf2_ZLibMemoryLevel_2 = 3,
	bnkf2_ZLibMemoryLevel_3 = 4,
	bnkf2_ZLibMemoryLevel_4 = 5,
	bnkf2_ZLibMemoryLevel_5 = 6,
	bnkf2_ZLibMemoryLevel_6 = 7,
	bnkf2_ZLibMemoryLevel_7 = 8,
	bnkf2_ZLibMemoryLevel_8 = 9,
	bnkf2_ZLibMemoryLevel_9 = 10
} bnkf2_ZLibMemoryLevel;


typedef size_t (*bnkf2_ContiguousOutputBufferFlusher) (
	void *context,
	uint8_t **freshBuffer,
	uint8_t *flushBuffer,
	size_t flushSize
);

typedef size_t (*bnkf2_DiscontiguousOutputBufferFlusher) (
	void *context,
	uint8_t **freshBuffer,
	uint8_t *flushBuffer,
	size_t flushSize,
	uint32_t bufferIndex
);

typedef void *(*bnkf2_CStyleMemoryAllocate) (void *context, size_t size);
typedef void (*bnkf2_CStyleMemoryFree) (void *context, void *memory);

typedef void *(*bnkf2_MemoryAllocate) (void *context, size_t size, size_t alignment);
typedef void (*bnkf2_MemoryFree) (void *context, void *memory, size_t size);

typedef void (*bnkf2_ProgressObserver) (void *context, size_t progressOpcode, const void *operand0, size_t operand1);


typedef struct
{
	void *context;
	bnkf2_ProgressObserver observer;
} bnkf2_ContextualisedProgressObserver;


typedef enum
{
	bnkf2_BNKToZipProgressOpcode_decompressingFileTable = 0,
	bnkf2_BNKToZipProgressOpcode_decompressedFileTable = 1,
	bnkf2_BNKToZipProgressOpcode_decompressingFile = 2,
	bnkf2_BNKToZipProgressOpcode_copyingFile = 3,
	bnkf2_BNKToZipProgressOpcode_skippedDuplicateFileName = 4,
	bnkf2_BNKToZipProgressOpcode_checksummingFile = 5,
	bnkf2_BNKToZipProgressOpcode_checksummedFile = 6,
	bnkf2_BNKToZipProgressOpcode_writingFileMetadata = 7
} bnkf2_BNKToZipProgressOpcode;


typedef enum
{
	bnkf2_ZipToBNKProgressOpcode_searchingForCentralDirectory = 0,
	bnkf2_ZipToBNKProgressOpcode_foundCentralDirectory = 1,
	bnkf2_ZipToBNKProgressOpcode_copyingFile = 2,
	bnkf2_ZipToBNKProgressOpcode_compressingFile = 3,
	bnkf2_ZipToBNKProgressOpcode_compressingFileChunk = 4,
	bnkf2_ZipToBNKProgressOpcode_compressedFileChunk = 5,
	bnkf2_ZipToBNKProgressOpcode_decompressingFile = 6
} bnkf2_ZipToBNKProgressOpcode;


#ifdef z_stream
#	define bnkf2_zlib_z_stream z_stream;
#else
	typedef struct bnkf2_zlib_z_stream bnkf2_zlib_z_stream;
#endif


typedef enum
{
	bnkf2_DynamicallyLinkedZLibProvisionVersion_latest = 0,
	bnkf2_DynamicallyLinkedZLibProvisionVersion_0 = 0
} bnkf2_DynamicallyLinkedZLibProvisionVersion;


typedef int (*bnkf2_zlib_deflateInit_) (bnkf2_zlib_z_stream *strm, int level, const char *version, int stream_size);
typedef int (*bnkf2_zlib_deflateInit2_) (bnkf2_zlib_z_stream *strm, int level, int method, int windowBits, int memLevel, int strategy, const char *version, int stream_size);
typedef int (*bnkf2_zlib_deflate) (bnkf2_zlib_z_stream *strm, int flush);
typedef int (*bnkf2_zlib_deflateEnd) (bnkf2_zlib_z_stream *strm);
typedef int (*bnkf2_zlib_deflateReset) (bnkf2_zlib_z_stream *strm);
typedef int (*bnkf2_zlib_deflatePrime) (bnkf2_zlib_z_stream *strm, int bits, int value);
typedef int (*bnkf2_zlib_deflateTune) (bnkf2_zlib_z_stream *strm, int good_length, int max_lazy, int nice_length, int max_chain);
typedef int (*bnkf2_zlib_inflateInit_) (bnkf2_zlib_z_stream *strm, const char *version, int stream_size);
typedef int (*bnkf2_zlib_inflateInit2_) (bnkf2_zlib_z_stream *strm, int windowBits, const char *version, int stream_size);
typedef int (*bnkf2_zlib_inflate) (bnkf2_zlib_z_stream *strm, int flush);
typedef int (*bnkf2_zlib_inflateEnd) (bnkf2_zlib_z_stream *strm);
typedef int (*bnkf2_zlib_inflateReset) (bnkf2_zlib_z_stream *strm);
typedef int (*bnkf2_zlib_inflateReset2) (bnkf2_zlib_z_stream *strm, int windowBits);
typedef int (*bnkf2_zlib_inflatePrime) (bnkf2_zlib_z_stream *strm, int bits, int value);
typedef unsigned long (*bnkf2_zlib_crc32) (unsigned long crc, const uint8_t *buf, uint32_t len);


typedef struct
{
	size_t provisionVersion; /* bnkf2_DynamicallyLinkedZLibProvisionVersion */

	bnkf2_zlib_deflateInit_ deflateInit_;
	bnkf2_zlib_deflateInit2_ deflateInit2_;
	bnkf2_zlib_deflate deflate;
	bnkf2_zlib_deflateEnd deflateEnd;
	bnkf2_zlib_deflateReset deflateReset;
	bnkf2_zlib_deflatePrime deflatePrime;
	bnkf2_zlib_deflateTune deflateTune;
	bnkf2_zlib_inflateInit_ inflateInit_;
	bnkf2_zlib_inflateInit2_ inflateInit2_;
	bnkf2_zlib_inflate inflate;
	bnkf2_zlib_inflateEnd inflateEnd;
	bnkf2_zlib_inflateReset inflateReset;
	bnkf2_zlib_inflateReset2 inflateReset2;
	bnkf2_zlib_inflatePrime inflatePrime;
	bnkf2_zlib_crc32 crc32;
} bnkf2_DynamicallyLinkedZLib;


typedef enum
{
	bnkf2_MemoryAllocatorProvisionPackedStateFlags_none = 0,
	bnkf2_MemoryAllocatorProvisionPackedStateFlags_allocatesZeroedMemory = 1 << 0,
	bnkf2_MemoryAllocatorProvisionPackedStateFlags_cStyleAllocatesZeroedMemory = 1 << 1
} bnkf2_MemoryAllocatorProvisionPackedStateFlags;


typedef struct
{
	size_t value;
} bnkf2_MemoryAllocatorProvisionPackedState;


typedef struct
{
#	define bnkf2_MemoryAllocatorProvision_fundamentalAlignment (sizeof(void*) << 1)

	bnkf2_MemoryAllocatorProvisionPackedState packedState;

	void *memoryContext;
	bnkf2_MemoryAllocate memoryAllocate;
	bnkf2_MemoryFree memoryFree;

	void *cStyleMemoryContext;
	bnkf2_CStyleMemoryAllocate cStyleMemoryAllocate;
	bnkf2_CStyleMemoryFree cStyleMemoryFree;
} bnkf2_MemoryAllocatorProvision;


typedef enum
{
	bnkf2_BNKToZipResultV0PackedStateFlags_none = 0,
	bnkf2_BNKToZipResultV0PackedStateFlags_bnkCompressionStatusIsKnown = 1 << 0,
	bnkf2_BNKToZipResultV0PackedStateFlags_bnkWasCompressed = 1 << 1
} bnkf2_BNKToZipResultV0PackedStateFlags;


typedef struct
{
	size_t value;
} bnkf2_BNKToZipResultV0PackedState;


typedef struct
{
	bnkf2_BNKToZipResultV0PackedState packedState;
} bnkf2_BNKToZipResultV0;


typedef struct
{
	union
	{
		bnkf2_BNKToZipResultV0 v0;
	};
} bnkf2_BNKToZipResult;


typedef enum
{
	bnkf2_BNKToZipStatePackedStateFlags_none = 0,
	bnkf2_BNKToZipStatePackedStateFlags_forwardAllocatorToZLib = 1 << 0,
	bnkf2_BNKToZipStatePackedStateFlags_omitBNKF2Metadata = 1 << 3,
	bnkf2_BNKToZipStatePackedStateFlags_emitDuplicateFiles = 1 << 4
} bnkf2_BNKToZipStatePackedStateFlags;


typedef struct
{
	size_t value;
} bnkf2_BNKToZipStatePackedState;


typedef struct
{
	bnkf2_BNKToZipStatePackedState packedState;

	bnkf2_MemoryAllocatorProvision *memoryAllocators;
	const bnkf2_DynamicallyLinkedZLib *zlib;
	bnkf2_ContextualisedProgressObserver progressObserver;

	bnkf2_BNKToZipResult *extendedReturnChannel;
} bnkf2_BNKToZipState;


typedef enum
{
	bnkf2_ZipToBNKResultV0PackedStateFlags_none = 0,
	bnkf2_ZipToBNKResultV0PackedStateFlags_bnkCompressionStatusIsKnown = 1 << 0,
	bnkf2_ZipToBNKResultV0PackedStateFlags_bnkIsCompressed = 1 << 1
} bnkf2_ZipToBNKResultV0PackedStateFlags;


typedef struct
{
	size_t value;
} bnkf2_ZipToBNKResultV0PackedState;


typedef struct
{
	bnkf2_ZipToBNKResultV0PackedState packedState;
} bnkf2_ZipToBNKResultV0;


typedef struct
{
	union
	{
		bnkf2_ZipToBNKResultV0 v0;
	};
} bnkf2_ZipToBNKResult;


typedef enum
{
	bnkf2_ZipToBNKStatePackedStateFlags_none = 0,
	bnkf2_ZipToBNKStatePackedStateFlags_forwardAllocatorToZLib = 1 << 0,
	bnkf2_ZipToBNKStatePackedStateFlags_ignoreBNKF2MetadataForCompressionSetting = 1 << 5,
	bnkf2_ZipToBNKStatePackedStateFlags_outputCompressedBNK = 1 << 6
} bnkf2_ZipToBNKStatePackedStateFlags;


typedef struct
{
	size_t value;
} bnkf2_ZipToBNKStatePackedState;


typedef struct
{
	bnkf2_ZipToBNKStatePackedState packedState;

	bnkf2_MemoryAllocatorProvision *memoryAllocators;
	const bnkf2_DynamicallyLinkedZLib *zlib;
	bnkf2_ContextualisedProgressObserver progressObserver;

	bnkf2_ZipToBNKResult *extendedReturnChannel;

	uint8_t fileTableCompressionLevel; /* bnkf2_DEFLATECompressionLevel */
	uint8_t fileTableMemoryLevel; /* bnkf2_ZLibMemoryLevel */
	uint8_t fileDataCompressionLevel; /* bnkf2_DEFLATECompressionLevel */
	uint8_t fileDataMemoryLevel; /* bnkf2_ZLibMemoryLevel */

	uint32_t fileTableUncompressedChunkThreshold;
} bnkf2_ZipToBNKState;


typedef struct
{
	size_t size;
	const uint8_t *data;
} bnkf2_const_uint8_t_Slice;


BNKF2_IMPORT BNKF2_D_SYSTEM_CONVENTION(
bnkf2_Status) bnkf2_bnkToZip (
	void *context,
	bnkf2_const_uint8_t_Slice *inputBuffer,
	bnkf2_ContiguousOutputBufferFlusher outputFlusher,
	bnkf2_BNKToZipState *state
);


BNKF2_IMPORT BNKF2_D_SYSTEM_CONVENTION(
bnkf2_Status) bnkf2_zipToBNK (
	void *context,
	bnkf2_const_uint8_t_Slice *inputBuffer,
	bnkf2_DiscontiguousOutputBufferFlusher outputFlusher,
	bnkf2_ZipToBNKState *state
);


BNKF2_IMPORT BNKF2_D_SYSTEM_CONVENTION(
bnkf2_Status) bnkf2_bnkIsCompressed (
	const uint8_t *inputBuffer,
	size_t inputLength,
	uint8_t *bnkIsCompressed
);


BNKF2_IMPORT BNKF2_D_SYSTEM_CONVENTION(
const char *) bnkf2_messageForStatusCode (bnkf2_StatusCode code);


BNKF2_IMPORT BNKF2_D_SYSTEM_CONVENTION(
const char *) bnkf2_messageForStatusCodeWithLength (bnkf2_StatusCode code, uint32_t *length);


BNKF2_IMPORT extern uint32_t bnkf2_longestStatusCodeMessageLength;

#ifdef __cplusplus
}
#endif

