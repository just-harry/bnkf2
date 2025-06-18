
namespace BNKF2.NET;

using BNKF2.Native;
using BNKF2.ZLib;

using Microsoft.Win32.SafeHandles;

using System;
using System.IO;
using System.IO.MemoryMappedFiles;
using System.Runtime.InteropServices;
using System.Text;


public class BNKF2RuntimeGlue
{
	public static BNKF2RuntimeGlue defaultInstance = new BNKF2RuntimeGlue{
		memoryAllocators = BNKF2MemoryAllocatorProvision.ProvideDotNetAllocator(),
		zlib = BNKF2DynamicallyLinkedZLib.LinkViaDllImport()
	};

	public BNKF2MemoryAllocatorProvision memoryAllocators;
	public BNKF2DynamicallyLinkedZLib zlib;
}


public class BNKToZipConverter
{
	public BNKToZipState.PackedState packedState;

	public BNKF2ContiguousOutputBufferFlusher outputFlusher;
	public BNKToZipProgressObserver? progressObserver;

	public BNKToZipConverter (BNKF2ContiguousOutputBufferFlusher outputFlusher)
	{
		this.outputFlusher = outputFlusher;
	}

	public struct ConversionResult
	{
		public BNKF2Status status;
		public BNKToZipResult.V0 result;
	}

	public unsafe ConversionResult ConvertBNKToZip (byte* inputBuffer, nuint inputLength)
	{
		return this.ConvertBNKToZip(inputBuffer, inputLength, BNKF2RuntimeGlue.defaultInstance);
	}

	public unsafe ConversionResult ConvertBNKToZip (byte* inputBuffer, nuint inputLength, BNKF2RuntimeGlue runtimeGlue)
	{
		fixed (BNKF2MemoryAllocatorProvision* memoryAllocators = &runtimeGlue.memoryAllocators)
		{
			fixed (BNKF2DynamicallyLinkedZLib* zlib = &runtimeGlue.zlib)
			{
				ConversionResult conversionResult;

				BNKToZipState state = new BNKToZipState{
					packedState = this.packedState,
					memoryAllocators = memoryAllocators,
					zlib = zlib,
					extendedReturnChannel = (BNKToZipResult*) &conversionResult.result
				};

				GCHandle progressObserverContext = default;

				if (this.progressObserver != null)
				{
					progressObserverContext = GCHandle.Alloc(this.progressObserver);
				}

				try
				{
					if (this.progressObserver != null)
					{
						state.progressObserver.observer = Marshal.GetFunctionPointerForDelegate(
							(BNKF2ProgressObserver.Ptr_ProgressObserver) BNKF2ProgressObserver.ProgressObserver
						);
						state.progressObserver.context = GCHandle.ToIntPtr(progressObserverContext);
					}

					DSlice<byte> input = new DSlice<byte>{data = inputBuffer, size = inputLength};

					IntPtr outputFlusher = Marshal.GetFunctionPointerForDelegate(
						(BNKF2ContiguousOutputBufferFlusher.Ptr_ContiguousOutputBufferFlusher) BNKF2ContiguousOutputBufferFlusher.ContiguousOutputBufferFlusher
					);
					GCHandle outputFlusherContext = GCHandle.Alloc(this.outputFlusher);

					try
					{
						 conversionResult.status = Exports.bnkf2_bnkToZip(
							GCHandle.ToIntPtr(outputFlusherContext),
							&input,
							outputFlusher,
							&state
						);

						 return conversionResult;
					}
					finally
					{
						outputFlusherContext.Free();
					}
				}
				finally
				{
					if (progressObserverContext.IsAllocated)
					{
						progressObserverContext.Free();
					}
				}
			}
		}
	}

	public ConversionResult ConvertBNKToZip (SafeMemoryMappedViewHandle input)
	{
		unsafe
		{
			byte* inputBuffer = null;
			input.AcquirePointer(ref inputBuffer);

			try
			{
				return this.ConvertBNKToZip(inputBuffer, unchecked((nuint) input.ByteLength));
			}
			finally
			{
				input.ReleasePointer();
			}
		}
	}

