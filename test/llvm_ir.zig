pub fn addCases(cases: *tests.LlvmIrContext) void {
    cases.addMatches("nonnull ptr load",
        \\export fn entry(ptr: *i16) i16 {
        \\    return ptr.*;
        \\}
    , &.{
        "ptr nonnull",
        "load i16, ptr %0",
    }, .{});

    cases.addMatches("nonnull ptr store",
        \\export fn entry(ptr: *i16) void {
        \\    ptr.* = 42;
        \\}
    , &.{
        "ptr nonnull",
        "store i16 42, ptr %0",
    }, .{});

    cases.addMatches("unused acquire atomic ptr load",
        \\export fn entry(ptr: *i16) void {
        \\    _ = @atomicLoad(i16, ptr, .acquire);
        \\}
    , &.{
        "load atomic i16, ptr %0 acquire",
    }, .{});

    cases.addMatches("unused unordered atomic volatile ptr load",
        \\export fn entry(ptr: *volatile i16) void {
        \\    _ = @atomicLoad(i16, ptr, .unordered);
        \\}
    , &.{
        "load atomic volatile i16, ptr %0 unordered",
    }, .{});

    cases.addMatches("unused volatile ptr load",
        \\export fn entry(ptr: *volatile i16) void {
        \\    _ = ptr.*;
        \\}
    , &.{
        "load volatile i16, ptr %0",
    }, .{});

    cases.addMatches("dead volatile ptr store",
        \\export fn entry(ptr: *volatile i16) void {
        \\    ptr.* = 123;
        \\    ptr.* = 321;
        \\}
    , &.{
        "store volatile i16 123, ptr %0",
        "store volatile i16 321, ptr %0",
    }, .{});

    cases.addMatches("unused volatile slice load",
        \\export fn entry(ptr: *volatile i16) void {
        \\    entry2(ptr[0..1]);
        \\}
        \\fn entry2(ptr: []volatile i16) void {
        \\    _ = ptr[0];
        \\}
    , &.{
        "load volatile i16, ptr",
    }, .{});

    cases.addMatches("dead volatile slice store",
        \\export fn entry(ptr: *volatile i16) void {
        \\    entry2(ptr[0..1]);
        \\}
        \\fn entry2(ptr: []volatile i16) void {
        \\    ptr[0] = 123;
        \\    ptr[0] = 321;
        \\}
    , &.{
        "store volatile i16 123, ptr",
        "store volatile i16 321, ptr",
    }, .{});

    cases.addMatches("allowzero ptr load",
        \\export fn entry(ptr: *allowzero i16) i16 {
        \\    return ptr.*;
        \\}
    , &.{
        "null_pointer_is_valid",
        "load i16, ptr %0",
    }, .{});

    cases.addMatches("allowzero ptr store",
        \\export fn entry(ptr: *allowzero i16) void {
        \\    ptr.* = 42;
        \\}
    , &.{
        "null_pointer_is_valid",
        "store i16 42, ptr %0",
    }, .{});

    cases.addMatches("allowzero slice load",
        \\export fn entry(ptr: *allowzero i16) i16 {
        \\    return entry2(ptr[0..1]);
        \\}
        \\fn entry2(ptr: []allowzero i16) i16 {
        \\    return ptr[0];
        \\}
    , &.{
        "null_pointer_is_valid",
        "load i16, ptr",
    }, .{});

    cases.addMatches("allowzero slice store",
        \\export fn entry(ptr: *allowzero i16) void {
        \\    entry2(ptr[0..1]);
        \\}
        \\fn entry2(ptr: []allowzero i16) void {
        \\    ptr[0] = 42;
        \\}
    , &.{
        "null_pointer_is_valid",
        "store i16 42, ptr",
    }, .{});

    cases.addMatches("dereferenceable single-item ptr param",
        \\const S = extern struct { a: i32, b: i32, c: i32, d: i32 };
        \\export fn entry(p: *const S) i32 {
        \\    return p.d;
        \\}
    , &.{
        "dereferenceable(16)",
    }, .{});

    cases.addMatches("dereferenceable_or_null optional ptr param",
        \\export fn entry(p: ?*u64) u64 {
        \\    if (p) |q| return q.*;
        \\    return 0;
        \\}
    , &.{
        "dereferenceable_or_null(8)",
    }, .{});

    cases.addMatches("sret writable dead_on_unwind",
        \\const R = extern struct { a: u64, b: u64, c: u64, d: u64 };
        \\export fn entry(x: u64) R {
        \\    return .{ .a = x, .b = x, .c = x, .d = x };
        \\}
    , &.{
        "sret(",
        "writable",
        "dead_on_unwind",
        "noundef",
    }, .{});

    cases.addMatches("byref param dereferenceable noundef",
        \\const Big = extern struct { data: [8]u64 };
        \\export fn entry(b: Big) u64 {
        \\    return b.data[0];
        \\}
    , &.{
        "noundef",
        "dereferenceable(64)",
    }, .{ .target = .{ .cpu_arch = .x86_64, .os_tag = .linux } });

    cases.addMatches("intCast trunc nuw",
        \\export fn entry(x: u64) u32 {
        \\    return @intCast(x);
        \\}
    , &.{
        "trunc nuw i64",
    }, .{ .optimize = .ReleaseFast });

    cases.addMatches("intCast trunc nsw",
        \\export fn entry(x: i64) i32 {
        \\    return @intCast(x);
        \\}
    , &.{
        "trunc nsw i64",
    }, .{ .optimize = .ReleaseFast });

    cases.addMatches("intCast zext nneg",
        \\export fn entry(x: i32) u64 {
        \\    return @intCast(x);
        \\}
    , &.{
        "zext nneg i32",
    }, .{ .optimize = .ReleaseFast });

    cases.addMatches("fneg fast under optimized float mode",
        \\export fn entry(x: f64) f64 {
        \\    @setFloatMode(.optimized);
        \\    return -x;
        \\}
    , &.{
        "fneg fast double",
    }, .{});

    cases.addMatches("cold branch hint adds optsize",
        \\export fn entry() void {
        \\    @branchHint(.cold);
        \\}
    , &.{
        " cold ",
        " optsize ",
    }, .{});
}

const std = @import("std");
const tests = @import("tests.zig");
