/** @brief Package-local soft assertions using the SDK test harness counter ABI. */
part of NetTransport;

@extern("C") func AddFail(count: int32) -> void;

func net_test_assert_true(condition: bool, message: ref string) -> int32 {
  if condition { return 0; }
  Console.Eprintln(message);
  AddFail(1);
  return 1;
}
func net_test_assert_i32(actual: int32, expected: int32, message: ref string) -> int32 {
  return net_test_assert_true(actual == expected, message);
}
func net_test_assert_i64(actual: int64, expected: int64, message: ref string) -> int32 {
  return net_test_assert_true(actual == expected, message);
}
func net_test_assert_string(actual: ref string, expected: ref string, message: ref string) -> int32 {
  return net_test_assert_true(actual.Equal(expected), message);
}