	public ConversionResult ConvertBNKToZip (string filePath)
	{
		using var fileMapping = MemoryMappedFile.CreateFromFile(
			filePath,
			FileMode.Open,
			null,
			0,
			MemoryMappedFileAccess.ReadWrite
		);

		using var viewAccessor = fileMapping.CreateViewAccessor(0, 0, MemoryMappedFileAccess.ReadWrite);

		return this.ConvertBNKToZip(viewAccessor.SafeMemoryMappedViewHandle);
	}

	public bool EmitDuplicateFiles
	{
		get => (this.packedState.value & (nuint) BNKToZipState.PackedState.Flags.emitDuplicateFiles) != 0;
		set
		{
			this.packedState.value &= ~(nuint) BNKToZipState.PackedState.Flags.emitDuplicateFiles;
			this.packedState.value |= value ? (nuint) BNKToZipState.PackedState.Flags.emitDuplicateFiles : 0;
		}
	}

	public bool OmitBNKF2Metadata
	{
		get => (this.packedState.value & (nuint) BNKToZipState.PackedState.Flags.omitBNKF2Metadata) != 0;
		set
		{
			this.packedState.value &= ~(nuint) BNKToZipState.PackedState.Flags.omitBNKF2Metadata;
			this.packedState.value |= value ? (nuint) BNKToZipState.PackedState.Flags.omitBNKF2Metadata : 0;
		}
	}
}


public class ZipToBNKConverter
{
	public ZipToBNKState.PackedState packedState;
	public DEFLATECompressionLevel fileTableCompressionLevel;
	public ZLibMemoryLevel fileTableMemoryLevel;
	public DEFLATECompressionLevel fileDataCompressionLevel;
	public ZLibMemoryLevel fileDataMemoryLevel;
	public uint fileTableUncompressedChunkThreshold;

	public BNKF2DiscontiguousOutputBufferFlusher outputFlusher;
	public ZipToBNKProgressObserver? progressObserver;

	public ZipToBNKConverter (BNKF2DiscontiguousOutputBufferFlusher outputFlusher)
	{
		this.outputFlusher = outputFlusher;
	}

	public struct ConversionResult
	{
		public BNKF2Status status;
		public ZipToBNKResult.V0 result;
	}

	public unsafe ConversionResult ConvertZipToBNK (byte* inputBuffer, nuint inputLength)
	{
		return this.ConvertZipToBNK(inputBuffer, inputLength, BNKF2RuntimeGlue.defaultInstance);
	}

	public unsafe ConversionResult ConvertZipToBNK (byte* inputBuffer, nuint inputLength, BNKF2RuntimeGlue runtimeGlue)
	{
		fixed (BNKF2MemoryAllocatorProvision* memoryAllocators = &runtimeGlue.memoryAllocators)
		{
			fixed (BNKF2DynamicallyLinkedZLib* zlib = &runtimeGlue.zlib)
			{
				ConversionResult conversionResult;

				ZipToBNKState state = new ZipToBNKState{
					packedState = this.packedState,
					memoryAllocators = memoryAllocators,
					zlib = zlib,
					extendedReturnChannel = (ZipToBNKResult*) &conversionResult.result,
					fileTableCompressionLevel = fileTableCompressionLevel,
					fileTableMemoryLevel = fileTableMemoryLevel,
					fileDataCompressionLevel = fileDataCompressionLevel,
					fileDataMemoryLevel = fileDataMemoryLevel,
					fileTableUncompressedChunkThreshold = fileTableUncompressedChunkThreshold
				};

				GCHandle progressObserverContext = default;

				if (this.progressObserver != null)
				{
					progressObserverContext = GCHandle.Alloc(this.progressObserver);
				}

				try
				{
					if (this.progressObserver != null)
					{
						state.progressObserver.observer = Marshal.GetFunctionPointerForDelegate(
							(BNKF2ProgressObserver.Ptr_ProgressObserver) BNKF2ProgressObserver.ProgressObserver
						);
						state.progressObserver.context = GCHandle.ToIntPtr(progressObserverContext);
					}

					DSlice<byte> input = new DSlice<byte>{data = inputBuffer, size = inputLength};

					IntPtr outputFlusher = Marshal.GetFunctionPointerForDelegate(
						(BNKF2DiscontiguousOutputBufferFlusher.Ptr_DiscontiguousOutputBufferFlusher) BNKF2DiscontiguousOutputBufferFlusher.DiscontiguousOutputBufferFlusher
					);
					GCHandle outputFlusherContext = GCHandle.Alloc(this.outputFlusher);

					try
					{
						 conversionResult.status = Exports.bnkf2_zipToBNK(
							GCHandle.ToIntPtr(outputFlusherContext),
							&input,
							outputFlusher,
							&state
						);

						 return conversionResult;
					}
					finally
					{
						outputFlusherContext.Free();
					}
				}
				finally
				{
					if (progressObserverContext.IsAllocated)
					{
						progressObserverContext.Free();
					}
				}
			}
		}
	}

