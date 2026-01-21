//-----------------------------------------------------------------------------
// Module: arbiter_round_robin
// Description: Fair round-robin arbiter with rotating priority.
//              Implements classic round-robin where the last granted requester
//              has lowest priority in the next arbitration cycle.
//
// Algorithm:
//   1. Rotate request vector so (last_grant + 1) is at position 0
//   2. Find first set bit in rotated vector (priority encode)
//   3. Rotate result back to get actual grant index
//   4. Update last_grant only on successful grant acknowledgment
//-----------------------------------------------------------------------------

module arbiter_round_robin #(
    parameter int unsigned N = 4  // Number of requesters (2 to 32)
) (
    input  logic                    clk,
    input  logic                    rst,

    // Arbitration interface
    input  logic [N-1:0]            req,        // Request vector (one bit per requester)
    input  logic                    grant_ack,  // Grant was accepted by downstream

    // Grant outputs
    output logic [N-1:0]            grant,      // One-hot grant vector
    output logic [$clog2(N)-1:0]    grant_idx,  // Binary index of granted requester
    output logic                    grant_valid // At least one request was granted
);

    //-------------------------------------------------------------------------
    // Local Parameters
    //-------------------------------------------------------------------------
    localparam int unsigned IDX_W = $clog2(N);

    //-------------------------------------------------------------------------
    // Internal Signals
    //-------------------------------------------------------------------------
    logic [IDX_W-1:0]   last_grant_q;       // Index of last granted requester
    logic [N-1:0]       rotated_req;        // Request vector rotated by last_grant+1
    logic [N-1:0]       rotated_grant;      // One-hot grant in rotated space
    logic [IDX_W-1:0]   rotated_idx;        // Index of grant in rotated space
    logic [IDX_W-1:0]   actual_idx;         // Index of grant in original space
    logic               any_request;        // At least one active request

    //-------------------------------------------------------------------------
    // Combinational Logic
    //-------------------------------------------------------------------------

    // Check if any requests are active
    assign any_request = |req;

    // Rotate requests so position (last_grant + 1) becomes position 0
    // This gives lowest priority to the last granted requester
    always_comb begin
        for (int i = 0; i < N; i++) begin
            automatic int unsigned src_idx;
            src_idx = (i + last_grant_q + 1) % N;
            rotated_req[i] = req[src_idx];
        end
    end

    // Priority encode: find first set bit in rotated request vector
    always_comb begin
        rotated_grant = '0;
        rotated_idx = '0;
        for (int i = 0; i < N; i++) begin
            if (rotated_req[i]) begin
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
        if (any_request) begin
            grant[actual_idx] = 1'b1;
        end
    end

    // Output assignments
    assign grant_idx   = actual_idx;
    assign grant_valid = any_request;

    //-------------------------------------------------------------------------
    // Sequential Logic - Last Grant Tracking
    //-------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            last_grant_q <= '0;
        end else if (grant_valid && grant_ack) begin
            // Update last grant only when grant is acknowledged
            last_grant_q <= actual_idx;
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
                $error("arbiter_round_robin: grant is not one-hot");
        end
    end

    // Grant index must match one-hot grant
    always_ff @(posedge clk) begin
        if (!rst && grant_valid) begin
            assert (grant[grant_idx]) else
                $error("arbiter_round_robin: grant_idx does not match grant vector");
        end
    end

    // Granted requester must have an active request
    always_ff @(posedge clk) begin
        if (!rst && grant_valid) begin
            assert (req[grant_idx]) else
                $error("arbiter_round_robin: granted a requester without active request");
        end
    end

    // synthesis translate_on

endmodule : arbiter_round_robin
