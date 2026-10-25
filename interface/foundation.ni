/**
 * @brief Network value types, borrowed byte ranges and operation controls.
 * @note Import net_core:net_core.ny. No OS descriptors or C ABI are exported.
 */
import "stdlib:stdlib.ny";

/** @brief Stable network failure category; native codes remain on NetError. */
pub enum NetErrorKind {
  InvalidArgument, InvalidAddress, InvalidPort, UnsupportedFamily,
  NameNotFound, PermissionDenied, AddressInUse, AddressUnavailable,
  ConnectionRefused, ConnectionReset, ConnectionAborted, NotConnected,
  NetworkUnreachable, HostUnreachable, WouldBlock, TimedOut, Cancelled,
  Closed, MessageTooLarge, NotSupported, System,
}

/**
 * @brief Copyable failure payload; construction and messages allocate nothing.
 * @note native_code is zero for package validation, otherwise an OS/resolver code.
 */
pub struct NetError { kind: NetErrorKind; native_code: int32; }
/** @brief Stable English description, returned as an immutable global string. */
pub method(NetError) Message() -> string;

/** @brief IP family; a default address is invalid until constructed or parsed. */
pub enum IpFamily { Unspecified, V4, V6 }
/** @brief Validated IP value with inline network-order bytes and numeric scope. */
pub struct IpAddress;
/** @brief Construct an IPv4 address from four octets; allocates nothing. */
pub static method(IpAddress) V4(a: uint8, b: uint8, c: uint8, d: uint8) -> IpAddress;
/** @brief Copy 16 IPv6 octets and an OS numeric interface scope; allocates nothing. */
pub static method(IpAddress) V6(bytes: ref <uint8>[16], scope_id: uint32) -> IpAddress;
/**
 * @brief Parse strict decimal IPv4 or IPv6, including a final dotted IPv4 tail.
 * @param text Borrowed literal, without brackets, whitespace, hostname or CIDR.
 * @returns An inline address or InvalidAddress; allocates and retains nothing.
 * @note IPv6 accepts numeric %scope only; interface-name lookup belongs to the OS adapter.
 */
pub static method(IpAddress) Parse(text: ref string) -> Result<IpAddress, NetError>;
/** @brief Address family, or Unspecified for a never-initialized value. */
pub method(IpAddress) Family() -> IpFamily;
/** @brief Numeric IPv6 interface scope; zero for IPv4 and unscoped IPv6. */
pub method(IpAddress) ScopeId() -> uint32;
/** @brief Octet in network order; returns InvalidArgument outside 4/16 bytes. */
pub method(IpAddress) ByteAt(index: int32) -> Result<uint8, NetError>;
/** @brief Whether this is a valid all-zero IPv4/IPv6 address. */
pub method(IpAddress) IsUnspecified() -> bool;
/** @brief Whether this is IPv4 127/8 or IPv6 ::1; no implicit family conversion. */
pub method(IpAddress) IsLoopback() -> bool;
/** @brief Whether this is an IPv4-mapped IPv6 value (::ffff:0:0/96). */
pub method(IpAddress) IsV4Mapped() -> bool;
/** @brief Compare family, address bytes and numeric scope; invalid values compare equal. */
pub method(IpAddress) Equals(other: ref IpAddress) -> bool;
/**
 * @brief Owned textual address; lowercase/longest-leftmost IPv6 zero compression.
 * @returns ARC-managed string, or empty for an invalid value; mapped IPv6 uses a dotted tail.
 */
pub method(IpAddress) ToString() -> string;

/** @brief IP address and host-order port; independent of native sockaddr layout. */
pub struct NetEndpoint;
/** @brief Combine a valid address and port (0..65535); no allocation. */
pub static method(NetEndpoint) New(address: ref IpAddress, port: int32) -> Result<NetEndpoint, NetError>;
/**
 * @brief Parse IPv4:port or [IPv6%scope]:port; hostnames require a resolver.
 * @returns Inline endpoint or validation failure; no allocation or retained text.
 * @note Port zero is valid for local ephemeral binding. Brackets are mandatory for IPv6.
 */
pub static method(NetEndpoint) Parse(text: ref string) -> Result<NetEndpoint, NetError>;
/** @brief Copy the inline IP value; no allocation. */
pub method(NetEndpoint) Address() -> IpAddress;
/** @brief Host-order port. */
pub method(NetEndpoint) Port() -> uint16;
/** @brief Compare address, scope and port; no allocation. */
pub method(NetEndpoint) Equals(other: ref NetEndpoint) -> bool;
/** @brief Owned endpoint text; brackets surround IPv6. Invalid values return empty. */
pub method(NetEndpoint) ToString() -> string;