	public ConversionResult ConvertZipToBNK (SafeMemoryMappedViewHandle input)
	{
		unsafe
		{
			byte* inputBuffer = null;
			input.AcquirePointer(ref inputBuffer);

			try
			{
				return this.ConvertZipToBNK(inputBuffer, unchecked((nuint) input.ByteLength));
			}
			finally
			{
				input.ReleasePointer();
			}
		}
	}

	public ConversionResult ConvertZipToBNK (string filePath)
	{
		using var fileMapping = MemoryMappedFile.CreateFromFile(
			filePath,
			FileMode.Open,
			null,
			0,
			MemoryMappedFileAccess.ReadWrite
		);

		using var viewAccessor = fileMapping.CreateViewAccessor(0, 0, MemoryMappedFileAccess.ReadWrite);

		return this.ConvertZipToBNK(viewAccessor.SafeMemoryMappedViewHandle);
	}

	public bool IgnoreBNKF2MetadataForCompressionSetting
	{
		get => (this.packedState.value & (nuint) ZipToBNKState.PackedState.Flags.ignoreBNKF2MetadataForCompressionSetting) != 0;
		set
		{
			this.packedState.value &= ~(nuint) ZipToBNKState.PackedState.Flags.ignoreBNKF2MetadataForCompressionSetting;
			this.packedState.value |= value ? (nuint) ZipToBNKState.PackedState.Flags.ignoreBNKF2MetadataForCompressionSetting : 0;
		}
	}

	public bool OutputCompressedBNK
	{
		get => (this.packedState.value & (nuint) ZipToBNKState.PackedState.Flags.outputCompressedBNK) != 0;
		set
		{
			this.packedState.value &= ~(nuint) ZipToBNKState.PackedState.Flags.outputCompressedBNK;
			this.packedState.value |= value ? (nuint) ZipToBNKState.PackedState.Flags.outputCompressedBNK : 0;
		}
	}
}


public abstract class BNKF2ContiguousOutputBufferFlusher : IDisposable
{
	[UnmanagedFunctionPointer(CallingConvention.Winapi)]
	public unsafe delegate nuint Ptr_ContiguousOutputBufferFlusher (
		IntPtr context,
		byte** freshBuffer,
		byte* flushBuffer,
		nuint flushSize
	);

	public static unsafe nuint ContiguousOutputBufferFlusher (
		IntPtr context,
		byte** freshBuffer,
		byte* flushBuffer,
		nuint flushSize
	)
	{
		return (GCHandle.FromIntPtr(context).Target! as BNKF2ContiguousOutputBufferFlusher)!.FlushBuffer(
			freshBuffer,
			flushBuffer,
			flushSize
		);
	}

	public unsafe nuint FlushBuffer (byte** freshBuffer, byte* flushBuffer, nuint flushSize)
	{
		try
		{
			return this.Flush(freshBuffer, flushBuffer, flushSize);
		}
		catch (Exception error)
		{
			*freshBuffer = null;
			return (nuint) error.HResult;
		}
	}

