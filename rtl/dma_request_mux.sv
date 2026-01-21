//-----------------------------------------------------------------------------
// Module: dma_request_mux
// Description: Parameterized N:1 multiplexer for DMA request fields.
//              Selects one of N input request data bundles based on a
//              binary select index.
//-----------------------------------------------------------------------------

module dma_request_mux #(
    parameter int unsigned N      = 4,    // Number of input channels
    parameter int unsigned ADDR_W = 32,   // Address width
    parameter int unsigned LEN_W  = 16,   // Transfer length width
    parameter int unsigned ID_W   = 8     // Request ID width
) (
    // Selection input
    input  logic [$clog2(N)-1:0]        sel,        // Binary select index

    // Input request data (N channels)
    input  logic [N-1:0][ADDR_W-1:0]    req_addr,   // Request addresses
    input  logic [N-1:0][LEN_W-1:0]     req_len,    // Request lengths
    input  logic [N-1:0][ID_W-1:0]      req_id,     // Request IDs

    // Output (selected request)
    output logic [ADDR_W-1:0]           out_addr,   // Selected address
    output logic [LEN_W-1:0]            out_len,    // Selected length
    output logic [ID_W-1:0]             out_id      // Selected ID
);

    //-------------------------------------------------------------------------
    // Multiplexer Logic
    //-------------------------------------------------------------------------

    // Direct indexing for clean synthesis
    assign out_addr = req_addr[sel];
    assign out_len  = req_len[sel];
    assign out_id   = req_id[sel];

endmodule : dma_request_mux
