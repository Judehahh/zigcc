const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("Tokenizer.zig");
const Token = Tokenizer.Token;
const Ast = @import("Ast.zig");
const Node = Ast.Node;
const TokenIndex = Ast.TokenIndex;

const Parse = @This();

pub const Error = error{ParseError} || Allocator.Error;

source: []const u8,
gpa: Allocator,
token_tags: []const Token.Tag,
token_starts: []const Ast.ByteOffset,
tok_i: TokenIndex,
nodes: Ast.NodeList,
extra_data: std.ArrayListUnmanaged(Node.Index),
scratch: std.ArrayListUnmanaged(Node.Index),

const null_node: Node.Index = 0;

const Members = struct {
    len: usize,
    lhs: Node.Index,
    rhs: Node.Index,

    fn toSpan(self: Members, p: *Parse) !Node.SubRange {
        if (self.len <= 2) {
            const nodes = [2]Node.Index{ self.lhs, self.rhs };
            return p.listToSpan(nodes[0..self.len]);
        } else {
            return Node.SubRange{ .start = self.lhs, .end = self.rhs };
        }
    }
};

fn listToSpan(p: *Parse, list: []const Node.Index) !Node.SubRange {
    try p.extra_data.appendSlice(p.gpa, list);
    return Node.SubRange{
        .start = @as(Node.Index, @intCast(p.extra_data.items.len - list.len)),
        .end = @as(Node.Index, @intCast(p.extra_data.items.len)),
    };
}

fn addNode(p: *Parse, elem: Ast.Node) Allocator.Error!Node.Index {
    const result = p.nodes.len;
    try p.nodes.append(p.gpa, elem);
    return result;
}

fn setNode(p: *Parse, i: usize, elem: Ast.Node) Node.Index {
    p.nodes.set(i, elem);
    return i;
}

fn reserveNode(p: *Parse, tag: Ast.Node.Tag) !usize {
    try p.nodes.resize(p.gpa, p.nodes.len + 1);
    p.nodes.items(.tag)[p.nodes.len - 1] = tag;
    return p.nodes.len - 1;
}

fn unreserveNode(p: *Parse, node_index: usize) void {
    if (p.nodes.len == node_index) {
        p.nodes.resize(p.gpa, p.nodes.len - 1) catch unreachable;
    } else {
        // There is zombie node left in the tree, let's make it as inoffensive as possible
        // (sadly there's no no-op node)
        p.nodes.items(.tag)[node_index] = .unreachable_literal;
        p.nodes.items(.main_token)[node_index] = p.tok_i;
    }
}

pub fn parseRoot(p: *Parse) !void {
    p.nodes.appendAssumeCapacity(.{
        .tag = .root,
        .main_token = 0,
        .data = undefined,
    });
    const root_members = try p.parseContainerMembers();
    const root_decls = try root_members.toSpan(p);
    if (p.token_tags[p.tok_i] != .eof) {
        std.debug.panic("expected eof", .{});
    }
    p.nodes.items(.data)[0] = .{
        .lhs = root_decls.start,
        .rhs = root_decls.end,
    };
}

fn parseContainerMembers(p: *Parse) Allocator.Error!Members {
    const scratch_top = p.scratch.items.len;
    defer p.scratch.shrinkRetainingCapacity(scratch_top);

    var field_state: union(enum) {
        /// No fields have been seen.
        none,
        /// Currently parsing fields.
        seen,
        /// Saw fields and then a declaration after them.
        /// Payload is first token of previous declaration.
        end: Node.Index,
        /// There was a declaration between fields, don't report more errors.
        err,
    } = .none;

    var last_field: TokenIndex = undefined;

    while (true) {
        switch (p.token_tags[p.tok_i]) {
            .keyword_int => {
                const top_level_decl = try p.expectTopLevelDeclRecoverable();
                if (top_level_decl != 0) {
                    if (field_state == .seen) {
                        field_state = .{ .end = top_level_decl };
                    }
                    try p.scratch.append(p.gpa, top_level_decl);
                }
            },
            .eof, .r_brace => break,
            else => {
                const identifier = p.tok_i;
                defer last_field = identifier;
            },
        }
    }

    const items = p.scratch.items[scratch_top..];
    switch (items.len) {
        0 => return Members{
            .len = 0,
            .lhs = 0,
            .rhs = 0,
        },
        1 => return Members{
            .len = 1,
            .lhs = items[0],
            .rhs = 0,
        },
        2 => return Members{
            .len = 2,
            .lhs = items[0],
            .rhs = items[1],
        },
        else => {
            const span = try p.listToSpan(items);
            return Members{
                .len = items.len,
                .lhs = span.start,
                .rhs = span.end,
            };
        },
    }
}

fn findNextContainerMember(p: *Parse) void {
    _ = p;
    std.debug.panic("nor support for now", .{});
    return;
}

