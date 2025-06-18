
namespace BNKF2.Native;

using BNKF2.ZLib;

using System;
using System.Runtime.InteropServices;


/* See `bnkf2.d` or `bnkf2.h` for the actual types of all the `IntPtr`s
   in the following definitions.
   We're targeting the .NET Framework, so we can't use the function pointer types
   introduced in C# 9.0. */


public static class Exports
{
	[DllImport("bnkf2", CallingConvention = CallingConvention.Winapi, CharSet = CharSet.Unicode)]
	public static unsafe extern BNKF2Status bnkf2_bnkToZip (
		IntPtr context,
		DSlice<byte>* inputBuffer,
		IntPtr outputFlusher,
		BNKToZipState* state
	);


	[DllImport("bnkf2", CallingConvention = CallingConvention.Winapi, CharSet = CharSet.Unicode)]
	public static unsafe extern BNKF2Status bnkf2_zipToBNK (
		IntPtr context,
		DSlice<byte>* inputBuffer,
		IntPtr outputFlusher,
		ZipToBNKState* state
	);


	[DllImport("bnkf2", CallingConvention = CallingConvention.Winapi, CharSet = CharSet.Unicode)]
	public static unsafe extern BNKF2Status bnkf2_bnkIsCompressed (
		byte* inputBuffer,
		nuint inputLength,
		byte* bnkIsCompressed
	);


	[DllImport("bnkf2", CallingConvention = CallingConvention.Winapi, CharSet = CharSet.Unicode)]
	public static unsafe extern byte* bnkf2_messageForStatusCode (BNKF2StatusCode code);


	[DllImport("bnkf2", CallingConvention = CallingConvention.Winapi, CharSet = CharSet.Unicode)]
	public static unsafe extern byte* bnkf2_messageForStatusCodeWithLength (BNKF2StatusCode code, uint* length);


	[DllImport("bnkf2", CallingConvention = CallingConvention.Winapi, CharSet = CharSet.Unicode)]
	public static extern uint bnkf2_getLongestStatusCodeMessageLength ();
}


/* The ABI-representation of a slice in the D programming language. */
public unsafe struct DSlice <T>
where T : unmanaged
{
	public nuint size;
	public T* data;
}


public struct BNKF2DynamicallyLinkedZLib
{
	public enum ProvisionVersion : uint
	{
		latest = _0,
		_0 = 0
	}

	public ProvisionVersion provisionVersion;

	public IntPtr deflateInit_;
	public IntPtr deflateInit2_;
	public IntPtr deflate;
	public IntPtr deflateEnd;
	public IntPtr deflateReset;
	public IntPtr deflatePrime;
	public IntPtr deflateTune;
	public IntPtr inflateInit_;
	public IntPtr inflateInit2_;
	public IntPtr inflate;
	public IntPtr inflateEnd;
	public IntPtr inflateReset;
	public IntPtr inflateReset2;
	public IntPtr inflatePrime;
	public IntPtr crc32;

	public static unsafe BNKF2DynamicallyLinkedZLib LinkViaDllImport ()
	{
		return new BNKF2DynamicallyLinkedZLib{
			provisionVersion = ProvisionVersion.latest,
			deflateInit_ = Marshal.GetFunctionPointerForDelegate((Ptr_deflateInit_) ZLib.deflateInit_),
			deflateInit2_ = Marshal.GetFunctionPointerForDelegate((Ptr_deflateInit2_) ZLib.deflateInit2_),
			deflate = Marshal.GetFunctionPointerForDelegate((Ptr_deflate) ZLib.deflate),
			deflateEnd = Marshal.GetFunctionPointerForDelegate((Ptr_deflateEnd) ZLib.deflateEnd),
			deflateReset = Marshal.GetFunctionPointerForDelegate((Ptr_deflateReset) ZLib.deflateReset),
			deflatePrime = Marshal.GetFunctionPointerForDelegate((Ptr_deflatePrime) ZLib.deflatePrime),
			deflateTune = Marshal.GetFunctionPointerForDelegate((Ptr_deflateTune) ZLib.deflateTune),
			inflateInit_ = Marshal.GetFunctionPointerForDelegate((Ptr_inflateInit_) ZLib.inflateInit_),
			inflateInit2_ = Marshal.GetFunctionPointerForDelegate((Ptr_inflateInit2_) ZLib.inflateInit2_),
			inflate = Marshal.GetFunctionPointerForDelegate((Ptr_inflate) ZLib.inflate),
			inflateEnd = Marshal.GetFunctionPointerForDelegate((Ptr_inflateEnd) ZLib.inflateEnd),
			inflateReset = Marshal.GetFunctionPointerForDelegate((Ptr_inflateReset) ZLib.inflateReset),
			inflateReset2 = Marshal.GetFunctionPointerForDelegate((Ptr_inflateReset2) ZLib.inflateReset2),
			inflatePrime = Marshal.GetFunctionPointerForDelegate((Ptr_inflatePrime) ZLib.inflatePrime),
			crc32 = Marshal.GetFunctionPointerForDelegate((Ptr_crc32) ZLib.crc32),
		};
	}
}


