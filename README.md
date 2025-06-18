
BNKF2 is a tool, and a library for converting Fable II's BNK files to and from zip files.

The tool is a CLI which supports only 64-bit Windows. \
The library is an extremely portable native library, written in D, with only one dependency: zlib; it doesn't rely on any runtime, all IO (including linking with zlib) is delegated to the caller.

Also included in this repo are wrapper libraries for the native D library:
- A set of C bindings and a wrapper which uses libc for IO.
- A set of .NET bindings and a wrapper which uses the .NET BCL for IO.

However, I ran out of steam whilst finishing up the .NET wrapper, so it doesn't work for converting zip files back to BNK files. \
Also the C bindings and wrapper are wholly untested. \
And everything—except for the CLI's basic help—is undocumented. \
¯\\_(ツ)_/¯

Regardless, the CLI and the D library seem to work well, so it's best that they not languish on my machine for any longer.

---

Everything in this repo is licensed under the terms of the Zero-Clause BSD licence unless otherwise stated.

