const props = @This();
const std = @import("std");
const assert = std.debug.assert;
const uucode = @import("uucode");
const lut = @import("lut.zig");

/// The lookup tables for Ghostty.
pub const table = table: {
    // This is only available after running main() below as part of the Ghostty
    // build.zig, but due to Zig's lazy analysis we can still reference it here.
    const generated = @import("symbols_tables").Tables(bool);
    const Tables = lut.Tables(bool);
    break :table Tables{
        .stage1 = &generated.stage1,
        .stage2 = &generated.stage2,
        .stage3 = &generated.stage3,
    };
};

/// Runnable binary to generate the lookup tables and output to stdout.
pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const gen: lut.Generator(
        bool,
        struct {
            pub fn get(ctx: @This(), cp: u21) !bool {
                _ = ctx;
                return if (cp > uucode.config.max_code_point)
                    false
                else
                    uucode.get(.is_symbol, @intCast(cp));
            }

            pub fn eql(ctx: @This(), a: bool, b: bool) bool {
                _ = ctx;
                return a == b;
            }
        },
    ) = .{};

    const t = try gen.generate(alloc);
    defer alloc.free(t.stage1);
    defer alloc.free(t.stage2);
    defer alloc.free(t.stage3);
    try t.writeZig(std.io.getStdOut().writer());

    // Uncomment when manually debugging to see our table sizes.
    // std.log.warn("stage1={} stage2={} stage3={}", .{
    //     t.stage1.len,
    //     t.stage2.len,
    //     t.stage3.len,
    // });
}

test "unicode symbols: tables match uucode" {
    if (std.valgrind.runningOnValgrind() > 0) return error.SkipZigTest;

    const testing = std.testing;

    for (0..std.math.maxInt(u21)) |cp| {
        const t = table.get(@intCast(cp));
        const uu = if (cp > uucode.config.max_code_point)
            false
        else
            uucode.get(.is_symbol, @intCast(cp));

        if (t != uu) {
            std.log.warn("mismatch cp=U+{x} t={} uu={}", .{ cp, t, uu });
            try testing.expect(false);
        }
    }
}

test "unicode symbols: tables match ziglyph" {
    if (std.valgrind.runningOnValgrind() > 0) return error.SkipZigTest;

    const ziglyph = @import("ziglyph");
    const testing = std.testing;

    for (0..std.math.maxInt(u21)) |cp_usize| {
        const cp: u21 = @intCast(cp_usize);
        const t = table.get(cp);
        const zg = ziglyph.general_category.isPrivateUse(cp) or
            ziglyph.blocks.isDingbats(cp) or
            ziglyph.blocks.isEmoticons(cp) or
            ziglyph.blocks.isMiscellaneousSymbols(cp) or
            ziglyph.blocks.isEnclosedAlphanumerics(cp) or
            ziglyph.blocks.isEnclosedAlphanumericSupplement(cp) or
            ziglyph.blocks.isMiscellaneousSymbolsAndPictographs(cp) or
            ziglyph.blocks.isTransportAndMapSymbols(cp);

        if (t != zg) {
            std.log.warn("mismatch cp=U+{x} t={} zg={}", .{ cp, t, zg });
            try testing.expect(false);
        }
    }
}
