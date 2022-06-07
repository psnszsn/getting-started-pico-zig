const std = @import("std");
const builtin = @import("builtin");
const uf2 = @import("uf2/src/main.zig");
const rp2040 = @import("rp2040/build.zig");
const microzig = @import("microzig/src/main.zig");

const Builder = std.build.Builder;
const Step = std.build.Step;
const LibExeObjStep = std.build.LibExeObjStep;

const Message = @import("src/device_info.zig").Message;

fn root() []const u8 {
    return (std.fs.path.dirname(@src().file) orelse ".") ++ "/";
}

pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();
    const mounted_dir_opt = b.option([]const u8, "path", "override where the pi pico is mounted");
    const flash_step = b.step("flash", "Flash the pi pico");
    const blinky = rp2040.addPiPicoExecutable(
        microzig,
        b,
        "blinky",
        "examples/blinky.zig",
        .{},
    );
    blinky.setBuildMode(mode);
    blinky.install();

    if (mounted_dir_opt) |mounted_dir| {
        const uf2_step = uf2.Uf2Step.create(blinky, .{
            .family_id = .RP2040,
        });

        const uf2_flash_op = uf2_step.addFlashOperation(mounted_dir);
        flash_step.dependOn(&uf2_flash_op.step);
    } else {
        switch (builtin.os.tag) {
            .linux => {
                const device_info = DeviceInfoStep.create(b);
                flash_step.dependOn(&device_info.step);

                // TODO: add ability for uf2 to mount the device. For systems
                // permissions look into polkit and PAM, or even do some
                // analysis on the user and if they're able to mount drives.
                // It's important if we do all this work for them, then it
                // won't be more painful than getting them to manually mount a
                // drive

            },
            else => {
                // TODO: device discovery for windows, macos, fuck it why not even BSD?
                std.log.err("you must provide a path to the pi pico's directory", .{});
                return error.NoDir;
            },
        }
    }
}

pub const DeviceInfoStep = struct {
    step: Step,
    builder: *Builder,
    exe: *LibExeObjStep,

    pub fn create(b: *Builder) *DeviceInfoStep {
        var ret = b.allocator.create(DeviceInfoStep) catch @panic("failed to allocate DeviceInfoStep");
        ret.* = .{
            .step = Step.init(.custom, "device_info", b.allocator, make),
            .builder = b,
            .exe = b.addExecutable("device_info", root() ++ "src/device_info.zig"),
        };
        ret.step.dependOn(&ret.exe.step);

        if (builtin.os.tag == .linux) {
            ret.exe.linkLibC();
            // TODO: can we check for the existence of this library?
            ret.exe.linkSystemLibrary("libudev");
        }

        return ret;
    }

    fn make(step: *Step) !void {
        const device_info = @fieldParentPtr(DeviceInfoStep, "step", step);

        std.log.info("exe path: {s}", .{device_info.exe.getOutputSource().generated.getPath()});

        const child = try std.ChildProcess.init(&.{
            device_info.exe.getOutputSource().generated.getPath(),
        }, device_info.builder.allocator);
        defer child.deinit();

        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Pipe;

        try child.spawn();

        const writer = child.stdin.?.writer();
        _ = writer;
        const reader = child.stdout.?.reader();

        while (true) {
            const line = reader.readUntilDelimiterAlloc(device_info.builder.allocator, '\n', 1024 * 1024) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
            defer device_info.builder.allocator.free(line);

            var stream = std.json.TokenStream.init(line);
            const message = try std.json.parse(Message, &stream, .{ .allocator = device_info.builder.allocator });

            if (std.mem.eql(u8, "log", message.tag)) {
                std.log.info("{s}", .{message.payload});
            } else if (std.mem.eql(u8, "found", message.tag)) {
                std.log.info("found pi pico with device path: {s}", .{message.payload});
            } else @panic("incorrect message tag");
        }

        std.log.err("this device discovery thing isn't fully implemented yet, make sure it's mounted and specify that path.", .{});

        // could wait instead, but I'm in a bloodthirsty mood
        _ = try child.kill();
    }
};
