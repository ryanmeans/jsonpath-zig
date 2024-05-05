# jsonpath-zig
Boilerplate free, safe stdlib JSON Value access.

Provides a simple utility function to more safely access stdlib's JSON Values
It let's you get a child Value from any arbitary Value by giving it a path of keys (`[]const u8`) and
integer types, as well as the expected type for that value.

This library avoids needing to make any allocations, but note that any returned data will be tied to the lifetime
of the original Value.

# Examples

```zig
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
```
