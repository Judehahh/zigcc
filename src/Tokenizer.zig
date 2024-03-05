const std = @import("std");

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const keywords = std.ComptimeStringMap(Tag, .{
        .{ "return", .keyword_return },
        .{ "int", .keyword_int },
    });

    pub fn getKeyword(bytes: []const u8) ?Tag {
        return keywords.get(bytes);
    }

    pub const Tag = enum {
        invalid,
        identifier,
        eof,

        l_paren,
        r_paren,
        semicolon,
        l_brace,
        r_brace,
        slash,
        number_literal,

        keyword_return,
        keyword_int,

        pub fn lexeme(tag: Tag) ?[]const u8 {
            return switch (tag) {
                .invalid,
                .identifier,
                .eof,
                .number_literal,
                => null,

                .l_paren => "(",
                .r_paren => ")",
                .semicolon => ";",
                .l_brace => "{",
                .r_brace => "}",
                .slash => "/",

                .keyword_return => "return",
                .keyword_int => "int",
            };
        }

        pub fn symbol(tag: Tag) []const u8 {
            return tag.lexeme() orelse switch (tag) {
                .invalid => "invalid bytes",
                .identifier => "an identifier",
                .eof => "EOF",
                .number_literal => "a number literal",
                else => unreachable,
            };
        }
    };
};

const Tokenizer = @This();

buffer: [:0]const u8,
index: usize,

/// For debugging purposes
pub fn dump(self: *Tokenizer, token: *const Token) void {
    std.debug.print("{s} \"{s}\"\n", .{ @tagName(token.tag), self.buffer[token.loc.start..token.loc.end] });
}

pub fn init(buffer: [:0]const u8) Tokenizer {
    // Skip the UTF-8 BOM if present
    const src_start: usize = if (std.mem.startsWith(u8, buffer, "\xEF\xBB\xBF")) 3 else 0;
    return Tokenizer{
        .buffer = buffer,
        .index = src_start,
    };
}

pub fn next(self: *Tokenizer) Token {
    var state: enum {
        start,
        identifier,
        slash,
        line_comment,
        int,
    } = .start;

    var result = Token{
        .tag = .eof,
        .loc = .{
            .start = self.index,
            .end = undefined,
        },
    };

    while (true) : (self.index += 1) {
        const c = self.buffer[self.index];
        switch (state) {
            .start => switch (c) {
                0 => {
                    if (self.index != self.buffer.len) {
                        result.tag = .invalid;
                        result.loc.start = self.index;
                        self.index += 1;
                        result.loc.end = self.index;
                        return result;
                    }
                    break;
                },
                ' ', '\n', '\t', '\r' => {
                    result.loc.start = self.index + 1;
                },
                'a'...'z', 'A'...'Z', '_' => {
                    state = .identifier;
                    result.tag = .identifier;
                },
                '(' => {
                    result.tag = .l_paren;
                    self.index += 1;
                    break;
                },
                ')' => {
                    result.tag = .r_paren;
                    self.index += 1;
                    break;
                },
                ';' => {
                    result.tag = .semicolon;
                    self.index += 1;
                    break;
                },
                '{' => {
                    result.tag = .l_brace;
                    self.index += 1;
                    break;
                },
                '}' => {
                    result.tag = .r_brace;
                    self.index += 1;
                    break;
                },
                '/' => {
                    state = .slash;
                },
                '0'...'9' => {
                    state = .int;
                    result.tag = .number_literal;
                },
                else => {
                    result.tag = .invalid;
                    result.loc.end = self.index;
                    self.index += 1;
                    return result;
                },
            },

            .identifier => switch (c) {
                'a'...'z', 'A'...'Z', '_', '0'...'9' => {},
                else => {
                    if (Token.getKeyword(self.buffer[result.loc.start..self.index])) |tag| {
                        result.tag = tag;
                    }
                    break;
                },
            },

            .slash => switch (c) {
                '/' => { // meet double slashes, it is a line comment
                    state = .line_comment;
                },
                else => {
                    result.tag = .slash;
                    break;
                },
            },
            .line_comment => switch (c) {
                0 => {
                    if (self.index != self.buffer.len) {
                        result.tag = .invalid;
                        self.index += 1;
                    }
                    break;
                },
                '\n' => { // line comment end
                    state = .start;
                    result.loc.start = self.index + 1;
                },
                else => {},
            },

            .int => switch (c) {
                '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {},
                else => break,
            },
        }
    }

    result.loc.end = self.index;
    return result;
}