/**
 * @brief Non-owning read-only byte range; copying never retains its backing store.
 * @note The owner must outlive every use. Do not queue this view without retaining an owner.
 */
pub struct NetBytes;
/**
 * @brief Borrow readable memory; rejects negative lengths and null nonempty ranges.
 * @param data Caller guarantees at least length accessible bytes for the view's lifetime.
 * @returns Borrowed view or InvalidArgument; an empty null range is valid.
 */
pub static method(NetBytes) FromRaw(data: *const uint8, length: intptr) -> Result<NetBytes, NetError>;
/** @brief Borrow a string's bytes; caller keeps the string alive and unchanged. */
pub static method(NetBytes) FromString(text: ref string) -> NetBytes;
/** @brief Borrowed address; never transfer or free it. */
pub method(NetBytes) Data() -> *const uint8;
/** @brief Number of readable bytes. */
pub method(NetBytes) Len() -> intptr;
/** @brief Borrow a checked subrange; validates with subtraction to avoid overflow. */
pub method(NetBytes) Slice(start: intptr, length: intptr) -> Result<NetBytes, NetError>;

/**
 * @brief Non-owning mutable range; copying does not establish exclusive access.
 * @note Caller prevents concurrent/overlapping mutation and keeps the owner alive.
 */
pub struct NetMutableBytes;
/** @brief Borrow writable memory under the same bounds/lifetime contract as NetBytes.FromRaw. */
pub static method(NetMutableBytes) FromRaw(data: *mut uint8, length: intptr) -> Result<NetMutableBytes, NetError>;
/** @brief Borrowed writable address; never transfer or free it. */
pub method(NetMutableBytes) Data() -> *mut uint8;
/** @brief Number of writable bytes. */
pub method(NetMutableBytes) Len() -> intptr;
/** @brief Borrow a checked subrange; caller preserves exclusive mutation. */
pub method(NetMutableBytes) Slice(start: intptr, length: intptr) -> Result<NetMutableBytes, NetError>;
/** @brief Read-only view of the same memory; does not extend its lifetime. */
pub method(NetMutableBytes) AsReadOnly() -> NetBytes;

/**
 * @brief Absolute deadline in caller-supplied monotonic nanoseconds; default is unlimited.
 * @note All calls must use the same clock origin. No wall clock or global clock is read.
 */
pub struct NetDeadline;
/** @brief Unlimited deadline; no allocation. */
pub static method(NetDeadline) Never() -> NetDeadline;
/** @brief Finite absolute monotonic deadline; zero expires at monotonic zero. */
pub static method(NetDeadline) At(nanoseconds: uint64) -> NetDeadline;
/** @brief Add timeout to now with saturation at uint64 max; zero expires immediately. */
pub static method(NetDeadline) After(now_ns: uint64, timeout_ns: uint64) -> NetDeadline;
/** @brief Whether a finite deadline exists (including an already expired deadline). */
pub method(NetDeadline) IsFinite() -> bool;
/** @brief Whether a finite deadline is at or before now_ns. */
pub method(NetDeadline) IsExpired(now_ns: uint64) -> bool;
/** @brief Remaining nanoseconds, zero if expired, uint64 max if unlimited. */
pub method(NetDeadline) RemainingNanoseconds(now_ns: uint64) -> uint64;
/** @brief OS wait budget: -1 unlimited, 0 expired, otherwise ceil milliseconds clamped to int32 max. */
pub method(NetDeadline) PollMilliseconds(now_ns: uint64) -> int32;

/**
 * @brief Shared sticky cancellation flag; copies share an ARC-owned atomic cell.
 * @note No reset or callbacks. Polling the flag does not wake a blocked OS wait.
 */
pub struct NetCancellation;
/** @brief Allocate one shared atomic cancellation cell, initially not cancelled. */
pub static method(NetCancellation) New() -> NetCancellation;
/** @brief Allocation-free token that cannot be cancelled; also the default value. */
pub static method(NetCancellation) None() -> NetCancellation;
/** @brief Publish cancellation with release ordering; None is a no-op. */
pub method(NetCancellation) Cancel() -> void;
/** @brief Observe cancellation with acquire ordering; None returns false. */
pub method(NetCancellation) IsCancelled() -> bool;

/**
 * @brief Per-operation deadline and cancellation; default means no limit/cancellation.
 * @note Owned token retains its cell. The operation must supply monotonic now_ns.
 */
pub struct NetOperationOptions { deadline: NetDeadline; cancellation: NetCancellation; }
/** @brief Check cancellation first, then deadline; returns Ok(Unit), Cancelled or TimedOut. */
pub method(NetOperationOptions) Check(now_ns: uint64) -> Result<Unit, NetError>;
