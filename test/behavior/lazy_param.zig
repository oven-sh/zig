const std = @import("std");
const builtin = @import("builtin");
const expect = std.testing.expect;

const enabled = false;

inline fn gatedTouch(zig_lazy ok: bool) void {
    if (comptime !enabled) return;
    if (!ok) unreachable;
}

inline fn liveTouch(zig_lazy ok: bool) void {
    if (comptime enabled) return;
    if (!ok) unreachable;
}

fn sideEffect(p: *u32) bool {
    p.* += 1;
    return true;
}

fn poison() bool {
    @panic("lazy argument was evaluated when it should have been elided");
}

test "zig_lazy: argument elided behind comptime-false branch" {
    var n: u32 = 0;
    gatedTouch(sideEffect(&n));
    try expect(n == 0);
    gatedTouch(poison());
}

test "zig_lazy: argument evaluated when reached" {
    var n: u32 = 0;
    liveTouch(sideEffect(&n));
    try expect(n == 1);
}

test "zig_lazy: comptime-invalid argument never analyzed" {
    gatedTouch(@as(*u32, undefined).* == 0);
    comptime gatedTouch(@compileError("must not be analyzed"));
}

inline fn lazyLog(comptime check: bool, zig_lazy args: anytype) usize {
    if (comptime !check) return 0;
    return args.len;
}

test "zig_lazy: anytype argument" {
    var n: u32 = 0;
    const off = lazyLog(false, .{sideEffect(&n)});
    try expect(off == 0);
    try expect(n == 0);

    const on = lazyLog(true, .{ sideEffect(&n), sideEffect(&n) });
    try expect(on == 2);
    try expect(n == 2);
}

inline fn pickByMask(
    comptime mask: u4,
    zig_lazy a: u32,
    zig_lazy b: i32,
    zig_lazy c: []const u8,
    zig_lazy d: f32,
) u32 {
    var r: u32 = 0;
    if (comptime mask & 0b0001 != 0) r +%= a;
    if (comptime mask & 0b0010 != 0) r +%= @as(u32, @bitCast(b));
    if (comptime mask & 0b0100 != 0) r +%= @intCast(c.len);
    if (comptime mask & 0b1000 != 0) r +%= @intFromFloat(d);
    return r;
}

test "zig_lazy: multiple lazy params of differing types, selectively evaluated" {
    var na: u32 = 0;
    var nb: u32 = 0;
    var nc: u32 = 0;
    var nd: u32 = 0;

    const r1 = pickByMask(
        0b0101,
        blk: {
            na += 1;
            break :blk @as(u32, 7);
        },
        blk: {
            nb += 1;
            break :blk @as(i32, -1);
        },
        blk: {
            nc += 1;
            break :blk "hello";
        },
        blk: {
            nd += 1;
            break :blk @as(f32, 3.0);
        },
    );
    try expect(r1 == 7 + 5);
    try expect(na == 1);
    try expect(nb == 0);
    try expect(nc == 1);
    try expect(nd == 0);

    const r2 = pickByMask(
        0b1010,
        blk: {
            na += 1;
            break :blk @as(u32, 7);
        },
        blk: {
            nb += 1;
            break :blk @as(i32, -1);
        },
        blk: {
            nc += 1;
            break :blk "hello";
        },
        blk: {
            nd += 1;
            break :blk @as(f32, 3.0);
        },
    );
    try expect(r2 == @as(u32, @bitCast(@as(i32, -1))) +% 3);
    try expect(na == 1);
    try expect(nb == 1);
    try expect(nc == 1);
    try expect(nd == 1);
}

inline fn middleLazy(a: u32, zig_lazy b: u32, c: u32) u32 {
    if (comptime enabled) return a + b + c;
    return a + c;
}

