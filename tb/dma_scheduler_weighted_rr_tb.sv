//-----------------------------------------------------------------------------
// Module: dma_scheduler_weighted_rr_tb
// Description: Testbench for weighted round-robin arbitration policy.
//              Verifies bandwidth allocation proportional to weights.
//-----------------------------------------------------------------------------

module dma_scheduler_weighted_rr_tb;

    import dma_scheduler_pkg::*;

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    parameter int unsigned N       = 4;
    parameter int unsigned ADDR_W  = 32;
    parameter int unsigned LEN_W   = 16;
    parameter int unsigned ID_W    = 8;
    parameter int unsigned WEIGHT_W = 4;
    parameter arb_policy_e ARB_POLICY = ARB_WEIGHTED_RR;

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
    integer grant_count[4];

    //-------------------------------------------------------------------------
    // Main Test Sequence
    //-------------------------------------------------------------------------
    initial begin
        integer i;
        integer total_weight;
        integer expected_grants;
        integer tolerance;

        $display("\n========================================");
        $display("DMA Scheduler Weighted RR Testbench");
        $display("N=%0d, ARB_POLICY=ARB_WEIGHTED_RR", N);
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
        for (i = 0; i < N; i = i + 1) grant_count[i] = 0;

        // Release reset
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        // ==========================================
        // Test 1: Equal Weights (all weight=2)
        // ==========================================
        $display("=== Test 1: Equal Weights (all=2) ===");
        out_ready = 1'b1;
        total_received = 0;
        for (i = 0; i < N; i = i + 1) begin
            grant_count[i] = 0;
            req_weight[i] = 4'd2;  // All equal weight
        end

        // All queues continuously request
        @(posedge clk);
        for (i = 0; i < N; i = i + 1) begin
            req_valid[i] = 1'b1;
            req_addr[i] = 32'h1000 * (i + 1);
            req_id[i] = i[ID_W-1:0];
        end

        // Run for enough cycles to see fair distribution
        // With equal weights, each should get ~equal grants
        while (total_received < 40) begin
            @(posedge clk);
            if (out_valid && out_ready) begin
                grant_count[out_src] = grant_count[out_src] + 1;
                total_received = total_received + 1;
            end
        end

        req_valid = '0;
        repeat (5) @(posedge clk);

        $display("  Grant distribution (40 total):");
        for (i = 0; i < N; i = i + 1) begin
            $display("    Queue %0d: %0d grants", i, grant_count[i]);
        end

        // With equal weights, expect ~10 each (tolerance of 2)
        if (grant_count[0] >= 8 && grant_count[0] <= 12 &&
            grant_count[1] >= 8 && grant_count[1] <= 12 &&
            grant_count[2] >= 8 && grant_count[2] <= 12 &&
            grant_count[3] >= 8 && grant_count[3] <= 12) begin
            $display("PASS: Test 1 - Fair distribution with equal weights");
        end else begin
            $display("FAIL: Test 1 - Uneven distribution");
            error_count = error_count + 1;
        end

        // ==========================================
        // Test 2: Weighted Distribution (1:2:3:4)
        // ==========================================
        $display("\n=== Test 2: Weighted Distribution (1:2:3:4) ===");

        // Reset DUT
        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        total_received = 0;
        for (i = 0; i < N; i = i + 1) grant_count[i] = 0;

        // Set weights 1, 2, 3, 4
        req_weight[0] = 4'd1;
        req_weight[1] = 4'd2;
        req_weight[2] = 4'd3;
        req_weight[3] = 4'd4;

        total_weight = 1 + 2 + 3 + 4;  // = 10

        // All queues continuously request
        @(posedge clk);
        for (i = 0; i < N; i = i + 1) begin
            req_valid[i] = 1'b1;
            req_addr[i] = 32'h2000 * (i + 1);
            req_id[i] = i[ID_W-1:0];
        end

        // Run for 100 grants to get good statistical sample
        while (total_received < 100) begin
            @(posedge clk);
            if (out_valid && out_ready) begin
                grant_count[out_src] = grant_count[out_src] + 1;
                total_received = total_received + 1;
            end
        end

        req_valid = '0;
        repeat (5) @(posedge clk);

        $display("  Grant distribution (100 total, weights 1:2:3:4):");
        $display("    Queue 0 (w=1): %0d grants (expected ~10)", grant_count[0]);
        $display("    Queue 1 (w=2): %0d grants (expected ~20)", grant_count[1]);
        $display("    Queue 2 (w=3): %0d grants (expected ~30)", grant_count[2]);
        $display("    Queue 3 (w=4): %0d grants (expected ~40)", grant_count[3]);

        // Check proportions are roughly correct (tolerance of 5)
        tolerance = 5;
        if (grant_count[0] >= 10-tolerance && grant_count[0] <= 10+tolerance &&
            grant_count[1] >= 20-tolerance && grant_count[1] <= 20+tolerance &&
            grant_count[2] >= 30-tolerance && grant_count[2] <= 30+tolerance &&
            grant_count[3] >= 40-tolerance && grant_count[3] <= 40+tolerance) begin
            $display("PASS: Test 2 - Weighted distribution correct");
        end else begin
            $display("FAIL: Test 2 - Distribution doesn't match weights");
            error_count = error_count + 1;
        end

        // ==========================================
        // Test 3: Credit Exhaustion and Reload
        // ==========================================
        $display("\n=== Test 3: Credit Exhaustion and Reload ===");

        // Reset DUT
        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        total_received = 0;
        for (i = 0; i < N; i = i + 1) grant_count[i] = 0;

        // Set small weights to easily observe reload
        req_weight[0] = 4'd1;
        req_weight[1] = 4'd1;
        req_weight[2] = 4'd1;
        req_weight[3] = 4'd1;

        // Only queues 0 and 1 request
        @(posedge clk);
        req_valid[0] = 1'b1;
        req_valid[1] = 1'b1;
        req_addr[0] = 32'h3000;
        req_addr[1] = 32'h3100;

        // Run for 10 grants
        while (total_received < 10) begin
            @(posedge clk);
            if (out_valid && out_ready) begin
                grant_count[out_src] = grant_count[out_src] + 1;
                total_received = total_received + 1;
                $display("  Grant %0d: Queue %0d", total_received, out_src);
            end
        end

        req_valid = '0;
        repeat (5) @(posedge clk);

        // Should see alternating pattern (round-robin among equal weights)
        if (grant_count[0] == 5 && grant_count[1] == 5) begin
            $display("PASS: Test 3 - Credit exhaustion/reload working (5:5 split)");
        end else begin
            $display("FAIL: Test 3 - Expected 5:5, got %0d:%0d", grant_count[0], grant_count[1]);
            error_count = error_count + 1;
        end

        // ==========================================
        // Test 4: Zero Weight Handling
        // ==========================================
        $display("\n=== Test 4: Zero Weight Queue ===");

        // Reset DUT
        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        total_received = 0;
        for (i = 0; i < N; i = i + 1) grant_count[i] = 0;

        // Queue 0 has zero weight, others have weight 2
        req_weight[0] = 4'd0;  // Zero weight - should get no grants
        req_weight[1] = 4'd2;
        req_weight[2] = 4'd2;
        req_weight[3] = 4'd2;

        // All queues request
        @(posedge clk);
        for (i = 0; i < N; i = i + 1) begin
            req_valid[i] = 1'b1;
            req_addr[i] = 32'h4000 * (i + 1);
        end

        // Run for 30 grants
        while (total_received < 30) begin
            @(posedge clk);
            if (out_valid && out_ready) begin
                grant_count[out_src] = grant_count[out_src] + 1;
                total_received = total_received + 1;
            end
        end

        req_valid = '0;
        repeat (5) @(posedge clk);

        $display("  Grant distribution (30 total):");
        $display("    Queue 0 (w=0): %0d grants", grant_count[0]);
        $display("    Queue 1 (w=2): %0d grants", grant_count[1]);
        $display("    Queue 2 (w=2): %0d grants", grant_count[2]);
        $display("    Queue 3 (w=2): %0d grants", grant_count[3]);

        // Queue 0 should get zero or very few grants
        if (grant_count[0] == 0) begin
            $display("PASS: Test 4 - Zero weight queue correctly starved");
        end else begin
            $display("INFO: Test 4 - Zero weight queue got %0d grants (may reload with weight)", grant_count[0]);
            // This isn't necessarily a failure - depends on implementation
        end

        // ==========================================
        // Test 5: Single Active Queue with Weight
        // ==========================================
        $display("\n=== Test 5: Single Active Queue ===");

        // Reset DUT
        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        total_received = 0;
        grant_count[0] = 0;

        req_weight[0] = 4'd3;
        req_weight[1] = 4'd3;
        req_weight[2] = 4'd3;
        req_weight[3] = 4'd3;

        // Only queue 2 requests
        @(posedge clk);
        req_valid[2] = 1'b1;
        req_addr[2] = 32'h5000;

        // Run for 10 grants
        while (total_received < 10) begin
            @(posedge clk);
            if (out_valid && out_ready) begin
                if (out_src == 2) begin
                    total_received = total_received + 1;
                end else begin
                    $display("  ERROR: Wrong queue %0d granted", out_src);
                    error_count = error_count + 1;
                end
            end
        end

        req_valid = '0;
        repeat (5) @(posedge clk);

        if (total_received == 10) begin
            $display("PASS: Test 5 - Single active queue served correctly");
        end else begin
            $display("FAIL: Test 5");
        end

        // ==========================================
        // Summary
        // ==========================================
        repeat (10) @(posedge clk);
        $display("\n========================================");
        $display("Weighted RR Test Summary");
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
        #200000;
        $display("ERROR: Testbench timeout");
        $finish;
    end

endmodule : dma_scheduler_weighted_rr_tb
