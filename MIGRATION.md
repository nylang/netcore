# 1.0.5 source migration

The empty `NetClock` namespace is removed. Use
`Instant.Now().ToDurationSinceEpochish().ToNanoseconds()` for the same monotonic
origin, or `options.CheckNow()` for current deadline/cancellation admission.
The generic clock belongs to stdlib; transport adds no clock owner or epoch.