	public unsafe abstract nuint Flush (byte** freshBuffer, byte* flushBuffer, nuint flushSize);

	public abstract void Dispose ();
}


public class BNKF2ContiguousStreamFlusher : BNKF2ContiguousOutputBufferFlusher
{
	protected IntPtr bufferBase;
	protected nuint bufferSize;
	public Stream outputStream;

	public BNKF2ContiguousStreamFlusher (Stream outputStream) : this(outputStream, 4194304)
	{}

	public BNKF2ContiguousStreamFlusher (Stream outputStream, nuint bufferSize)
	{
		#if NETFRAMEWORK
			this.bufferBase = Marshal.AllocHGlobal((nint) bufferSize);
		#else
			unsafe
			{
				this.bufferBase = (IntPtr) NativeMemory.Alloc(bufferSize);
			}
		#endif

		this.bufferSize = bufferSize;

		this.outputStream = outputStream;
	}

	public override void Dispose ()
	{
		#if NETFRAMEWORK
			Marshal.FreeHGlobal(this.bufferBase);
		#else
			unsafe
			{
				NativeMemory.Free((void*) this.bufferBase);
			}
		#endif
	}

	public unsafe override nuint Flush (byte** freshBuffer, byte* flushBuffer, nuint flushSize)
	{
		if (flushBuffer == null)
		{
			*freshBuffer = (byte*) this.bufferBase;
			return this.bufferSize;
		}
		else if (flushSize == 0)
		{
			try
			{
				this.outputStream.Flush();
			}
			catch (Exception)
			{}

			return 0;
		}

		try
		{
			new UnmanagedMemoryStream(flushBuffer, unchecked((long) flushSize)).CopyTo(this.outputStream);
		}
		catch (Exception error)
		{
			*freshBuffer = null;
			return (nuint) error.HResult;
		}

		return this.bufferSize;
	}
}


public abstract class BNKF2DiscontiguousOutputBufferFlusher : IDisposable
{
	[UnmanagedFunctionPointer(CallingConvention.Winapi)]
	public unsafe delegate nuint Ptr_DiscontiguousOutputBufferFlusher (
		IntPtr context,
		byte** freshBuffer,
		byte* flushBuffer,
		nuint flushSize,
		uint bufferIndex
	);

	public static unsafe nuint DiscontiguousOutputBufferFlusher (
		IntPtr context,
		byte** freshBuffer,
		byte* flushBuffer,
		nuint flushSize,
		uint bufferIndex
	)
	{
		return (GCHandle.FromIntPtr(context).Target! as BNKF2DiscontiguousOutputBufferFlusher)!.FlushBuffer(
			freshBuffer,
			flushBuffer,
			flushSize,
			bufferIndex
		);
	}

	public unsafe nuint FlushBuffer (byte** freshBuffer, byte* flushBuffer, nuint flushSize, uint bufferIndex)
	{
		try
		{
			return this.Flush(freshBuffer, flushBuffer, flushSize, bufferIndex);
		}
		catch (Exception error)
		{
			*freshBuffer = null;
			return (nuint) error.HResult;
		}
	}

	public unsafe abstract nuint Flush (byte** freshBuffer, byte* flushBuffer, nuint flushSize, uint bufferIndex);

	public abstract void Dispose ();
}


public class BNKFileFlusher : BNKF2DiscontiguousOutputBufferFlusher
{
	protected IntPtr buffersBase;
	protected nuint fileTableBufferSize;
	protected nuint fileDataBufferSize;
	protected FileOffsetsByBuffer fileOffsetsByBuffer;
	public FileStream fileStream;

	protected struct FileOffsetsByBuffer
	{
		public ulong offset0;
		public ulong offset1;
		public ulong offset2;
	}

	public BNKFileFlusher (FileStream fileStream) : this(fileStream, 131072, 4194304)
	{}

