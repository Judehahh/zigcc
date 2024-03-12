const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("Token.zig").Tokenizer;
const Token = @import("Token.zig").Token;
const Ast = @import("Ast.zig");
const Node = Ast.Node;
const TokenIndex = Ast.TokenIndex;

const Parser = @This();

source: [:0]const u8,

gpa: std.mem.Allocator,
tok_tags: []const Token.Tag,
tok_i: TokenIndex = 0,

nodes: Ast.Node.List = .{},

pub const Error = error{ParseError} || Allocator.Error;

pub fn parseRoot(p: *Parser) !void {
    _ = try p.addNode(.{ .tag = .invalid, .ty = undefined, .data = undefined });

    while (p.eatToken(.eof) == null) {
        // TODO: do parsing here.
        std.debug.print("next token: {}\n", .{p.tok_tags[p.nextToken()]});
    }
    std.debug.print("meet eof\n", .{});
}

fn eatToken(p: *Parser, tag: Token.Tag) ?TokenIndex {
    if (p.tok_tags[p.tok_i] == tag) {
        defer p.tok_i += 1;
        return p.tok_i;
    } else return null;
}

fn nextToken(p: *Parser) TokenIndex {
    defer p.tok_i += 1;
    return p.tok_i;
}

fn addNode(p: *Parser, node: Ast.Node) !Ast.NodeIndex {
    const res = p.nodes.len;
    try p.nodes.append(p.gpa, node);
    return @enumFromInt(res);
}
