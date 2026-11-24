//=============================================================================
// tb_soak.sv - long-running randomized soak test.
//
// Purpose: run the arbiter for thousands of cycles with randomized traffic,
// randomized source/destination backpressure and changing traffic modes, and
// check the hard invariants EVERY cycle:
//
//   1. orthogonality: at most one grant per source and per destination;
//   2. output consistency: o_grant_src_vld / o_grant_dest_vld / ptr fields
//      agree with o_grant_rand_vld;
//   3. grant implies effective request (req & ~src_bp & ~dest_bp);
//   4. backpressured sources/destinations are never granted;
//   5. MAXIMALITY: no pair (i,j) with eff_req[i][j]=1 and BOTH source i and
//      destination j idle.  This is the user's hard criterion, checked under
//      backpressure as well (a backpressured port is not "idle").
//
// Traffic modes rotate every 500 cycles: Bernoulli at a random density, full
// crossbar, hot source, hot destination, near-diagonal, and stripes.  The
// destination/source backpressure is re-randomized every cycle at 10%.
//
// Two tops are provided:
//   tb_soak_top   : 8x8 A1, 9x9 A1, 10x10 A0 - 1500 cycles each (max 10x10)
//   tb_soak10_top : 10x10 default (ITER=4, AUGMENT=1) - 20000 cycles
//=============================================================================
`timescale 1ns/1ps

module soak_runner #(
    parameter integer N       = 8,
    parameter integer M       = 8,
    parameter integer ITER    = 4,
    parameter integer AUGMENT = 1,
    parameter integer CYCLES  = 1500,
    parameter integer SEED    = 1
) (
    output reg done
);
    localparam integer NM  = N*M;
    localparam integer CWN = $clog2(N);
    localparam integer CWM = $clog2(M);
    localparam integer MINNM = (N < M) ? N : M;

    logic clk, rst_n;
    logic [NM-1:0]          i_req;
    logic [N-1:0]           i_src_bp;
    logic [M-1:0]           i_dest_bp;
    logic [NM-1:0]          o_grant;
    logic [N-1:0]           o_src_vld;
    logic [N-1:0][CWM-1:0]  o_src_ptr;
    logic [M-1:0]           o_dest_vld;
    logic [M-1:0][CWN-1:0]  o_dest_ptr;

`ifdef FAIR_DUT
    fair_arbiter_fair #(.N(N), .M(M), .PTR_RESET(1), .ITER(ITER), .AUGMENT(AUGMENT)) dut (
