const std = @import("std");

const RESET_COLOR = "\x1B[0m";
const RED = "\x1B[31m";

const OpenFileError = std.fs.File.OpenError;
const File = std.fs.File;

fn printLn(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
    std.debug.print("\n", .{});
}

fn printRedLn(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(RED, .{});
    std.debug.print(fmt, args);
    std.debug.print("{s}\n", .{RESET_COLOR});
}

const ValidChard: [8]u8 = .{ '+', '-', '<', '>', '[', ']', '.', ',' };
var Bytes = std.ArrayList(u8).init(std.heap.page_allocator);
var Pointer: usize = 0;

fn isValidChar(ch: u8) bool {
    for (ValidChard) |vCh| {
        if (ch == vCh) return true;
    }
    return false;
}

pub fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    if (a.ptr == b.ptr) return true;
    for (a, b) |a_elem, b_elem| {
        if (a_elem != b_elem) return false;
    }
    return true;
}

pub fn main() !void {
    defer Bytes.deinit();

    try Bytes.append(0);
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printRedLn("* You must pass a file path as an argument", .{});
        return;
    }
    var showMemory = false;
    if (args.len > 2) {
        const thirdArg = args[2];
        showMemory = eql(thirdArg, "-s");
    }

    const filePath = args[1];
    if (std.fs.cwd().openFile(filePath, .{})) |file| {
        defer file.close();
        var fileContent = try readFile(file);
        defer fileContent.deinit();

        try executeCode(fileContent.items);

        if (showMemory) {
            std.debug.print("\n\n", .{});
            printLn("Pointer: {}", .{Pointer});
            printLn("Memory: {any}", .{Bytes.items});
        }
    } else |fileError| {
        switch (fileError) {
            OpenFileError.AccessDenied => {
                printRedLn("* Access denied error", .{});
            },
            OpenFileError.BadPathName => {
                printRedLn("* The file name provider is not valid", .{});
            },
            OpenFileError.FileBusy => {
                printRedLn("* The file is already in use", .{});
            },
            OpenFileError.FileNotFound => {
                printRedLn("* The file doesn't exists", .{});
            },
            OpenFileError.InvalidUtf8 => {
                printRedLn("* The file bytes are not a valid utf-8", .{});
            },
            else => {
                printRedLn("* Unable to open the file", .{});
            },
        }
    }
}

fn readFile(file: File) !std.ArrayListAligned(u8, null) {
    var reader = std.io.bufferedReader(file.reader());
    var buffer: [1]u8 = undefined;
    var fileContent = std.ArrayList(u8).init(std.heap.page_allocator);

    while (reader.read(&buffer)) |byte| {
        if (byte == 0) {
            break;
        }

        const ch = buffer[0];
        if (!isValidChar(ch)) continue;
        try fileContent.append(ch);
    } else |_| {
        printRedLn("* An unexpected error occurred", .{});
        return error.UnexpectedError;
    }

    return fileContent;
}

fn executeCode(code: []u8) anyerror!void {
    var index: usize = 0;
    while (index < code.len) {
        const ch = code[index];
        index += 1;
        switch (ch) {
            '+' => {
                Bytes.items[Pointer] = @addWithOverflow(Bytes.items[Pointer], 1)[0];
            },
            '-' => {
                Bytes.items[Pointer] = @subWithOverflow(Bytes.items[Pointer], 1)[0];
            },
            '>' => {
                if (Pointer + 1 == Bytes.items.len) {
                    try Bytes.append(0);
                }
                Pointer += 1;
            },
            '<' => {
                if (Pointer == 0) {
                    Pointer = Bytes.items.len - 1;
                } else {
                    Pointer -= 1;
                }
            },
            '[' => {
                index = try createLoop(code, index);
            },
            ']' => {
                printRedLn("* Found end of loop without the start", .{});
                return error.EndOfLoop;
            },
            '.' => {
                try printUtf8();
            },
            else => {},
        }
    }
}

fn createLoop(code: []u8, startIndex: usize) !usize {
    var lastIndex = startIndex;
    var deep: usize = 0;
    for (startIndex..code.len) |index| {
        if (code[index] == '[') {
            deep += 1;
            continue;
        }
        if (code[index] != ']') continue;
        if (deep == 0) {
            lastIndex = index;
            break;
        } else {
            deep -= 1;
        }
    }

    const loopPointer = Pointer;
    while (Bytes.items[loopPointer] != 0) {
        try executeCode(code[startIndex..lastIndex]);
    }
    return lastIndex + 1;
}

fn printUtf8() !void {
    const charCount = utf8CharLen(Bytes.items[Pointer]);
    if (charCount == 0) {
        printRedLn("* The utf-8 sequence has a problem in its first byte", .{});
        return error.InvalidFirstByte;
    }

    var utf8Bytes = std.ArrayList(u8).init(std.heap.page_allocator);
    defer utf8Bytes.deinit();

    for (0..charCount) |i| {
        try utf8Bytes.append(Bytes.items[Pointer + i]);
    }

    if (!std.unicode.utf8ValidateSlice(utf8Bytes.items)) {
        printRedLn("* The utf-8 is not valid", .{});
        return error.InvalidUtf8;
    }
    std.debug.print("{s}", .{utf8Bytes.items});
}

fn utf8CharLen(firstByte: u8) u8 {
    if (firstByte < 128) return 1;

    var b = firstByte >> 3;
    if (b == 0b11110) return 4;

    b = b >> 1;
    if (b == 0b1110) return 3;

    b = b >> 1;
    if (b == 0b110) return 2;

    return 0;
}
