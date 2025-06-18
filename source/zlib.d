
/+ SPDX-LICENSE-IDENTIFIER: 0BSD +/

module zlib;

import core.stdc.config : c_ulong;


enum string ZLIBNG_VERSION = "2.2.4";
enum string ZLIB_VERSION = "1.3.1";
enum uint ZLIBNG_VERNUM = 0x020204F0;
enum uint ZLIBNG_VER_MAJOR = 2;
enum uint ZLIBNG_VER_MINOR = 2;
enum uint ZLIBNG_VER_REVISION = 4;
enum char ZLIBNG_VER_STATUS = 'F';
enum uint ZLIBNG_VER_STATUSH = 0xF;
enum uint ZLIBNG_VER_MODIFIED = 0;
enum uint ZLIB_VERNUM = 0x131f;
enum uint ZLIB_VER_MAJOR = 1;
enum uint ZLIB_VER_MINOR = 3;
enum uint ZLIB_VER_REVISION = 1;
enum uint ZLIB_VER_SUBREVISION = 15;


extern(C)
{
	alias alloc_func = void* function (scope void* opaque, uint items, uint size) nothrow @nogc;
	alias free_func = void function (scope void* opaque, scope void* address) nothrow @nogc;
}


struct z_stream
{
	const(ubyte)* next_in;
	uint avail_in;
	c_ulong total_in;

	ubyte* next_out;
	uint avail_out;
	c_ulong total_out;

	const(char)* msg;
	void* state;

	alloc_func zalloc;
	free_func zfree;
	void* opaque;

	int data_type;
	c_ulong adler;
	c_ulong reserved;
}


enum
{
	Z_NO_FLUSH = 0,
	Z_PARTIAL_FLUSH = 1,
	Z_SYNC_FLUSH = 2,
	Z_FULL_FLUSH = 3,
	Z_FINISH = 4,
	Z_BLOCK = 5,
	Z_TREES = 6,
	Z_OK = 0,
	Z_STREAM_END = 1,
	Z_NEED_DICT = 2,
	Z_ERRNO = -1,
	Z_STREAM_ERROR = -2,
	Z_DATA_ERROR = -3,
	Z_MEM_ERROR = -4,
	Z_BUF_ERROR = -5,
	Z_VERSION_ERROR = -6,
	Z_NO_COMPRESSION = 0,
	Z_BEST_SPEED = 1,
	Z_BEST_COMPRESSION = 9,
	Z_DEFAULT_COMPRESSION = -1,
	Z_FILTERED = 1,
	Z_HUFFMAN_ONLY = 2,
	Z_RLE = 3,
	Z_FIXED = 4,
	Z_DEFAULT_STRATEGY = 0,
	Z_BINARY = 0,
	Z_TEXT = 1,
	Z_ASCII = Z_TEXT,
	Z_UNKNOWN = 2,
	Z_DEFLATED = 8
}


pragma(inline, true)
int deflateInit () (scope z_stream* strm, int level) nothrow @nogc
{
	return deflateInit_(strm, level, ZLIB_VERSION, z_stream.sizeof);
}


pragma(inline, true)
int inflateInit () (scope z_stream* strm) nothrow @nogc
{
	return inflateInit_(strm, ZLIB_VERSION, z_stream.sizeof);
}


pragma(inline, true)
int deflateInit2 () (scope z_stream* strm, int level, int method, int windowBits, int memLevel, int strategy) nothrow @nogc
{
	return deflateInit2_(strm, level, method, windowBits, memLevel, strategy, ZLIB_VERSION, z_stream.sizeof);
}


pragma(inline, true)
int inflateInit2 () (scope z_stream* strm, int windowBits) nothrow @nogc
{
	return inflateInit2_(strm, windowBits, ZLIB_VERSION, z_stream.sizeof);
}


extern(C)
{
	int deflateInit_ (scope z_stream* strm, int level, scope const(char)* version_, int stream_size) nothrow @nogc;
	int deflateInit2_ (scope z_stream* strm, int level, int method, int windowBits, int memLevel, int strategy, scope const(char)* version_, int stream_size) nothrow @nogc;
	int deflate (scope z_stream* strm, int flush) nothrow @nogc;
	int deflateEnd (scope z_stream* strm) nothrow @nogc;
	int deflateReset (scope z_stream* strm) nothrow @nogc;
	int deflatePrime (scope z_stream* strm, int bits, int value) nothrow @nogc;
	int deflateTune (scope z_stream* strm, int good_length, int max_lazy, int nice_length, int max_chain) nothrow @nogc;

	int inflateInit_ (scope z_stream* strm, scope const(char)* version_, int stream_size) nothrow @nogc;
	int inflateInit2_ (scope z_stream* strm, int windowBits, scope const(char)* version_, int stream_size) nothrow @nogc;
	int inflate (scope z_stream* strm, int flush) nothrow @nogc;
	int inflateEnd (scope z_stream* strm) nothrow @nogc;
	int inflateReset (scope z_stream* strm) nothrow @nogc;
	int inflateReset2 (scope z_stream* strm, int windowBits) nothrow @nogc;
	int inflatePrime (scope z_stream* strm, int bits, int value) nothrow @nogc;

	c_ulong crc32 (c_ulong crc, scope const(ubyte)* buf, uint len) nothrow @nogc;
}

