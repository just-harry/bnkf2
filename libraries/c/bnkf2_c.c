
#include "./bnkf2.h"
#include "stdlib.h"
#include "stdio.h"

#ifdef _WIN32
#	include "io.h"
#	define bnkf2_fileno _fileno
#	define bnkf2_ftruncate _chsize_s
#else
#	include "unistd.h"
#	define bnkf2_fileno fileno
#	define bnkf2_ftruncate ftruncate
#endif


#ifdef _WIN32
#	define bnkf2_fseek _fseeki64
#	define bnkf2_ftell _ftelli64
#elif UINTPTR_MAX == UINT32_MAX
#	define bnkf2_fseek fseeko
#	define bnkf2_ftell ftello
#else
#	define bnkf2_fseek fseek
#	define bnkf2_ftell ftell
#endif


void *bnkf2c_mallocProvider (void *context, size_t size)
{
	return malloc(size);
}


void bnkf2c_freeProvider (void *context, void *memory)
{
	free(memory);
}


size_t bnkf2c_zipFileFlusher (
	void *context,
	uint8_t **freshBuffer,
	uint8_t *flushBuffer,
	size_t flushSize
)
{
	size_t bufferSize = 4 << 20;

	size_t ultimateResult;

	if (flushBuffer == NULL)
	{
		uint8_t *allocated = malloc(bufferSize);
		*freshBuffer = allocated;
		return allocated ? bufferSize : 0;
	}
	else if (flushSize == 0)
	{
		ultimateResult = 0;
		goto ceaseFlushing;
	}

	FILE *file = (FILE *) context;

	if (fwrite(flushBuffer, 1, flushSize, file) < flushSize)
	{
		*freshBuffer = NULL;
		ultimateResult = 1;
		goto ceaseFlushing;
	}

	return bufferSize;
ceaseFlushing:
	free(flushBuffer);
	return ultimateResult;
}


typedef struct
{
	FILE *file;
	uint64_t fileOffsetsByBuffer[3];
	uint8_t *allocatedMemory;
	uint8_t ultimateFileHeader[17];
} bnkf2c_bnkFileFlusherContext;


size_t bnkf2c_bnkFileFlusher (
	void *context,
	uint8_t **freshBuffer,
	uint8_t *flushBuffer,
	size_t flushSize,
	uint32_t bufferIndex
)
{
	size_t fileTableBufferSize = 128 << 10;
	size_t fileDataBufferSize = 4 << 20;
	size_t completeBufferSize = fileTableBufferSize + fileDataBufferSize;
	size_t ultimateFileHeaderSize = 17;

	size_t ultimateResult;

	bnkf2c_bnkFileFlusherContext *state = (bnkf2c_bnkFileFlusherContext *) context;

	if (bufferIndex == -1)
	{
		if ((flushSize & (1 << 16)) == 0)
		{
			state->allocatedMemory = malloc(completeBufferSize);

			if (state->allocatedMemory == NULL)
			{
				return 1;
			}

			state->fileOffsetsByBuffer[0] = 0;
			state->fileOffsetsByBuffer[1] = ultimateFileHeaderSize;
			state->fileOffsetsByBuffer[2] = 4ull << 30;

			return 0;
		}
		else
		{
			uint64_t sourceOffset = 4ull << 30;
			uint64_t destinationOffset = state->fileOffsetsByBuffer[1];

			uint64_t copyLength = state->fileOffsetsByBuffer[2] - sourceOffset;
			uint64_t remainingCopyLength = copyLength;

			FILE *file = state->file;
			uint8_t *buffer = state->allocatedMemory;

			size_t chunkLength = (
				remainingCopyLength <= completeBufferSize ? remainingCopyLength : completeBufferSize
			);

			while (chunkLength != 0)
			{
				if (
					   bnkf2_fseek(file, sourceOffset, SEEK_SET)
					|| fread(buffer, 1, chunkLength, file) < chunkLength
					|| bnkf2_fseek(file, destinationOffset, SEEK_SET)
					|| fwrite(buffer, 1, chunkLength, file) < chunkLength
				)
				{
					ultimateResult = 1;
					goto ceaseFlushing;
				}

				sourceOffset += chunkLength;
				destinationOffset += chunkLength;
				remainingCopyLength -= chunkLength;

				chunkLength = (
					remainingCopyLength <= completeBufferSize ? remainingCopyLength : completeBufferSize
				);
			}

			if (bnkf2_ftruncate(bnkf2_fileno(state->file), destinationOffset))
			{
				ultimateResult = 1;
				goto ceaseFlushing;
			}

			ultimateResult = 0;
			goto ceaseFlushing;
		}
	}

	if (flushBuffer == NULL)
	{
		if (bufferIndex == 0)
		{
			*freshBuffer = (uint8_t *) &state->ultimateFileHeader;
			return ultimateFileHeaderSize;
		}
		else if (bufferIndex == 1)
		{
			*freshBuffer = state->allocatedMemory + fileDataBufferSize;
			return fileTableBufferSize;
		}
		else
		{
			*freshBuffer = state->allocatedMemory;
			return fileDataBufferSize;
		}
	}
	else if (flushSize == 0)
	{
		return 0;
	}

	uint64_t offsetForBuffer = state->fileOffsetsByBuffer[bufferIndex];
	state->fileOffsetsByBuffer[bufferIndex] += flushSize;

	FILE *file = state->file;

	if (
		   bnkf2_fseek(file, offsetForBuffer, SEEK_SET)
		|| fwrite(flushBuffer, 1, flushSize, file) < flushSize
	)
	{
		*freshBuffer = NULL;
		ultimateResult = 1;
		goto ceaseFlushing;
	}

	if (bufferIndex == 2)
	{
		return fileDataBufferSize;
	}
	else if (bufferIndex == 1)
	{
		return fileTableBufferSize;
	}
	else
	{
		return ultimateFileHeaderSize;
	}
ceaseFlushing:
	free(state->allocatedMemory);
	return ultimateResult;
}

