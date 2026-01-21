// RTL file list for DMA Scheduler
// Compilation order matters - package first, then modules in dependency order

// Package (must be first)
../rtl/dma_scheduler_pkg.sv

// Leaf arbiters (no dependencies except package)
../rtl/arbiter_round_robin.sv
../rtl/arbiter_fixed_priority.sv
../rtl/arbiter_weighted_rr.sv

// Arbiter wrapper (depends on leaf arbiters)
../rtl/dma_arbiter.sv

// Other components
../rtl/dma_request_mux.sv
../rtl/dma_handshake_ctrl.sv

// Top-level (depends on all above)
../rtl/dma_scheduler.sv
