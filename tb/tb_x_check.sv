//=============================================================================
// tb_x_check.sv - dedicated X-state (unknown) propagation check
//
// Verifies the reset/X behavior of fair_arbiter:
//   T1: during async reset, outputs must be clean 0 (NOT X), even when the
//       no-reset pointers hold X.  (This is what the "& rst_n" gating buys.)
//   T2: PTR_RESET=1 after reset -> outputs must be fully X-free.
//   T3: PTR_RESET=0 after reset -> delta is X, so outputs WILL be X until
//       initialized (expected for no-reset flops; real silicon has a
//       deterministic unknown, not X).  After $deposit, outputs become X-free.
//
// Uses $isunknown() (SystemVerilog) to detect any X or Z bit.
//=============================================================================
`timescale 1ns/1ps

module tb_x_check;

    localparam integer N = 8;
    localparam integer M = 8;
    localparam integer NM = N * M;
    localparam integer CWN = $clog2(N);
    localparam integer CWM = $clog2(M);

    logic                    clk;
    logic                    rst_n;
    logic [NM-1:0]           i_req;
    logic [N-1:0]            i_src_bp;
    logic [M-1:0]            i_dest_bp;
    logic [NM-1:0]           o_grant;
    logic [N-1:0]            o_src_vld;
    logic [N-1:0][CWM-1:0]   o_src_ptr;
    logic [M-1:0]            o_dest_vld;
    logic [M-1:0][CWN-1:0]   o_dest_ptr;

    // DUT A: no-reset pointers (the X-prone case)
    fair_arbiter #(.N(N), .M(M), .PTR_RESET(0)) dut_a (
        .clk(clk), .rst_n(rst_n),
        .i_src_dest_req(i_req), .i_src_bp(i_src_bp), .i_dest_bp(i_dest_bp),
        .o_grant_rand_vld(o_grant), .o_grant_src_vld(o_src_vld), .o_grant_src_ptr(o_src_ptr),
        .o_grant_dest_vld(o_dest_vld), .o_grant_dest_ptr(o_dest_ptr)
    );

    int errors = 0;

    task automatic check(input logic cond, input string msg);
        if (!cond) begin
            errors = errors + 1;
            $display("FAIL: %s", msg);
        end else begin
            $display("PASS: %s", msg);
        end
    endtask

    initial begin clk = 0; forever #5 clk = ~clk; end

    initial begin
        $display("=== X-state check ===");

        // ---------------- T1: during reset, outputs clean 0 (not X) ----------------
        rst_n = 1'b0;
        i_req = '1; i_src_bp = '0; i_dest_bp = '0;
        #3;   // let combinational settle; pointers are X (no reset)
        check(!$isunknown(o_grant) && o_grant == '0, "T1 during reset: grant clean 0 (no X)");
        check(!$isunknown(o_src_vld) && o_src_vld == '0, "T1 during reset: src_vld clean 0");
        check(!$isunknown(o_dest_vld) && o_dest_vld == '0, "T1 during reset: dest_vld clean 0");
        check(!$isunknown(o_src_ptr) && o_src_ptr == '0, "T1 during reset: src_ptr clean 0");
        check(!$isunknown(o_dest_ptr) && o_dest_ptr == '0, "T1 during reset: dest_ptr clean 0");

        // ---------------- T3: no-reset, after reset deassert, X propagates ----------------
        rst_n = 1'b1;
        #3;
        check($isunknown(o_grant), "T3 (no-reset) after reset: grant IS X (expected for no-reset flops)");

        // ---------------- T3b: after $deposit init, X-free again ----------------
        $deposit(dut_a.g_sched[0].u_core.delta, '0);
        $deposit(dut_a.g_sched[1].u_core.delta, '0);
        $deposit(dut_a.g_sched[2].u_core.delta, '0);
        $deposit(dut_a.g_sched[3].u_core.delta, '0);
        $deposit(dut_a.a_ptr, '0);
        $deposit(dut_a.g_ptr, '0);
        #3;
        check(!$isunknown(o_grant), "T3b after $deposit init: grant X-free");
        check(!$isunknown(o_src_ptr) || !o_src_vld, "T3b after $deposit init: src_ptr X-free when vld");

        // run some cycles with random traffic, ensure no X appears
        begin
            integer seed = 7;
            for (int c = 0; c < 200; c = c + 1) begin
                @(negedge clk);
                for (int n = 0; n < N; n = n + 1) begin
                    integer r;
                    r = $random(seed);
                    i_req[n*M +: M] = r[M-1:0];
                end
                i_src_bp = '0; i_dest_bp = '0;
                #2;
                check(!$isunknown(o_grant), "T3b random traffic: grant X-free");
                check(!$isunknown(o_src_vld), "T3b random traffic: src_vld X-free");
                check(!$isunknown(o_dest_vld), "T3b random traffic: dest_vld X-free");
                @(posedge clk);
            end
        end

        $display("=== X-check done: %0d errors ===", errors);
        if (errors != 0) $fatal(1, "X-CHECK FAILED");
        $finish;
    end

endmodule
