
namespace BNKF2.ZLib;

using System;
using System.Runtime.InteropServices;


[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public unsafe delegate void* alloc_func (void* opaque, uint items, uint size);


[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public unsafe delegate void free_func (void* opaque, void* address);


public unsafe struct z_stream
{
	public byte* next_in;
	public uint avail_in;

#if NETFRAMEWORK
	public uint total_in;
#else
	public CULong total_in;
#endif

	public byte* next_out;
	public uint avail_out;

#if NETFRAMEWORK
	public uint total_out;
#else
	public CULong total_out;
#endif

	public byte* msg;
	public void* state;

	public IntPtr zalloc;
	public IntPtr zfree;
	public void* opaque;

	public int data_type;

#if NETFRAMEWORK
	public uint adler;
#else
	public CULong adler;
#endif

#if NETFRAMEWORK
	public uint reserved;
#else
	public CULong reserved;
#endif
}


public static class ZLib
{
	public static readonly byte[] ZLIBNG_VERSION = {(byte) '2', (byte) '.', (byte) '2', (byte) '.', (byte) '4', (byte) '\0'};
	public static readonly byte[] ZLIB_VERSION = {(byte) '1', (byte) '.', (byte) '3', (byte) '.', (byte) '1', (byte) '\0'};
	public const uint ZLIBNG_VERNUM = 0x020204F0;
	public const uint ZLIBNG_VER_MAJOR = 2;
	public const uint ZLIBNG_VER_MINOR = 2;
	public const uint ZLIBNG_VER_REVISION = 4;
	public const byte ZLIBNG_VER_STATUS = (byte) 'F';
	public const uint ZLIBNG_VER_STATUSH = 0xF;
	public const uint ZLIBNG_VER_MODIFIED = 0;
	public const uint ZLIB_VERNUM = 0x131f;
	public const uint ZLIB_VER_MAJOR = 1;
	public const uint ZLIB_VER_MINOR = 3;
	public const uint ZLIB_VER_REVISION = 1;
	public const uint ZLIB_VER_SUBREVISION = 15;

	[DllImport("zlib1", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
	public static unsafe extern int deflateInit_ (z_stream* strm, int level, byte* version, int stream_size);
	[DllImport("zlib1", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
	public static unsafe extern int deflateInit2_ (z_stream* strm, int level, int method, int windowBits, int memLevel, int strategy, byte* version, int stream_size);
	[DllImport("zlib1", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
	public static unsafe extern int deflate (z_stream* strm, int flush);
	[DllImport("zlib1", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
	public static unsafe extern int deflateEnd (z_stream* strm);
	[DllImport("zlib1", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
	public static unsafe extern int deflateReset (z_stream* strm);
	[DllImport("zlib1", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
	public static unsafe extern int deflatePrime (z_stream* strm, int bits, int value);
	[DllImport("zlib1", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
	public static unsafe extern int deflateTune (z_stream* strm, int good_length, int max_lazy, int nice_length, int max_chain);
	[DllImport("zlib1", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
	public static unsafe extern int inflateInit_ (z_stream* strm, byte* version, int stream_size);
	[DllImport("zlib1", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
	public static unsafe extern int inflateInit2_ (z_stream* strm, int windowBits, byte* version, int stream_size);
	[DllImport("zlib1", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
	public static unsafe extern int inflate (z_stream* strm, int flush);
	[DllImport("zlib1", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
	public static unsafe extern int inflateEnd (z_stream* strm);
	[DllImport("zlib1", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
	public static unsafe extern int inflateReset (z_stream* strm);
	[DllImport("zlib1", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
	public static unsafe extern int inflateReset2 (z_stream* strm, int windowBits);
	[DllImport("zlib1", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
	public static unsafe extern int inflatePrime (z_stream* strm, int bits, int value);

	#if NETFRAMEWORK
		[DllImport("zlib1", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
		public static unsafe extern uint crc32 (uint crc, byte* buf, uint len);
	#else
		[DllImport("zlib1", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
		public static unsafe extern CULong crc32 (CULong crc, byte* buf, uint len);
	#endif
}


[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public unsafe delegate int Ptr_deflateInit_ (z_stream* strm, int level, byte* version, int stream_size);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public unsafe delegate int Ptr_deflateInit2_ (z_stream* strm, int level, int method, int windowBits, int memLevel, int strategy, byte* version, int stream_size);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public unsafe delegate int Ptr_deflate (z_stream* strm, int flush);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public unsafe delegate int Ptr_deflateEnd (z_stream* strm);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public unsafe delegate int Ptr_deflateReset (z_stream* strm);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public unsafe delegate int Ptr_deflatePrime (z_stream* strm, int bits, int value);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public unsafe delegate int Ptr_deflateTune (z_stream* strm, int good_length, int max_lazy, int nice_length, int max_chain);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public unsafe delegate int Ptr_inflateInit_ (z_stream* strm, byte* version, int stream_size);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public unsafe delegate int Ptr_inflateInit2_ (z_stream* strm, int windowBits, byte* version, int stream_size);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public unsafe delegate int Ptr_inflate (z_stream* strm, int flush);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public unsafe delegate int Ptr_inflateEnd (z_stream* strm);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public unsafe delegate int Ptr_inflateReset (z_stream* strm);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public unsafe delegate int Ptr_inflateReset2 (z_stream* strm, int windowBits);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public unsafe delegate int Ptr_inflatePrime (z_stream* strm, int bits, int value);

#if NETFRAMEWORK
	[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
	public unsafe delegate uint Ptr_crc32 (uint crc, byte* buf, uint len);
#else
	[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
	public unsafe delegate CULong Ptr_crc32 (CULong crc, byte* buf, uint len);
#endif


public enum Z : int
{
	NO_FLUSH = 0,
	PARTIAL_FLUSH = 1,
	SYNC_FLUSH = 2,
	FULL_FLUSH = 3,
	FINISH = 4,
	BLOCK = 5,
	TREES = 6,
	OK = 0,
	STREAM_END = 1,
	NEED_DICT = 2,
	ERRNO = -1,
	STREAM_ERROR = -2,
	DATA_ERROR = -3,
	MEM_ERROR = -4,
	BUF_ERROR = -5,
	VERSION_ERROR = -6,
	NO_COMPRESSION = 0,
	BEST_SPEED = 1,
	BEST_COMPRESSION = 9,
	DEFAULT_COMPRESSION = -1,
	FILTERED = 1,
	HUFFMAN_ONLY = 2,
	RLE = 3,
	FIXED = 4,
	DEFAULT_STRATEGY = 0,
	BINARY = 0,
	TEXT = 1,
	ASCII = TEXT,
	UNKNOWN = 2,
	DEFLATED = 8
}

