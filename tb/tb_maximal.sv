//=============================================================================
// tb_maximal.sv - maximality / orthogonality checker.
//
// User criterion (verbatim intent): a scheduled cycle must never leave a
// requested pair unserved when BOTH its endpoints are idle.  In graph terms
// the output matching must be MAXIMAL:
//
//     error  <=>  exists (i,j): req[i][j]=1
//                              and source i has no grant
//                              and dest   j has no grant
//
// The checker also verifies:
//   - orthogonality: at most one grant per source and per destination;
//   - output consistency: o_grant_src_vld / o_grant_dest_vld /
//     o_grant_src_ptr / o_grant_dest_ptr agree with o_grant_rand_vld;
//   - multiple traffic shapes: random densities, full crossbar, staircases,
//     diagonals, hot source, hot destination, checkerboard, sparse and
//     permutation patterns.
//
// A broad set of N/M shapes is instantiated, including N<M, N>M, N=M,
// non-power-of-two (9, 11, 15) and the requested 10x10.
//=============================================================================
`timescale 1ns/1ps

module maximal_runner #(
    parameter integer N = 8,
    parameter integer M = 8,
    parameter integer ITER = 4,
    parameter integer AUGMENT = 1,
    parameter integer RAND_CYC = 100,
    parameter integer PAT_CYC = 6,
    parameter integer SEED = 1
) ();
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

`ifdef GREEDY_DUT
    fair_arbiter_greedy #(.N(N), .M(M), .PTR_RESET(1), .ITER(ITER), .AUGMENT(AUGMENT)) dut (
