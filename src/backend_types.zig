const std = @import("std");

pub const ProcessParams = struct {
    file: [:0]const u8,
    args: [][:0]const u8,
    env: *const std.process.EnvMap,
    cwd: ?[]const u8 = null,
};

pub const WriteResult = union(enum) {
    written: usize,
    timeout,
    interrupted,
};
