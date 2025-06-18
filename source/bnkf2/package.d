
/+ SPDX-LICENSE-IDENTIFIER: 0BSD +/

module bnkf2;

public import bnkf2.core;


extern(System)
export BNKF2Status bnkf2_bnkToZip (
	scope void* context,
	scope const(ubyte)[]* inputBuffer,
	scope ContiguousOutputBufferFlusher outputFlusher,
	scope BNKToZipState* state
);


extern(System)
export BNKF2Status bnkf2_zipToBNK (
	scope void* context,
	scope const(ubyte)[]* inputBuffer,
	scope DiscontiguousOutputBufferFlusher outputFlusher,
	scope ZipToBNKState* state
);


extern(System)
export BNKF2Status bnkf2_bnkIsCompressed (
	scope const(ubyte)* inputBuffer,
	scope size_t inputLength,
	scope bool* bnkIsCompressed
);


extern(System)
export immutable(char)* bnkf2_messageForStatusCode (BNKF2StatusCode code);


extern(System)
export immutable(char)* bnkf2_messageForStatusCodeWithLength (BNKF2StatusCode code, scope uint* length);


extern(System)
export extern shared immutable(uint) bnkf2_longestStatusCodeMessageLength;


/+ Provided for the benefit of deficient language runtimes. +/
extern(System)
export uint bnkf2_getLongestStatusCodeMessageLength ();

