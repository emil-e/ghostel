const std = @import("std");
const gt = @import("ghostty-vt");
const kitty = gt.kitty.graphics;

const Self = @This();

const TrackedPlacement = struct {
    position: *gt.Pin,
    rows: u32,
};

const SliceList = std.DoublyLinkedList(Slice);

const Slice = struct {
    image_id: u32,
    start: u32,
    cols: u32,

    source_x: u32 = 0,
    source_y: u32 = 0,
    source_width: u32 = 0,
    source_height: u32 = 0,

    z: i32 = 0,
};

const PlacementMap = @FieldType(kitty.ImageStorage, "placements");

term: *gt.Terminal,
alloc: std.mem.Allocator,

rendered_screen: *gt.Screen,
rendered_placements: std.ArrayList(TrackedPlacement) = .empty,

rows: std.AutoHashMapUnmanaged(gt.Pin, SliceList),
slice_arena: std.heap.ArenaAllocator = undefined,

pub fn init(
    alloc: std.mem.Allocator,
    term: *gt.Terminal,
) Self {
    return .{
        .term = term,
        .alloc = alloc,
        .slice_arena = .init(alloc),
    };
}

fn update(self: *Self) void {
    self.rows.clearRetainingCapacity();
    self.slice_arena.reset(.retain_capacity);

    for (self.rendered_placements.items) |placement| {
        var row_it = placement.position.rowIterator(.right_down, null);
        var i: usize = 0;
        while (row_it.next()) |pin| : (i += 1) {
            if (i > placement.rows) break;
            self.rows.put(pin, .{});
        }
    }

    const screen = self.term.screens.active;
    var placement_it = screen.kitty_images.placements.iterator();
    for (placement_it.next()) |*placement| self.updateWithPlacement(placement);

    self.capturePlacements();
    self.rendered_screen = screen;
}

fn updateWithPlacement(self: *Self, placement: *const kitty.ImageStorage.Placement) void {
    if (placement.location == .virtual) return;

    var it = placement.location.pin.rowIterator(.right_down, null);
	var i: usize = 0;
	while (it.next()) |pin| (i += 1) {

	}
}

fn slice(self: *Self, entry: *PlacementMap.Entry, i: usize) Slice {
	const key = entry.key_ptr;
	const val = entry.value_ptr;

	const heightf: f64 = @floatFromInt(val.source_height);
	const slice_height: f64 = @floatFromInt(heightf / @floatFromInt(val.rows));
	const cell_height = self.term.height_px / self.term.rows;
	const x_offset = cell_height - val.x_offset;
	const y_offset = cell_height - val.y_offset;

	return .{
		.image_id = key.image_id,
		.start = val.location.pin.x,
		.cols = val.columns,
		.source_x = x_offset + val.source_x,
		.source_y = y_offset + val.source_y + (i * slice_height),
		.source_height = slice_height,
		.source_width = val.source_width,
		.z = val.z,
	};
}

fn capturePlacements(self: *Self) void {
    self.clearPlacements();

    const screen = self.term.screens.active;
    const image_storage = &screen.kitty_images;
    var it = image_storage.placements.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.location == .virtual) continue;
        self.rendered_placements.add(self.alloc, .key_ptr.*, .{
            .position = screen.pages.trackPin(entry.value_ptr.pin.*),
            .rows = entry.value_ptr.rows,
        });
    }
}

fn clearPlacements(self: *Self) void {
    while (self.rendered_placements.items) |*placement| {
        self.rendered_screen.pages.untrackPin(placement.position);
    }
    self.rendered_placements.clearRetainingCapacity();
}

fn bol(pin: *gt.Pin) gt.Pin {
    var p = pin.*;
    p.x = 0;
    return p;
}

pub fn deinit(self: *Self) void {
    self.rendered_placements.deinit(self.alloc);

    self.rows.deinit(self.alloc);
    self.slice_arena.deinit();
}
