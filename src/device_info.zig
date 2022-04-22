const std = @import("std");
const c = @cImport({
    @cInclude("libudev.h");
});

pub const Message = struct {
    tag: []const u8,
    payload: []const u8,
};

const raspi_vendor_id = "2e8a";

pub fn main() !void {

    // TODO: initial scan
    const message = Message{
        .tag = "log",
        .payload = "no raspberry pi picos found on this computer, plug yours in now to continue.",
    };

    const writer = std.io.getStdOut().writer();
    try std.json.stringify(message, .{}, writer);
    try writer.writeByte('\n');

    const udev = c.udev_new();
    if (udev == null)
        return error.FailedNewUdev;
    defer _ = c.udev_unref(udev);

    const monitor = c.udev_monitor_new_from_netlink(udev, "udev");
    if (monitor == null)
        return error.FailedNewMonitor;
    defer _ = c.udev_monitor_unref(monitor);

    const rc = c.udev_monitor_enable_receiving(monitor);
    if (rc != 0)
        return error.FailedEnableReceiving;

    while (true) {
        const device = c.udev_monitor_receive_device(monitor);
        if (device != null) {
            const vendor_id = std.mem.span(c.udev_device_get_property_value(device, "ID_VENDOR_ID") orelse continue);
            const devtype = std.mem.span(c.udev_device_get_devtype(device) orelse continue);
            const action = std.mem.span(c.udev_device_get_property_value(device, "ACTION") orelse continue);

            if (std.mem.eql(u8, raspi_vendor_id, vendor_id) and
                std.mem.eql(u8, "partition", devtype) and
                std.mem.eql(u8, "add", action))
            {
                const devnode = std.mem.span(c.udev_device_get_devnode(device) orelse return error.NoDevNode);
                const found_message = Message{
                    .tag = "found",
                    .payload = devnode,
                };

                try std.json.stringify(found_message, .{}, writer);
                try writer.writeByte('\n');

                break;
            }
        } else {
            std.os.nanosleep(0, std.time.ns_per_s / 2);
        }
    }
}
