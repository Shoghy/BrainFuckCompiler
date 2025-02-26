const std = @import("std");

const RESET_COLOR = "\x1B[0m";
const RED = "\x1B[31m";

const OpenFileError = std.fs.File.OpenError;
const File = std.fs.File;

fn println(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
    std.debug.print("\n", .{});
}

const ValidChard: [8]u8 = .{ '+', '-', '<', '>', '[', ']', '.', ',' };
var Bytes = std.ArrayList(u8).init(std.heap.page_allocator);
var Pointer: usize = 0;
var FileReader: std.io.BufferedReader(4096, std.fs.File.Reader) = undefined;

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
        println("{s}* You must pass a file path as an argument{s}", .{ RED, RESET_COLOR });
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
        FileReader = std.io.bufferedReader(file.reader());
        try readFile();
        if (showMemory) {
            std.debug.print("\n\n", .{});
            println("Pointer: {}", .{Pointer});
            println("Memory: {any}", .{Bytes.items});
        }
    } else |fileError| {
        switch (fileError) {
            OpenFileError.AccessDenied => {
                println("{s}* Access denied error{s}", .{ RED, RESET_COLOR });
            },
            OpenFileError.BadPathName => {
                println("{s}* The file name provider is not valid{s}", .{ RED, RESET_COLOR });
            },
            OpenFileError.FileBusy => {
                println("{s}* The file is already in use{s}", .{ RED, RESET_COLOR });
            },
            OpenFileError.FileNotFound => {
                println("{s}* The file doesn't exists{s}", .{ RED, RESET_COLOR });
            },
            OpenFileError.InvalidUtf8 => {
                println("{s}* The file bytes are not a valid utf-8{s}", .{ RED, RESET_COLOR });
            },
            else => {
                println("{s}* Unable to open the file{s}", .{ RED, RESET_COLOR });
            },
        }
    }
}

fn readFile() !void {
    var buffer: [1]u8 = undefined;

    while (FileReader.read(&buffer)) |byte| {
        if (byte == 0) {
            break;
        }

        const ch = buffer[0];
        if (!isValidChar(ch)) continue;
        try checkChar(ch);
    } else |_| {
        println("{s}* An unexpected error occurred{s}", .{ RED, RESET_COLOR });
    }
}

fn checkChar(ch: u8) !void {
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
            try createLoop();
        },
        ']' => {
            println("{s}* Found end of loop without the start{s}", .{ RED, RESET_COLOR });
            return error.EndOfLoop;
        },
        '.' => {
            try printUtf8();
        },
        else => {},
    }
}

fn createLoop() anyerror!void {
    var buffer: [1]u8 = undefined;
    var loopCode = std.ArrayList(u8).init(std.heap.page_allocator);
    defer loopCode.deinit();

    while (FileReader.read(&buffer)) |byte| {
        if (byte == 0) {
            println("{s}* Didn't find the end of the loop{s}", .{ RED, RESET_COLOR });
            return;
        }

        const ch = buffer[0];
        if (!isValidChar(ch)) continue;
        if (ch == ']') break;
        try loopCode.append(ch);
    } else |_| {
        println("{s}* An unexpected error occurred{s}", .{ RED, RESET_COLOR });
    }

    const loopPointer = Pointer;
    while (Bytes.items[loopPointer] != 0) {
        for (loopCode.items) |ch| {
            try checkChar(ch);
        }
    }
}

fn printUtf8() !void {
    const charCount = utf8CharLen(Bytes.items[Pointer]);
    if (charCount == 0) {
        println("{s}* The utf-8 sequence has a problem in its first byte{s}", .{ RED, RESET_COLOR });
        return error.InvalidFirstByte;
    }

    var utf8Bytes = std.ArrayList(u8).init(std.heap.page_allocator);
    defer utf8Bytes.deinit();

    for (0..charCount) |i| {
        try utf8Bytes.append(Bytes.items[Pointer + i]);
    }

    if (!std.unicode.utf8ValidateSlice(utf8Bytes.items)) {
        println("{s}* The utf-8 is not valid{s}", .{ RED, RESET_COLOR });
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
