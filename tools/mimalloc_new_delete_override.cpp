// mimalloc operator new/delete override for the zig compiler on Windows.
//
// LLVM emit at high --llvm-codegen-threads counts allocates heavily through
// C++ operator new from N concurrent LLVM contexts. The Windows CRT routes
// operator new -> malloc -> HeapAlloc(GetProcessHeap()), and the process heap
// is guarded by a single critical section, so 24 threads serialise on it.
//
// On linux-musl the CI splices a MI_MALLOC_OVERRIDE static.c object so
// malloc/free themselves are replaced (POSIX symbol interposition). That
// doesn't work for static MSVC linking — the CRT's malloc is a strong symbol
// — but C++ operator new/delete *are* replaceable per the standard, and
// LLVM's hot allocations go through them. So compile mimalloc here and
// provide global new/delete that forward to it; LLVM picks these up at link
// time and zig's gpa is handled separately by smp_allocator.
//
// Compiled with:
//   clang-cl /O2 /MT /std:c++17 /EHsc /DNDEBUG /DMI_STATIC_LIB
//     -I <mimalloc>/include /c mimalloc-override.cpp
// and passed to zig's build via -Dmimalloc-obj=<this>.obj.

// mimalloc unity build — defines mi_malloc/mi_free/mi_new and friends.
// Compiled as C++ (mimalloc supports this), *without* MI_MALLOC_OVERRIDE so
// it doesn't try to redefine malloc/free — MSVC link would reject the
// duplicate symbols against the static CRT.
#include "src/static.c" // NOLINT

// Replaceable global operator new/delete -> mimalloc.
// Header is self-contained; only needs the mi_* symbols above.
#include "mimalloc-new-delete.h"
