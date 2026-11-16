//=============================================================================
// tb_fair_arbiter.sv
//
// Comprehensive self-checking testbench for the fair_arbiter module.
//
// Structure:
//   - tb_pkg  : shared result counters across all config instances.
//   - tb_core : parameterized (N, M, PTR_RESET) testbench that instantiates
//               the DUT and runs the full scenario suite for ONE config.
//   - tb_top  : instantiates tb_core for a sweep of configurations covering
//               N==M, N>M, N<M, power-of-two, non-power-of-two, small,
//               large, and no-reset.
//
// Scenario suite (each scenario also re-checks the global invariants
// orthogonality and grant-implies-request):
//   S1  idle / no requests
//   S2  single request at corner/edge positions
//   S3  same-cycle (zero latency) result
//   S4  source-side round-robin, all destinations (order + wrap)
//   S5  source-side round-robin, subset of destinations (skip + wrap)
//   S6  destination-side round-robin, all sources (order + wrap)
//   S7  destination-side round-robin, subset of sources (skip + wrap)
//   S8  conflict-free permutation (diagonal) - all granted
//   S9  full crossbar - perfect matching of size min(N,M) after warmup
//   S10 random traffic - invariants
//   S11 source backpressure (single, all)
//   S12 destination backpressure (single, all)
//   S13 source + destination backpressure together
//   S14 dynamic backpressure toggle
//   S15 long-run fairness under full crossbar
//   S16 starvation freedom under a persistent request matrix
//
// The DUT grant output is combinational: a request driven on cycle T is
// granted on cycle T.  Inputs change at negedge; outputs are checked after a
// small settle delay, before the next posedge advances the pointers.
//
// Indexing: request/grant matrices are flat 1-D vectors (bit (n,m) = n*M+m)
// because Icarus Verilog does not support chained variable indexing arr[n][m]
// on 2-D packed arrays.  Rows are selected with [n*M +: M]; pointer slices
// with [n*CW_M +: CW_M] / [m*CW_N +: CW_N].
//
// ASCII only.
//=============================================================================

