//=============================================================================
// tb_fairness.sv - strict per-port round-robin fairness tests.
//
// Source-side: only source 0 requests a set of destinations.  Over successive
// cycles its granted destination must follow the requested set in ascending
// cyclic order (0,1,2,... or 0,2,4,...), and o_grant_src_ptr must match.
//
// Destination-side: only destination 0 receives requests from a set of
// sources.  Its granted source must follow the requested set in ascending
// cyclic order, and o_grant_dest_ptr must match.
//
// These are the "one source -> many destinations" and "many sources -> one
// destination" fairness requirements.  They are strict.
//
// Status: the low-depth WFA-only default FAILS these checks (subset and
// destination-side order, plus N>M source order).  The fair variant
// (iSLIP first pass + cyclic WFA fill) passes all 42 checks; see the design
// notes in docs/testpoints.md.  This TB is the acceptance test for the fair
// variant and is intentionally kept separate from the default regression.
//=============================================================================
`timescale 1ns/1ps

module fairness_runner #(
    parameter integer N    = 8,
    parameter integer M    = 8,
    parameter string  NAME = "8x8"
) ();
    localparam integer NM   = N * M;
    localparam integer CWN  = $clog2(N);
    localparam integer CWM  = $clog2(M);

    logic clk;
    logic rst_n;
    logic [NM-1:0] i_req;
    logic [N-1:0]  i_src_bp;
    logic [M-1:0]  i_dest_bp;
    logic [NM-1:0] o_grant;
    logic [N-1:0]  o_src_vld;
    logic [N*CWM-1:0] o_src_ptr;
    logic [M-1:0]  o_dest_vld;
    logic [M*CWN-1:0] o_dest_ptr;

`ifdef WTF_DUT
    fair_arbiter_wtf #(.N(N), .M(M), .PTR_RESET(1)) dut (
`else
    fair_arbiter #(.N(N), .M(M), .PTR_RESET(1)) dut (
`endif
        .clk(clk), .rst_n(rst_n),
        .i_src_dest_req(i_req), .i_src_bp(i_src_bp), .i_dest_bp(i_dest_bp),
        .o_grant_rand_vld(o_grant),
        .o_grant_src_vld(o_src_vld), .o_grant_src_ptr(o_src_ptr),
        .o_grant_dest_vld(o_dest_vld), .o_grant_dest_ptr(o_dest_ptr)
    );

    integer local_errors = 0;

    initial begin clk = 0; forever #5 clk = ~clk; end

    task automatic reset_dut();
        rst_n = 0; i_req = '0; i_src_bp = '0; i_dest_bp = '0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask

    task automatic fail(input string msg);
        local_errors = local_errors + 1;
        tb_fairness_top.errors = tb_fairness_top.errors + 1;
        $display("  FAIL [%s] %s", NAME, msg);
    endtask

    task automatic pass(input string msg);
        $display("  PASS [%s] %s", NAME, msg);
    endtask

    // source 0 requests the selected destinations; expect ascending cyclic RR
    task automatic test_source(input integer mode, input string label);
        int k, d, exp;
        int sel[0:31];
        int err0;
        k = 0;
        for (d = 0; d < M; d = d + 1) begin
            if ((mode == 0) || (mode == 1 && (d % 2 == 0)) ||
                (mode == 2 && (d % 2 == 1))) begin
                sel[k] = d; k = k + 1;
            end
        end
        reset_dut();
        err0 = local_errors;
        for (int c = 0; c < 2*k; c = c + 1) begin
            @(negedge clk);
            i_req = '0;
            for (int s = 0; s < k; s = s + 1) i_req[0*M + sel[s]] = 1'b1;
            i_src_bp = '0; i_dest_bp = '0;
            #2;
            exp = sel[c % k];
            if (o_src_vld[0] !== 1'b1)
                fail($sformatf("%s cycle %0d: src0 vld", label, c));
            if (o_src_ptr[0*CWM +: CWM] !== exp)
                fail($sformatf("%s cycle %0d: src0 dest %0d, got %0d",
                               label, c, exp, o_src_ptr[0*CWM +: CWM]));
            if (o_grant[0*M + exp] !== 1'b1)
                fail($sformatf("%s cycle %0d: grant (0,%0d) missing",
                               label, c, exp));
            if ($countones(o_grant) != 1)
                fail($sformatf("%s cycle %0d: grant count != 1", label, c));
            @(posedge clk);
        end
        if (local_errors == err0)
            pass($sformatf("%s strict RR", label));
        else
            $display("  FAIL [%s] %s strict RR", NAME, label);
    endtask

    // selected sources request destination 0; expect ascending cyclic RR
    task automatic test_dest(input integer mode, input string label);
        int k, s, exp;
        int sel[0:31];
        int err0;
        k = 0;
        for (s = 0; s < N; s = s + 1) begin
            if ((mode == 0) || (mode == 1 && (s % 2 == 0)) ||
                (mode == 2 && (s % 2 == 1))) begin
                sel[k] = s; k = k + 1;
            end
        end
        reset_dut();
        err0 = local_errors;
        for (int c = 0; c < 2*k; c = c + 1) begin
            @(negedge clk);
            i_req = '0;
            for (int q = 0; q < k; q = q + 1) i_req[sel[q]*M + 0] = 1'b1;
            i_src_bp = '0; i_dest_bp = '0;
            #2;
            exp = sel[c % k];
            if (o_dest_vld[0] !== 1'b1)
                fail($sformatf("%s cycle %0d: dest0 vld", label, c));
            if (o_dest_ptr[0*CWN +: CWN] !== exp)
                fail($sformatf("%s cycle %0d: dest0 src %0d, got %0d",
                               label, c, exp, o_dest_ptr[0*CWN +: CWN]));
            if (o_grant[exp*M + 0] !== 1'b1)
                fail($sformatf("%s cycle %0d: grant (%0d,0) missing",
                               label, c, exp));
            if ($countones(o_grant) != 1)
                fail($sformatf("%s cycle %0d: grant count != 1", label, c));
            @(posedge clk);
        end
        if (local_errors == err0)
            pass($sformatf("%s strict RR", label));
        else
            $display("  FAIL [%s] %s strict RR", NAME, label);
    endtask

    initial begin
        test_source(0, "src all");
        test_source(1, "src even");
        test_source(2, "src odd");
        test_dest(0, "dst all");
        test_dest(1, "dst even");
        test_dest(2, "dst odd");
        tb_fairness_top.done = tb_fairness_top.done + 1;
    end
endmodule

module tb_fairness_top;
    integer errors = 0;
    integer done = 0;

    fairness_runner #(.N(8),  .M(8),  .NAME("8x8"))   r0 ();
    fairness_runner #(.N(10), .M(10), .NAME("10x10")) r1 ();
    fairness_runner #(.N(3),  .M(5),  .NAME("3x5"))   r2 ();
    fairness_runner #(.N(5),  .M(3),  .NAME("5x3"))   r3 ();
    fairness_runner #(.N(9),  .M(11), .NAME("9x11"))  r4 ();
    fairness_runner #(.N(11), .M(9),  .NAME("11x9"))  r5 ();
    fairness_runner #(.N(16), .M(16), .NAME("16x16")) r6 ();

    localparam integer NUM = 7;

    initial begin
        $display("=== strict per-port fairness tests ===");
        while (done < NUM) #10;
        $display("=== fairness done: %0d errors ===", errors);
        if (errors != 0) $fatal(1, "FAIRNESS FAILED");
        $finish;
    end
endmodule
