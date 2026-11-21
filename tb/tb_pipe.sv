// tb/tb_pipe.sv - equivalence + maximality check for the pipelined variant.
//
// fair_arbiter (single cycle) and fair_arbiter_pipe run side by side on the
// same stimulus.  The pipelined outputs are one cycle later, so the golden
// outputs are registered once and compared with the pipelined outputs in the
// next cycle.  Maximality/orthogonality are checked against the request of
// the previous cycle.

`timescale 1ns/1ps

module pipe_runner #(
    parameter integer N = 10,
    parameter integer M = 10,
    parameter integer NSCHED = 4,
    parameter integer SPLIT = 0,
    parameter integer SEED = 1,
    parameter integer NCY = 2000
);
    localparam integer NM = N * M;

    logic clk = 0;
    logic rst_n = 0;
    logic [NM-1:0] req;
    logic [N-1:0] src_bp;
    logic [M-1:0] dest_bp;

    logic [NM-1:0] g_rand, p_rand;
    logic [N-1:0] g_sv, p_sv;
    logic [N-1:0][$clog2(M)-1:0] g_sp, p_sp;
    logic [M-1:0] g_dv, p_dv;
    logic [M-1:0][$clog2(N)-1:0] g_dp, p_dp;

    fair_arbiter #(.N(N), .M(M), .PTR_RESET(1), .NSCHED(NSCHED)) u_gold (
        .clk(clk), .rst_n(rst_n),
        .i_src_dest_req(req), .i_src_bp(src_bp), .i_dest_bp(dest_bp),
        .o_grant_rand_vld(g_rand), .o_grant_src_vld(g_sv),
        .o_grant_src_ptr(g_sp), .o_grant_dest_vld(g_dv),
        .o_grant_dest_ptr(g_dp)
    );

    fair_arbiter_pipe #(.N(N), .M(M), .PTR_RESET(1), .NSCHED(NSCHED),
                        .SPLIT(SPLIT)) u_pipe (
        .clk(clk), .rst_n(rst_n),
        .i_src_dest_req(req), .i_src_bp(src_bp), .i_dest_bp(dest_bp),
        .o_grant_rand_vld(p_rand), .o_grant_src_vld(p_sv),
        .o_grant_src_ptr(p_sp), .o_grant_dest_vld(p_dv),
        .o_grant_dest_ptr(p_dp)
    );

    // golden outputs and request delayed by one cycle
    logic [NM-1:0] g_rand_d, req_d;
    logic [N-1:0] g_sv_d, src_bp_d;
    logic [N-1:0][$clog2(M)-1:0] g_sp_d;
    logic [M-1:0] g_dv_d, dest_bp_d;
    logic [M-1:0][$clog2(N)-1:0] g_dp_d;

    always @(posedge clk) begin
        g_rand_d  <= g_rand;
        g_sv_d    <= g_sv;
        g_sp_d    <= g_sp;
        g_dv_d    <= g_dv;
        g_dp_d    <= g_dp;
        req_d     <= req;
        src_bp_d  <= src_bp;
        dest_bp_d <= dest_bp;
    end

    integer i, j, k, c, errors;
    integer ncy, cnt;
    integer seed;

    always #5 clk = ~clk;

    initial begin
        errors = 0;
        seed = SEED;
        rst_n = 0;
        req = '0;
        src_bp = '0;
        dest_bp = '0;
        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1;
        for (ncy = 0; ncy < NCY; ncy = ncy + 1) begin
            @(negedge clk);
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < M; j = j + 1) begin
                    c = $random(seed);
                    req[i*M+j] = (c & 3) != 0;   // ~75% density
                end
                src_bp[i] = (($random(seed) & 7) == 0);
            end
            for (j = 0; j < M; j = j + 1)
                dest_bp[j] = (($random(seed) & 7) == 0);
        end
        @(negedge clk);
        $display("RESULT n=%0dx%0d nsched=%0d split=%0d seed=%0d errors=%0d",
                 N, M, NSCHED, SPLIT, SEED, errors);
        $finish;
    end

    // compare in the middle of the cycle (after the register update)
    always @(negedge clk) begin
        if (rst_n) begin
            if (g_rand_d !== p_rand) errors = errors + 1;
            if (g_sv_d !== p_sv) errors = errors + 1;
            if (g_sp_d !== p_sp) errors = errors + 1;
            if (g_dv_d !== p_dv) errors = errors + 1;
            if (g_dp_d !== p_dp) errors = errors + 1;
            // maximality / orthogonality against the delayed request
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < M; j = j + 1) begin
                    if (req_d[i*M+j] && !src_bp_d[i] && !dest_bp_d[j]
                        && !p_sv[i] && !p_dv[j]) begin
                        errors = errors + 1;
                        if (errors < 5)
                            $display("non-max at %0d,%0d", i, j);
                    end
                    if (p_rand[i*M+j] && (!req_d[i*M+j] || src_bp_d[i] || dest_bp_d[j]))
                        errors = errors + 1;
                end
            end
            for (i = 0; i < N; i = i + 1) begin
                cnt = 0;
                for (j = 0; j < M; j = j + 1) if (p_rand[i*M+j]) cnt = cnt + 1;
                if (cnt > 1) errors = errors + 1;
            end
            for (j = 0; j < M; j = j + 1) begin
                cnt = 0;
                for (i = 0; i < N; i = i + 1) if (p_rand[i*M+j]) cnt = cnt + 1;
                if (cnt > 1) errors = errors + 1;
            end
        end
    end
endmodule

module tb_pipe_top;
    // SPLIT=0 selects the auto split inside the core
    pipe_runner #(.N(10), .M(10), .SPLIT(0), .SEED(1), .NCY(1200)) a0 ();
    pipe_runner #(.N(10), .M(10), .SPLIT(0), .SEED(2), .NCY(1200)) a1 ();
    pipe_runner #(.N(8),  .M(8),  .SPLIT(0), .SEED(3), .NCY(1200)) a2 ();
    pipe_runner #(.N(9),  .M(11), .SPLIT(0), .SEED(4), .NCY(1200)) a3 ();
    pipe_runner #(.N(11), .M(9),  .SPLIT(0), .SEED(5), .NCY(1200)) a4 ();
endmodule
