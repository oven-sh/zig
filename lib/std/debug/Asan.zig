//! AddressSanitizer manual-poisoning helpers.
//!
//! These wrap the ASAN runtime's manual-poison API so that allocators and
//! containers can mark freed/unused regions as inaccessible. All functions
//! compile to no-ops when `builtin.sanitize_address` is false, so call sites
//! need no `if` guard.
//!
//! Poisoning is shadow-byte granular (8 bytes on most targets). A region
//! whose start is not 8-aligned may leave the first partial qword unpoisoned;
//! this is a limitation of the ASAN shadow encoding, not of these wrappers.

const builtin = @import("builtin");

/// Whether the current compilation has AddressSanitizer instrumentation.
pub const enabled = builtin.sanitize_address;

/// Mark `[ptr, ptr+len)` as inaccessible. Any subsequent load or store in
/// that range triggers an ASAN `use-after-poison` report.
pub inline fn poison(ptr: [*]const u8, len: usize) void {
    if (!enabled) return;
    __asan_poison_memory_region(ptr, len);
}

/// Mark `[ptr, ptr+len)` as accessible again.
pub inline fn unpoison(ptr: [*]const u8, len: usize) void {
    if (!enabled) return;
    __asan_unpoison_memory_region(ptr, len);
}

/// Convenience overload taking any slice.
pub inline fn poisonSlice(slice: anytype) void {
    if (!enabled) return;
    if (slice.len == 0) return;
    const bytes = @import("std").mem.sliceAsBytes(slice);
    __asan_poison_memory_region(bytes.ptr, bytes.len);
}

/// Convenience overload taking any slice.
pub inline fn unpoisonSlice(slice: anytype) void {
    if (!enabled) return;
    if (slice.len == 0) return;
    const bytes = @import("std").mem.sliceAsBytes(slice);
    __asan_unpoison_memory_region(bytes.ptr, bytes.len);
}

/// Tell ASAN about a contiguous container's `[storage, storage+capacity)`
/// where only `[storage, storage+new_len)` is valid. Equivalent to libc++'s
/// vector annotation. `old_len` must be the value passed as `new_len` on the
/// previous call (or `capacity` on first call). All lengths are in bytes.
pub inline fn annotateContiguousContainer(
    storage: [*]const u8,
    capacity: usize,
    old_len: usize,
    new_len: usize,
) void {
    if (!enabled) return;
    if (capacity == 0) return;
    __sanitizer_annotate_contiguous_container(
        storage,
        storage + capacity,
        storage + old_len,
        storage + new_len,
    );
}

/// Returns true if the byte at `ptr` is currently poisoned. Intended for
/// assertions in tests.
pub inline fn isPoisoned(ptr: *const anyopaque) bool {
    if (!enabled) return false;
    return __asan_address_is_poisoned(ptr) != 0;
}

extern fn __asan_poison_memory_region(addr: [*]const u8, size: usize) void;
extern fn __asan_unpoison_memory_region(addr: [*]const u8, size: usize) void;
extern fn __asan_address_is_poisoned(addr: *const anyopaque) c_int;
extern fn __sanitizer_annotate_contiguous_container(
    beg: [*]const u8,
    end: [*]const u8,
    old_mid: [*]const u8,
    new_mid: [*]const u8,
) void;
