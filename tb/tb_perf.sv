//=============================================================================
// tb_perf.sv - scheduling performance benchmark
//
// For each (N, M, ITER) configuration, measures over a LONG run:
//   first      : matches in the first cycle of full-crossbar traffic
//   converge   : cycles until the matching reaches min(N,M)
//   full       : average matches/cycle under full-crossbar (100% load)
//   bernoulli  : average matches/cycle under Bernoulli(0.5) random traffic
//
// "matches/cycle" is the number of source->dest grants issued in one cycle,
// i.e. how many requests the scheduler dispatches per beat (max = min(N,M)).
//=============================================================================
`timescale 1ns/1ps

module perf_runner #(
    parameter integer N    = 8,
    parameter integer M    = 8,
    parameter integer ITER = 2
) ();
    localparam integer CWN = $clog2(N);
    localparam integer CWM = $clog2(M);
    localparam integer NM  = N * M;
    localparam integer MIN = (N < M) ? N : M;

    logic                    clk, rst_n;
    logic [NM-1:0]           i_req;
    logic [N-1:0]            i_src_bp;
    logic [M-1:0]            i_dest_bp;
    logic [NM-1:0]           o_grant;
    logic [N-1:0]            o_src_vld;
    logic [N-1:0][CWM-1:0]   o_src_ptr;
    logic [M-1:0]            o_dest_vld;
    logic [M-1:0][CWN-1:0]   o_dest_ptr;
    logic [31:0]             rw;

    localparam integer WARMUP = 100;
    localparam integer NCY    = 1500;

    integer seed = 12345;
    integer first_cnt;
    integer converge;
    integer full_sum;
    integer bern_sum;
    integer g;

    fair_arbiter #(.N(N), .M(M), .PTR_RESET(1), .ITER(ITER)) dut (
        .clk(clk), .rst_n(rst_n),
        .i_src_dest_req(i_req), .i_src_bp(i_src_bp), .i_dest_bp(i_dest_bp),
        .o_grant_rand_vld(o_grant), .o_grant_src_vld(o_src_vld), .o_grant_src_ptr(o_src_ptr),
        .o_grant_dest_vld(o_dest_vld), .o_grant_dest_ptr(o_dest_ptr)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    function automatic integer count_g();
        integer c;
        c = 0;
        for (integer k = 0; k < NM; k = k + 1)
            if (o_grant[k]) c = c + 1;
        return c;
    endfunction

    function automatic integer rnd();
        seed = (seed * 1103515245 + 12345) & 32'h7fff_ffff;
        return seed;
    endfunction

    initial begin
        // reset
        rst_n = 1'b0; i_req = '0; i_src_bp = '0; i_dest_bp = '0;
        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // ---- full crossbar ----
        converge = -1;
        full_sum = 0;
        for (int c = 0; c < WARMUP + NCY; c = c + 1) begin
            @(negedge clk);
            i_req = '1; i_src_bp = '0; i_dest_bp = '0;
            #2;
            g = count_g();
            if (c == 0) first_cnt = g;
            if (c >= WARMUP) full_sum = full_sum + g;
            if (converge < 0 && g == MIN) converge = c;
            @(posedge clk);
        end

        // ---- Bernoulli(0.5) random traffic ----
        bern_sum = 0;
        for (int c = 0; c < NCY; c = c + 1) begin
            @(negedge clk);
            for (int n = 0; n < N; n = n + 1) begin
                rw = rnd();
                i_req[n*M +: M] = rw[M-1:0];
            end
            i_src_bp = '0; i_dest_bp = '0;
            #2;
            bern_sum = bern_sum + count_g();
            @(posedge clk);
        end

        $display("  %0dx%-0d  ITER=%0d | first=%0d  converge=%0d | full=%.2f/%0d (%.0f%%) | bern=%.2f/%0d (%.0f%%)",
                 N, M, ITER, first_cnt, converge,
                 full_sum * 1.0 / NCY, MIN, 100.0 * full_sum / (NCY * MIN),
                 bern_sum * 1.0 / NCY, MIN, 100.0 * bern_sum / (NCY * MIN));

        tb_perf_top.num_done = tb_perf_top.num_done + 1;
    end
endmodule

module tb_perf_top;

    integer num_done = 0;

    perf_runner #(.N(4),  .M(4),  .ITER(1)) p00 ();
    perf_runner #(.N(4),  .M(4),  .ITER(2)) p01 ();
    perf_runner #(.N(4),  .M(4),  .ITER(3)) p02 ();
    perf_runner #(.N(8),  .M(8),  .ITER(1)) p03 ();
    perf_runner #(.N(8),  .M(8),  .ITER(2)) p04 ();
    perf_runner #(.N(8),  .M(8),  .ITER(3)) p05 ();
    perf_runner #(.N(16), .M(16), .ITER(1)) p06 ();
    perf_runner #(.N(8),  .M(4),  .ITER(1)) p08 ();
    perf_runner #(.N(8),  .M(4),  .ITER(2)) p09 ();
    perf_runner #(.N(4),  .M(8),  .ITER(1)) p10 ();
    perf_runner #(.N(4),  .M(8),  .ITER(2)) p11 ();
    perf_runner #(.N(9),  .M(11), .ITER(1)) p12 ();
    perf_runner #(.N(9),  .M(11), .ITER(2)) p13 ();

    localparam integer NUM = 13;

    initial begin
        $display("=====================================================================");
        $display(" fair_arbiter performance benchmark  (PTR_RESET=1, per config 1600 cyc)");
        $display("   full   = full-crossbar 100%% load ;  bern = Bernoulli(0.5)");
        $display("   ratio  = matches/cycle over min(N,M)  (max = 100%%)");
        $display("---------------------------------------------------------------------");
        $display("  NxM  ITER | first converge | full match/cyc | bern match/cyc");

        while (num_done < NUM)
            #10;

        $display("=====================================================================");
        $finish;
    end

endmodule