test "zig_lazy: lazy at middle index, eager neighbours unaffected" {
    var n: u32 = 0;
    const r = middleLazy(
        blk: {
            n += 1;
            break :blk 10;
        },
        blk: {
            n += 100;
            break :blk 0;
        },
        blk: {
            n += 1;
            break :blk 20;
        },
    );
    try expect(r == 30);
    try expect(n == 2);
}

inline fn lastLazy(a: u32, b: u32, c: u32, zig_lazy d: u32) u32 {
    _ = a;
    _ = b;
    return c + d;
}

test "zig_lazy: lazy at last index" {
    var n: u32 = 0;
    const r = lastLazy(1, 2, 3, blk: {
        n += 1;
        break :blk 4;
    });
    try expect(r == 7);
    try expect(n == 1);
}

inline fn pair(zig_lazy a: u32, zig_lazy b: u32) [2]u32 {
    // `b` is referenced first; verify the order of first-use, not declaration, drives evaluation.
    const vb = b;
    const va = a;
    return .{ va, vb };
}

test "zig_lazy: evaluation order follows first use, not declaration order" {
    var trace: u32 = 0;
    const r = pair(
        blk: {
            trace = trace * 10 + 1;
            break :blk 100;
        },
        blk: {
            trace = trace * 10 + 2;
            break :blk 200;
        },
    );
    try expect(r[0] == 100);
    try expect(r[1] == 200);
    try expect(trace == 21);
}

inline fn useTwice(zig_lazy x: u32) u32 {
    return x + x;
}

test "zig_lazy: argument evaluated exactly once across multiple uses" {
    var n: u32 = 0;
    const r = useTwice(blk: {
        n += 1;
        break :blk n;
    });
    try expect(r == 2);
    try expect(n == 1);
}

inline fn outerGate(zig_lazy x: u32) u32 {
    if (comptime !enabled) return 0;
    return innerForce(x);
}

inline fn innerForce(zig_lazy y: u32) u32 {
    return y + 1;
}

test "zig_lazy: nested inline call, outer gate elides through inner lazy" {
    var n: u32 = 0;
    const r = outerGate(blk: {
        n += 1;
        break :blk 5;
    });
    try expect(r == 0);
    try expect(n == 0);
}

inline fn outerForce(zig_lazy x: u32) u32 {
    return innerForce(x);
}

test "zig_lazy: forcing through chained lazy params resolves outer thunk" {
    var n: u32 = 0;
    const r = outerForce(blk: {
        n += 1;
        break :blk 5;
    });
    try expect(r == 6);
    try expect(n == 1);
}

inline fn forceB(zig_lazy a: u32, zig_lazy b: u32) u32 {
    if (b == 0) return 0;
    return a;
}

test "zig_lazy: evaluating one lazy arg whose value gates another" {
    var na: u32 = 0;
    var nb: u32 = 0;
    var seed: u32 = 0;
    _ = .{ &na, &nb, &seed };
    // b evaluates first; its runtime value selects whether a is needed.
    const r = forceB(
        blk: {
            na += 1;
            break :blk 7;
        },
        blk: {
            nb += 1;
            break :blk seed;
        },
    );
    try expect(r == 0);
    try expect(nb == 1);
    // `a` is referenced from a runtime branch, so it is analyzed (laziness is comptime-only).
    try expect(na == 1);
}

inline fn captureOuter(zig_lazy x: u32) u32 {
    const closure = struct {
        var hit: u32 = 0;
    };
    closure.hit = x;
    return closure.hit;
}

test "zig_lazy: argument expression closes over caller locals" {
    var local: u32 = 42;
    _ = &local;
    try expect(captureOuter(local + 1) == 43);
}

inline fn bunAssert(zig_lazy ok: bool) void {
    if (comptime enabled) return;
    if (!ok) unreachable;
}

inline fn noopLog(comptime _: []const u8, zig_lazy _: anytype) void {}

test "zig_lazy: callconv(.inline) form, discard params" {
    var n: u32 = 0;
    bunAssert(sideEffect(&n));
    try expect(n == 1);

    noopLog("{}", .{poison()});
    noopLog("{}", .{@compileError("must not be analyzed")});
}

