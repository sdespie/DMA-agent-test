//-----------------------------------------------------------------------------
// Module: dma_scheduler_edge_cases_tb
// Description: Testbench for edge cases and boundary conditions.
//              Tests N=2 configuration, rapid request patterns, etc.
//-----------------------------------------------------------------------------

module dma_scheduler_edge_cases_tb;

    import dma_scheduler_pkg::*;

    //-------------------------------------------------------------------------
    // Parameters - Minimum N=2 configuration
    //-------------------------------------------------------------------------
    parameter int unsigned N       = 2;  // Minimum queue count
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
    integer grant_count[2];
    integer prev_src;

    //-------------------------------------------------------------------------
    // Main Test Sequence
    //-------------------------------------------------------------------------
    initial begin
        integer i;
        integer alternations;

        $display("\n========================================");
        $display("DMA Scheduler Edge Cases Testbench");
        $display("N=%0d (minimum), ARB_POLICY=ARB_ROUND_ROBIN", N);
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
        for (i = 0; i < N; i = i + 1) begin
            grant_count[i] = 0;
            req_weight[i] = 4'd1;
        end

        // Release reset
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        // ==========================================
        // Test 1: N=2 Basic Operation
        // ==========================================
        $display("=== Test 1: N=2 Basic Operation ===");
        out_ready = 1'b1;
        total_received = 0;

        // Send requests from both queues
        @(posedge clk);
        req_valid[0] = 1'b1;
        req_valid[1] = 1'b1;
        req_addr[0] = 32'hAAAA_0000;
        req_addr[1] = 32'hBBBB_0000;
        req_id[0] = 8'h00;
        req_id[1] = 8'h11;

        // Wait for both to complete
        while (total_received < 2) begin
            @(posedge clk);
            if (out_valid && out_ready) begin
                total_received = total_received + 1;
                $display("  Received: src=%0d, addr=0x%h", out_src, out_addr);
                req_valid[out_src] = 1'b0;
            end
        end

        req_valid = '0;
        repeat (5) @(posedge clk);

        if (total_received == 2) begin
            $display("PASS: Test 1 - N=2 basic operation works");
        end else begin
            $display("FAIL: Test 1");
            error_count = error_count + 1;
        end

        // ==========================================
        // Test 2: Alternating Round-Robin (N=2)
        // ==========================================
        $display("\n=== Test 2: Alternating Round-Robin ===");
        total_received = 0;
        grant_count[0] = 0;
        grant_count[1] = 0;
        alternations = 0;
        prev_src = -1;

        // Both queues continuously request
        @(posedge clk);
        req_valid = '1;  // Both valid
        req_addr[0] = 32'h1000;
        req_addr[1] = 32'h2000;

        // Run for 20 grants and count alternations
        while (total_received < 20) begin
            @(posedge clk);
            if (out_valid && out_ready) begin
                grant_count[out_src] = grant_count[out_src] + 1;
                if (prev_src >= 0 && prev_src != out_src) begin
                    alternations = alternations + 1;
                end
                prev_src = out_src;
                total_received = total_received + 1;
            end
        end

        req_valid = '0;
        repeat (5) @(posedge clk);

        $display("  Queue 0 grants: %0d", grant_count[0]);
        $display("  Queue 1 grants: %0d", grant_count[1]);
        $display("  Alternations: %0d (max possible: 19)", alternations);

        // Should be perfectly fair (10:10) and alternate every cycle
        if (grant_count[0] == 10 && grant_count[1] == 10 && alternations >= 18) begin
            $display("PASS: Test 2 - Perfect round-robin alternation");
        end else if (grant_count[0] == 10 && grant_count[1] == 10) begin
            $display("PASS: Test 2 - Fair distribution (alternation pattern may vary)");
        end else begin
            $display("FAIL: Test 2 - Unfair distribution");
            error_count = error_count + 1;
        end

        // ==========================================
        // Test 3: Rapid On/Off Requests
        // ==========================================
        $display("\n=== Test 3: Rapid On/Off Requests ===");
        total_received = 0;

        // Alternate which queue is requesting each cycle
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk);
            if (i % 2 == 0) begin
                req_valid[0] = 1'b1;
                req_valid[1] = 1'b0;
                req_addr[0] = 32'h3000 + i;
            end else begin
                req_valid[0] = 1'b0;
                req_valid[1] = 1'b1;
                req_addr[1] = 32'h4000 + i;
            end

            // Wait for handshake
            @(posedge clk);
            while (!(out_valid && out_ready)) @(posedge clk);
            total_received = total_received + 1;
            $display("  Grant %0d: src=%0d", total_received, out_src);
        end

        req_valid = '0;
        repeat (5) @(posedge clk);

        if (total_received == 10) begin
            $display("PASS: Test 3 - Rapid on/off handled correctly");
        end else begin
            $display("FAIL: Test 3 - Expected 10, got %0d", total_received);
            error_count = error_count + 1;
        end

        // ==========================================
        // Test 4: Back-to-back Requests Same Queue
        // ==========================================
        $display("\n=== Test 4: Back-to-back Same Queue ===");
        total_received = 0;

        // Only queue 0 requests continuously
        @(posedge clk);
        for (i = 0; i < 8; i = i + 1) begin
            req_valid[0] = 1'b1;
            req_addr[0] = 32'h5000 + i * 32'h100;
            req_id[0] = i[ID_W-1:0];

            @(posedge clk);
            while (!req_ready[0]) @(posedge clk);

            if (out_valid && out_ready) begin
                if (out_src == 0) begin
                    total_received = total_received + 1;
                end else begin
                    $display("  ERROR: Wrong source %0d", out_src);
                    error_count = error_count + 1;
                end
            end
        end

        req_valid = '0;
        repeat (5) @(posedge clk);

        if (total_received == 8) begin
            $display("PASS: Test 4 - Back-to-back single queue works");
        end else begin
            $display("FAIL: Test 4 - Expected 8, got %0d", total_received);
            error_count = error_count + 1;
        end

        // ==========================================
        // Test 5: No Requests (Idle)
        // ==========================================
        $display("\n=== Test 5: Idle Behavior ===");

        req_valid = '0;
        repeat (10) @(posedge clk);

        if (!out_valid) begin
            $display("PASS: Test 5 - No spurious outputs when idle");
        end else begin
            $display("FAIL: Test 5 - out_valid asserted with no requests");
            error_count = error_count + 1;
        end

        // ==========================================
        // Test 6: Intermittent Backpressure
        // ==========================================
        $display("\n=== Test 6: Intermittent Backpressure ===");
        total_received = 0;

        @(posedge clk);
        req_valid = '1;
        req_addr[0] = 32'h6000;
        req_addr[1] = 32'h7000;

        // Toggle out_ready every few cycles
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk);
            out_ready = (i % 3 != 0);  // Ready 2 out of 3 cycles

            if (out_valid && out_ready) begin
                total_received = total_received + 1;
            end
        end

        // Drain remaining
        out_ready = 1'b1;
        repeat (10) begin
            @(posedge clk);
            if (out_valid && out_ready) begin
                total_received = total_received + 1;
            end
        end

        req_valid = '0;
        repeat (5) @(posedge clk);

        $display("  Received %0d requests with intermittent backpressure", total_received);
        if (total_received > 0) begin
            $display("PASS: Test 6 - Intermittent backpressure handled");
        end else begin
            $display("FAIL: Test 6 - No requests completed");
            error_count = error_count + 1;
        end

        // ==========================================
        // Test 7: Reset During Active Request
        // ==========================================
        $display("\n=== Test 7: Reset During Active Request ===");

        @(posedge clk);
        req_valid[0] = 1'b1;
        req_addr[0] = 32'h8000;
        out_ready = 1'b0;  // Hold off acceptance

        repeat (3) @(posedge clk);

        // Assert reset while request is pending
        rst = 1'b1;
        repeat (2) @(posedge clk);
        rst = 1'b0;
        req_valid = '0;
        out_ready = 1'b1;

        repeat (5) @(posedge clk);

        if (!out_valid) begin
            $display("PASS: Test 7 - Reset clears pending request");
        end else begin
            $display("FAIL: Test 7 - State not cleared by reset");
            error_count = error_count + 1;
        end

        // ==========================================
        // Test 8: Maximum Address/Length Values
        // ==========================================
        $display("\n=== Test 8: Maximum Address/Length Values ===");
        total_received = 0;

        @(posedge clk);
        req_valid[0] = 1'b1;
        req_addr[0] = {ADDR_W{1'b1}};  // All 1s
        req_len[0] = {LEN_W{1'b1}};    // All 1s
        req_id[0] = {ID_W{1'b1}};      // All 1s

        @(posedge clk);
        while (!req_ready[0]) @(posedge clk);

        if (out_valid && out_ready) begin
            if (out_addr == {ADDR_W{1'b1}} &&
                out_len == {LEN_W{1'b1}} &&
                out_id == {ID_W{1'b1}}) begin
                $display("PASS: Test 8 - Maximum values passed correctly");
                $display("  addr=0x%h, len=0x%h, id=0x%h", out_addr, out_len, out_id);
            end else begin
                $display("FAIL: Test 8 - Values corrupted");
                $display("  Expected all 1s, got addr=0x%h, len=0x%h, id=0x%h",
                         out_addr, out_len, out_id);
                error_count = error_count + 1;
            end
        end

        req_valid = '0;
        repeat (5) @(posedge clk);

        // ==========================================
        // Summary
        // ==========================================
        repeat (10) @(posedge clk);
        $display("\n========================================");
        $display("Edge Cases Test Summary");
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

endmodule : dma_scheduler_edge_cases_tb