public struct BNKF2MemoryAllocatorProvision
{
	public static readonly nuint fundamentalAlignment = (nuint) IntPtr.Size << 1;

	public PackedState packedState;

	public IntPtr memoryContext;
	public IntPtr memoryAllocate;
	public IntPtr memoryFree;

	public IntPtr cStyleMemoryContext;
	public IntPtr cStyleMemoryAllocate;
	public IntPtr cStyleMemoryFree;

	public struct PackedState
	{
		public nuint value;

		public enum Flags : uint
		{
			none = 0,
			allocatesZeroedMemory = 1 << 0,
			cStyleAllocatesZeroedMemory = 1 << 1
		}
	}

	public static unsafe BNKF2MemoryAllocatorProvision ProvideDotNetAllocator ()
	{
		return new BNKF2MemoryAllocatorProvision{
			cStyleMemoryAllocate = Marshal.GetFunctionPointerForDelegate((Ptr_DotNetAllocate) DotNetAllocate),
			cStyleMemoryFree = Marshal.GetFunctionPointerForDelegate((Ptr_DotNetFree) DotNetFree),
		};
	}

	public static unsafe void* DotNetAllocate (void* context, nuint size)
	{
		try
		{
			#if NETFRAMEWORK
				return (void*) Marshal.AllocHGlobal((nint) size);
			#else
				return NativeMemory.Alloc(size);
			#endif
		}
		catch (Exception)
		{
			return null;
		}
	}

	public static unsafe void DotNetFree (void* context, void* memory)
	{
		try
		{
			#if NETFRAMEWORK
				Marshal.FreeHGlobal((nint) memory);
			#else
				NativeMemory.Free(memory);
			#endif
		}
		catch (Exception)
		{}
	}

	[UnmanagedFunctionPointer(CallingConvention.Winapi)]
	public unsafe delegate void* Ptr_DotNetAllocate (void* context, nuint size);

	[UnmanagedFunctionPointer(CallingConvention.Winapi)]
	public unsafe delegate void Ptr_DotNetFree (void* context, void* memory);
}


public struct ContextualisedProgressObserver
{
	public IntPtr context;
	public IntPtr observer;
}


public struct BNKF2Status
{
	public uint code;
	public byte padding0;
	public byte padding1;
	public byte padding2;
	public CodeSource source;

	public enum CodeSource : byte
	{
		bnkf2 = 0,
		caller = 1,
		system = 2,
		zlib = 3
	}
}


public enum BNKToZipProgressOpcode : uint
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


[StructLayout(LayoutKind.Explicit)]
public struct BNKToZipResult
{
	public struct V0
	{
		public PackedState packedState;

		public struct PackedState
		{
			public nuint value;

			public enum Flags : uint
			{
				none = 0,
				bnkCompressionStatusIsKnown = 1 << 0,
				bnkWasCompressed = 1 << 1
			}
		}
	}

	[FieldOffset(0)] public V0 v0;
}


public unsafe struct BNKToZipState
{
	public PackedState packedState;

	public struct PackedState
	{
		public enum Flags : uint
		{
			none = 0,
			forwardAllocatorToZLib = 1 << 0,
			omitBNKF2Metadata = 1 << 3,
			emitDuplicateFiles = 1 << 4
		}

		public nuint value;
	}

	public BNKF2MemoryAllocatorProvision* memoryAllocators;
	public BNKF2DynamicallyLinkedZLib* zlib;
	public ContextualisedProgressObserver progressObserver;

	public BNKToZipResult* extendedReturnChannel;
}


