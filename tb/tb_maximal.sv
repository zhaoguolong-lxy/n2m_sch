//=============================================================================
// tb_maximal.sv - maximality check (the user's criterion):
//   a matching is maximal if there is NO pair (i,j) with req[i][j]=1 and both
//   source i and destination j unmatched.  Any such wasted opportunity is an
//   error.  Counts non-maximal cycles over random traffic.
//=============================================================================
`timescale 1ns/1ps
module maximal_runner #(parameter integer N=8, M=8, ITER=4, AUGMENT=1) ();
    localparam NM=N*M, CWN=$clog2(N), CWM=$clog2(M);
    logic clk, rst_n;
    logic [NM-1:0] i_req;
    logic [N-1:0] i_src_bp;
    logic [M-1:0] i_dest_bp;
    logic [NM-1:0] o_grant;
    logic [N-1:0] o_src_vld;
    logic [N-1:0][CWM-1:0] o_src_ptr;
    logic [M-1:0] o_dest_vld;
    logic [M-1:0][CWN-1:0] o_dest_ptr;
    fair_arbiter #(.N(N),.M(M),.PTR_RESET(1),.ITER(ITER),.AUGMENT(AUGMENT)) dut(
        .clk(clk),.rst_n(rst_n),.i_src_dest_req(i_req),.i_src_bp(i_src_bp),.i_dest_bp(i_dest_bp),
        .o_grant_rand_vld(o_grant),.o_grant_src_vld(o_src_vld),.o_grant_src_ptr(o_src_ptr),
        .o_grant_dest_vld(o_dest_vld),.o_grant_dest_ptr(o_dest_ptr));
    initial begin clk=0; forever #5 clk=~clk; end
    integer seed=42;
    function automatic logic [31:0] rnd(); seed=(seed*1103515245+12345)&32'h7fffffff; return seed; endfunction
    logic [31:0] rw;
    integer nonmax, total_grants, cyc, orth_viol;
    initial begin
        rst_n=0; i_req='0; i_src_bp='0; i_dest_bp='0;
        repeat(2) @(posedge clk); rst_n=1; @(posedge clk);
        nonmax=0; total_grants=0; cyc=0; orth_viol=0;
        for (int c=0; c<300; c++) begin
            integer g;
            @(negedge clk);
            for (int n=0;n<N;n++) begin rw=rnd(); i_req[n*M+:M]=rw[M-1:0]; end
            i_src_bp='0; i_dest_bp='0;
            #2;
            // orthogonality: each row/col at most one grant
            for (int n=0;n<N;n++) begin
                integer rc; rc=0;
                for (int m=0;m<M;m++) if (o_grant[n*M+m]) rc++;
                if (rc>1) begin orth_viol++; $display("  ORTH-VIOL row %0d", n); end
            end
            for (int m=0;m<M;m++) begin
                integer cc; cc=0;
                for (int n=0;n<N;n++) if (o_grant[n*M+m]) cc++;
                if (cc>1) begin orth_viol++; $display("  ORTH-VIOL col %0d", m); end
            end
            // maximality check
            for (int n=0;n<N;n++) begin
                for (int m=0;m<M;m++) begin
                    if (i_req[n*M+m] && !o_src_vld[n] && !o_dest_vld[m]) begin
                        nonmax++;
                        if (nonmax<=3) $display("  NON-MAXIMAL: src %0d -> dst %0d wasted", n, m);
                    end
                end
            end
            g=0; for (int k=0;k<NM;k++) if (o_grant[k]) g++;
            total_grants+=g; cyc++;
            @(posedge clk);
        end
        $display("[%0dx%0d ITER=%0d AUG=%0d] non-maximal=%0d/%0d (%.3f%%), orth_viol=%0d, avg grants=%.2f/%0d (%.1f%%)",
                 N, M, ITER, AUGMENT, nonmax, cyc, 100.0*nonmax/cyc, orth_viol,
                 total_grants*1.0/cyc, (N<M)?N:M, 100.0*total_grants/(cyc*((N<M)?N:M)));
        tb_maximal_top.num_done = tb_maximal_top.num_done + 1;
    end
endmodule

module tb_maximal_top;
    integer num_done=0;
    maximal_runner #(.N(8),.M(8),.ITER(4),.AUGMENT(1)) a();
    maximal_runner #(.N(8),.M(8),.ITER(2),.AUGMENT(1)) b();
    maximal_runner #(.N(9),.M(11),.ITER(4),.AUGMENT(1)) d();
    maximal_runner #(.N(8),.M(8),.ITER(4),.AUGMENT(0)) e();
    localparam NUM=4;
    initial begin
        while (num_done<NUM) #10;
        $finish;
    end
endmodule
