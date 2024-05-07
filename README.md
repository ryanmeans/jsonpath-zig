# jsonpath-zig
Boilerplate free, safe stdlib JSON Value access.

Provides a simple utility function to more safely access stdlib's JSON Values
It let's you get a child Value from any arbitary Value by giving it a path of
keys (`[]const u8`) and integer types, as well as the expected type for that value.

This library avoids needing to make any allocations, but note that any
returned data will be tied to the lifetime of the original Value.

# Usage and Examples

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
        \\    {
        \\      "some": {
        \\        "nested": {
        \\          "json": "value"
        \\        }
        \\      }
        \\    }
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

The "types" you can pass in are the same as the underlying
types of the `json.Value` union. Any other type will result in a comptime error.
Those types being the following (with the corresponding json.Value field)

```
bool (bool)
i64 (integer)
f64 (float)
[]const u8 (string)
json.Array (array)
json.ObjectMap (object)
json.Value
```

There is no direct way to handle `null` or `number_string` values, but you
can retrieve it as a `json.Value` and handle the value manually.
