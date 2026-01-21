//-----------------------------------------------------------------------------
// Module: dma_scheduler
// Description: Top-level parameterizable multi-queue DMA scheduler.
//              Arbitrates requests from N independent input queues and
//              issues them onto a single downstream interface.
//
// Features:
//   - Configurable number of input queues (N = 2 to 32)
//   - Configurable arbitration policy (round-robin, fixed-priority, weighted RR)
//   - Fully backpressure-aware with atomic handshaking
//   - Synthesizable pure RTL
//
// Architecture:
//   - dma_arbiter: Selects among active requesters based on policy
//   - dma_request_mux: N:1 mux for request data fields
//   - dma_handshake_ctrl: Manages output handshake and backpressure
//-----------------------------------------------------------------------------

module dma_scheduler
    import dma_scheduler_pkg::*;
#(
    parameter int unsigned N         = 4,                    // Number of input queues (2-32)
    parameter int unsigned ADDR_W    = 32,                   // Address width
    parameter int unsigned LEN_W     = 16,                   // Transfer length width
    parameter int unsigned ID_W      = 8,                    // Request ID width
    parameter arb_policy_e ARB_POLICY = ARB_ROUND_ROBIN,     // Arbitration policy
    parameter int unsigned WEIGHT_W  = 4                     // Weight width for weighted RR
) (
    input  logic                        clk,
    input  logic                        rst,        // Synchronous, active-high

    // Input request interfaces (N queues)
    input  logic [N-1:0]                req_valid,
    output logic [N-1:0]                req_ready,
    input  logic [N-1:0][ADDR_W-1:0]    req_addr,
    input  logic [N-1:0][LEN_W-1:0]     req_len,
    input  logic [N-1:0][ID_W-1:0]      req_id,

    // Optional: per-queue weights for weighted RR (active when ARB_POLICY == ARB_WEIGHTED_RR)
    input  logic [N-1:0][WEIGHT_W-1:0]  req_weight,

    // Output interface (single selected request)
    output logic                        out_valid,
    input  logic                        out_ready,
    output logic [ADDR_W-1:0]           out_addr,
    output logic [LEN_W-1:0]            out_len,
    output logic [ID_W-1:0]             out_id,
    output logic [$clog2(N)-1:0]        out_src     // Source queue index
);

    //-------------------------------------------------------------------------
    // Local Parameters
    //-------------------------------------------------------------------------
    localparam int unsigned IDX_W = $clog2(N);

    //-------------------------------------------------------------------------
    // Internal Signals
    //-------------------------------------------------------------------------

    // Arbiter signals
    logic [N-1:0]       arb_grant;
    logic [IDX_W-1:0]   arb_grant_idx;
    logic               arb_grant_valid;
    logic               arb_ack;

    // Muxed request data
    logic [ADDR_W-1:0]  mux_addr;
    logic [LEN_W-1:0]   mux_len;
    logic [ID_W-1:0]    mux_id;

    //-------------------------------------------------------------------------
    // Arbiter Instance
    //-------------------------------------------------------------------------
    dma_arbiter #(
        .N          (N),
        .WEIGHT_W   (WEIGHT_W),
        .ARB_POLICY (ARB_POLICY)
    ) u_arbiter (
        .clk        (clk),
        .rst        (rst),
        .req        (req_valid),
        .weight     (req_weight),
        .grant_ack  (arb_ack),
        .grant      (arb_grant),
        .grant_idx  (arb_grant_idx),
        .grant_valid(arb_grant_valid)
    );

    //-------------------------------------------------------------------------
    // Request Multiplexer Instance
    //-------------------------------------------------------------------------
    dma_request_mux #(
        .N      (N),
        .ADDR_W (ADDR_W),
        .LEN_W  (LEN_W),
        .ID_W   (ID_W)
    ) u_mux (
        .sel      (arb_grant_idx),
        .req_addr (req_addr),
        .req_len  (req_len),
        .req_id   (req_id),
        .out_addr (mux_addr),
        .out_len  (mux_len),
        .out_id   (mux_id)
    );

    //-------------------------------------------------------------------------
    // Handshake Controller Instance
    //-------------------------------------------------------------------------
    dma_handshake_ctrl #(
        .N      (N),
        .ADDR_W (ADDR_W),
        .LEN_W  (LEN_W),
        .ID_W   (ID_W)
    ) u_handshake (
        .clk            (clk),
        .rst            (rst),
        .arb_valid      (arb_grant_valid),
        .arb_grant_idx  (arb_grant_idx),
        .arb_ack        (arb_ack),
        .mux_addr       (mux_addr),
        .mux_len        (mux_len),
        .mux_id         (mux_id),
        .out_valid      (out_valid),
        .out_ready      (out_ready),
        .out_addr       (out_addr),
        .out_len        (out_len),
        .out_id         (out_id),
        .out_src        (out_src),
        .req_ready      (req_ready)
    );

    //-------------------------------------------------------------------------
    // Parameter Validation
    //-------------------------------------------------------------------------
    // synthesis translate_off
    initial begin
        assert (N >= 2 && N <= 32) else
            $fatal(1, "dma_scheduler: N must be between 2 and 32, got %0d", N);
        assert (ADDR_W > 0) else
            $fatal(1, "dma_scheduler: ADDR_W must be positive");
        assert (LEN_W > 0) else
            $fatal(1, "dma_scheduler: LEN_W must be positive");
        assert (ID_W > 0) else
            $fatal(1, "dma_scheduler: ID_W must be positive");
    end
    // synthesis translate_on

endmodule : dma_scheduler
