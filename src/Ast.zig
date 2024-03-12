const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("Token.zig").Tokenizer;
const Token = @import("Token.zig").Token;
const Parser = @import("Parser.zig");

const Ast = @This();

/// Reference to externally-owned data.
source: [:0]const u8,

tokens: Token.List.Slice,
nodes: Node.List.Slice,

pub const TokenIndex = usize;
pub const NodeIndex = enum(u32) { none, _ };
pub const ByteOffset = usize;

pub fn deinit(tree: *Ast, gpa: Allocator) void {
    tree.tokens.deinit(gpa);
    tree.nodes.deinit(gpa);
    tree.* = undefined;
}

/// Result should be freed with tree.deinit() when there are
/// no more references to any of the tokens or nodes.
pub fn parse(gpa: Allocator, source: [:0]const u8) Allocator.Error!Ast {
    var tokens = Token.List{};
    defer tokens.deinit(gpa);

    var tokenizer = Tokenizer.init(source);
    while (true) {
        const token = tokenizer.next();
        try tokens.append(gpa, .{
            .tag = token.tag,
            .loc = token.loc,
        });
        if (token.tag == .eof) break;
    }

    var parser: Parser = .{
        .source = source,
        .gpa = gpa,
        .tok_tags = tokens.items(.tag),
        .tok_i = 0,
        .nodes = .{},
    };
    defer parser.nodes.deinit(gpa);

    // Make sure at least 1 so we can use appendAssumeCapacity on the root node below.
    const estimated_node_count = (tokens.len + 2) / 2;
    try parser.nodes.ensureTotalCapacity(gpa, estimated_node_count);

    try parser.parseRoot();

    return Ast{
        .source = source,
        .tokens = tokens.toOwnedSlice(),
        .nodes = parser.nodes.toOwnedSlice(),
    };
}

pub const Node = struct {
    tag: Tag,
    ty: Type = .invalid,
    data: Data,

    pub const List = std.MultiArrayList(Node);

    pub const Range = struct { start: u32, end: u32 };

    pub const Tag = enum {
        invalid,

        fn_proto,
        fn_decl,

        return_stmt,
    };

    pub const Type = enum {
        invalid,
        int,
    };

    pub const Data = union {};
};