`elsif WTF_DUT
    fair_arbiter_wtf #(.N(N), .M(M), .PTR_RESET(1), .ITER(ITER), .AUGMENT(AUGMENT)) dut (
`elsif FAIR_DUT
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
    function automatic logic [31:0] rnd();
        seed = (seed * 1103515245 + 12345) & 32'h7fff_ffff;
        return seed;
    endfunction

    // Error counters (one cycle is reported once even with several wasted pairs)
    integer bad_cycles, wasted_pairs, orth_viol, cons_viol;
    integer cycles, total_grants;

    //-------------------------------------------------------------------------
    // Check the current combinational output for one cycle.
    //-------------------------------------------------------------------------
    task automatic check_cycle(input logic [NM-1:0] req, input string tag);
        integer wasted_this;
        begin
            // ---- orthogonality + vld/ptr consistency ----
            for (int i = 0; i < N; i++) begin
                integer rc;
                rc = 0;
                for (int j = 0; j < M; j++)
                    if (o_grant[i*M+j]) rc++;
                if (rc > 1) begin
                    orth_viol++;
                    $display("  ORTH row %0d has %0d grants (%s)", i, rc, tag);
                end
                if (o_src_vld[i] !== (rc != 0)) begin
                    cons_viol++;
                    $display("  CONS src_vld[%0d]=%b but row count=%0d (%s)",
                             i, o_src_vld[i], rc, tag);
                end
                if (rc == 1) begin
                    for (int j = 0; j < M; j++)
                        if (o_grant[i*M+j] && (o_src_ptr[i] != j)) begin
                            cons_viol++;
                            $display("  CONS src_ptr[%0d]=%0d but grant dest=%0d (%s)",
                                     i, o_src_ptr[i], j, tag);
                        end
                end
            end
            for (int j = 0; j < M; j++) begin
                integer cc;
                cc = 0;
                for (int i = 0; i < N; i++)
                    if (o_grant[i*M+j]) cc++;
                if (cc > 1) begin
                    orth_viol++;
                    $display("  ORTH col %0d has %0d grants (%s)", j, cc, tag);
                end
                if (o_dest_vld[j] !== (cc != 0)) begin
                    cons_viol++;
                    $display("  CONS dest_vld[%0d]=%b but col count=%0d (%s)",
                             j, o_dest_vld[j], cc, tag);
                end
                if (cc == 1) begin
                    for (int i = 0; i < N; i++)
                        if (o_grant[i*M+j] && (o_dest_ptr[j] != i)) begin
                            cons_viol++;
                            $display("  CONS dest_ptr[%0d]=%0d but grant source=%0d (%s)",
                                     j, o_dest_ptr[j], i, tag);
                        end
                end
            end

            // ---- maximality: no requested pair with both ends idle ----
            wasted_this = 0;
            for (int i = 0; i < N; i++)
                for (int j = 0; j < M; j++)
                    if (req[i*M+j] && !o_src_vld[i] && !o_dest_vld[j]) begin
                        wasted_this++;
                        if (wasted_pairs < 4)
                            $display("  NON-MAXIMAL: src %0d -> dst %0d wasted (%s)",
                                     i, j, tag);
                    end
            wasted_pairs += wasted_this;
            if (wasted_this != 0) bad_cycles++;

            // ---- size accounting ----
            begin
                integer g;
                g = 0;
                for (int b = 0; b < NM; b++) if (o_grant[b]) g++;
                total_grants += g;
            end
            cycles++;
        end
    endtask

    //-------------------------------------------------------------------------
    // Drive one pattern for ncyc cycles and check every cycle.
    //-------------------------------------------------------------------------
    task automatic run_pat(input logic [NM-1:0] pat, input integer ncyc,
                           input string tag);
        begin
            repeat (ncyc) begin
                @(negedge clk);
                i_req = pat; i_src_bp = '0; i_dest_bp = '0;
                #2;
                check_cycle(pat, tag);
                @(posedge clk);
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // Random patterns at a given density.
    //-------------------------------------------------------------------------
    task automatic run_rand(input integer ncyc, input integer pct, input string tag);
        logic [NM-1:0] p;
        begin
            repeat (ncyc) begin
                for (int i = 0; i < N; i++) begin
                    for (int j = 0; j < M; j++) begin
                        logic [31:0] w;
                        w = rnd();
                        p[i*M+j] = (($unsigned(w) % 100) < pct) ? 1'b1 : 1'b0;
                    end
                end
                @(negedge clk);
                i_req = p; i_src_bp = '0; i_dest_bp = '0;
                #2;
                check_cycle(p, tag);
                @(posedge clk);
            end
        end
    endtask

    integer i0, j0;
    logic [NM-1:0] pat;

    initial begin
        rst_n = 0; i_req = '0; i_src_bp = '0; i_dest_bp = '0;
        repeat (2) @(posedge clk);
        rst_n = 1; @(posedge clk);

        bad_cycles = 0; wasted_pairs = 0; orth_viol = 0; cons_viol = 0;
        cycles = 0; total_grants = 0;

        // ---- deterministic / adversarial patterns ----
        pat = '1;
        run_pat(pat, PAT_CYC, "full-crossbar");

        pat = '0;
        run_pat(pat, 1, "idle");

        pat = '0;
        for (int i = 0; i < N; i++)
            for (int j = 0; j < M; j++)
                if (j >= (i * M / N)) pat[i*M+j] = 1'b1;
        run_pat(pat, PAT_CYC, "staircase-up");

        pat = '0;
        for (int i = 0; i < N; i++)
            for (int j = 0; j < M; j++)
                if (j <= (i * M / N)) pat[i*M+j] = 1'b1;
        run_pat(pat, PAT_CYC, "staircase-down");

        pat = '0;
        for (int i = 0; i < N; i++) begin
            j0 = (i * M) / N;
            pat[i*M+j0] = 1'b1;
        end
        run_pat(pat, PAT_CYC, "diagonal");

        pat = '0;
        for (int i = 0; i < N; i++) begin
            j0 = M - 1 - ((i * M) / N);
            if (j0 < 0) j0 = 0;
            pat[i*M+j0] = 1'b1;
        end
        run_pat(pat, PAT_CYC, "anti-diagonal");

        pat = '0;
        for (int j = 0; j < M; j++) pat[0*M+j] = 1'b1;
        run_pat(pat, PAT_CYC, "hot-source");

        pat = '0;
        for (int i = 0; i < N; i++) pat[i*M+0] = 1'b1;
        run_pat(pat, PAT_CYC, "hot-dest");

        pat = '0;
        for (int i = 0; i < N; i++)
            for (int j = 0; j < M; j++)
                if ((i % 2) == (j % 2)) pat[i*M+j] = 1'b1;
        run_pat(pat, PAT_CYC, "checkerboard");

        pat = '0;
        for (int i = 0; i < N; i++)
            for (int j = 0; j < M; j++)
                if ((i % 3) == (j % 3)) pat[i*M+j] = 1'b1;
        run_pat(pat, PAT_CYC, "mod3-blocks");

        pat = '0;
        for (int i = 0; i < N; i++) begin
            j0 = (i * 7 + 3) % M;
            pat[i*M+j0] = 1'b1;
        end
        run_pat(pat, PAT_CYC, "sparse");

        // two full rows and two full columns: high contention on both sides
        pat = '0;
        for (int j = 0; j < M; j++) begin
            pat[0*M+j] = 1'b1;
            pat[(N-1)*M+j] = 1'b1;
        end
        for (int i = 0; i < N; i++) begin
            pat[i*M+0] = 1'b1;
            pat[i*M+(M-1)] = 1'b1;
        end
        run_pat(pat, PAT_CYC, "two-rows-two-cols");

        // single pair at both corners
        pat = '0;
        pat[0*M + (M-1)] = 1'b1;
        pat[(N-1)*M + 0] = 1'b1;
        run_pat(pat, PAT_CYC, "corners");

        // ---- random densities ----
        run_rand(RAND_CYC, 5,  "rand05");
        run_rand(RAND_CYC, 10, "rand10");
        run_rand(RAND_CYC, 25, "rand25");
        run_rand(RAND_CYC, 50, "rand50");
        run_rand(RAND_CYC, 75, "rand75");
        run_rand(RAND_CYC, 90, "rand90");
        run_rand(RAND_CYC, 99, "rand99");

        // ---- report ----
        $display("[%0dx%0d ITER=%0d AUG=%0d] cycles=%0d non-max-cycles=%0d wasted-pairs=%0d orth=%0d cons=%0d size=%.2f/%0d (%.1f%%)",
                 N, M, ITER, AUGMENT,
                 cycles, bad_cycles, wasted_pairs, orth_viol, cons_viol,
                 total_grants * 1.0 / cycles, MINNM,
                 100.0 * total_grants / (cycles * MINNM));

        tb_maximal_top.num_done = tb_maximal_top.num_done + 1;
    end
