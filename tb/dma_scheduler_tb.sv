//-----------------------------------------------------------------------------
// Module: dma_scheduler_tb
// Description: Self-checking testbench for the DMA scheduler.
//              Simplified for Icarus Verilog compatibility.
//-----------------------------------------------------------------------------

module dma_scheduler_tb;

    import dma_scheduler_pkg::*;

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    parameter int unsigned N       = 4;
    parameter int unsigned ADDR_W  = 32;
    parameter int unsigned LEN_W   = 16;
    parameter int unsigned ID_W    = 8;
    parameter int unsigned WEIGHT_W = 4;
    parameter arb_policy_e ARB_POLICY = ARB_ROUND_ROBIN;

    localparam int unsigned IDX_W = $clog2(N);

    //-------------------------------------------------------------------------
    // Clock and Reset
    //-------------------------------------------------------------------------
    reg clk;
    reg rst;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;  // 100MHz clock
    end

    //-------------------------------------------------------------------------
    // DUT Signals
    //-------------------------------------------------------------------------
    reg [N-1:0]                 req_valid;
    wire [N-1:0]                req_ready;
    reg [N-1:0][ADDR_W-1:0]     req_addr;
    reg [N-1:0][LEN_W-1:0]      req_len;
    reg [N-1:0][ID_W-1:0]       req_id;
    reg [N-1:0][WEIGHT_W-1:0]   req_weight;

    wire                        out_valid;
    reg                         out_ready;
    wire [ADDR_W-1:0]           out_addr;
    wire [LEN_W-1:0]            out_len;
    wire [ID_W-1:0]             out_id;
    wire [IDX_W-1:0]            out_src;

    //-------------------------------------------------------------------------
    // DUT Instance
    //-------------------------------------------------------------------------
    dma_scheduler #(
        .N          (N),
        .ADDR_W     (ADDR_W),
        .LEN_W      (LEN_W),
        .ID_W       (ID_W),
        .WEIGHT_W   (WEIGHT_W),
        .ARB_POLICY (ARB_POLICY)
    ) dut (
        .clk        (clk),
        .rst        (rst),
        .req_valid  (req_valid),
        .req_ready  (req_ready),
        .req_addr   (req_addr),
        .req_len    (req_len),
        .req_id     (req_id),
        .req_weight (req_weight),
        .out_valid  (out_valid),
        .out_ready  (out_ready),
        .out_addr   (out_addr),
        .out_len    (out_len),
        .out_id     (out_id),
        .out_src    (out_src)
    );

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    integer total_received;
    integer error_count;

    //-------------------------------------------------------------------------
    // Main Test Sequence
    //-------------------------------------------------------------------------
    initial begin
        integer i;

        $display("\n========================================");
        $display("DMA Scheduler Testbench");
        $display("N=%0d, ADDR_W=%0d, LEN_W=%0d, ID_W=%0d", N, ADDR_W, LEN_W, ID_W);
        $display("========================================\n");

        // Initialize
        rst = 1'b1;
        req_valid = '0;
        req_addr = '0;
        req_len = '0;
        req_id = '0;
        out_ready = 1'b0;
        total_received = 0;
        error_count = 0;

        // Set weights
        for (i = 0; i < N; i = i + 1) begin
            req_weight[i] = 4'd1 + i[WEIGHT_W-1:0];
        end

        // Release reset
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        // ==========================================
        // Test 1: Single Queue Basic
        // ==========================================
        $display("=== Test 1: Single Queue Basic ===");
        out_ready = 1'b1;
        total_received = 0;

        // Send 5 requests from queue 0
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk);
            req_valid[0] = 1'b1;
            req_addr[0] = 32'h1000 + i*4;
            req_len[0] = 16'd64;
            req_id[0] = i[ID_W-1:0];

            // Wait for handshake
            @(posedge clk);
            while (!req_ready[0]) @(posedge clk);

            // Count when handshake completes
            if (out_valid && out_ready) begin
                total_received = total_received + 1;
                $display("  Received request %0d: addr=0x%h, id=%0d, src=%0d",
                         total_received, out_addr, out_id, out_src);
            end

            req_valid[0] = 1'b0;
            @(posedge clk);
        end

        // Drain any remaining
        repeat (10) @(posedge clk);

        $display("  Total received: %0d", total_received);
        if (total_received == 5) begin
            $display("PASS: Test 1");
        end else begin
            $display("FAIL: Test 1 - expected 5, got %0d", total_received);
            error_count = error_count + 1;
        end

        // ==========================================
        // Test 2: Multiple Queues
        // ==========================================
        $display("\n=== Test 2: Multiple Queues ===");
        total_received = 0;
        req_valid = '0;

        // Send 1 request from each queue (set all at once)
        @(posedge clk);
        for (i = 0; i < N; i = i + 1) begin
            req_valid[i] = 1'b1;
            req_addr[i] = (32'h1000 * (i+1));
            req_len[i] = 16'd32;
            req_id[i] = i[ID_W-1:0];
        end

        // Wait for all to complete (N requests)
        while (total_received < N) begin
            @(posedge clk);
            if (out_valid && out_ready) begin
                total_received = total_received + 1;
                $display("  Received: addr=0x%h, src=%0d", out_addr, out_src);
                req_valid[out_src] = 1'b0;  // Clear the one that was accepted
            end
        end

        // Clear any remaining
        req_valid = '0;
        repeat (5) @(posedge clk);

        $display("  Total received: %0d", total_received);
        if (total_received == N) begin
            $display("PASS: Test 2");
        end else begin
            $display("FAIL: Test 2 - expected %0d, got %0d", N, total_received);
            error_count = error_count + 1;
        end

        // ==========================================
        // Test 3: Backpressure
        // ==========================================
        $display("\n=== Test 3: Backpressure ===");
        total_received = 0;
        req_valid = '0;

        @(posedge clk);
        // Set up a request
        req_valid[0] = 1'b1;
        req_addr[0] = 32'hDEAD;
        req_id[0] = 8'hBE;

        // Wait for out_valid without ready
        out_ready = 1'b0;
        repeat (5) @(posedge clk);

        if (out_valid) begin
            $display("  out_valid asserted (good)");
            // Check data is stable
            repeat (3) @(posedge clk);
            if (out_addr == 32'hDEAD && out_id == 8'hBE) begin
                $display("  Data stable during backpressure (good)");
            end else begin
                $display("  FAIL: Data changed during backpressure");
                error_count = error_count + 1;
            end
        end else begin
            $display("  FAIL: out_valid not asserted");
            error_count = error_count + 1;
        end

        // Now accept
        out_ready = 1'b1;
        @(posedge clk);
        if (req_ready[0]) begin
            total_received = 1;
            $display("  Request accepted after ready (good)");
        end
        req_valid[0] = 1'b0;

        repeat (5) @(posedge clk);

        if (total_received == 1) begin
            $display("PASS: Test 3");
        end else begin
            $display("FAIL: Test 3");
            error_count = error_count + 1;
        end

        // ==========================================
        // Test 4: Reset Behavior
        // ==========================================
        $display("\n=== Test 4: Reset Behavior ===");

        // Set up a request
        req_valid[1] = 1'b1;
        req_addr[1] = 32'hCAFE;
        out_ready = 1'b1;

        repeat (2) @(posedge clk);

        // Assert reset
        rst = 1'b1;
        repeat (2) @(posedge clk);
        rst = 1'b0;
        req_valid = '0;

        repeat (3) @(posedge clk);

        if (!out_valid) begin
            $display("PASS: Test 4 - Reset clears state");
        end else begin
            $display("FAIL: Test 4 - out_valid still asserted after reset");
            error_count = error_count + 1;
        end

        // ==========================================
        // Summary
        // ==========================================
        repeat (10) @(posedge clk);
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        if (error_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d errors", error_count);
        $display("========================================\n");

        $finish;
    end

    // Timeout watchdog
    initial begin
        #50000;
        $display("ERROR: Testbench timeout");
        $finish;
    end

endmodule : dma_scheduler_tb
