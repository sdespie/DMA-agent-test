//-----------------------------------------------------------------------------
// Module: arbiter_fixed_priority
// Description: Static priority arbiter where queue 0 has highest priority
//              and queue N-1 has lowest priority. Purely combinational
//              (no state needed).
//
// Algorithm:
//   Find the lowest-indexed queue with an active request and grant to it.
//-----------------------------------------------------------------------------

module arbiter_fixed_priority #(
    parameter int unsigned N = 4  // Number of requesters (2 to 32)
) (
    input  logic                    clk,        // Unused, for interface consistency
    input  logic                    rst,        // Unused, for interface consistency

    // Arbitration interface
    input  logic [N-1:0]            req,        // Request vector (one bit per requester)
    input  logic                    grant_ack,  // Unused, for interface consistency

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
    // Combinational Priority Encoder
    //-------------------------------------------------------------------------

    // Check if any requests are active
    assign grant_valid = |req;

    // Priority encode: find lowest-indexed active request
    always_comb begin
        grant     = '0;
        grant_idx = '0;

        for (int i = 0; i < N; i++) begin
            if (req[i]) begin
                grant[i]  = 1'b1;
                grant_idx = i[IDX_W-1:0];
                break;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Assertions (for simulation/verification)
    //-------------------------------------------------------------------------
    // synthesis translate_off

    // Grant must be one-hot when valid
    always_comb begin
        if (grant_valid) begin
            assert ($onehot(grant)) else
                $error("arbiter_fixed_priority: grant is not one-hot");
        end
    end

    // Grant index must match one-hot grant
    always_comb begin
        if (grant_valid) begin
            assert (grant[grant_idx]) else
                $error("arbiter_fixed_priority: grant_idx does not match grant vector");
        end
    end

    // synthesis translate_on

endmodule : arbiter_fixed_priority