	public BNKFileFlusher (FileStream fileStream, nuint fileTableBufferSize, nuint fileDataBufferSize)
	{
		#if NETFRAMEWORK
			nint allocationSize = checked((nint) (fileTableBufferSize + fileDataBufferSize + 32));
			this.buffersBase = Marshal.AllocHGlobal(allocationSize);
		#else
			nuint allocationSize = checked(fileTableBufferSize + fileDataBufferSize + 32);
			unsafe
			{
				this.buffersBase = (IntPtr) NativeMemory.Alloc(allocationSize);
			}
		#endif

		this.fileTableBufferSize = fileTableBufferSize;
		this.fileDataBufferSize = fileDataBufferSize;

		this.fileStream = fileStream;
	}

	public override void Dispose ()
	{
		#if NETFRAMEWORK
			Marshal.FreeHGlobal(this.buffersBase);
		#else
			unsafe
			{
				NativeMemory.Free((void*) this.buffersBase);
			}
		#endif
	}

	public unsafe override nuint Flush (byte** freshBuffer, byte* flushBuffer, nuint flushSize, uint bufferIndex)
	{
		if (bufferIndex == unchecked((uint) -1))
		{
			if ((flushSize & (1 << 16)) == 0)
			{
				this.fileOffsetsByBuffer.offset0 = 0;
				this.fileOffsetsByBuffer.offset1 = 17;
				this.fileOffsetsByBuffer.offset2 = 4294967296;

				return 0;
			}
			else
			{
				try
				{
					ulong completeBufferSize = unchecked((ulong) this.fileTableBufferSize + (ulong) this.fileDataBufferSize);

					ulong sourceOffset = 4294967296;
					ulong destinationOffset = this.fileOffsetsByBuffer.offset1;

					ulong copyLength = this.fileOffsetsByBuffer.offset2 - sourceOffset;
					ulong remainingCopyLength = copyLength;

					FileStream file = this.fileStream;
					byte* buffer = (byte*) this.buffersBase;

					UnmanagedMemoryStream bufferStream = new UnmanagedMemoryStream(buffer, unchecked((long) completeBufferSize));

					ulong chunkLength = remainingCopyLength <= completeBufferSize ? remainingCopyLength : completeBufferSize;

					while (chunkLength != 0)
					{
						file.Position = unchecked((long) sourceOffset);
						file.CopyTo(bufferStream);
						bufferStream.Position = 0;

						file.Position = unchecked((long) destinationOffset);
						bufferStream.CopyTo(file);
						bufferStream.Position = 0;

						sourceOffset += chunkLength;
						destinationOffset += chunkLength;
						remainingCopyLength -= chunkLength;

						chunkLength = remainingCopyLength <= completeBufferSize ? remainingCopyLength : completeBufferSize;
					}

					file.SetLength(unchecked((long) destinationOffset));
				}
				catch (Exception error)
				{
					return (nuint) error.HResult;
				}

				return 0;
			}
		}

		if (flushBuffer == null)
		{
			if (bufferIndex == 0)
			{
				*freshBuffer = (byte*) this.buffersBase + this.fileDataBufferSize + this.fileTableBufferSize;
				return 17;
			}
			else if (bufferIndex == 1)
			{
				*freshBuffer = (byte*) this.buffersBase + this.fileDataBufferSize;
				return this.fileTableBufferSize;
			}
			else
			{
				*freshBuffer = (byte*) this.buffersBase;
				return this.fileDataBufferSize;
			}
		}
		else if (flushSize == 0)
		{
			return 0;
		}

		ulong offsetForBuffer;

		fixed (ulong* offsets = &this.fileOffsetsByBuffer.offset0)
		{
			offsetForBuffer = offsets[bufferIndex];
			offsets[bufferIndex] += flushSize;
		}

		try
		{
			this.fileStream.Position = unchecked((long) offsetForBuffer);
			new UnmanagedMemoryStream(flushBuffer, unchecked((long) flushSize)).CopyTo(fileStream);
		}
		catch (Exception error)
		{
			*freshBuffer = null;
			return (nuint) error.HResult;
		}

		if (bufferIndex == 2)
		{
			return this.fileDataBufferSize;
		}
		else if (bufferIndex == 1)
		{
			return this.fileTableBufferSize;
		}
		else
		{
			return 17;
		}
	}
}


