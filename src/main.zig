const std = @import("std");

const RESET_COLOR = "\x1B[0m";
const RED = "\x1B[31m";
const BOLD = "\x1B[1m";
const UNDERLINE = "\x1B[4m";

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

const ValidChars = "+-<>[].,";
var Bytes = std.ArrayList(u8).init(std.heap.page_allocator);
var Pointer: usize = 0;

fn isValidChar(ch: u8) bool {
    for (ValidChars) |valid| {
        if (ch == valid) return true;
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
        printRedLn("* You must pass a file path as an argument", .{});
        return;
    }
    var showMemory = false;
    if (args.len > 2) {
        const thirdArg = args[2];
        showMemory = std.mem.eql(u8, thirdArg, "-s");
    }

    const filePath = args[1];
    if (std.fs.cwd().openFile(filePath, .{})) |file| {
        defer file.close();
        var fileContent = try readFile(file);
        defer fileContent.deinit();

        try executeCode(fileContent.items);

        if (showMemory) {
            printMemory();
        }
    } else |fileError| switch (fileError) {
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

fn readFile(file: File) !std.ArrayListAligned(u8, null) {
    var reader = std.io.bufferedReader(file.reader());
    var buffer: [1]u8 = undefined;
    var fileContent = std.ArrayList(u8).init(std.heap.page_allocator);

    while (reader.read(&buffer)) |numberOfBytesRead| {
        if (numberOfBytesRead == 0) {
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
                Bytes.items[Pointer] +%= 1;
            },
            '-' => {
                Bytes.items[Pointer] -%= 1;
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
    var deep: usize = 1;
    while (deep != 0) {
        lastIndex += 1;
        if (lastIndex >= code.len) {
            break;
        }
        if (code[lastIndex] == '[') {
            deep += 1;
            continue;
        }
        if (code[lastIndex] != ']') continue;
        deep -= 1;
        if (deep == 0) {
            break;
        }
    }
    if (deep != 0) {
        return error.LoopWithoutClose;
    }

    while (Bytes.items[Pointer] != 0) {
        try executeCode(code[startIndex..lastIndex]);
    }
    return lastIndex + 1;
}

fn printUtf8() !void {
    var charCount: usize = utf8CharLen(Bytes.items[Pointer]);
    if (charCount == 0) {
        printRedLn("* The utf-8 sequence has a problem in its first byte", .{});
        return error.InvalidFirstByte;
    }

    charCount += Pointer;
    const utf8Bytes = Bytes.items[Pointer..charCount];

    if (!std.unicode.utf8ValidateSlice(utf8Bytes)) {
        printRedLn("* The utf-8 is not valid", .{});
        return error.InvalidUtf8;
    }
    std.debug.print("{s}", .{utf8Bytes});
}

fn utf8CharLen(firstByte: u8) u8 {
    if (firstByte < 128) return 1;

    if ((firstByte >> 3) == 0b11110) return 4;

    if ((firstByte >> 4) == 0b1110) return 3;

    if ((firstByte >> 5) == 0b110) return 2;

    return 0;
}

fn printMemory() void {
    std.debug.print("\n\n", .{});
    printLn("Pointer: {}", .{Pointer});
    std.debug.print("Memory: [", .{});

    for (0.., Bytes.items) |index, byte| {
        std.debug.print(" ", .{});

        if (index == Pointer) {
            std.debug.print("{s}{s}", .{ BOLD, UNDERLINE });
        }

        std.debug.print("{}", .{byte});

        if (index == Pointer) {
            std.debug.print("{s}", .{RESET_COLOR});
        }
        if (index + 1 < Bytes.items.len) {
            std.debug.print(",", .{});
        }
    }

    std.debug.print(" ]\n", .{});
}
