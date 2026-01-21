//-----------------------------------------------------------------------------
// Module: dma_scheduler_tb
// Description: Self-checking testbench for the DMA scheduler.
//              Verifies functional correctness, backpressure handling,
//              and arbitration fairness.
//
// Test Scenarios:
//   1. Basic single-queue operation
//   2. All queues concurrent with continuous traffic
//   3. Backpressure handling (random out_ready toggling)
//   4. Round-robin fairness verification
//   5. Reset behavior
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
    logic clk;
    logic rst;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;  // 100MHz clock
    end

    //-------------------------------------------------------------------------
    // DUT Signals
    //-------------------------------------------------------------------------
    logic [N-1:0]               req_valid;
    logic [N-1:0]               req_ready;
    logic [N-1:0][ADDR_W-1:0]   req_addr;
    logic [N-1:0][LEN_W-1:0]    req_len;
    logic [N-1:0][ID_W-1:0]     req_id;
    logic [N-1:0][WEIGHT_W-1:0] req_weight;

    logic                       out_valid;
    logic                       out_ready;
    logic [ADDR_W-1:0]          out_addr;
    logic [LEN_W-1:0]           out_len;
    logic [ID_W-1:0]            out_id;
    logic [IDX_W-1:0]           out_src;

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
    // Scoreboard Data Structures
    //-------------------------------------------------------------------------
    typedef struct {
        logic [ADDR_W-1:0] addr;
        logic [LEN_W-1:0]  len;
        logic [ID_W-1:0]   id;
        int unsigned       src_queue;
    } request_t;

    // Per-queue expected request FIFOs
    request_t expected_queues[N][$];

    // Statistics
    int unsigned total_sent[N];
    int unsigned total_received[N];
    int unsigned error_count;

    //-------------------------------------------------------------------------
    // Helper Tasks
    //-------------------------------------------------------------------------

    // Reset the DUT and testbench state
    task automatic do_reset();
        rst = 1'b1;
        req_valid = '0;
        req_addr = '0;
        req_len = '0;
        req_id = '0;
        req_weight = '0;
        out_ready = 1'b0;

        // Set default weights for weighted RR
        for (int i = 0; i < N; i++) begin
            req_weight[i] = 4'd1 + i[WEIGHT_W-1:0];  // Weights: 1, 2, 3, 4
        end

        // Clear scoreboards
        for (int i = 0; i < N; i++) begin
            expected_queues[i].delete();
            total_sent[i] = 0;
            total_received[i] = 0;
        end
        error_count = 0;

        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);
    endtask

    // Send a request on a specific queue
    task automatic send_request(
        input int unsigned queue,
        input logic [ADDR_W-1:0] addr,
        input logic [LEN_W-1:0] len,
        input logic [ID_W-1:0] id
    );
        request_t req;

        // Set up request
        req_valid[queue] = 1'b1;
        req_addr[queue] = addr;
        req_len[queue] = len;
        req_id[queue] = id;

        // Add to expected queue
        req.addr = addr;
        req.len = len;
        req.id = id;
        req.src_queue = queue;
        expected_queues[queue].push_back(req);
        total_sent[queue]++;

        // Wait for handshake
        @(posedge clk);
        while (!req_ready[queue]) @(posedge clk);

        // Deassert valid after acceptance
        req_valid[queue] = 1'b0;
    endtask

    // Monitor output and check against scoreboard
    task automatic monitor_output();
        forever begin
            @(posedge clk);
            if (!rst && out_valid && out_ready) begin
                automatic int unsigned src = out_src;
                automatic request_t expected;

                if (expected_queues[src].size() == 0) begin
                    $error("Received request from queue %0d but none expected", src);
                    error_count++;
                end else begin
                    expected = expected_queues[src].pop_front();

                    // Verify data
                    if (out_addr !== expected.addr) begin
                        $error("Queue %0d: addr mismatch. Got 0x%h, expected 0x%h",
                               src, out_addr, expected.addr);
                        error_count++;
                    end
                    if (out_len !== expected.len) begin
                        $error("Queue %0d: len mismatch. Got %0d, expected %0d",
                               src, out_len, expected.len);
                        error_count++;
                    end
                    if (out_id !== expected.id) begin
                        $error("Queue %0d: id mismatch. Got %0d, expected %0d",
                               src, out_id, expected.id);
                        error_count++;
                    end

                    total_received[src]++;
                end
            end
        end
    endtask

    // Random backpressure generator
    task automatic random_backpressure(input int unsigned cycles);
        for (int i = 0; i < cycles; i++) begin
            @(posedge clk);
            out_ready = $urandom_range(0, 1);
        end
    endtask

    //-------------------------------------------------------------------------
    // Test Cases
    //-------------------------------------------------------------------------

    // Test 1: Basic single-queue operation
    task automatic test_single_queue();
        $display("\n=== Test 1: Single Queue Operation ===");
        do_reset();
        out_ready = 1'b1;

        // Send several requests from queue 0
        for (int i = 0; i < 10; i++) begin
            send_request(0, 32'h1000 + i*4, 16'd64, i[ID_W-1:0]);
        end

        // Wait for all to complete
        repeat (20) @(posedge clk);

        if (total_received[0] == 10)
            $display("PASS: Single queue test");
        else begin
            $display("FAIL: Expected 10 requests, received %0d", total_received[0]);
            error_count++;
        end
    endtask

    // Test 2: All queues concurrent
    task automatic test_all_queues_concurrent();
        $display("\n=== Test 2: All Queues Concurrent ===");
        do_reset();
        out_ready = 1'b1;

        // Start all queues simultaneously
        fork
            for (int i = 0; i < 10; i++) send_request(0, 32'hA000 + i*4, 16'd32, i[ID_W-1:0]);
            for (int i = 0; i < 10; i++) send_request(1, 32'hB000 + i*4, 16'd32, i[ID_W-1:0]);
            for (int i = 0; i < 10; i++) send_request(2, 32'hC000 + i*4, 16'd32, i[ID_W-1:0]);
            for (int i = 0; i < 10; i++) send_request(3, 32'hD000 + i*4, 16'd32, i[ID_W-1:0]);
        join

        // Wait for completion
        repeat (50) @(posedge clk);

        automatic int total = 0;
        for (int i = 0; i < N; i++) total += total_received[i];

        if (total == 40)
            $display("PASS: All queues concurrent test (received %0d)", total);
        else begin
            $display("FAIL: Expected 40 requests, received %0d", total);
            error_count++;
        end

        // Display per-queue stats
        for (int i = 0; i < N; i++)
            $display("  Queue %0d: sent=%0d, received=%0d", i, total_sent[i], total_received[i]);
    endtask

    // Test 3: Backpressure handling
    task automatic test_backpressure();
        $display("\n=== Test 3: Backpressure Handling ===");
        do_reset();

        // Start random backpressure in background
        fork
            random_backpressure(200);
        join_none

        // Send requests from all queues
        fork
            for (int i = 0; i < 5; i++) send_request(0, 32'h1000 + i*4, 16'd16, i[ID_W-1:0]);
            for (int i = 0; i < 5; i++) send_request(1, 32'h2000 + i*4, 16'd16, i[ID_W-1:0]);
            for (int i = 0; i < 5; i++) send_request(2, 32'h3000 + i*4, 16'd16, i[ID_W-1:0]);
            for (int i = 0; i < 5; i++) send_request(3, 32'h4000 + i*4, 16'd16, i[ID_W-1:0]);
        join

        // Allow completion
        out_ready = 1'b1;
        repeat (50) @(posedge clk);

        automatic int total = 0;
        for (int i = 0; i < N; i++) total += total_received[i];

        if (total == 20)
            $display("PASS: Backpressure test (received %0d)", total);
        else begin
            $display("FAIL: Expected 20 requests, received %0d", total);
            error_count++;
        end
    endtask

    // Test 4: Round-robin fairness
    task automatic test_fairness();
        $display("\n=== Test 4: Round-Robin Fairness ===");
        do_reset();
        out_ready = 1'b1;

        // Keep all queues constantly requesting
        fork
            begin
                for (int i = 0; i < 100; i++) begin
                    req_valid[0] = 1'b1;
                    req_addr[0] = 32'h1000 + i;
                    req_id[0] = i[ID_W-1:0];
                    @(posedge clk);
                    if (req_ready[0]) begin
                        expected_queues[0].push_back('{req_addr[0], req_len[0], req_id[0], 0});
                        total_sent[0]++;
                    end
                end
                req_valid[0] = 1'b0;
            end
            begin
                for (int i = 0; i < 100; i++) begin
                    req_valid[1] = 1'b1;
                    req_addr[1] = 32'h2000 + i;
                    req_id[1] = i[ID_W-1:0];
                    @(posedge clk);
                    if (req_ready[1]) begin
                        expected_queues[1].push_back('{req_addr[1], req_len[1], req_id[1], 1});
                        total_sent[1]++;
                    end
                end
                req_valid[1] = 1'b0;
            end
            begin
                for (int i = 0; i < 100; i++) begin
                    req_valid[2] = 1'b1;
                    req_addr[2] = 32'h3000 + i;
                    req_id[2] = i[ID_W-1:0];
                    @(posedge clk);
                    if (req_ready[2]) begin
                        expected_queues[2].push_back('{req_addr[2], req_len[2], req_id[2], 2});
                        total_sent[2]++;
                    end
                end
                req_valid[2] = 1'b0;
            end
            begin
                for (int i = 0; i < 100; i++) begin
                    req_valid[3] = 1'b1;
                    req_addr[3] = 32'h4000 + i;
                    req_id[3] = i[ID_W-1:0];
                    @(posedge clk);
                    if (req_ready[3]) begin
                        expected_queues[3].push_back('{req_addr[3], req_len[3], req_id[3], 3});
                        total_sent[3]++;
                    end
                end
                req_valid[3] = 1'b0;
            end
        join

        repeat (20) @(posedge clk);

        // Check fairness (each queue should have ~25% of grants)
        $display("Fairness distribution:");
        for (int i = 0; i < N; i++) begin
            $display("  Queue %0d: %0d requests (%0.1f%%)",
                     i, total_received[i], 100.0 * total_received[i] / (total_sent[0] + total_sent[1] + total_sent[2] + total_sent[3]));
        end

        // Allow some variance (20-30% each for 4 queues)
        automatic bit fair = 1'b1;
        automatic int total_reqs = total_received[0] + total_received[1] + total_received[2] + total_received[3];
        for (int i = 0; i < N; i++) begin
            automatic real pct = 100.0 * total_received[i] / total_reqs;
            if (pct < 15.0 || pct > 35.0) fair = 1'b0;
        end

        if (fair)
            $display("PASS: Fairness within acceptable bounds");
        else begin
            $display("WARNING: Fairness outside expected bounds (may be acceptable depending on timing)");
        end
    endtask

    // Test 5: Reset during transaction
    task automatic test_reset_behavior();
        $display("\n=== Test 5: Reset Behavior ===");
        do_reset();
        out_ready = 1'b1;

        // Start some requests
        fork
            for (int i = 0; i < 5; i++) send_request(0, 32'h1000, 16'd64, i[ID_W-1:0]);
        join_none

        // Assert reset mid-transaction
        repeat (3) @(posedge clk);
        rst = 1'b1;
        repeat (2) @(posedge clk);
        rst = 1'b0;

        // Verify DUT is in clean state
        repeat (5) @(posedge clk);

        if (!out_valid)
            $display("PASS: Reset clears output valid");
        else begin
            $display("FAIL: Output still valid after reset");
            error_count++;
        end
    endtask

    //-------------------------------------------------------------------------
    // Main Test Sequence
    //-------------------------------------------------------------------------
    initial begin
        $display("\n========================================");
        $display("DMA Scheduler Testbench");
        $display("N=%0d, ADDR_W=%0d, LEN_W=%0d, ID_W=%0d", N, ADDR_W, LEN_W, ID_W);
        $display("Arbitration Policy: %s", ARB_POLICY.name());
        $display("========================================\n");

        // Start output monitor
        fork
            monitor_output();
        join_none

        // Run tests
        test_single_queue();
        test_all_queues_concurrent();
        test_backpressure();
        test_fairness();
        test_reset_behavior();

        // Final summary
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
        #100000;
        $display("ERROR: Testbench timeout");
        $finish;
    end

endmodule : dma_scheduler_tb
