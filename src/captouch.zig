const std = @import("std");
const File = std.fs.File;
const Handle = std.posix.fd_t;

// Device addresses
const DEVICE = "/dev/i2c-1";
const ADDRESS = 0x2c;
const I2C_SLAVE = 0x0703;

/// Register map
const R_MAIN_CONTROL: u8 = 0x00;
// Status addresses
const R_INPUT_STATUS: u8 = 0x03;
// LED controls
const R_LED_OUTPUT_CON = 0x74; // Control 1 LED per bit
const R_LED_BEHAVIOUR_1 = 0x81; // For LEDs 1-4
const R_LED_BEHAVIOUR_2 = 0x82; // For LEDs 5-8
// LED Behaviour
pub const BEHAVIOUR_CONSTANT = 0b00;
pub const BEHAVIOUR_PULSE_1 = 0b01;
pub const BEHAVIOUR_PULSE_2 = 0b10;
pub const BEHAVIOUR_BREATH = 0b11;

// Helper values
pub const ALL_ONES = 0xff;
pub const ALL_ZEROES = 0x00;

pub const Captouch = @This();
file: File,
handle: Handle,

// Initialize handle to the device to write and read instructions from/to.
pub fn init() !Captouch {
    const f: File = try std.fs.openFileAbsolute(DEVICE, .{ .mode = .read_write });
    // Set I2C address
    if (std.os.linux.ioctl(f.handle, I2C_SLAVE, ADDRESS) < 0)
        return error.IoctlFailed;

    const touch = Captouch{ .file = f, .handle = f.handle };
    try touch.reset();
    return touch;
}

// Reset controls and close file
pub fn deinit(this: Captouch) void {
    this.reset();
    this.file.close();
}

// Reset all relevant controls for this module
pub fn reset(this: Captouch) void {
    try this.disableLeds();
    try this.direct();
    try this.resetInput();
}

// Check if any key is pressed
pub fn anyPressed(this: Captouch) !bool {
    // Write register address to read
    if (std.os.linux.write(this.handle, &[_]u8{R_INPUT_STATUS}, 1) != 1)
        return error.WriteAddressToReadFailed;
    // Read 1 byte from register
    var readBuf: [1]u8 = undefined;
    if (std.os.linux.read(this.handle, &readBuf, 1) != 1)
        return error.ReadInputStatusFailed;
    return readBuf[0] > 0;
}

// Set all LEDs to breathing
pub fn breath(this: Captouch) !void {
    // Set 'breath' behaviour for all LEDs 1-4
    try this.writeRegister(R_LED_BEHAVIOUR_1, ALL_ONES);
    // Set 'breath' behaviour for all LEDs 5-8
    try this.writeRegister(R_LED_BEHAVIOUR_2, ALL_ONES);
}

// Set all LEDs to constant
pub fn direct(this: Captouch) !void {
    // Set behaviour for all LEDs 1-4 to constant
    try this.writeRegister(R_LED_BEHAVIOUR_1, ALL_ZEROES);
    // Set behaviour for all LEDs 5-8 to constant
    try this.writeRegister(R_LED_BEHAVIOUR_2, ALL_ZEROES);
}

// Set behaviour per LED
pub fn setLedBehaviour(this: Captouch, i: u4, behaviour: u8) !void {
    // Example: set LED 3 to breathing: R_LED_BEHAVIOUR_1 := 0b00110000
    const j: u3 = @intCast((2 * i) % 8);
    const shifted: u8 = behaviour << j;
    const ledGroup: u2 = i / 4;
    try this.writeRegister(R_LED_BEHAVIOUR_1 + ledGroup, shifted);
}

// Enable all LEDs
pub fn enableLeds(this: Captouch) !void {
    try this.writeRegister(R_LED_OUTPUT_CON, ALL_ONES);
}

// Disable all LEDs
pub fn disableLeds(this: Captouch) !void {
    try this.writeRegister(R_LED_OUTPUT_CON, ALL_ZEROES);
}

// Reset all touch button input
pub fn resetInput(this: Captouch) !void {
    try this.writeRegister(R_MAIN_CONTROL, ALL_ZEROES);
}

// Write given value to given register
fn writeRegister(this: Captouch, register: u8, val: u8) !void {
    if (std.os.linux.write(this.handle, &[_]u8{ register, val }, 2) != 2)
        return error.WriteFailed;
}
