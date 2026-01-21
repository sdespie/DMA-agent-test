# Multi-Queue DMA Scheduler

A synthesizable SystemVerilog RTL module that schedules and arbitrates DMA requests from multiple independent producer queues onto a single downstream interface.

## Architecture Overview

The scheduler is organized as a modular hierarchy:

```
dma_scheduler (top-level)
├── dma_arbiter (arbitration policy wrapper)
│   ├── arbiter_round_robin
│   ├── arbiter_fixed_priority
│   └── arbiter_weighted_rr
├── dma_request_mux (N:1 request multiplexer)
└── dma_handshake_ctrl (output handshake state machine)
```

### Module Responsibilities

| Module | Description |
|--------|-------------|
| `dma_scheduler` | Top-level integration, parameter propagation |
| `dma_arbiter` | Policy selection wrapper using generate |
| `arbiter_round_robin` | Fair round-robin with rotating priority |
| `arbiter_fixed_priority` | Static priority (queue 0 highest) |
| `arbiter_weighted_rr` | Credit-based weighted round-robin |
| `dma_request_mux` | Parameterized N:1 multiplexer |
| `dma_handshake_ctrl` | Handshake FSM ensuring atomicity |

## Arbitration Policies

### Round-Robin (Default)
- **Algorithm**: Rotating priority based on last-served tracking
- **Fairness**: Each queue receives equal bandwidth when all are active
- **State**: Maintains `last_grant` register, updated only on completed handshakes
- **Implementation**: Barrel rotation + priority encoder

### Fixed-Priority
- **Algorithm**: Static priority with queue 0 highest, queue N-1 lowest
- **Use Case**: When certain queues have strict latency requirements
- **State**: Stateless (purely combinational)
- **Implementation**: Simple priority encoder

### Weighted Round-Robin
- **Algorithm**: Credit-based deficit counter
- **Fairness**: Bandwidth proportional to configured weights
- **State**: Per-queue credit counters, reloaded when exhausted
- **Configuration**: Runtime-configurable weights via `req_weight` port

## Key Design Decisions

### 1. Registered Output Stage

**Choice**: All output data is registered (1-cycle latency).

**Trade-offs**:
- (+) Better timing closure, especially for large N
- (+) Clean handshake semantics
- (-) 1-cycle latency from grant to output valid

**Alternative**: Combinational output would achieve 0-cycle latency but complicate timing closure at higher clock frequencies.

### 2. Per-Request Arbitration

**Choice**: Re-arbitrate after every completed handshake.

**Trade-offs**:
- (+) Maximum fairness across all queues
- (+) Simpler state machine
- (-) No burst optimization

**Alternative**: Burst-aware arbitration could grant entire bursts to one queue, improving efficiency at the cost of fairness.

### 3. Backpressure Handling

**Choice**: Selection held stable during backpressure.

**Behavior**: When `out_valid` is asserted and `out_ready` is low:
- Output data remains stable
- No re-arbitration occurs
- `req_ready` remains deasserted
- Request is considered "in-flight" until accepted

### 4. Packed Array Interfaces

**Choice**: Use packed arrays `[N-1:0][WIDTH-1:0]` for multi-dimensional signals.

**Rationale**:
- Better synthesis tool compatibility
- Cleaner indexing in generate loops
- Contiguous bit representation

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N` | 4 | Number of input queues (2-32) |
| `ADDR_W` | 32 | Address width in bits |
| `LEN_W` | 16 | Transfer length width in bits |
| `ID_W` | 8 | Request ID width in bits |
| `ARB_POLICY` | `ARB_ROUND_ROBIN` | Arbitration policy selection |
| `WEIGHT_W` | 4 | Weight counter width (for weighted RR) |

## Interface Signals

### Input Request Interface (per queue)
```systemverilog
input  logic [N-1:0]              req_valid   // Request valid
output logic [N-1:0]              req_ready   // Request accepted
input  logic [N-1:0][ADDR_W-1:0]  req_addr    // Request address
input  logic [N-1:0][LEN_W-1:0]   req_len     // Transfer length
input  logic [N-1:0][ID_W-1:0]    req_id      // Request ID
input  logic [N-1:0][WEIGHT_W-1:0] req_weight // Weights (for weighted RR)
```

### Output Interface
```systemverilog
output logic                      out_valid   // Output valid
input  logic                      out_ready   // Downstream ready
output logic [ADDR_W-1:0]         out_addr    // Selected address
output logic [LEN_W-1:0]          out_len     // Selected length
output logic [ID_W-1:0]           out_id      // Selected ID
output logic [$clog2(N)-1:0]      out_src     // Source queue index
```

## Timing Characteristics

- **Latency**: 1 clock cycle from `req_valid` assertion to `out_valid`
- **Throughput**: 1 request per clock when downstream is ready
- **Backpressure**: Immediate propagation via `req_ready` gating

## Reset Behavior

- Synchronous, active-high reset (`rst`)
- All outputs deasserted on reset
- Arbiter state cleared (round-robin starts from queue 0)
- Credit counters initialized from weights (weighted RR)

## Known Limitations

1. **No Request Reordering**: Requests within a queue must complete in order. This is by design per the specification.

2. **No Request Coalescing**: Adjacent requests are not merged. Each request consumes one handshake cycle.

3. **Combinational Arbitration Path**: For very large N (>16), the priority encoder may become timing-critical.

4. **Weighted RR Credit Width**: The `WEIGHT_W` parameter limits maximum weight values. With default 4-bit width, weights are limited to 0-15.

## Future Extensions

1. **Pipelined Arbiter**: For N>16, implement tree-based arbitration with pipeline stages.

2. **Quality of Service**: Add priority levels orthogonal to arbitration policy.

3. **Request Timeouts**: Add watchdog timers per queue to prevent starvation under pathological conditions.

4. **Performance Counters**: Add optional instrumentation for bandwidth and latency monitoring.

## File Organization

```
rtl/
├── dma_scheduler_pkg.sv      # Package with types and enums
├── dma_scheduler.sv          # Top-level module
├── dma_arbiter.sv            # Arbiter wrapper
├── arbiter_round_robin.sv    # Round-robin implementation
├── arbiter_fixed_priority.sv # Fixed-priority implementation
├── arbiter_weighted_rr.sv    # Weighted RR implementation
├── dma_request_mux.sv        # N:1 multiplexer
└── dma_handshake_ctrl.sv     # Handshake controller

tb/
└── dma_scheduler_tb.sv       # Self-checking testbench

doc/
└── README.md                 # This file
```

## Simulation

The testbench (`tb/dma_scheduler_tb.sv`) includes:
- Single-queue basic operation
- Concurrent multi-queue traffic
- Random backpressure testing
- Round-robin fairness verification
- Reset behavior verification

To run with a SystemVerilog simulator:
```bash
# Example with VCS
vcs -sverilog -f filelist.f tb/dma_scheduler_tb.sv && ./simv

# Example with Verilator
verilator --binary -Wall --timing rtl/*.sv tb/dma_scheduler_tb.sv && ./obj_dir/Vdma_scheduler_tb
```

## Synthesis Notes

- All RTL is synthesizable (no testbench constructs in RTL)
- Assertions are wrapped in `synthesis translate_off` pragmas
- No latches inferred (all sequential logic uses `always_ff`)
- Clock domain: Single clock, synchronous design