/// Decl
///     <- FnProto
///      / VarDecl
fn expectTopLevelDecl(p: *Parse) !Node.Index {
    const fn_proto = try p.parseFnProto();
    if (fn_proto != 0) {
        switch (p.token_tags[p.tok_i]) {
            .semicolon => {
                p.tok_i += 1;
                return fn_proto;
            },
            .l_brace => {
                const fn_decl_index = try p.reserveNode(.fn_decl);
                errdefer p.unreserveNode(fn_decl_index);

                const body_block = try p.parseBlock();
                std.debug.assert(body_block != 0);

                return p.setNode(fn_decl_index, .{
                    .tag = .fn_decl,
                    .main_token = p.nodes.items(.main_token)[fn_proto],
                    .data = .{
                        .lhs = fn_proto,
                        .rhs = body_block,
                    },
                });
            },
            else => std.debug.panic("expected semi or lbrace, but meet {}!", .{p.token_tags[p.tok_i]}),
        }
    }
    return error.ParseError;
}

fn expectTopLevelDeclRecoverable(p: *Parse) error{OutOfMemory}!Node.Index {
    return p.expectTopLevelDecl() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ParseError => {
            p.findNextContainerMember();
            return null_node;
        },
    };
}

/// FnProto <- KEYWORD_int IDENTIFIER LPAREN ParamDeclList RPAREN
fn parseFnProto(p: *Parse) !Node.Index {
    const int_token = p.eatToken(.keyword_int) orelse return null_node;
    _ = p.eatToken(.identifier);
    if (p.eatToken(.l_paren) == null) std.debug.panic("expected lparen, but {}", .{p.token_tags[p.tok_i]});
    const params = null_node;
    if (p.eatToken(.r_paren) == null) std.debug.panic("expected rparen, but {}", .{p.token_tags[p.tok_i]});

    const fn_proto_index = try p.reserveNode(.fn_proto);
    errdefer p.unreserveNode(fn_proto_index);

    const return_type_expr = try p.addNode(.{ .tag = .int_type, .main_token = int_token, .data = .{
        .lhs = undefined,
        .rhs = undefined,
    } });

    return p.setNode(fn_proto_index, .{
        .tag = .fn_proto,
        .main_token = int_token,
        .data = .{
            .lhs = params,
            .rhs = return_type_expr,
        },
    });
}

/// Statement
///     <- KEYWORD_return Expr?
fn expectStatement(p: *Parse) Error!Node.Index {
    switch (p.token_tags[p.tok_i]) {
        .keyword_return => {
            const node = p.addNode(.{
                .tag = .@"return",
                .main_token = p.nextToken(),
                .data = .{
                    .lhs = try p.parseExpr(),
                    .rhs = null_node,
                },
            });
            if (p.eatToken(.semicolon) == null) std.debug.panic("expected semicolon at {}", .{@src()});
            return node;
        },
        else => {
            std.debug.panic("expected return, but meet {}", .{p.token_tags[p.tok_i]});
        },
    }
}

/// If a parse error occurs, reports an error, but then finds the next statement
/// and returns that one instead. If a parse error occurs but there is no following
/// statement, returns 0.
fn expectStatementRecoverable(p: *Parse) Error!Node.Index {
    while (true) {
        return p.expectStatement() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ParseError => {
                std.debug.panic("ParseError at {}", .{@src()});
            },
        };
    }
}

fn parseExpr(p: *Parse) Error!Node.Index {
    switch (p.token_tags[p.tok_i]) {
        .number_literal => {
            return try p.addNode(.{
                .tag = .number_literal,
                .main_token = p.nextToken(),
                .data = .{
                    .lhs = null_node,
                    .rhs = null_node,
                },
            });
        },
        else => {
            std.debug.panic("only support a number literal as Expr for now", .{});
        },
    }
}

/// Block <- LBRACE Statement* RBRACE
fn parseBlock(p: *Parse) !Node.Index {
    const lbrace = p.eatToken(.l_brace) orelse return null_node;
    const scratch_top = p.scratch.items.len;
    defer p.scratch.shrinkRetainingCapacity(scratch_top);
    while (true) {
        if (p.token_tags[p.tok_i] == .r_brace) break;
        const statement = try p.expectStatementRecoverable();
        if (statement == 0) break;
        try p.scratch.append(p.gpa, statement);
    }
    _ = p.expectToken(.r_brace);
    return p.addNode(.{ .tag = .block_two, .main_token = lbrace, .data = .{
        .lhs = 0,
        .rhs = 0,
    } });
}

fn eatToken(p: *Parse, tag: Token.Tag) ?TokenIndex {
    return if (p.token_tags[p.tok_i] == tag) p.nextToken() else null;
}

fn expectToken(p: *Parse, tag: Token.Tag) TokenIndex {
    if (p.token_tags[p.tok_i] != tag) {
        std.debug.panic("expected {}, meet {}", .{ tag, p.token_tags[p.tok_i] });
    }
    return p.nextToken();
}

fn nextToken(p: *Parse) TokenIndex {
    const result = p.tok_i;
    p.tok_i += 1;
    return result;
}
