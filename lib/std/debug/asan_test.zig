//! Tests that the manual ASAN poisoning applied by std allocators and
//! containers actually marks the right bytes. These tests query the ASAN
//! shadow via `Asan.isPoisoned` rather than dereferencing poisoned memory,
//! so they pass cleanly under `-fsanitize-address` instead of crashing.
//!
//! Every test is gated on `Asan.enabled` and skipped otherwise so that the
//! file can be built into the regular (non-sanitized) test binary without
//! producing false failures.
//!
//! Run directly with:
//!   zig test lib/std/debug/asan_test.zig --zig-lib-dir lib -fsanitize-address -lc

const std = @import("std");
const testing = std.testing;
const Asan = std.debug.Asan;

test "asan: ArrayList spare capacity is poisoned" {
    if (!Asan.enabled) return error.SkipZigTest;

    const gpa = testing.allocator;
    var list: std.ArrayList(u64) = try .initCapacity(gpa, 8);
    defer list.deinit(gpa);

    try testing.expectEqual(@as(usize, 8), list.capacity);

    try list.append(gpa, 1);
    try list.append(gpa, 2);
    try list.append(gpa, 3);

    // Base of the backing buffer (items.ptr is a [*]u64; treat as bytes for
    // shadow queries so we are explicit about granularity).
    const base: [*]const u8 = @ptrCast(list.items.ptr);

    // items[0..3] live, items[3..8] poisoned spare capacity.
    try testing.expect(!Asan.isPoisoned(&base[0 * @sizeOf(u64)]));
    try testing.expect(!Asan.isPoisoned(&base[2 * @sizeOf(u64)]));
    try testing.expect(Asan.isPoisoned(&base[3 * @sizeOf(u64)]));
    try testing.expect(Asan.isPoisoned(&base[7 * @sizeOf(u64)]));

    // Popping shrinks the live region; the just-vacated slot becomes poison.
    _ = list.pop();
    try testing.expect(!Asan.isPoisoned(&base[1 * @sizeOf(u64)]));
    try testing.expect(Asan.isPoisoned(&base[2 * @sizeOf(u64)]));
}

test "asan: FixedBufferAllocator poisons freed regions" {
    if (!Asan.enabled) return error.SkipZigTest;

    // 8-byte alignment so the ASAN shadow boundaries line up exactly with
    // the buffer; otherwise the first/last partial qword may be left
    // unpoisoned by the runtime.
    var buf: [256]u8 align(8) = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    defer fba.deinit();
    const a = fba.allocator();

    // init() does not poison eagerly (Zig has no per-frame shadow cleanup yet).
    try testing.expect(!Asan.isPoisoned(&buf[0]));
    try testing.expect(!Asan.isPoisoned(&buf[100]));

    const slab = try a.alloc(u8, 64);
    try testing.expect(!Asan.isPoisoned(&slab[0]));
    try testing.expect(!Asan.isPoisoned(&slab[32]));

    // free() poisons the returned region so use-after-free is caught.
    a.free(slab);
    try testing.expect(Asan.isPoisoned(&buf[0]));
    try testing.expect(Asan.isPoisoned(&buf[32]));

    // A fresh allocation past the high-water mark is still addressable.
    const slab2 = try a.alloc(u8, 64);
    try testing.expect(!Asan.isPoisoned(&slab2[0]));

    // reset() poisons everything that was handed out so far.
    fba.reset();
    try testing.expect(Asan.isPoisoned(&slab2[0]));
}

test "asan: ArenaAllocator reset(.retain_capacity) re-poisons" {
    if (!Asan.enabled) return error.SkipZigTest;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const slab = try a.alloc(u64, 16);
    const base: [*]const u8 = @ptrCast(slab.ptr);
    try testing.expect(!Asan.isPoisoned(&base[0]));
    try testing.expect(!Asan.isPoisoned(&base[15 * @sizeOf(u64)]));

    // Keep the buffer but rewind end_index to 0; the previously handed-out
    // bytes must now be inaccessible.
    _ = arena.reset(.retain_capacity);
    try testing.expect(Asan.isPoisoned(&base[0]));
    try testing.expect(Asan.isPoisoned(&base[8 * @sizeOf(u64)]));
}

test "asan: MemoryPool destroy poisons item tail" {
    if (!Asan.enabled) return error.SkipZigTest;

    // Item large enough that there is a poisonable tail past the free-list
    // `next` pointer (one usize).
    const Item = struct { data: [32]u8 };

    var pool = std.heap.MemoryPool(Item).init(testing.allocator);
    defer pool.deinit();

    const item = try pool.create();
    const bytes: [*]const u8 = @ptrCast(item);

    // Freshly created: whole item is addressable.
    try testing.expect(!Asan.isPoisoned(&bytes[0]));
    try testing.expect(!Asan.isPoisoned(&bytes[@sizeOf(Item) - 1]));

    pool.destroy(item);

    // First @sizeOf(usize) bytes hold the free-list link and stay unpoisoned;
    // everything after is poison.
    const link_end = @sizeOf(usize);
    try testing.expect(!Asan.isPoisoned(&bytes[0]));
    try testing.expect(Asan.isPoisoned(&bytes[link_end]));
    try testing.expect(Asan.isPoisoned(&bytes[@sizeOf(Item) - 1]));

    // Re-create pulls from the free list and unpoisons the full item again.
    const item2 = try pool.create();
    try testing.expectEqual(@intFromPtr(item), @intFromPtr(item2));
    try testing.expect(!Asan.isPoisoned(&bytes[link_end]));
    try testing.expect(!Asan.isPoisoned(&bytes[@sizeOf(Item) - 1]));
}
