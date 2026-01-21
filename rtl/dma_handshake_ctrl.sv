//-----------------------------------------------------------------------------
// Module: dma_handshake_ctrl
// Description: Handshake controller that ensures atomic request transfer
//              with full backpressure support. Once a request is selected
//              and out_valid asserted, the selection remains stable until
//              the downstream accepts with out_ready.
//
// Key Behaviors:
//   - Registered output stage for timing closure
//   - Selection held stable during backpressure
//   - req_ready only pulses when handshake completes
//   - Deterministic reset to idle state
//-----------------------------------------------------------------------------

module dma_handshake_ctrl #(
    parameter int unsigned N      = 4,    // Number of input channels
    parameter int unsigned ADDR_W = 32,   // Address width
    parameter int unsigned LEN_W  = 16,   // Transfer length width
    parameter int unsigned ID_W   = 8     // Request ID width
) (
    input  logic                        clk,
    input  logic                        rst,

    // Arbiter interface
    input  logic                        arb_valid,      // Arbiter has a valid grant
    input  logic [$clog2(N)-1:0]        arb_grant_idx,  // Granted queue index
    output logic                        arb_ack,        // Acknowledge grant (advance arbiter)

    // Muxed request data (from dma_request_mux)
    input  logic [ADDR_W-1:0]           mux_addr,       // Selected request address
    input  logic [LEN_W-1:0]            mux_len,        // Selected request length
    input  logic [ID_W-1:0]             mux_id,         // Selected request ID

    // Output interface
    output logic                        out_valid,
    input  logic                        out_ready,
    output logic [ADDR_W-1:0]           out_addr,
    output logic [LEN_W-1:0]            out_len,
    output logic [ID_W-1:0]             out_id,
    output logic [$clog2(N)-1:0]        out_src,

    // Per-queue ready signals
    output logic [N-1:0]                req_ready
);

    //-------------------------------------------------------------------------
    // Local Parameters
    //-------------------------------------------------------------------------
    localparam int unsigned IDX_W = $clog2(N);

    //-------------------------------------------------------------------------
    // State Machine Definition
    //-------------------------------------------------------------------------
    typedef enum logic {
        ST_IDLE,    // No active transaction, ready to accept new grant
        ST_ACTIVE   // Transaction in progress, holding selection
    } state_e;

    //-------------------------------------------------------------------------
    // Internal Signals
    //-------------------------------------------------------------------------
    state_e             state_q, state_d;
    logic [IDX_W-1:0]   grant_idx_q, grant_idx_d;
    logic [ADDR_W-1:0]  addr_q, addr_d;
    logic [LEN_W-1:0]   len_q, len_d;
    logic [ID_W-1:0]    id_q, id_d;

    logic               handshake_complete;
    logic               load_new_request;

    //-------------------------------------------------------------------------
    // Combinational Logic
    //-------------------------------------------------------------------------

    // Handshake completion detection
    assign handshake_complete = out_valid && out_ready;

    // State machine next-state logic
    always_comb begin
        state_d     = state_q;
        grant_idx_d = grant_idx_q;
        addr_d      = addr_q;
        len_d       = len_q;
        id_d        = id_q;
        load_new_request = 1'b0;

        case (state_q)
            ST_IDLE: begin
                if (arb_valid) begin
                    // Load new request and go active
                    state_d     = ST_ACTIVE;
                    grant_idx_d = arb_grant_idx;
                    addr_d      = mux_addr;
                    len_d       = mux_len;
                    id_d        = mux_id;
                    load_new_request = 1'b1;
                end
            end

            ST_ACTIVE: begin
                if (out_ready) begin
                    // Handshake complete
                    if (arb_valid) begin
                        // Back-to-back: immediately load next request
                        grant_idx_d = arb_grant_idx;
                        addr_d      = mux_addr;
                        len_d       = mux_len;
                        id_d        = mux_id;
                        load_new_request = 1'b1;
                        // Stay in ST_ACTIVE
                    end else begin
                        // No pending request, go idle
                        state_d = ST_IDLE;
                    end
                end
                // else: backpressure - hold current selection
            end

            default: begin
                state_d = ST_IDLE;
            end
        endcase
    end

    // Output valid is asserted when we have an active transaction
    assign out_valid = (state_q == ST_ACTIVE);

    // Registered output data
    assign out_addr = addr_q;
    assign out_len  = len_q;
    assign out_id   = id_q;
    assign out_src  = grant_idx_q;

    // Arbiter acknowledgment: signal when we accept a new grant
    assign arb_ack = load_new_request;

    // Per-queue ready: pulse only when handshake completes for that queue
    always_comb begin
        req_ready = '0;
        if (handshake_complete) begin
            req_ready[grant_idx_q] = 1'b1;
        end
    end

    //-------------------------------------------------------------------------
    // Sequential Logic
    //-------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state_q     <= ST_IDLE;
            grant_idx_q <= '0;
            addr_q      <= '0;
            len_q       <= '0;
            id_q        <= '0;
        end else begin
            state_q     <= state_d;
            grant_idx_q <= grant_idx_d;
            addr_q      <= addr_d;
            len_q       <= len_d;
            id_q        <= id_d;
        end
    end

    //-------------------------------------------------------------------------
    // Assertions (for simulation/verification)
    //-------------------------------------------------------------------------
    // synthesis translate_off

    // Output must be stable during backpressure
    property p_stable_during_backpressure;
        @(posedge clk) disable iff (rst)
        (out_valid && !out_ready) |=> (out_valid && $stable(out_addr) &&
                                        $stable(out_len) && $stable(out_id) &&
                                        $stable(out_src));
    endproperty
    assert property (p_stable_during_backpressure) else
        $error("dma_handshake_ctrl: output changed during backpressure");

    // req_ready must be one-hot or zero
    always_ff @(posedge clk) begin
        if (!rst) begin
            assert ($onehot0(req_ready)) else
                $error("dma_handshake_ctrl: req_ready is not one-hot or zero");
        end
    end

    // req_ready only asserts on handshake completion
    always_ff @(posedge clk) begin
        if (!rst && |req_ready) begin
            assert (handshake_complete) else
                $error("dma_handshake_ctrl: req_ready without handshake");
        end
    end

    // synthesis translate_on

endmodule : dma_handshake_ctrl
