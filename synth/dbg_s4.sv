`timescale 1ns/1ps
module dbg_s4;
    localparam N=8, M=8, NM=N*M, CWN=$clog2(N), CWM=$clog2(M);
    logic clk, rst_n;
    logic [NM-1:0] i_req;
    logic [N-1:0] i_src_bp;
    logic [M-1:0] i_dest_bp;
    logic [NM-1:0] o_grant;
    logic [N-1:0] o_src_vld;
    logic [N-1:0][CWM-1:0] o_src_ptr;
    logic [M-1:0] o_dest_vld;
    logic [M-1:0][CWN-1:0] o_dest_ptr;
    fair_arbiter #(.N(N),.M(M),.PTR_RESET(1),.ITER(4),.AUGMENT(1)) dut(
        .clk(clk),.rst_n(rst_n),.i_src_dest_req(i_req),.i_src_bp(i_src_bp),.i_dest_bp(i_dest_bp),
        .o_grant_rand_vld(o_grant),.o_grant_src_vld(o_src_vld),.o_grant_src_ptr(o_src_ptr),
        .o_grant_dest_vld(o_dest_vld),.o_grant_dest_ptr(o_dest_ptr));
    initial begin clk=0; forever #5 clk=~clk; end
    initial begin
        rst_n=0; i_req='0; i_src_bp='0; i_dest_bp='0;
        repeat(2) @(posedge clk); rst_n=1; @(posedge clk);
        for (int c=0; c<6; c++) begin
            @(negedge clk);
            i_req='0; i_req[0*M +: M]='1;
            #2;
            $display("cyc %0d: src_ptr0=%0d grant=%b a_ptr=%0d", c, o_src_ptr[0], o_grant[0*M +: M], dut.a_ptr[0*CWM +: CWM]);
            @(posedge clk);
        end
        $finish;
    end
endmodule
