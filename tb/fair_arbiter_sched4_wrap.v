//=============================================================================
// fair_arbiter_sched4_wrap.v - simulation wrapper for the optional fairness
// top.  Defines `fair_arbiter` with the same interface so the existing
// testbenches can target it; compile this file INSTEAD of rtl/fair_arbiter.v.
// For tb_fair_arbiter and tb_x_check also pass -DSCHED4_DUT so the
// PTR_RESET=0 deposits target the wrapped instance.
//=============================================================================
`default_nettype none
module fair_arbiter #(
    parameter integer N=8, M=8, PTR_RESET=1, ITER=4, AUGMENT=1,
    parameter integer NSCHED=1,
    parameter integer WAVEFRONT_PLUS=1, AOI_STYLE=1, SEL_OH=1
) (
    input wire clk, rst_n,
    input wire [N-1:0][M-1:0] i_src_dest_req,
    input wire [N-1:0] i_src_bp,
    input wire [M-1:0] i_dest_bp,
    output wire [N-1:0][M-1:0] o_grant_rand_vld,
    output wire [N-1:0] o_grant_src_vld,
    output wire [N-1:0][$clog2(M)-1:0] o_grant_src_ptr,
    output wire [M-1:0] o_grant_dest_vld,
    output wire [M-1:0][$clog2(N)-1:0] o_grant_dest_ptr
);
    fair_arbiter_sched4 #(
        .N(N), .M(M), .PTR_RESET(PTR_RESET),
        .ITER(ITER), .AUGMENT(AUGMENT), .NSCHED(NSCHED),
        .WAVEFRONT_PLUS(WAVEFRONT_PLUS), .AOI_STYLE(AOI_STYLE),
        .SEL_OH(SEL_OH)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .i_src_dest_req(i_src_dest_req),
        .i_src_bp(i_src_bp), .i_dest_bp(i_dest_bp),
        .o_grant_rand_vld(o_grant_rand_vld),
        .o_grant_src_vld(o_grant_src_vld),
        .o_grant_src_ptr(o_grant_src_ptr),
        .o_grant_dest_vld(o_grant_dest_vld),
        .o_grant_dest_ptr(o_grant_dest_ptr)
    );
endmodule
`default_nettype wire