const callconv_inline: std.builtin.CallingConvention = if (builtin.mode == .Debug) .auto else .@"inline";

fn modeAssert(zig_lazy ok: bool) callconv(callconv_inline) void {
    if (comptime !enabled) return;
    if (!ok) unreachable;
}

fn eagerLazy(zig_lazy x: u32) u32 {
    return x + 1;
}

test "zig_lazy: degrades to eager on non-inline calling convention" {
    var n: u32 = 0;
    // In Debug builds `modeAssert` has cc=.auto so the qualifier is a no-op and
    // the argument is evaluated eagerly; in Release it is inline and elided.
    modeAssert(sideEffect(&n));
    if (callconv_inline == .auto) {
        try expect(n == 1);
    } else {
        try expect(n == 0);
    }

    // Plain (non-inline) function: zig_lazy is accepted but always eager.
    var m: u32 = 0;
    try expect(eagerLazy(blk: {
        m += 1;
        break :blk 9;
    }) == 10);
    try expect(m == 1);
}

const lazy: u32 = 1234; // `lazy` remains a valid identifier.

test "zig_lazy: 'lazy' is still a valid identifier" {
    try expect(lazy == 1234);
}

test "zig_lazy: comptime call with elided arg" {
    const r = comptime middleLazy(1, @compileError("dead"), 2);
    try expect(r == 3);
}

inline fn runtimeBranchFirstUse(cond: bool, zig_lazy x: u32, sink: *u32) void {
    if (cond) {
        sink.* += x;
    }
    sink.* += x;
}

test "zig_lazy: first use inside runtime branch hoists evaluation, fires once" {
    var n: u32 = 0;
    var sink: u32 = 0;
    var cond = false;
    _ = &cond;

    runtimeBranchFirstUse(cond, blk: {
        n += 1;
        break :blk 5;
    }, &sink);
    try expect(sink == 5);
    // Evaluation is hoisted before the inline body, so the side effect fires
    // exactly once even though `cond` was false.
    try expect(n == 1);

    sink = 0;
    runtimeBranchFirstUse(true, blk: {
        n += 1;
        break :blk 5;
    }, &sink);
    try expect(sink == 10);
    try expect(n == 2);
}

inline fn runtimeBranchOnlyUse(cond: bool, zig_lazy x: u32) u32 {
    if (cond) return x;
    return 0;
}

var log_buf: [256]u8 = undefined;
var log_len: usize = 0;

fn realPrint(comptime fmt: []const u8, args: anytype) void {
    log_len = (std.fmt.bufPrint(&log_buf, fmt, args) catch unreachable).len;
}

inline fn scopedLog(comptime on: bool, comptime fmt: []const u8, zig_lazy args: anytype) void {
    if (comptime !on) return;
    realPrint(fmt, args);
}

fn computeName(hits: *u32) []const u8 {
    hits.* += 1;
    return "world";
}

test "zig_lazy: log-style runtime tuple, gated by comptime flag" {
    var hits: u32 = 0;
    var count: i32 = 5;
    _ = &count;

    log_len = 0;
    scopedLog(false, "hello {s} #{d}", .{ computeName(&hits), count });
    try expect(log_len == 0);
    try expect(hits == 0);

    scopedLog(true, "hello {s} #{d}", .{ computeName(&hits), count });
    try expect(hits == 1);
    try expect(std.mem.eql(u8, log_buf[0..log_len], "hello world #5"));
}

test "zig_lazy: only use inside runtime branch still evaluates once unconditionally" {
    var n: u32 = 0;
    var cond = false;
    _ = &cond;
    const r = runtimeBranchOnlyUse(cond, blk: {
        n += 1;
        break :blk 9;
    });
    try expect(r == 0);
    // Laziness is comptime-only: a use that is reachable at comptime forces
    // evaluation regardless of the runtime condition.
    try expect(n == 1);
}