`timescale 1ns/1ps

//=============================================================================
// tb_core: full scenario suite for a single (N, M, PTR_RESET) configuration.
//
// Result counters live in tb_top and are updated via hierarchical reference
// (Icarus Verilog does not reliably support the package "::" operator).
//=============================================================================
module tb_core #(
    parameter integer N         = 8,
    parameter integer M         = 8,
    parameter integer PTR_RESET = 1,
    parameter integer ITER      = 2,
    parameter string  NAME      = "8x8"
) ();

    localparam integer CW_N  = $clog2(N);
    localparam integer CW_M  = $clog2(M);
    localparam integer NM    = N * M;
    localparam integer MIN   = (N < M) ? N : M;

    logic                    clk;
    logic                    rst_n;
    logic [NM-1:0]           i_req;      // flat: bit n*M+m
    logic [N-1:0]            i_src_bp;
    logic [M-1:0]            i_dest_bp;
    logic [NM-1:0]           o_grant;    // flat: bit n*M+m
    logic [N-1:0]            o_src_vld;
    logic [N*CW_M-1:0]       o_src_ptr;  // flat: src n at [n*CW_M +: CW_M]
    logic [M-1:0]            o_dest_vld;
    logic [M*CW_N-1:0]       o_dest_ptr; // flat: dest m at [m*CW_N +: CW_N]

    fair_arbiter #(.N(N), .M(M), .PTR_RESET(PTR_RESET), .ITER(ITER)) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .i_src_dest_req   (i_req),
        .i_src_bp         (i_src_bp),
        .i_dest_bp        (i_dest_bp),
        .o_grant_rand_vld (o_grant),
        .o_grant_src_vld  (o_src_vld),
        .o_grant_src_ptr  (o_src_ptr),
        .o_grant_dest_vld (o_dest_vld),
        .o_grant_dest_ptr (o_dest_ptr)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    //-------------------------------------------------------------------------
    // Accounting.
    //-------------------------------------------------------------------------
    int errors = 0;
    int checks = 0;

    task automatic check(input logic cond, input string msg);
        checks = checks + 1;
        if (!cond) begin
            errors = errors + 1;
            $display("  FAIL [%s t=%0t] %s", NAME, $time, msg);
        end
    endtask

    //-------------------------------------------------------------------------
    // Pseudo-random source (LCG, deterministic).
    //-------------------------------------------------------------------------
    integer seed = 12345;
    logic [31:0] rnd_word;
    function automatic logic [31:0] rnd32();
        seed = (seed * 1103515245 + 12345) & 32'h7fff_ffff;
        return seed;
    endfunction

    //-------------------------------------------------------------------------
    // Reset + pointer init.  For PTR_RESET=0 the pointers have no reset, so
    // they are $deposit'd to 0 to simulate a deterministic power-on state and
    // avoid X in simulation.
    //-------------------------------------------------------------------------
    task automatic init_pointers();
        if (PTR_RESET == 0) begin
            $deposit(dut.g_ptr, {M*CW_N{1'b0}});
            $deposit(dut.a_ptr, {N*CW_M{1'b0}});
        end
    endtask

    task automatic soft_reset();
        rst_n = 1'b0;
        i_req = '0; i_src_bp = '0; i_dest_bp = '0;
        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        init_pointers();
    endtask

    //-------------------------------------------------------------------------
    // Global invariants.
    //
    // Note: these count bits with plain loops instead of $onehot0/$onehot/
    // $countones, because Icarus Verilog returns wrong results for those
    // system functions when given a "+:" indexed part-select.
    //-------------------------------------------------------------------------
    // count ones in o_grant bits [lo:hi]
    function automatic int count_ones(input int lo, input int hi);
        int c;
        c = 0;
        for (int k = lo; k <= hi; k = k + 1)
            if (o_grant[k]) c = c + 1;
        return c;
    endfunction

    task automatic check_orth();
        int cnt;
        // each source (row) matched to at most one destination
        for (int n = 0; n < N; n = n + 1) begin
            cnt = 0;
            for (int m = 0; m < M; m = m + 1)
                if (o_grant[n*M + m]) cnt = cnt + 1;
            if (cnt > 1) check(1'b0, $sformatf("orth row %0d has %0d bits grant=%0b", n, cnt, o_grant));
            else         checks = checks + 1;
        end
        // each destination (column) matched to at most one source
        for (int m = 0; m < M; m = m + 1) begin
            cnt = 0;
            for (int n = 0; n < N; n = n + 1)
                if (o_grant[n*M + m]) cnt = cnt + 1;
            if (cnt > 1) check(1'b0, $sformatf("orth col %0d has %0d bits grant=%0b", m, cnt, o_grant));
            else         checks = checks + 1;
        end
    endtask

    task automatic check_grant_implies();
        for (int n = 0; n < N; n = n + 1) begin
            for (int m = 0; m < M; m = m + 1) begin
                if (o_grant[n*M + m]) begin
                    check(i_req[n*M + m] == 1'b1,
                          $sformatf("grant (%0d,%0d) w/o request", n, m));
                    check(i_src_bp[n] == 1'b0,
                          $sformatf("grant (%0d,%0d) but src bp", n, m));
                    check(i_dest_bp[m] == 1'b0,
                          $sformatf("grant (%0d,%0d) but dest bp", n, m));
                end
            end
        end
    endtask

    // Helper: apply stimulus and settle, then run invariants.
    task automatic apply(input logic [NM-1:0] req,
                         input logic [N-1:0]  sbp,
                         input logic [M-1:0]  dbp);
        @(negedge clk);
        i_req = req; i_src_bp = sbp; i_dest_bp = dbp;
        #2;
        check_orth();
        check_grant_implies();
    endtask

    //=========================================================================
    // S1: idle (no requests).
    //=========================================================================
    task automatic s_idle();
        $display("[%s] S1 idle", NAME);
        for (int c = 0; c < 4; c = c + 1) begin
            @(negedge clk);
            i_req = '0; i_src_bp = '0; i_dest_bp = '0;
            #2;
            check(|o_grant == 1'b0, "S1 no grant when idle");
            check(|o_src_vld == 1'b0, "S1 no src vld when idle");
            check(|o_dest_vld == 1'b0, "S1 no dest vld when idle");
            @(posedge clk);
        end
    endtask

    //=========================================================================
    // S2: single request at corner / edge / middle positions.
    //=========================================================================
    task automatic s_single();
        $display("[%s] S2 single request", NAME);
        for (int k = 0; k < 5; k = k + 1) begin
            int n, m;
            case (k)
                0: begin n = 0;     m = 0;     end
                1: begin n = 0;     m = M-1;   end
                2: begin n = N-1;   m = 0;     end
                3: begin n = N-1;   m = M-1;   end
                4: begin n = N/2;   m = M/2;   end
            endcase
            @(negedge clk);
            i_req = '0;
            i_req[n*M + m] = 1'b1;
            i_src_bp = '0; i_dest_bp = '0;
            #2;
            check(count_ones(0, NM-1) == 1, "S2 exactly one grant");
            check(o_grant[n*M + m] == 1'b1, $sformatf("S2 grant at (%0d,%0d)", n, m));
            check(o_src_vld[n] == 1'b1, "S2 src vld");
            check(o_src_ptr[n*CW_M +: CW_M] == m, "S2 src ptr");
            check(o_dest_vld[m] == 1'b1, "S2 dest vld");
            check(o_dest_ptr[m*CW_N +: CW_N] == n, "S2 dest ptr");
            @(posedge clk);
        end
    endtask

    //=========================================================================
    // S3: same-cycle (zero latency) result.
    //=========================================================================
    task automatic s_same_cycle();
        $display("[%s] S3 same-cycle", NAME);
        @(negedge clk); i_req = '0; i_src_bp = '0; i_dest_bp = '0;
        @(posedge clk);
        @(negedge clk);
        i_req = '0;
        i_req[0*M + (M-1)] = 1'b1;   // src0 -> last dest, only request
        #2;
        check(o_grant[0*M + (M-1)] == 1'b1, "S3 same-cycle grant");
        check(o_src_ptr[0*CW_M +: CW_M] == (M-1), "S3 same-cycle ptr");
        @(posedge clk);
    endtask

    //=========================================================================
    // S4: source-side round-robin, all destinations.
    //=========================================================================
    task automatic s_src_rr();
        $display("[%s] S4 source RR (all dests)", NAME);
        soft_reset();
        for (int c = 0; c < 2*M; c = c + 1) begin
            @(negedge clk);
            i_req = '0;
            i_req[0*M +: M] = '1;
            i_src_bp = '0; i_dest_bp = '0;
            #2;
            check(o_src_vld[0] == 1'b1, "S4 src0 vld");
            check(o_src_ptr[0*CW_M +: CW_M] == (c % M),
                  $sformatf("S4 src0 -> dest %0d, got %0d", c % M, o_src_ptr[0*CW_M +: CW_M]));
            check(count_ones(0*M, 0*M + M-1) == 1, "S4 row onehot");
            @(posedge clk);
        end
    endtask

    //=========================================================================
    // S5: source-side round-robin, subset of destinations (even indices).
    //=========================================================================
    task automatic s_src_rr_subset();
        int k;
        $display("[%s] S5 source RR (subset)", NAME);
        k = (M + 1) / 2;   // number of even destinations
        soft_reset();
        for (int c = 0; c < 2*k; c = c + 1) begin
            @(negedge clk);
            i_req = '0;
            for (int m = 0; m < M; m = m + 1)
                if (m % 2 == 0) i_req[0*M + m] = 1'b1;   // even dests only
            i_src_bp = '0; i_dest_bp = '0;
            #2;
            check(o_src_vld[0] == 1'b1, "S5 src0 vld");
            check(o_src_ptr[0*CW_M +: CW_M] == (2*(c % k)),
                  $sformatf("S5 src0 -> dest %0d, got %0d", 2*(c % k), o_src_ptr[0*CW_M +: CW_M]));
            // grant must be to a requested (even) dest
            check(o_grant[0*M + o_src_ptr[0*CW_M +: CW_M]] == 1'b1, "S5 grant to requested dest");
            @(posedge clk);
        end
    endtask

    //=========================================================================
    // S6: destination-side round-robin, all sources.
    //=========================================================================
    task automatic s_dest_rr();
        $display("[%s] S6 dest RR (all srcs)", NAME);
        soft_reset();
        for (int c = 0; c < 2*N; c = c + 1) begin
            @(negedge clk);
            i_req = '0;
            for (int n = 0; n < N; n = n + 1)
                i_req[n*M + 0] = 1'b1;   // all sources -> dest 0
            i_src_bp = '0; i_dest_bp = '0;
            #2;
            check(o_dest_vld[0] == 1'b1, "S6 dest0 vld");
            check(o_dest_ptr[0*CW_N +: CW_N] == (c % N),
                  $sformatf("S6 dest0 <- src %0d, got %0d", c % N, o_dest_ptr[0*CW_N +: CW_N]));
            @(posedge clk);
        end
    endtask

    //=========================================================================
    // S7: destination-side round-robin, subset of sources (even indices).
    //=========================================================================
    task automatic s_dest_rr_subset();
        int k;
        $display("[%s] S7 dest RR (subset)", NAME);
        k = (N + 1) / 2;
        soft_reset();
        for (int c = 0; c < 2*k; c = c + 1) begin
            @(negedge clk);
            i_req = '0;
            for (int n = 0; n < N; n = n + 1)
                if (n % 2 == 0) i_req[n*M + 0] = 1'b1;   // even sources only
            i_src_bp = '0; i_dest_bp = '0;
            #2;
            check(o_dest_vld[0] == 1'b1, "S7 dest0 vld");
            check(o_dest_ptr[0*CW_N +: CW_N] == (2*(c % k)),
                  $sformatf("S7 dest0 <- src %0d, got %0d", 2*(c % k), o_dest_ptr[0*CW_N +: CW_N]));
            @(posedge clk);
        end
    endtask

    //=========================================================================
    // S8: conflict-free permutation (src i -> dest i, i < min(N,M)).
    //=========================================================================
    task automatic s_permutation();
        $display("[%s] S8 conflict-free permutation", NAME);
        soft_reset();
        for (int c = 0; c < 2; c = c + 1) begin
            @(negedge clk);
            i_req = '0;
            for (int i = 0; i < MIN; i = i + 1)
                i_req[i*M + i] = 1'b1;
            i_src_bp = '0; i_dest_bp = '0;
            #2;
            for (int i = 0; i < MIN; i = i + 1)
                check(o_grant[i*M + i] == 1'b1, $sformatf("S8 grant (%0d,%0d)", i, i));
            // total grants must equal MIN (each requested pair matched exactly)
            begin
                int gcnt;
                gcnt = 0;
                for (int b = 0; b < NM; b = b + 1)
                    if (o_grant[b]) gcnt = gcnt + 1;
                check(gcnt == MIN, $sformatf("S8 total grants %0d, want %0d", gcnt, MIN));
            end
            @(posedge clk);
        end
    endtask

    //=========================================================================
    // S9: full crossbar -> perfect matching of size min(N,M) after warmup.
    //=========================================================================
    task automatic s_full_crossbar();
        $display("[%s] S9 full crossbar", NAME);
        soft_reset();
        // warmup (pointers desynchronize over the first few cycles)
        for (int c = 0; c < 2*MIN; c = c + 1) begin
            @(negedge clk);
            i_req = '1;
            i_src_bp = '0; i_dest_bp = '0;
            #2;
            @(posedge clk);
        end
        // steady state: expect exactly MIN grants every cycle
        for (int c = 0; c < 60; c = c + 1) begin
            @(negedge clk);
            i_req = '1;
            i_src_bp = '0; i_dest_bp = '0;
            #2;
            check(count_ones(0, NM-1) == MIN,
                  $sformatf("S9 perfect matching, got %0d grants (want %0d)", count_ones(0, NM-1), MIN));
            check_orth();
            @(posedge clk);
        end
    endtask

    //=========================================================================
    // S10: random traffic invariants.
    //=========================================================================
    task automatic s_random();
        $display("[%s] S10 random traffic", NAME);
        for (int cyc = 0; cyc < 120; cyc = cyc + 1) begin
            logic [NM-1:0] req;
            logic [N-1:0]  sbp;
            logic [M-1:0]  dbp;
            req = '0; sbp = '0; dbp = '0;
            for (int n = 0; n < N; n = n + 1) begin
                rnd_word = rnd32();
                req[n*M +: M] = rnd_word[M-1:0];
                rnd_word = rnd32();
                sbp[n] = rnd_word[0];
            end
            for (int m = 0; m < M; m = m + 1) begin
                rnd_word = rnd32();
                dbp[m] = rnd_word[0];
            end
            apply(req, sbp, dbp);
            @(posedge clk);
        end
    endtask

    //=========================================================================
    // S11: source backpressure (single and all).
    //=========================================================================
    task automatic s_src_bp();
        $display("[%s] S11 source backpressure", NAME);
        // single source backpressured
        for (int cyc = 0; cyc < 50; cyc = cyc + 1) begin
            logic [N-1:0] sbp;
            sbp = '0;
            if (N >= 2) sbp[1] = 1'b1;
            apply('1, sbp, '0);
            if (N >= 2) check(o_src_vld[1] == 1'b0, "S11a bp'd src never granted");
            @(posedge clk);
        end
        // all sources backpressured -> no grant at all
        for (int cyc = 0; cyc < 50; cyc = cyc + 1) begin
            apply('1, '1, '0);
            check(|o_grant == 1'b0, "S11b no grant when all srcs bp'd");
            @(posedge clk);
        end
    endtask

    //=========================================================================
    // S12: destination backpressure (single and all).
    //=========================================================================
    task automatic s_dest_bp();
        $display("[%s] S12 destination backpressure", NAME);
        for (int cyc = 0; cyc < 50; cyc = cyc + 1) begin
            logic [M-1:0] dbp;
            dbp = '0;
            if (M >= 2) dbp[1] = 1'b1;
            apply('1, '0, dbp);
            if (M >= 2) check(o_dest_vld[1] == 1'b0, "S12a bp'd dest never granted");
            @(posedge clk);
        end
        for (int cyc = 0; cyc < 50; cyc = cyc + 1) begin
            apply('1, '0, '1);
            check(|o_grant == 1'b0, "S12b no grant when all dests bp'd");
            @(posedge clk);
        end
    endtask

    //=========================================================================
    // S13: source + destination backpressure together.
    //=========================================================================
    task automatic s_both_bp();
        $display("[%s] S13 src+dest backpressure", NAME);
        for (int cyc = 0; cyc < 50; cyc = cyc + 1) begin
            logic [N-1:0] sbp;
            logic [M-1:0] dbp;
            sbp = '0; dbp = '0;
            if (N >= 2) sbp[0] = 1'b1;
            if (M >= 2) dbp[0] = 1'b1;
            apply('1, sbp, dbp);
            if (N >= 2) check(o_src_vld[0] == 1'b0, "S13 bp'd src never granted");
            if (M >= 2) check(o_dest_vld[0] == 1'b0, "S13 bp'd dest never granted");
            @(posedge clk);
        end
    endtask

    //=========================================================================
    // S14: dynamic backpressure toggle.
    //=========================================================================
    task automatic s_bp_toggle();
        $display("[%s] S14 dynamic backpressure toggle", NAME);
        for (int cyc = 0; cyc < 100; cyc = cyc + 1) begin
            logic bp_on;
            bp_on = (cyc % 2 == 0);
            apply('1, {N{bp_on}}, '0);
            if (bp_on)
                check(|o_grant == 1'b0, "S14 no grant while bp asserted");
            @(posedge clk);
        end
    endtask

    //=========================================================================
    // S15: long-run fairness under full crossbar.
    //=========================================================================
    task automatic s_fairness();
        int src_cnt [0:N-1];
        int dst_cnt [0:M-1];
        int min_v, max_v;
        $display("[%s] S15 long-run fairness", NAME);
        for (int n = 0; n < N; n = n + 1) src_cnt[n] = 0;
        for (int m = 0; m < M; m = m + 1) dst_cnt[m] = 0;
        for (int cyc = 0; cyc < 500; cyc = cyc + 1) begin
            @(negedge clk);
            i_req = '1; i_src_bp = '0; i_dest_bp = '0;
            #2;
            for (int n = 0; n < N; n = n + 1)
                if (o_src_vld[n]) src_cnt[n] = src_cnt[n] + 1;
            for (int m = 0; m < M; m = m + 1)
                if (o_dest_vld[m]) dst_cnt[m] = dst_cnt[m] + 1;
            @(posedge clk);
        end
        min_v = src_cnt[0]; max_v = src_cnt[0];
        for (int n = 1; n < N; n = n + 1) begin
            if (src_cnt[n] < min_v) min_v = src_cnt[n];
            if (src_cnt[n] > max_v) max_v = src_cnt[n];
        end
        check(max_v <= 2*min_v + 2,
              $sformatf("S15 src fairness min=%0d max=%0d", min_v, max_v));
        min_v = dst_cnt[0]; max_v = dst_cnt[0];
        for (int m = 1; m < M; m = m + 1) begin
            if (dst_cnt[m] < min_v) min_v = dst_cnt[m];
            if (dst_cnt[m] > max_v) max_v = dst_cnt[m];
        end
        check(max_v <= 2*min_v + 2,
              $sformatf("S15 dest fairness min=%0d max=%0d", min_v, max_v));
    endtask

    //=========================================================================
    // S16: starvation freedom under a persistent request matrix.
    // Every requested (n,m) must be granted at least once within 4*N*M cycles.
    //=========================================================================
    task automatic s_starvation();
        logic [NM-1:0] pat;
        int grant_cnt [0:NM-1];
        int need_cnt;
        $display("[%s] S16 starvation freedom", NAME);
        // build a fixed random-ish pattern (about half the entries requested)
        pat = '0;
        for (int n = 0; n < N; n = n + 1) begin
            rnd_word = rnd32();
            pat[n*M +: M] = rnd_word[M-1:0];
        end
        need_cnt = 0;
        for (int b = 0; b < NM; b = b + 1) begin
            grant_cnt[b] = 0;
            if (pat[b]) need_cnt = need_cnt + 1;
        end
        // run enough cycles for every requested pair to be served
        for (int cyc = 0; cyc < 4*N*M; cyc = cyc + 1) begin
            @(negedge clk);
            i_req = pat; i_src_bp = '0; i_dest_bp = '0;
            #2;
            for (int b = 0; b < NM; b = b + 1)
                if (o_grant[b]) grant_cnt[b] = grant_cnt[b] + 1;
            @(posedge clk);
        end
        for (int b = 0; b < NM; b = b + 1)
            if (pat[b])
                check(grant_cnt[b] >= 1,
                      $sformatf("S16 requested pair %0d never granted", b));
    endtask

    //=========================================================================
    // S17: matching quality (scheduling efficiency).
    // Reports the matching size in the first cycle of full crossbar traffic
    // (where a single pass leaves "hot source" collisions) and how many cycles
    // it takes to converge to a perfect matching of size min(N,M).
    //=========================================================================
    task automatic s_matching_quality();
        int g0;
        int conv;
        $display("[%s] S17 matching quality", NAME);
        soft_reset();
        // first-cycle matching size (fresh pointers)
        @(negedge clk);
        i_req = '1; i_src_bp = '0; i_dest_bp = '0;
        #2;
        g0 = count_ones(0, NM-1);
        @(posedge clk);
        // convergence: first cycle where the match reaches size MIN
        conv = -1;
        for (int c = 0; c < 4*MIN; c = c + 1) begin
            @(negedge clk);
            i_req = '1; i_src_bp = '0; i_dest_bp = '0;
            #2;
            if (count_ones(0, NM-1) == MIN && conv < 0)
                conv = c;
            @(posedge clk);
        end
        $display("[%s] S17 first-cycle grants=%0d of %0d, converge in %0d cycles",
                 NAME, g0, MIN, conv);
        check(conv >= 0, "S17 converges to full matching");
    endtask

    //=========================================================================
    // Main sequence.
    //=========================================================================
    initial begin
        $display("[%s] start (N=%0d M=%0d PTR_RESET=%0d ITER=%0d)", NAME, N, M, PTR_RESET, ITER);

        soft_reset();
        s_idle();
        s_single();
        s_same_cycle();
        s_src_rr();
        s_src_rr_subset();
        s_dest_rr();
        s_dest_rr_subset();
        s_permutation();
        s_full_crossbar();
        s_random();
        s_src_bp();
        s_dest_bp();
        s_both_bp();
        s_bp_toggle();
        s_fairness();
        s_starvation();
        s_matching_quality();

        if (errors == 0)
            $display("[%s] PASS (%0d checks)", NAME, checks);
        else
            $display("[%s] FAIL (%0d errors / %0d checks)", NAME, errors, checks);

        tb_top.total_errors = tb_top.total_errors + errors;
        tb_top.total_checks = tb_top.total_checks + checks;
        tb_top.num_done     = tb_top.num_done + 1;
    end

endmodule

//=============================================================================
// tb_top: configuration sweep.
//=============================================================================
module tb_top;

    integer total_errors = 0;
    integer total_checks = 0;
    integer num_done     = 0;

    tb_core #(.N(8),   .M(8),   .PTR_RESET(1), .NAME("cfg_8x8"     )) c00 ();
    tb_core #(.N(6),   .M(6),   .PTR_RESET(1), .NAME("cfg_6x6"     )) c01 ();
    tb_core #(.N(8),   .M(4),   .PTR_RESET(1), .NAME("cfg_8x4"     )) c02 ();
    tb_core #(.N(4),   .M(8),   .PTR_RESET(1), .NAME("cfg_4x8"     )) c03 ();
    tb_core #(.N(6),   .M(4),   .PTR_RESET(1), .NAME("cfg_6x4"     )) c04 ();
    tb_core #(.N(4),   .M(6),   .PTR_RESET(1), .NAME("cfg_4x6"     )) c05 ();
    tb_core #(.N(5),   .M(3),   .PTR_RESET(1), .NAME("cfg_5x3"     )) c06 ();
    tb_core #(.N(3),   .M(5),   .PTR_RESET(1), .NAME("cfg_3x5"     )) c07 ();
    tb_core #(.N(2),   .M(2),   .PTR_RESET(1), .NAME("cfg_2x2"     )) c08 ();
    tb_core #(.N(16),  .M(16),  .PTR_RESET(1), .ITER(1), .NAME("cfg_16x16_i1")) c09 ();
    tb_core #(.N(8),   .M(8),   .PTR_RESET(0), .NAME("cfg_8x8_nrst")) c10 ();
    tb_core #(.N(8),   .M(8),   .PTR_RESET(1), .ITER(1), .NAME("cfg_8x8_i1"  )) c11 ();
    tb_core #(.N(8),   .M(8),   .PTR_RESET(1), .ITER(3), .NAME("cfg_8x8_i3"  )) c12 ();
    // non-power-of-two boundary sweep (around the $clog2 wrap edges)
    tb_core #(.N(9),   .M(9),   .PTR_RESET(1), .NAME("cfg_9x9"     )) c13 ();
    tb_core #(.N(9),   .M(11),  .PTR_RESET(1), .NAME("cfg_9x11"    )) c14 ();
    tb_core #(.N(8),   .M(9),   .PTR_RESET(1), .NAME("cfg_8x9"     )) c15 ();
    tb_core #(.N(11),  .M(9),   .PTR_RESET(1), .NAME("cfg_11x9"    )) c16 ();
    tb_core #(.N(7),   .M(11),  .PTR_RESET(1), .NAME("cfg_7x11"    )) c17 ();
    tb_core #(.N(15),  .M(15),  .PTR_RESET(1), .ITER(1), .NAME("cfg_15x15_i1")) c18 ();

    localparam integer NUM_CFG = 19;

    initial begin
        $display("============================================================");
        $display(" fair_arbiter comprehensive testbench");
        $display(" %0d configurations", NUM_CFG);
        $display("============================================================");

        // wait until every configuration has finished
        while (num_done < NUM_CFG)
            #10;

        $display("============================================================");
        $display(" total checks : %0d", total_checks);
        if (total_errors == 0) begin
            $display(" RESULT: ALL CONFIGURATIONS PASSED");
        end else begin
            $display(" RESULT: %0d ERRORS ACROSS ALL CONFIGURATIONS", total_errors);
        end
        $display("============================================================");
        if (total_errors != 0) $fatal(1, "TB FAILED");
        $finish;
    end

    // Watchdog.
    initial begin
        #200_000_000;
        $display("WATCHDOG TIMEOUT");
        $fatal(1, "TB timed out");
    end

endmodule