endmodule

module tb_maximal_top;
    integer num_done = 0;

    // N = M, powers of two
    maximal_runner #(.N(2),  .M(2),  .ITER(4), .AUGMENT(1), .SEED(2))  c00 ();
    maximal_runner #(.N(4),  .M(4),  .ITER(4), .AUGMENT(1), .SEED(4))  c01 ();
    maximal_runner #(.N(8),  .M(8),  .ITER(4), .AUGMENT(1), .SEED(8))  c02 ();
    maximal_runner #(.N(8),  .M(8),  .ITER(1), .AUGMENT(0), .SEED(9))  c03 ();
    maximal_runner #(.N(16), .M(16), .ITER(4), .AUGMENT(1), .SEED(16)) c04 ();

    // N < M (more destinations than sources)
    maximal_runner #(.N(3),  .M(5),  .ITER(4), .AUGMENT(1), .SEED(35)) c05 ();
    maximal_runner #(.N(5),  .M(7),  .ITER(4), .AUGMENT(1), .SEED(57)) c06 ();
    maximal_runner #(.N(8),  .M(9),  .ITER(4), .AUGMENT(1), .SEED(89)) c07 ();
    maximal_runner #(.N(9),  .M(11), .ITER(4), .AUGMENT(1), .SEED(91)) c08 ();
    maximal_runner #(.N(10), .M(10), .ITER(4), .AUGMENT(1), .SEED(101)) c09 ();
    maximal_runner #(.N(10), .M(10), .ITER(1), .AUGMENT(0), .SEED(102)) c10 ();
    maximal_runner #(.N(10), .M(10), .ITER(1), .AUGMENT(1), .SEED(103)) c11 ();

    // N > M
    maximal_runner #(.N(5),  .M(3),  .ITER(4), .AUGMENT(1), .SEED(53)) c12 ();
    maximal_runner #(.N(11), .M(9),  .ITER(4), .AUGMENT(1), .SEED(119)) c13 ();
    maximal_runner #(.N(12), .M(7),  .ITER(4), .AUGMENT(1), .SEED(127)) c14 ();

    // non-power-of-two, larger
    maximal_runner #(.N(13), .M(13), .ITER(4), .AUGMENT(1), .SEED(131)) c15 ();
    maximal_runner #(.N(15), .M(15), .ITER(4), .AUGMENT(1), .SEED(151)) c16 ();
    maximal_runner #(.N(7),  .M(11), .ITER(4), .AUGMENT(1), .SEED(711)) c17 ();

    localparam NUM = 18;

    initial begin
        while (num_done < NUM) #10;
        $finish;
    end
endmodule