public enum DEFLATECompressionLevel : byte
{
	default_ = 0,
	/* *Fastest decompression of the output
	    whilst still performing _some_ compression of the input. */
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


public enum ZLibMemoryLevel : byte
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


public enum ZipToBNKProgressOpcode : uint
{
	searchingForCentralDirectory = 0,
	foundCentralDirectory = 1,
	copyingFile = 2,
	compressingFile = 3,
	compressingFileChunk = 4,
	compressedFileChunk = 5,
	decompressingFile = 6
}


[StructLayout(LayoutKind.Explicit)]
public struct ZipToBNKResult
{
	public struct V0
	{
		public PackedState packedState;

		public struct PackedState
		{
			public nuint value;

			public enum Flags : uint
			{
				none = 0,
				bnkCompressionStatusIsKnown = 1 << 0,
				bnkIsCompressed = 1 << 1
			}
		}
	}

	[FieldOffset(0)] public V0 v0;
}


public unsafe struct ZipToBNKState
{
	public PackedState packedState;

	public struct PackedState
	{
		public enum Flags : uint
		{
			none = 0,
			forwardAllocatorToZLib = 1 << 0,
			ignoreBNKF2MetadataForCompressionSetting = 1 << 5,
			outputCompressedBNK = 1 << 6
		}

		public nuint value;
	}

	public BNKF2MemoryAllocatorProvision* memoryAllocators;
	public BNKF2DynamicallyLinkedZLib* zlib;
	public ContextualisedProgressObserver progressObserver;

	public ZipToBNKResult* extendedReturnChannel;

	public DEFLATECompressionLevel fileTableCompressionLevel;
	public ZLibMemoryLevel fileTableMemoryLevel;
	public DEFLATECompressionLevel fileDataCompressionLevel;
	public ZLibMemoryLevel fileDataMemoryLevel;

	public uint fileTableUncompressedChunkThreshold;
}


public enum BNKF2StatusCode : uint
{
	success = 0,
	memoryAllocationFailed = 1,
	inputIsTooLong = 2,
	inputIsTruncated = 3,
	inputIsInvalid = 4,
	fileTableUncompressedChunkThresholdIsTooBig = 5,
	impossiblyLargeFileTableInBNK = 6,
	impossiblyLongFilePathInBNK = 7,
	outOfBoundsDataOffsetInBNK = 8,
	outOfBoundsDataSpanInBNK = 9,
	mismatchingCompressedChunkCountInBNK = 10,
	invalidZLibHeaderForFileInBNK = 11,
	presetDictionaryRequiredByFileInBNK = 12,
	couldNotFindEndOfCentralDirectoryRecordInZip = 13,
	invalidSignatureForEndOfCentralDirectoryLocator64InZip = 14,
	invalidSignatureForEndOfCentralDirectoryRecord64InZip = 15,
	invalidSignatureForCentralDirectoryRecordInZip = 16,
	invalidSignatureForLocalFileHeaderInZip = 17,
	invalidOffsetForCentralDirectoryInZip = 18,
	invalidSizeForCentralDirectoryInZip = 19,
	invalidOffsetForEndOfCentralDirectoryRecord64InZip = 20,
	invalidSizeForEndOfCentralDirectoryRecord64InZip = 21,
	invalidOffsetForCentralDirectoryRecordInZip = 22,
	unsupportedVersionRequiredForExtractionInZip = 23,
	unsupportedEncryptedFileInZip = 24,
	unsupportedCompressedPatchedDataInZip = 25,
	unsupportedEnhancedCompressionInZip = 26,
	unsupportedCompressionMethodInZip = 27,
	invalidFooterSizeForCentralDirectoryRecordInZip = 28,
	invalidFooterSizeForLocalFileHeaderInZip = 29,
	excessivelyLongFileNameForCentralDirectoryRecordInZip = 30,
	tooMuchFileNameInZip = 31,
	invalidExtraFieldLengthForCentralDirectoryRecordInZip = 32,
	invalidExtraFieldSizeForCentralDirectoryRecordInZip = 33,
	failedToFindExtendedInformationExtraField64ForCentralDirectoryRecordInZip = 34,
	invalidOffsetForLocalFileHeaderInZip = 35,
	invalidCompressedSizeForFileInZip = 36,
	invalidUncompressedSizeForFileInZip = 37,
	zipFileIsTooBigForBNKFile = 38,
	invalidSizeForFileInZip = 39,
}

