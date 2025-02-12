// Copyright Materialize, Inc. and contributors. All rights reserved.
//
// Use of this software is governed by the Business Source License
// included in the LICENSE file.
//
// As of the Change Date specified in that file, in accordance with
// the Business Source License, use of this software will be governed
// by the Apache License, Version 2.0.

#![warn(missing_docs)]

//! Driver for timely/differential dataflow.

pub mod boundary;
#[cfg(feature = "server")]
pub(crate) mod decode;
#[cfg(feature = "server")]
pub(crate) mod render;
#[cfg(feature = "server")]
pub(crate) mod server;
#[cfg(feature = "server")]
pub mod source;
#[cfg(feature = "server")]
pub mod storage_state;

pub use boundary::{tcp_boundary, ComputeReplay, DummyBoundary, StorageCapture};
#[cfg(feature = "server")]
pub use decode::metrics::DecodeMetrics;
#[cfg(feature = "server")]
pub use server::{serve_boundary_requests, Config, Server};
