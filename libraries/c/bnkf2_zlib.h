
/* Include zlib.h before including bnkf2.h when using this header. */

#pragma once

#include "./bnkf2.h"
#include "stdbool.h"


static bool bnkf2_dynamicallyLinkZLib (bnkf2_DynamicallyLinkedZLib *zlib)
{
	bool succeeded = true;
	zlib->provisionVersion = bnkf2_DynamicallyLinkedZLibProvisionVersion_0;
	succeeded &= !!(zlib->deflateInit_ = &deflateInit_);
	succeeded &= !!(zlib->deflateInit2_ = &deflateInit2_);
	succeeded &= !!(zlib->deflate = &deflate);
	succeeded &= !!(zlib->deflateEnd = &deflateEnd);
	succeeded &= !!(zlib->deflateReset = &deflateReset);
	succeeded &= !!(zlib->deflatePrime = &deflatePrime);
	succeeded &= !!(zlib->deflateTune = &deflateTune);
	succeeded &= !!(zlib->inflateInit_ = &inflateInit_);
	succeeded &= !!(zlib->inflateInit2_ = &inflateInit2_);
	succeeded &= !!(zlib->inflate = &inflate);
	succeeded &= !!(zlib->inflateEnd = &inflateEnd);
	succeeded &= !!(zlib->inflateReset = &inflateReset);
	succeeded &= !!(zlib->inflateReset2 = &inflateReset2);
	succeeded &= !!(zlib->inflatePrime = &inflatePrime);
	succeeded &= !!(zlib->crc32 = &crc32);
	return succeeded;
}