public class BNKStreamFlusher : BNKF2DiscontiguousOutputBufferFlusher
{
	protected IntPtr buffersBase;
	protected nuint fileTableBufferSize;
	protected nuint fileDataBufferSize;
	public Stream fileHeaderStream;
	public Stream fileTableStream;
	public Stream fileDataStream;

	public BNKStreamFlusher (
		Stream fileHeaderStream,
		Stream fileTableStream,
		Stream fileDataStream
	) : this(fileHeaderStream, fileTableStream, fileDataStream, 131072, 4194304)
	{}

	public BNKStreamFlusher (
		Stream fileHeaderStream,
		Stream fileTableStream,
		Stream fileDataStream,
		nuint fileTableBufferSize,
		nuint fileDataBufferSize
	)
	{

		#if NETFRAMEWORK
			nint allocationSize = checked((nint) (fileTableBufferSize + fileDataBufferSize + 32));
			this.buffersBase = Marshal.AllocHGlobal(allocationSize);
		#else
			nuint allocationSize = checked(fileTableBufferSize + fileDataBufferSize + 32);
			unsafe
			{
				this.buffersBase = (IntPtr) NativeMemory.Alloc(allocationSize);
			}
		#endif

		this.fileTableBufferSize = fileTableBufferSize;
		this.fileDataBufferSize = fileDataBufferSize;

		this.fileHeaderStream = fileHeaderStream;
		this.fileTableStream = fileTableStream;
		this.fileDataStream = fileDataStream;
	}

	public override void Dispose ()
	{
		#if NETFRAMEWORK
			Marshal.FreeHGlobal(this.buffersBase);
		#else
			unsafe
			{
				NativeMemory.Free((void*) this.buffersBase);
			}
		#endif
	}

	public void CoalesceInto (Stream stream)
	{
		this.fileHeaderStream.CopyTo(stream);
		this.fileTableStream.CopyTo(stream);
		this.fileDataStream.CopyTo(stream);
	}

	public unsafe override nuint Flush (byte** freshBuffer, byte* flushBuffer, nuint flushSize, uint bufferIndex)
	{
		if (bufferIndex == unchecked((uint) -1))
		{
			if ((flushSize & (1 << 16)) == 0)
			{
				return 0;
			}
			else
			{
				try
				{
					this.fileHeaderStream.Flush();
					this.fileTableStream.Flush();
					this.fileDataStream.Flush();
				}
				catch (Exception)
				{}

				return 0;
			}
		}

		if (flushBuffer == null)
		{
			if (bufferIndex == 0)
			{
				*freshBuffer = (byte*) this.buffersBase + this.fileDataBufferSize + this.fileTableBufferSize;
				return 17;
			}
			else if (bufferIndex == 1)
			{
				*freshBuffer = (byte*) this.buffersBase + this.fileDataBufferSize;
				return this.fileTableBufferSize;
			}
			else
			{
				*freshBuffer = (byte*) this.buffersBase;
				return this.fileDataBufferSize;
			}
		}
		else if (flushSize == 0)
		{
			return 0;
		}

		nuint bufferSize;
		Stream stream;

		if (bufferIndex == 2)
		{
			bufferSize = this.fileDataBufferSize;
			stream = this.fileDataStream;
		}
		else if (bufferIndex == 1)
		{
			bufferSize = this.fileTableBufferSize;
			stream = this.fileTableStream;
		}
		else
		{
			bufferSize = 17;
			stream = this.fileHeaderStream;
		}

		try
		{
			new UnmanagedMemoryStream(flushBuffer, unchecked((long) flushSize)).CopyTo(stream);
		}
		catch (Exception error)
		{
			*freshBuffer = null;
			return (nuint) error.HResult;
		}

		return bufferSize;
	}
}


public abstract class BNKF2ProgressObserver
{
	[UnmanagedFunctionPointer(CallingConvention.Winapi)]
	public unsafe delegate void Ptr_ProgressObserver (
		IntPtr context,
		nuint progressOpcode,
		void* operand0,
		nuint operand1
	);