`else
    fair_arbiter #(.N(N), .M(M), .PTR_RESET(1), .ITER(ITER), .AUGMENT(AUGMENT)) dut (
`endif
        .clk(clk), .rst_n(rst_n),
        .i_src_dest_req(i_req), .i_src_bp(i_src_bp), .i_dest_bp(i_dest_bp),
        .o_grant_rand_vld(o_grant),
        .o_grant_src_vld(o_src_vld), .o_grant_src_ptr(o_src_ptr),
        .o_grant_dest_vld(o_dest_vld), .o_grant_dest_ptr(o_dest_ptr));

    initial begin clk = 0; forever #5 clk = ~clk; end

    integer seed = SEED;
    function automatic integer rnd();
        seed = (seed * 1103515245 + 12345) & 32'h7fff_ffff;
        return seed;
    endfunction

    // error counters
    integer nonmax_cycles, wasted_pairs, orth_err, cons_err, impl_err, bp_err;
    integer cycles_run, total_grants, eff_pairs;

    logic [NM-1:0] req;
    logic [NM-1:0] eff;

    task automatic check_cycle();
        integer wasted_this;
        integer g;
        begin
            // effective request (what the arbiter is allowed to serve)
            for (int i = 0; i < N; i++)
                for (int j = 0; j < M; j++)
                    eff[i*M+j] = req[i*M+j] & ~i_src_bp[i] & ~i_dest_bp[j];

            // ---- row checks ----
            for (int i = 0; i < N; i++) begin
                integer rc;
                rc = 0;
                for (int j = 0; j < M; j++) begin
                    if (o_grant[i*M+j]) begin
                        rc++;
                        if (!eff[i*M+j]) impl_err++;
                    end
                end
                if (rc > 1) orth_err++;
                if (o_src_vld[i] !== (rc != 0)) cons_err++;
                if (i_src_bp[i] && o_src_vld[i]) bp_err++;
                if (rc == 1) begin
                    for (int j = 0; j < M; j++)
                        if (o_grant[i*M+j] && (o_src_ptr[i] != j)) cons_err++;
                end
            end

            // ---- column checks ----
            for (int j = 0; j < M; j++) begin
                integer cc;
                cc = 0;
                for (int i = 0; i < N; i++)
                    if (o_grant[i*M+j]) cc++;
                if (cc > 1) orth_err++;
                if (o_dest_vld[j] !== (cc != 0)) cons_err++;
                if (i_dest_bp[j] && o_dest_vld[j]) bp_err++;
                if (cc == 1) begin
                    for (int i = 0; i < N; i++)
                        if (o_grant[i*M+j] && (o_dest_ptr[j] != i)) cons_err++;
                end
            end

            // ---- maximality under effective requests ----
            wasted_this = 0;
            for (int i = 0; i < N; i++)
                for (int j = 0; j < M; j++) begin
                    if (eff[i*M+j]) eff_pairs++;
                    if (eff[i*M+j] && !o_src_vld[i] && !o_dest_vld[j])
                        wasted_this++;
                end
            wasted_pairs += wasted_this;
            if (wasted_this != 0) nonmax_cycles++;

            // ---- grant count ----
            g = 0;
            for (int b = 0; b < NM; b++) if (o_grant[b]) g++;
            total_grants += g;
            cycles_run++;
        end
    endtask

    integer mode;
    integer dens;
    initial begin
        rst_n = 0; i_req = '0; i_src_bp = '0; i_dest_bp = '0;
        repeat (2) @(posedge clk);
        rst_n = 1; @(posedge clk);

        done = 0;
        nonmax_cycles = 0; wasted_pairs = 0; orth_err = 0; cons_err = 0;
        impl_err = 0; bp_err = 0; cycles_run = 0; total_grants = 0; eff_pairs = 0;

        for (int c = 0; c < CYCLES; c++) begin
            @(negedge clk);

            mode = (c / 500) % 6;
            dens = 5 + (rnd() % 95);
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < M; j++) begin
                    case (mode)
                        0: req[i*M+j] = ((rnd() % 100) < dens);
                        1: req[i*M+j] = 1'b1;                       // full crossbar
                        2: req[i*M+j] = (i == 0) ? 1'b1 :            // hot source
                                         ((rnd() % 100) < 20);
                        3: req[i*M+j] = (j == 0) ? 1'b1 :            // hot dest
                                         ((rnd() % 100) < 20);
                        4: req[i*M+j] = (j == (i * M) / N) ? 1'b1 :  // near diagonal
                                         ((rnd() % 100) < 10);
                        default: req[i*M+j] = (((i + j) % 3) == 0);  // stripes
                    endcase
                end
            end

            for (int i = 0; i < N; i++) i_src_bp[i] = ((rnd() % 100) < 10);
            for (int j = 0; j < M; j++) i_dest_bp[j] = ((rnd() % 100) < 10);

            i_req = req;
            #2;
            check_cycle();
            @(posedge clk);
        end

        $display("[%0dx%0d ITER=%0d AUG=%0d] cycles=%0d eff_pairs=%0d grants=%0d avg=%.2f/%0d (%.1f%%)",
                 N, M, ITER, AUGMENT, cycles_run, eff_pairs, total_grants,
                 total_grants * 1.0 / cycles_run, MINNM,
                 100.0 * total_grants / (cycles_run * MINNM));
        $display("    nonmax_cycles=%0d wasted_pairs=%0d orth=%0d cons=%0d impl=%0d bp=%0d  %s",
                 nonmax_cycles, wasted_pairs, orth_err, cons_err, impl_err, bp_err,
                 ((nonmax_cycles + orth_err + cons_err + impl_err + bp_err) == 0)
                     ? "PASS" : "FAIL");

        done = 1;
    end
endmodule

module tb_soak_top;
    wire d0, d1, d2;

    soak_runner #(.N(8),  .M(8),  .ITER(4), .AUGMENT(1), .CYCLES(1500), .SEED(11)) s0 (.done(d0));
    soak_runner #(.N(9),  .M(9),  .ITER(4), .AUGMENT(1), .CYCLES(1500), .SEED(22)) s1 (.done(d1));
    soak_runner #(.N(10), .M(10), .ITER(4), .AUGMENT(0), .CYCLES(1500), .SEED(33)) s2 (.done(d2));

    initial begin
        #100;
        while (!(d0 && d1 && d2)) #10;
        $display("=== soak (3 shapes, max 10x10) done ===");
        $finish;
    end
endmodule

module tb_soak10_top;
    wire d0;

    soak_runner #(.N(10), .M(10), .ITER(4), .AUGMENT(1), .CYCLES(20000), .SEED(99)) s0 (.done(d0));

    initial begin
        #100;
        while (!d0) #10;
        $display("=== 10x10 20k-cycle soak done ===");
        $finish;
    end
endmodule
