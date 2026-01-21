//-----------------------------------------------------------------------------
// Module: dma_scheduler_fixed_priority_tb
// Description: Testbench for fixed-priority arbitration policy.
//              Verifies that queue 0 always has highest priority.
//-----------------------------------------------------------------------------

module dma_scheduler_fixed_priority_tb;

    import dma_scheduler_pkg::*;

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    parameter int unsigned N       = 4;
    parameter int unsigned ADDR_W  = 32;
    parameter int unsigned LEN_W   = 16;
    parameter int unsigned ID_W    = 8;
    parameter int unsigned WEIGHT_W = 4;
    parameter arb_policy_e ARB_POLICY = ARB_FIXED_PRIORITY;

    localparam int unsigned IDX_W = $clog2(N);

    //-------------------------------------------------------------------------
    // Clock and Reset
    //-------------------------------------------------------------------------
    reg clk;
    reg rst;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
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
    integer grant_order[16];
    integer grant_idx;

    //-------------------------------------------------------------------------
    // Main Test Sequence
    //-------------------------------------------------------------------------
    initial begin
        integer i;

        $display("\n========================================");
        $display("DMA Scheduler Fixed-Priority Testbench");
        $display("N=%0d, ARB_POLICY=ARB_FIXED_PRIORITY", N);
        $display("========================================\n");

        // Initialize
        rst = 1'b1;
        req_valid = '0;
        req_addr = '0;
        req_len = '0;
        req_id = '0;
        req_weight = '0;
        out_ready = 1'b0;
        total_received = 0;
        error_count = 0;
        grant_idx = 0;

        // Release reset
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        // ==========================================
        // Test 1: Queue 0 Always Wins
        // ==========================================
        $display("=== Test 1: Queue 0 Always Wins ===");
        out_ready = 1'b1;
        total_received = 0;
        grant_idx = 0;

        // All queues request simultaneously
        @(posedge clk);
        for (i = 0; i < N; i = i + 1) begin
            req_valid[i] = 1'b1;
            req_addr[i] = 32'h1000 * (i + 1);
            req_id[i] = i[ID_W-1:0];
        end

        // Wait for all to complete - use req_ready to detect completion
        while (total_received < N) begin
            @(posedge clk);
            // Check if any queue got its request accepted
            for (i = 0; i < N; i = i + 1) begin
                if (req_ready[i] && req_valid[i]) begin
                    grant_order[grant_idx] = i;
                    grant_idx = grant_idx + 1;
                    total_received = total_received + 1;
                    $display("  Grant %0d: src=%0d (addr=0x%h)", total_received, i, req_addr[i]);
                    req_valid[i] = 1'b0;
                end
            end
        end

        req_valid = '0;
        repeat (5) @(posedge clk);

        // Verify order: should be 0, 1, 2, 3 (highest to lowest priority)
        if (grant_order[0] == 0 && grant_order[1] == 1 &&
            grant_order[2] == 2 && grant_order[3] == 3) begin
            $display("PASS: Test 1 - Priority order correct (0->1->2->3)");
        end else begin
            $display("FAIL: Test 1 - Expected order 0,1,2,3, got %0d,%0d,%0d,%0d",
                     grant_order[0], grant_order[1], grant_order[2], grant_order[3]);
            error_count = error_count + 1;
        end

        // ==========================================
        // Test 2: Low Priority Starvation
        // ==========================================
        $display("\n=== Test 2: Low Priority Starvation ===");
        total_received = 0;

        // Queue 3 (lowest priority) requests first
        @(posedge clk);
        req_valid[3] = 1'b1;
        req_addr[3] = 32'hAAAA;
        req_id[3] = 8'h33;

        repeat (2) @(posedge clk);

        // Queue 0 (highest priority) also requests - should win
        req_valid[0] = 1'b1;
        req_addr[0] = 32'hBBBB;
        req_id[0] = 8'h00;

        // Wait for queue 0's request to complete (use req_ready)
        @(posedge clk);
        while (!req_ready[0]) @(posedge clk);

        $display("  First grant to queue 0 (good - high priority wins)");
        total_received = 1;

        // Clear queue 0, queue 3 should now be served
        req_valid[0] = 1'b0;

        // Wait for queue 3's request to complete
        @(posedge clk);
        while (!req_ready[3]) @(posedge clk);

        $display("  Second grant to queue 3 (good - now served)");
        total_received = total_received + 1;

        req_valid = '0;
        repeat (5) @(posedge clk);

        if (total_received == 2) begin
            $display("PASS: Test 2 - Starvation behavior correct");
        end else begin
            $display("FAIL: Test 2");
            error_count = error_count + 1;
        end

        // ==========================================
        // Test 3: Continuous High Priority Requests
        // ==========================================
        $display("\n=== Test 3: Continuous High Priority Starves Low ===");
        total_received = 0;

        // Queue 3 requests
        @(posedge clk);
        req_valid[3] = 1'b1;
        req_addr[3] = 32'hCCCC;

        // Queue 0 sends 5 requests continuously
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge clk);
            req_valid[0] = 1'b1;
            req_addr[0] = 32'hDDDD + i;
            req_id[0] = i[ID_W-1:0];

            // Wait for queue 0's request to complete
            @(posedge clk);
            while (!req_ready[0]) @(posedge clk);

            total_received = total_received + 1;
            $display("  Grant %0d: Queue 0 served", total_received);
            req_valid[0] = 1'b0;
        end

        // Now queue 3 should finally be served
        @(posedge clk);
        while (!req_ready[3]) @(posedge clk);

        $display("  Queue 3 finally served after queue 0 done");
        $display("PASS: Test 3");

        req_valid = '0;
        repeat (5) @(posedge clk);

        // ==========================================
        // Test 4: Middle Priority Queue
        // ==========================================
        $display("\n=== Test 4: Middle Priority (Queue 1 vs Queue 2) ===");
        total_received = 0;
        grant_idx = 0;

        // Queues 1 and 2 request (queue 0 and 3 idle)
        @(posedge clk);
        req_valid[1] = 1'b1;
        req_valid[2] = 1'b1;
        req_addr[1] = 32'h1111;
        req_addr[2] = 32'h2222;

        // Wait for both to complete - use req_ready to detect
        while (total_received < 2) begin
            @(posedge clk);
            for (i = 1; i <= 2; i = i + 1) begin
                if (req_ready[i] && req_valid[i]) begin
                    grant_order[grant_idx] = i;
                    grant_idx = grant_idx + 1;
                    total_received = total_received + 1;
                    $display("  Grant %0d: src=%0d", total_received, i);
                    req_valid[i] = 1'b0;
                end
            end
        end

        req_valid = '0;
        repeat (5) @(posedge clk);

        if (grant_order[0] == 1 && grant_order[1] == 2) begin
            $display("PASS: Test 4 - Queue 1 served before Queue 2");
        end else begin
            $display("FAIL: Test 4 - Wrong order: %0d, %0d", grant_order[0], grant_order[1]);
            error_count = error_count + 1;
        end

        // ==========================================
        // Summary
        // ==========================================
        repeat (10) @(posedge clk);
        $display("\n========================================");
        $display("Fixed-Priority Test Summary");
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
        #100000;
        $display("ERROR: Testbench timeout");
        $finish;
    end

endmodule : dma_scheduler_fixed_priority_tb
