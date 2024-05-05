const std = @import("std");
const json = std.json;

pub const JsonPathError = error{
    PathDoesNotLeadToExpectedType,
    ValueIsNotArray,
    ArrayIndexOutOfBounds,
    ValueIsNotObject,
    KeyDoesNotExist,
};

fn objGet(val: json.Value, idx: []const u8) JsonPathError!json.Value {
    switch (val) {
        .object => |obj| {
            const value = obj.get(idx);
            if (value) |v| {
                return v;
            } else {
                return JsonPathError.KeyDoesNotExist;
            }
        },
        else => return JsonPathError.ValueIsNotObject,
    }
}

fn next(val: json.Value, idx: anytype) JsonPathError!json.Value {
    switch (@typeInfo(@TypeOf(idx))) {
        .Int, .ComptimeInt => {
            switch (val) {
                .array => |v| {
                    if (idx >= v.items.len) {
                        return JsonPathError.ArrayIndexOutOfBounds;
                    }
                    return v.items[idx];
                },
                else => return JsonPathError.ValueIsNotArray,
            }
        },
        .Pointer => |key| if (key.size == .One and key.is_const) {
            // Check if it's a static string
            switch (@typeInfo(key.child)) {
                .Array => |x| if (x.child == u8) {
                    return objGet(val, idx);
                } else {
                    @compileError("Invalid type in path: '" ++ @typeName(@TypeOf(idx)) ++ "'");
                },
                else => {
                    @compileError("Invalid type in path: '" ++ @typeName(@TypeOf(idx)) ++ "'");
                },
            }
        } else if (key.size == .Slice and key.child == u8) {
            return objGet(val, idx);
        } else {
            @compileError("Invalid type in path: '" ++ @typeName(@TypeOf(idx)) ++ "'");
        },
        // TODO: Maybe allow Arrays in here as well? There are probably some types
        // which can be implicitly coerced to []const u8 which we reject
        else => {
            @compileError("Invalid type in path: '" ++ @typeName(@TypeOf(idx)) ++ "'");
        },
    }
}

pub fn coerceToType(comptime T: type, value: json.Value) JsonPathError!T {
    if (T == bool) {
        switch (value) {
            .bool => |v| return v,
            else => return JsonPathError.PathDoesNotLeadToExpectedType,
        }
    } else if (T == i64) {
        switch (value) {
            .integer => |v| return v,
            else => return JsonPathError.PathDoesNotLeadToExpectedType,
        }
    } else if (T == f64) {
        switch (value) {
            .float => |v| return v,
            else => return JsonPathError.PathDoesNotLeadToExpectedType,
        }
    } else if (T == []const u8) {
        switch (value) {
            .string => |v| return v,
            else => return JsonPathError.PathDoesNotLeadToExpectedType,
        }
    } else if (T == json.Array) {
        switch (value) {
            .array => |v| return v,
            else => return JsonPathError.PathDoesNotLeadToExpectedType,
        }
    } else if (T == json.ObjectMap) {
        switch (value) {
            .object => |v| return v,
            else => return JsonPathError.PathDoesNotLeadToExpectedType,
        }
    } else if (T == json.Value) {
        return value;
    } else {
        @compileError("Cannot convert json.Value to '" ++ @typeName(T) ++ "'");
    }
}

// Safely access some child item in a stdlib json.Value object on some given path
// A path is an anonymous struct of either []const u8 or integers, corresponding to
// either JSON Objects or Arrays, then ensure the result Value can be safely
// cast to the type T, and return that
// This doesn't require any additional allocations, but lifetimes for any returns objects
// are the same as the original json.Value
pub fn jsonPath(comptime T: type, value: json.Value, path: anytype) JsonPathError!T {
    comptime var idx: usize = 0;

    var cur: json.Value = value;

    inline while (idx < path.len) {
        cur = try next(cur, path[idx]);
        idx += 1;
    }

    return coerceToType(T, cur);
}

test "type coercing" {
    const alloc = std.testing.allocator;
    const expectEqual = std.testing.expectEqual;
    const expectEqualSlices = std.testing.expectEqualSlices;

    // Test bool
    const json_bool = "true";
    const parsed_bool = try json.parseFromSlice(json.Value, alloc, json_bool, .{});
    defer parsed_bool.deinit();

    const bool_val = try coerceToType(bool, parsed_bool.value);
    try expectEqual(true, bool_val);

    // Test integer
    const json_int = "25";
    const parsed_int = try json.parseFromSlice(json.Value, alloc, json_int, .{});
    defer parsed_int.deinit();

    const int_val = try coerceToType(i64, parsed_int.value);
    try expectEqual(25, int_val);

    // Test float
    const json_float = "0.125";
    const parsed_float = try json.parseFromSlice(json.Value, alloc, json_float, .{});
    defer parsed_float.deinit();

    const float_val = try coerceToType(f64, parsed_float.value);
    try expectEqual(0.125, float_val);

    // Test string
    const json_str = "\"foo\"";
    const parsed_str = try json.parseFromSlice(json.Value, alloc, json_str, .{});
    defer parsed_str.deinit();

    const str_val = try coerceToType([]const u8, parsed_str.value);
    try expectEqualSlices(u8, "foo", str_val);

    // Test array
    const json_array = "[25, 14, 51]";
    const parsed_array = try json.parseFromSlice(json.Value, alloc, json_array, .{});
    defer parsed_array.deinit();

    const array_val = try coerceToType(json.Array, parsed_array.value);
    try expectEqual(3, array_val.items.len);

    // Test object
    const json_obj = "{\"foo\": \"bar\", \"baz\": \"buz\"}";
    const parsed_obj = try json.parseFromSlice(json.Value, alloc, json_obj, .{});
    defer parsed_obj.deinit();

    const obj_val = try coerceToType(json.ObjectMap, parsed_obj.value);
    try expectEqual(2, obj_val.keys().len);
}

