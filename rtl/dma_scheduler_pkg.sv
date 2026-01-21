//-----------------------------------------------------------------------------
// Module: dma_scheduler_pkg
// Description: Package containing types, enumerations, and utility functions
//              for the DMA scheduler module hierarchy.
//-----------------------------------------------------------------------------

package dma_scheduler_pkg;

    //-------------------------------------------------------------------------
    // Arbitration Policy Enumeration
    //-------------------------------------------------------------------------
    typedef enum logic [1:0] {
        ARB_ROUND_ROBIN     = 2'b00,  // Fair round-robin arbitration
        ARB_FIXED_PRIORITY  = 2'b01,  // Static priority (queue 0 highest)
        ARB_WEIGHTED_RR     = 2'b10,  // Credit-based weighted round-robin
        ARB_RESERVED        = 2'b11   // Reserved for future use
    } arb_policy_e;

    //-------------------------------------------------------------------------
    // Utility Functions
    //-------------------------------------------------------------------------

    // Find first set bit (priority encode) - returns index of lowest set bit
    // Returns 0 if no bits are set (caller should check for valid input)
    function automatic int unsigned find_first_set #(
        parameter int unsigned WIDTH = 32
    )(
        input logic [WIDTH-1:0] vec
    );
        for (int i = 0; i < WIDTH; i++) begin
            if (vec[i]) return i;
        end
        return 0;
    endfunction

    // Count leading zeros - returns number of zeros before first set bit
    function automatic int unsigned count_leading_zeros #(
        parameter int unsigned WIDTH = 32
    )(
        input logic [WIDTH-1:0] vec
    );
        for (int i = WIDTH-1; i >= 0; i--) begin
            if (vec[i]) return WIDTH - 1 - i;
        end
        return WIDTH;
    endfunction

    // One-hot to binary conversion
    function automatic logic [$clog2(32)-1:0] onehot_to_binary #(
        parameter int unsigned WIDTH = 32
    )(
        input logic [WIDTH-1:0] onehot
    );
        logic [$clog2(WIDTH)-1:0] result;
        result = '0;
        for (int i = 0; i < WIDTH; i++) begin
            if (onehot[i]) result = i[$clog2(WIDTH)-1:0];
        end
        return result;
    endfunction

    // Binary to one-hot conversion
    function automatic logic [31:0] binary_to_onehot #(
        parameter int unsigned WIDTH = 32
    )(
        input logic [$clog2(WIDTH)-1:0] binary
    );
        logic [WIDTH-1:0] result;
        result = '0;
        result[binary] = 1'b1;
        return result[31:0];
    endfunction

endpackage : dma_scheduler_pkg
