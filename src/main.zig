const std = @import("std");
const Ast = @import("Ast.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    if (std.os.argv.len != 2) {
        std.debug.print("Usage: jcc file\n", .{});
        return;
    }

    const file = std.fs.cwd().openFile(std.mem.span(std.os.argv[1]), .{ .mode = .read_only }) catch {
        std.debug.panic("Can not open {s}\n", .{std.os.argv[1]});
    };
    defer file.close();

    // Use readToEndAllocOptions() to add an sentinel "0" at the end of the source.
    const source = try file.readToEndAllocOptions(allocator, std.math.maxInt(u32), null, @alignOf(u8), 0);
    defer allocator.free(source);

    var tree = try Ast.parse(allocator, source);
    defer tree.deinit(allocator);

    std.debug.print("source code:\n{s}\n", .{tree.source});
    std.debug.print("tokens:\n", .{});
    for (tree.tokens.items(.tag)) |tag| {
        std.debug.print("{s}\n", .{tag.symbol()});
    }

    std.debug.print("\nAstNodes:\n", .{});
    for (0..tree.nodes.len) |i| {
        std.debug.print(
            "{d}: tag {s: <16} lhs {}\t rhs {} \n",
            .{
                i,
                @tagName(tree.nodes.items(.tag)[i]),
                tree.nodes.items(.data)[i].lhs,
                tree.nodes.items(.data)[i].rhs,
            },
        );
    }
}