	public static unsafe void ProgressObserver (
		IntPtr context,
		nuint progressOpcode,
		void* operand0,
		nuint operand1
	)
	{
		(GCHandle.FromIntPtr(context).Target! as BNKF2ProgressObserver)!.ObserveProgress(
			progressOpcode,
			operand0,
			operand1
		);
	}

	public unsafe void ObserveProgress (nuint progressOpcode, void* operand0, nuint operand1)
	{
		try
		{
			this.Observe(progressOpcode, operand0, operand1);
		}
		catch (Exception)
		{}
	}

	public unsafe abstract void Observe (nuint progressOpcode, void* operand0, nuint operand1);
}


public abstract class BNKToZipProgressObserver : BNKF2ProgressObserver
{
	public unsafe override void Observe (nuint progressOpcode, void* operand0, nuint operand1)
	{
		switch (unchecked((BNKToZipProgressOpcode) progressOpcode))
		{
		case BNKToZipProgressOpcode.decompressingFileTable: this.DecompressingFileTable(); return;
		case BNKToZipProgressOpcode.decompressedFileTable: this.DecompressedFileTable(unchecked((uint) operand1)); return;
		case BNKToZipProgressOpcode.decompressingFile: this.DecompressingFile(new UTF8Encoding(false, false).GetString(((DSlice<byte>*) operand0)->data, unchecked((int) ((DSlice<byte>*) operand0)->size)), unchecked((uint) operand1)); return;
		case BNKToZipProgressOpcode.copyingFile: this.CopyingFile(new UTF8Encoding(false, false).GetString(((DSlice<byte>*) operand0)->data, unchecked((int) ((DSlice<byte>*) operand0)->size)), unchecked((uint) operand1)); return;
		case BNKToZipProgressOpcode.skippedDuplicateFileName: this.SkippedDuplicateFileName((new UTF8Encoding(false, false).GetString(((DSlice<byte>*) operand0)->data, unchecked((int) ((DSlice<byte>*) operand0)->size)))); return;
		case BNKToZipProgressOpcode.checksummingFile: this.ChecksummingFile(new UTF8Encoding(false, false).GetString(((DSlice<byte>*) operand0)->data, unchecked((int) ((DSlice<byte>*) operand0)->size)), unchecked((uint) operand1)); return;
		case BNKToZipProgressOpcode.checksummedFile: this.ChecksummedFile(new UTF8Encoding(false, false).GetString(((DSlice<byte>*) operand0)->data, unchecked((int) ((DSlice<byte>*) operand0)->size)), unchecked((uint) operand1)); return;
		case BNKToZipProgressOpcode.writingFileMetadata: this.WritingFileMetadata(new UTF8Encoding(false, false).GetString(((DSlice<byte>*) operand0)->data, unchecked((int) ((DSlice<byte>*) operand0)->size))); return;
		default: return;
		}
	}

	public virtual void DecompressingFileTable () {}
	public virtual void DecompressedFileTable (uint fileCount) {}
	public virtual void DecompressingFile (string name, uint compressedFileSize) {}
	public virtual void CopyingFile (string name, uint uncompressedFileSize) {}
	public virtual void SkippedDuplicateFileName (string name) {}
	public virtual void ChecksummingFile (string name, uint uncompressedFileSize) {}
	public virtual void ChecksummedFile (string name, uint crc32) {}
	public virtual void WritingFileMetadata (string name) {}
}


