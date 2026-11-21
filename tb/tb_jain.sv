// tb/tb_jain.sv - multi-source fairness measurement on the RTL.
//
// Runs a persistent request pattern for N_CYC cycles, counts grants per
// (source,destination) pair, and prints the average Jain index of each
// source's destination counts and each destination's source counts.
// Compares NSCHED = 1 / 2 / 4 for three seeds.

`timescale 1ns/1ps

module jain_runner #(
    parameter integer N = 10,
    parameter integer M = 10,
    parameter integer NSCHED = 4,
    parameter integer N_CYC = 3000,
    parameter integer SEED = 3,
    parameter integer MODE = 0,   // 0 = LFSR pattern, 1 = K-regular
    parameter integer DEG = 5     // K for MODE=1
);
    logic clk = 0;
    logic rst_n = 0;
    logic [N*M-1:0] req;
    logic [N-1:0] src_bp = '0;
    logic [M-1:0] dest_bp = '0;
    logic [N*M-1:0] g_rand;
    logic [N-1:0] g_src;
    logic [N-1:0][$clog2(M)-1:0] g_sptr;
    logic [M-1:0] g_dst;
    logic [M-1:0][$clog2(N)-1:0] g_dptr;

    integer cnt [N][M];
    integer i, j, c, k;
    integer ssum, sq, nsrc, dsum, dq, ndst;
    real jsum_src, jsum_dst, jv;

`ifdef GREEDY_DUT
    fair_arbiter_greedy #(.N(N), .M(M), .PTR_RESET(1), .NSCHED(NSCHED)) dut (
`elsif WTF_DUT
    fair_arbiter_wtf #(.N(N), .M(M), .PTR_RESET(1), .NSCHED(NSCHED)) dut (
`else
    fair_arbiter #(.N(N), .M(M), .PTR_RESET(1), .NSCHED(NSCHED)) dut (
`endif
        .clk(clk), .rst_n(rst_n),
        .i_src_dest_req(req), .i_src_bp(src_bp), .i_dest_bp(dest_bp),
        .o_grant_rand_vld(g_rand), .o_grant_src_vld(g_src),
        .o_grant_src_ptr(g_sptr), .o_grant_dest_vld(g_dst),
        .o_grant_dest_ptr(g_dptr)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst_n) begin
            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < M; j = j + 1)
                    if (g_rand[i*M+j]) cnt[i][j] = cnt[i][j] + 1;
        end
    end

    initial begin
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < M; j = j + 1) cnt[i][j] = 0;
        if (MODE == 0) begin
            c = SEED;
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < M; j = j + 1) begin
                    c = c * 1103515245 + 12345;
                    req[i*M+j] = ((c >> 16) & 1);
                end
                if (!(|req[i*M +: M])) req[i*M] = 1'b1;
            end
        end else begin
            // K-regular circulant: source i asks (i .. i+K-1) mod M, so every
            // source and every destination has degree K (saturated + uniform).
            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < M; j = j + 1)
                    req[i*M+j] = (((j + M - i) % M) < DEG);
        end
        #20 rst_n = 1'b1;
        repeat (N_CYC) @(posedge clk);
        #2;

        jsum_src = 0.0; nsrc = 0;
        for (i = 0; i < N; i = i + 1) begin
            ssum = 0; sq = 0; c = 0;
            for (j = 0; j < M; j = j + 1) begin
                if (req[i*M+j]) begin
                    ssum = ssum + cnt[i][j];
                    sq = sq + cnt[i][j] * cnt[i][j];
                    c = c + 1;
                end
            end
            if (c > 1 && sq > 0) begin
                jv = (1.0 * ssum * ssum) / (1.0 * c * sq);
                jsum_src = jsum_src + jv;
                nsrc = nsrc + 1;
            end
        end
        jsum_dst = 0.0; ndst = 0;
        for (j = 0; j < M; j = j + 1) begin
            dsum = 0; dq = 0; c = 0;
            for (i = 0; i < N; i = i + 1) begin
                if (req[i*M+j]) begin
                    dsum = dsum + cnt[i][j];
                    dq = dq + cnt[i][j] * cnt[i][j];
                    c = c + 1;
                end
            end
            if (c > 1 && dq > 0) begin
                jv = (1.0 * dsum * dsum) / (1.0 * c * dq);
                jsum_dst = jsum_dst + jv;
                ndst = ndst + 1;
            end
        end
        if (nsrc > 0 && ndst > 0)
            $display("RESULT mode=%0d deg=%0d seed=%0d nsched=%0d src_jain=%.3f dst_jain=%.3f",
                     MODE, DEG, SEED, NSCHED, jsum_src / nsrc, jsum_dst / ndst);
        $finish;
    end
endmodule

module tb_jain_top;
    jain_runner #(.N(10), .M(10), .NSCHED(1), .SEED(3)) u0 ();
    jain_runner #(.N(10), .M(10), .NSCHED(2), .SEED(3)) u1 ();
    jain_runner #(.N(10), .M(10), .NSCHED(4), .SEED(3)) u2 ();
    jain_runner #(.N(10), .M(10), .NSCHED(1), .SEED(5)) u3 ();
    jain_runner #(.N(10), .M(10), .NSCHED(2), .SEED(5)) u4 ();
    jain_runner #(.N(10), .M(10), .NSCHED(4), .SEED(5)) u5 ();
    jain_runner #(.N(10), .M(10), .NSCHED(1), .SEED(7)) u6 ();
    jain_runner #(.N(10), .M(10), .NSCHED(2), .SEED(7)) u7 ();
    jain_runner #(.N(10), .M(10), .NSCHED(4), .SEED(7)) u8 ();

    // saturated uniform traffic: K-regular circulant
    jain_runner #(.N(10), .M(10), .NSCHED(1), .MODE(1), .DEG(8)) r0 ();
    jain_runner #(.N(10), .M(10), .NSCHED(2), .MODE(1), .DEG(8)) r1 ();
    jain_runner #(.N(10), .M(10), .NSCHED(4), .MODE(1), .DEG(8)) r2 ();
    jain_runner #(.N(10), .M(10), .NSCHED(1), .MODE(1), .DEG(5)) r3 ();
    jain_runner #(.N(10), .M(10), .NSCHED(2), .MODE(1), .DEG(5)) r4 ();
    jain_runner #(.N(10), .M(10), .NSCHED(4), .MODE(1), .DEG(5)) r5 ();
    jain_runner #(.N(10), .M(10), .NSCHED(1), .MODE(1), .DEG(3)) r6 ();
    jain_runner #(.N(10), .M(10), .NSCHED(2), .MODE(1), .DEG(3)) r7 ();
    jain_runner #(.N(10), .M(10), .NSCHED(4), .MODE(1), .DEG(3)) r8 ();
endmodule
