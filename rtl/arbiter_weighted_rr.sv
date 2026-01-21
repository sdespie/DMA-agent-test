//-----------------------------------------------------------------------------
// Module: arbiter_weighted_rr
// Description: Weighted round-robin arbiter using a credit-based (deficit)
//              counter approach. Each queue has a configurable weight that
//              determines its share of the bandwidth.
//
// Algorithm:
//   - Each queue maintains a credit counter initialized to its weight
//   - A queue can be granted if it has active request AND credit > 0
//   - When granted, credit is decremented
//   - When all queues have exhausted credits, all credits are reloaded
//   - Among eligible queues (credit > 0, req active), use round-robin
//-----------------------------------------------------------------------------

module arbiter_weighted_rr #(
    parameter int unsigned N        = 4,  // Number of requesters (2 to 32)
    parameter int unsigned WEIGHT_W = 4   // Width of weight/credit counters
) (
    input  logic                            clk,
    input  logic                            rst,

    // Arbitration interface
    input  logic [N-1:0]                    req,        // Request vector
    input  logic [N-1:0][WEIGHT_W-1:0]      weight,     // Per-queue weights
    input  logic                            grant_ack,  // Grant was accepted

    // Grant outputs
    output logic [N-1:0]                    grant,      // One-hot grant vector
    output logic [$clog2(N)-1:0]            grant_idx,  // Binary index of granted
    output logic                            grant_valid // At least one request granted
);

    //-------------------------------------------------------------------------
    // Local Parameters
    //-------------------------------------------------------------------------
    localparam int unsigned IDX_W = $clog2(N);

    //-------------------------------------------------------------------------
    // Internal Signals
    //-------------------------------------------------------------------------

    // Credit counters
    logic [N-1:0][WEIGHT_W-1:0] credit_q;       // Current credit per queue
    logic [N-1:0][WEIGHT_W-1:0] credit_d;       // Next credit values

    // Round-robin state for tie-breaking among eligible queues
    logic [IDX_W-1:0] last_grant_q;

    // Eligible mask: queues with active request AND remaining credit
    logic [N-1:0] eligible;

    // Check if credits need reload
    logic credits_exhausted;

    // Round-robin selection among eligible
    logic [N-1:0] rotated_eligible;
    logic [N-1:0] rotated_grant;
    logic [IDX_W-1:0] rotated_idx;
    logic [IDX_W-1:0] actual_idx;

    //-------------------------------------------------------------------------
    // Combinational Logic
    //-------------------------------------------------------------------------

    // Determine which queues are eligible (have request and credit)
    always_comb begin
        for (int i = 0; i < N; i++) begin
            eligible[i] = req[i] && (credit_q[i] > 0);
        end
    end

    // Check if any eligible queue exists
    assign grant_valid = |eligible;

    // Check if all credits are exhausted (need reload)
    // This happens when no queue has remaining credit
    always_comb begin
        credits_exhausted = 1'b1;
        for (int i = 0; i < N; i++) begin
            if (credit_q[i] > 0) credits_exhausted = 1'b0;
        end
    end

    // Rotate eligible mask for round-robin among eligible queues
    always_comb begin
        for (int i = 0; i < N; i++) begin
            automatic int unsigned src_idx;
            src_idx = (i + last_grant_q + 1) % N;
            rotated_eligible[i] = eligible[src_idx];
        end
    end

    // Priority encode rotated eligible mask
    always_comb begin
        rotated_grant = '0;
        rotated_idx = '0;
        for (int i = 0; i < N; i++) begin
            if (rotated_eligible[i]) begin
                rotated_grant[i] = 1'b1;
                rotated_idx = i[IDX_W-1:0];
                break;
            end
        end
    end

    // Rotate grant back to original space
    always_comb begin
        actual_idx = (rotated_idx + last_grant_q + 1) % N;
        grant = '0;
        if (grant_valid) begin
            grant[actual_idx] = 1'b1;
        end
    end

    assign grant_idx = actual_idx;

    // Compute next credit values
    always_comb begin
        credit_d = credit_q;

        if (credits_exhausted || (!grant_valid && |req)) begin
            // Reload all credits from weights
            // This also handles the case where requests exist but none are eligible
            for (int i = 0; i < N; i++) begin
                credit_d[i] = weight[i];
            end
        end else if (grant_valid && grant_ack) begin
            // Decrement credit for granted queue
            credit_d[actual_idx] = credit_q[actual_idx] - 1'b1;
        end
    end

    //-------------------------------------------------------------------------
    // Sequential Logic
    //-------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            credit_q <= '0;
            last_grant_q <= '0;
            // Load initial credits from weights on first cycle after reset
            for (int i = 0; i < N; i++) begin
                credit_q[i] <= weight[i];
            end
        end else begin
            credit_q <= credit_d;
            if (grant_valid && grant_ack) begin
                last_grant_q <= actual_idx;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Assertions (for simulation/verification)
    //-------------------------------------------------------------------------
    // synthesis translate_off

    // Grant must be one-hot when valid
    always_ff @(posedge clk) begin
        if (!rst && grant_valid) begin
            assert ($onehot(grant)) else
                $error("arbiter_weighted_rr: grant is not one-hot");
        end
    end

    // Granted queue must be eligible
    always_ff @(posedge clk) begin
        if (!rst && grant_valid) begin
            assert (eligible[grant_idx]) else
                $error("arbiter_weighted_rr: granted an ineligible queue");
        end
    end

    // synthesis translate_on

endmodule : arbiter_weighted_rr
