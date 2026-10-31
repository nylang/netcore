// Copyright (c) 2026 tangxiangjiang
// SPDX-License-Identifier: MIT

/** @brief Snapshot of an external producer's readiness and control budget. */
import "interface/foundation.ni";

/** @brief Immutable producer readiness, closure state and next absolute control deadline. */
pub struct NetReadinessState {
  ready: bool;
  closed: bool;
  deadline: NetDeadline;
  poll_controls: bool;
}
