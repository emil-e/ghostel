const std = @import("std");
const gt = @import("ghostty-vt");
const kitty = gt.kitty.graphics;

const Self = @This();

const PlacementKey = kitty.ImageStorage.PlacementKey;
const Placement = kitty.ImageStorage.Placement;
const PlacementMap = @FieldType(kitty.ImageStorage, "placements");

const TrackedPlacement = struct {
    position: *gt.Pin,
    rows: u32,
};

const SliceList = std.DoublyLinkedList(Slice);

const Slice = struct {
    node: std.DoublyLinkedList.Node,
    placement: PlacementKey,
    source_row: u32,
    source_col: u32,
    width: u32,
    z: i32,
};

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
            if (i >= placement.rows) break;
            self.rows.put(pin, .{});
        }
    }

    const screen = self.term.screens.active;
    var placement_it = screen.kitty_images.placements.iterator();
    for (placement_it.next()) |*placement| self.updateWithPlacement(placement);

    self.capturePlacements();
    self.rendered_screen = screen;
}

fn updateWithPlacement(self: *Self, entry: *const PlacementMap.Entry) void {
    if (entry.value_ptr.location == .virtual) return;

    var it = entry.value_ptr.location.pin.rowIterator(.right_down, null);
    var i: usize = 0;
    while (it.next()) |pin| : (i += 1) {
        if (i >= entry.value_ptr.rows) break;
        const slice = try self.slice_arena.allocator().create(Slice);
        errdefer self.slice_arena.allocator().destroy(slice);
        slice.* = .{
            .placement = entry.key_ptr.*,
            .source_row = i,
            .source_col = 0,
            .width = entry,
            .z = entry.value_ptr.z,
        };

        self.insertSlice(pin, slice);
    }
}

fn insertSlice(self: *Self, pin: gt.Pin, slice: *Slice) void {
    const result = try self.rows.getOrPut(self.alloc, pin);
    const list = result.value_ptr;
    if (!result.found_existing) list.* = .empty;

    var node = list.first;
    while (node) |n| : (node = n.next) {
        const other: *const Slice = @fieldParentPtr("node", n);
        if (slice.z < other.z) {
            self.list.rows.insertBefore(n, &slice.node);
            return;
        }
    }

    list.append(&slice.node);
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
