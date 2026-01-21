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

endpackage : dma_scheduler_pkg
