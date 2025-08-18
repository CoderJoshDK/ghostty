const props = @This();
const std = @import("std");
const assert = std.debug.assert;
const uucode = @import("uucode");
const lut = @import("lut.zig");

/// The lookup tables for Ghostty.
pub const table = table: {
    // This is only available after running main() below as part of the Ghostty
    // build.zig, but due to Zig's lazy analysis we can still reference it here.
    const generated = @import("unicode_tables").Tables(Properties);
    const Tables = lut.Tables(Properties);
    break :table Tables{
        .stage1 = &generated.stage1,
        .stage2 = &generated.stage2,
        .stage3 = &generated.stage3,
    };
};

/// Property set per codepoint that Ghostty cares about.
///
/// Adding to this lets you find new properties but also potentially makes
/// our lookup tables less efficient. Any changes to this should run the
/// benchmarks in src/bench to verify that we haven't regressed.
pub const Properties = struct {
    /// Codepoint width. We clamp to [0, 2] since Ghostty handles control
    /// characters and we max out at 2 for wide characters (i.e. 3-em dash
    /// becomes a 2-em dash).
    width: u2 = 0,

    /// Grapheme boundary class.
    grapheme_boundary_class: GraphemeBoundaryClass = .invalid,

    // Needed for lut.Generator
    pub fn eql(a: Properties, b: Properties) bool {
        return a.width == b.width and
            a.grapheme_boundary_class == b.grapheme_boundary_class;
    }

    // Needed for lut.Generator
    pub fn format(
        self: Properties,
        comptime layout: []const u8,
        opts: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = layout;
        _ = opts;
        try std.fmt.format(writer,
            \\.{{
            \\    .width= {},
            \\    .grapheme_boundary_class= .{s},
            \\}}
        , .{
            self.width,
            @tagName(self.grapheme_boundary_class),
        });
    }
};

/// Possible grapheme boundary classes. This isn't an exhaustive list:
/// we omit control, CR, LF, etc. because in Ghostty's usage that are
/// impossible because they're handled by the terminal.
pub const GraphemeBoundaryClass = enum(u4) {
    invalid,
    L,
    V,
    T,
    LV,
    LVT,
    prepend,
    extend,
    zwj,
    spacing_mark,
    regional_indicator,
    extended_pictographic,
    extended_pictographic_base, // \p{Extended_Pictographic} & \p{Emoji_Modifier_Base}
    emoji_modifier, // \p{Emoji_Modifier}

    /// Gets the grapheme boundary class for a codepoint.
    /// The use case for this is only in generating lookup tables.
    pub fn init(cp: u21) GraphemeBoundaryClass {
        if (cp < uucode.code_point_range_end) {
            return switch (uucode.get(.grapheme_break, cp)) {
                .emoji_modifier_base => .extended_pictographic_base,
                .emoji_modifier => .emoji_modifier,
                .extended_pictographic => .extended_pictographic,
                .l => .L,
                .v => .V,
                .t => .T,
                .lv => .LV,
                .lvt => .LVT,
                .prepend => .prepend,
                .extend => .extend,
                .zwj => .zwj,
                .spacing_mark => .spacing_mark,
                .regional_indicator => .regional_indicator,

                // This is obviously not INVALID invalid, there is SOME grapheme
                // boundary class for every codepoint. But we don't care about
                // anything that doesn't fit into the above categories.
                .other, .cr, .lf, .control => .invalid,
            };
        } else {
            return .invalid;
        }
    }

    /// Returns true if this is an extended pictographic type. This
    /// should be used instead of comparing the enum value directly
    /// because we classify multiple.
    pub fn isExtendedPictographic(self: GraphemeBoundaryClass) bool {
        return switch (self) {
            .extended_pictographic,
            .extended_pictographic_base,
            => true,

            else => false,
        };
    }
};

pub fn get(cp: u21) Properties {
    const wcwidth = if (cp < uucode.code_point_range_end) uucode.get(.wcwidth, cp) else 0;

    return .{
        .width = @intCast(@min(2, @max(0, wcwidth))),
        .grapheme_boundary_class = .init(cp),
    };
}

/// Runnable binary to generate the lookup tables and output to stdout.
pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const gen: lut.Generator(
        Properties,
        struct {
            pub fn get(ctx: @This(), cp: u21) !Properties {
                _ = ctx;
                return props.get(cp);
            }

            pub fn eql(ctx: @This(), a: Properties, b: Properties) bool {
                _ = ctx;
                return a.eql(b);
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

// This is not very fast in debug modes, so its commented by default.
// IMPORTANT: UNCOMMENT THIS WHENEVER MAKING CODEPOINTWIDTH CHANGES.
//test "tables match uucode" {
//    const testing = std.testing;
//
//    const min = 0xFF + 1; // start outside ascii
//    for (min..uucode.code_point_range_end) |cp| {
//        const t = table.get(@intCast(cp));
//        const uu = @min(2, @max(0, uucode.get(.wcwidth, @intCast(cp))));
//        if (t.width != uu) {
//            std.log.warn("mismatch cp=U+{x} t={} uucode={}", .{ cp, t, uu });
//            try testing.expect(false);
//        }
//    }
//}