test "type coercing error" {
    const expectError = std.testing.expectError;
    const alloc = std.testing.allocator;

    const json_int = "25";
    const parsed_int = try json.parseFromSlice(json.Value, alloc, json_int, .{});
    defer parsed_int.deinit();

    const int_val = coerceToType([]const u8, parsed_int.value);
    try expectError(JsonPathError.PathDoesNotLeadToExpectedType, int_val);
}

test "next" {
    const alloc = std.testing.allocator;
    const expectEqual = std.testing.expectEqual;
    const expectEqualSlices = std.testing.expectEqualSlices;

    const json_array = "[25, 14, 51]";
    const parsed_array = try json.parseFromSlice(json.Value, alloc, json_array, .{});
    defer parsed_array.deinit();

    const idx_obj = try next(parsed_array.value, 1);
    const num = try coerceToType(i64, idx_obj);
    try expectEqual(14, num);

    const json_obj = "{\"foo\": \"bar\", \"baz\": \"buz\"}";
    const parsed_obj = try json.parseFromSlice(json.Value, alloc, json_obj, .{});
    defer parsed_obj.deinit();

    const val_static = try next(parsed_obj.value, "foo");
    const str_static = try coerceToType([]const u8, val_static);
    try expectEqualSlices(u8, "bar", str_static);

    // Coerce static string to slice type
    const slice: []const u8 = "foo";
    const val_slice = try next(parsed_obj.value, slice);
    const str_slice = try coerceToType([]const u8, val_slice);
    try expectEqualSlices(u8, "bar", str_slice);
}

test "next error" {
    const alloc = std.testing.allocator;
    const expectError = std.testing.expectError;

    const json_array = "[25, 14, 51]";
    const parsed_array = try json.parseFromSlice(json.Value, alloc, json_array, .{});
    defer parsed_array.deinit();

    try expectError(JsonPathError.ArrayIndexOutOfBounds, next(parsed_array.value, 3));
    try expectError(JsonPathError.ValueIsNotObject, next(parsed_array.value, "foo"));

    const json_obj = "{\"foo\": \"bar\", \"baz\": \"buz\"}";
    const parsed_obj = try json.parseFromSlice(json.Value, alloc, json_obj, .{});
    defer parsed_obj.deinit();

    try expectError(JsonPathError.KeyDoesNotExist, next(parsed_obj.value, "booze"));
    try expectError(JsonPathError.ValueIsNotArray, next(parsed_obj.value, 0));
}

test "jsonpath" {
    const alloc = std.testing.allocator;
    const expectEqual = std.testing.expectEqual;
    const expectEqualSlices = std.testing.expectEqualSlices;

    const json_obj =
        \\{
        \\  "str": "string_val",
        \\  "bool": true,
        \\  "float": 0.125,
        \\  "int": 25,
        \\  "array": [
        \\      {
        \\          "some": {
        \\              "nested": {
        \\                  "json": "value"
        \\              }
        \\          }
        \\      }
        \\  ]
        \\}
    ;

    const parsed_obj = try json.parseFromSlice(json.Value, alloc, json_obj, .{});
    defer parsed_obj.deinit();
    const val = parsed_obj.value;

    try expectEqual(true, try jsonPath(bool, val, .{"bool"}));
    try expectEqual(25, try jsonPath(i64, val, .{"int"}));
    try expectEqual(0.125, try jsonPath(f64, val, .{"float"}));
    try expectEqualSlices(u8, "string_val", try jsonPath([]const u8, val, .{"str"}));
    try expectEqualSlices(u8, "value", try jsonPath([]const u8, val, .{ "array", 0, "some", "nested", "json" }));
}

test "jsonpath errors" {
    const alloc = std.testing.allocator;
    const expectError = std.testing.expectError;

    const json_obj =
        \\{
        \\  "str": "string_val",
        \\  "bool": true,
        \\  "float": 0.125,
        \\  "int": 25,
        \\  "array": [
        \\      {
        \\          "some": {
        \\              "nested": {
        \\                  "json": "value"
        \\              }
        \\          }
        \\      }
        \\  ]
        \\}
    ;

    const parsed_obj = try json.parseFromSlice(json.Value, alloc, json_obj, .{});
    defer parsed_obj.deinit();
    const val = parsed_obj.value;

    try expectError(JsonPathError.PathDoesNotLeadToExpectedType, jsonPath([]const u8, val, .{"int"}));
    try expectError(JsonPathError.ValueIsNotArray, jsonPath(i64, val, .{0}));
    try expectError(JsonPathError.ArrayIndexOutOfBounds, jsonPath(i64, val, .{ "array", 1 }));
    try expectError(JsonPathError.ValueIsNotObject, jsonPath(i64, val, .{ "str", "key" }));
    try expectError(JsonPathError.KeyDoesNotExist, jsonPath(i64, val, .{"doesnotexist"}));
}
