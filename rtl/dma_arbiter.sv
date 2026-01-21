//-----------------------------------------------------------------------------
// Module: dma_arbiter
// Description: Arbiter wrapper that instantiates the appropriate arbiter
//              based on the configured arbitration policy parameter.
//
// Supported Policies:
//   - ARB_ROUND_ROBIN: Fair round-robin with rotating priority
//   - ARB_FIXED_PRIORITY: Static priority (queue 0 highest)
//   - ARB_WEIGHTED_RR: Credit-based weighted round-robin
//-----------------------------------------------------------------------------

module dma_arbiter
    import dma_scheduler_pkg::*;
#(
    parameter int unsigned N            = 4,                // Number of requesters
    parameter int unsigned WEIGHT_W     = 4,                // Weight width for weighted RR
    parameter arb_policy_e ARB_POLICY   = ARB_ROUND_ROBIN   // Arbitration policy
) (
    input  logic                            clk,
    input  logic                            rst,

    // Request interface
    input  logic [N-1:0]                    req,        // Request vector
    input  logic [N-1:0][WEIGHT_W-1:0]      weight,     // Per-queue weights (for weighted RR)
    input  logic                            grant_ack,  // Grant acknowledgment

    // Grant outputs
    output logic [N-1:0]                    grant,      // One-hot grant vector
    output logic [$clog2(N)-1:0]            grant_idx,  // Binary index of granted
    output logic                            grant_valid // At least one request granted
);

    //-------------------------------------------------------------------------
    // Policy Selection via Generate
    //-------------------------------------------------------------------------

    generate
        case (ARB_POLICY)
            ARB_ROUND_ROBIN: begin : gen_rr
                arbiter_round_robin #(
                    .N(N)
                ) u_arbiter (
                    .clk        (clk),
                    .rst        (rst),
                    .req        (req),
                    .grant_ack  (grant_ack),
                    .grant      (grant),
                    .grant_idx  (grant_idx),
                    .grant_valid(grant_valid)
                );
            end

            ARB_FIXED_PRIORITY: begin : gen_fp
                arbiter_fixed_priority #(
                    .N(N)
                ) u_arbiter (
                    .clk        (clk),
                    .rst        (rst),
                    .req        (req),
                    .grant_ack  (grant_ack),
                    .grant      (grant),
                    .grant_idx  (grant_idx),
                    .grant_valid(grant_valid)
                );
            end

            ARB_WEIGHTED_RR: begin : gen_wrr
                arbiter_weighted_rr #(
                    .N       (N),
                    .WEIGHT_W(WEIGHT_W)
                ) u_arbiter (
                    .clk        (clk),
                    .rst        (rst),
                    .req        (req),
                    .weight     (weight),
                    .grant_ack  (grant_ack),
                    .grant      (grant),
                    .grant_idx  (grant_idx),
                    .grant_valid(grant_valid)
                );
            end

            default: begin : gen_default
                // Default to round-robin for safety
                arbiter_round_robin #(
                    .N(N)
                ) u_arbiter (
                    .clk        (clk),
                    .rst        (rst),
                    .req        (req),
                    .grant_ack  (grant_ack),
                    .grant      (grant),
                    .grant_idx  (grant_idx),
                    .grant_valid(grant_valid)
                );

                // synthesis translate_off
                initial begin
                    $warning("dma_arbiter: Unknown ARB_POLICY, defaulting to round-robin");
                end
                // synthesis translate_on
            end
        endcase
    endgenerate

endmodule : dma_arbiter