public abstract class ZipToBNKProgressObserver : BNKF2ProgressObserver
{
	public unsafe override void Observe (nuint progressOpcode, void* operand0, nuint operand1)
	{
		switch (unchecked((ZipToBNKProgressOpcode) progressOpcode))
		{
		case ZipToBNKProgressOpcode.searchingForCentralDirectory: this.SearchingForCentralDirectory(); return;
		case ZipToBNKProgressOpcode.foundCentralDirectory: this.FoundCentralDirectory(unchecked((uint) operand1)); return;
		case ZipToBNKProgressOpcode.copyingFile: this.CopyingFile(new UTF8Encoding(false, false).GetString(((DSlice<byte>*) operand0)->data, unchecked((int) ((DSlice<byte>*) operand0)->size)), unchecked((uint) operand1)); return;
		case ZipToBNKProgressOpcode.compressingFile: this.CompressingFile(new UTF8Encoding(false, false).GetString(((DSlice<byte>*) operand0)->data, unchecked((int) ((DSlice<byte>*) operand0)->size)), unchecked((uint) operand1)); return;
		case ZipToBNKProgressOpcode.compressingFileChunk: this.CompressingFileChunk(new UTF8Encoding(false, false).GetString(((DSlice<byte>*) operand0)->data, unchecked((int) ((DSlice<byte>*) operand0)->size)), unchecked((uint) operand1)); return;
		case ZipToBNKProgressOpcode.compressedFileChunk: this.CompressedFileChunk(new UTF8Encoding(false, false).GetString(((DSlice<byte>*) operand0)->data, unchecked((int) ((DSlice<byte>*) operand0)->size)), unchecked((uint) operand1)); return;
		case ZipToBNKProgressOpcode.decompressingFile: this.DecompressingFile(new UTF8Encoding(false, false).GetString(((DSlice<byte>*) operand0)->data, unchecked((int) ((DSlice<byte>*) operand0)->size)), unchecked((uint) operand1)); return;
		default: return;
		}
	}

	public virtual void SearchingForCentralDirectory () {}
	public virtual void FoundCentralDirectory (uint entryCountOfCentralDirectory) {}
	public virtual void CopyingFile (string name, uint compressedFileSize) {}
	public virtual void CompressingFile (string name, uint uncompressedFileSize) {}
	public virtual void CompressingFileChunk (string name, uint remainingUncompressedSize) {}
	public virtual void CompressedFileChunk (string name, uint compressedChunkSize) {}
	public virtual void DecompressingFile (string name, uint uncompressedSizeOfFile) {}
}


public static class BNKF2StatusExtensions
{
	public static string? GetMessage (this BNKF2Status status)
	{
		switch (status.source)
		{
		case BNKF2Status.CodeSource.bnkf2:
			unsafe
			{
				uint length;
				byte* message = Exports.bnkf2_messageForStatusCodeWithLength((BNKF2StatusCode) status.code, &length);

				if (message == null)
				{
					return $"Unknown BNKF2 error-code {status.code:08X}.";
				}

				return new UTF8Encoding(false, false).GetString(message, unchecked((int) length));
			}
		case BNKF2Status.CodeSource.caller:
			return $"Caller error-code: {status.code:08X}.";
		case BNKF2Status.CodeSource.system:
			return Marshal.GetExceptionForHR(unchecked((int) status.code))?.Message ?? (
				$"Unknown system error-code {status.code:08X}."
			);
		case BNKF2Status.CodeSource.zlib:
			switch ((Z) status.code)
			{
			case Z.VERSION_ERROR: return "zlib error-code: Z_VERSION_ERROR.";
			case Z.BUF_ERROR: return "zlib error-code: Z_BUF_ERROR.";
			case Z.MEM_ERROR: return "zlib error-code: Z_MEM_ERROR.";
			case Z.DATA_ERROR: return "zlib error-code: Z_DATA_ERROR.";
			case Z.STREAM_ERROR: return "zlib error-code: Z_STREAM_ERROR.";
			case Z.ERRNO: return "zlib error-code: Z_ERRNO.";
			case Z.NEED_DICT: return "zlib error-code: Z_NEED_DICT.";
			default: return $"Unknown zlib error-code: {status.code:08X}.";
			}
		default:
			ulong asInt = 0;
			asInt |= (ulong) status.source << 56;
			asInt |= (ulong) status.padding2 << 48;
			asInt |= (ulong) status.padding1 << 40;
			asInt |= (ulong) status.padding0 << 32;
			asInt |= (ulong) status.code;
			return $"Unknown error-code: {asInt:016X}";
		}
	}
}

