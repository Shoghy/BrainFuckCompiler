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

    const filePath = args[1];
    if (std.fs.cwd().openFile(filePath, .{})) |file| {
        defer file.close();
        FileReader = std.io.bufferedReader(file.reader());
        try readFile();
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
        '.' => {
            std.debug.print("{c}", .{Bytes.items[Pointer]});
        },
        else => {},
    }
}

fn createLoop() !void {
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
