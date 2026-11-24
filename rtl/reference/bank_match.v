//=============================================================================
// bank_match.v - SPIKE: replicate/bank matching path (square N=M only).
//
// P fixed-delta wavefront cores (rotation = wiring, 0 levels) run in parallel;
// a rotating delta register selects one core's grant via a P:1 mux.  This
// replaces the runtime input+output barrel rotators with a single output
// select mux.  Minimal top (grant + vld only, no override/ptr) to isolate the
// matching-path depth.  Throwaway reference for the rotator tradeoff.
//=============================================================================
`default_nettype none
module bank_match #(
    parameter integer N=10, M=10, PTR_RESET=1, AOI_STYLE=1
) (
    input  wire           clk, rst_n,
    input  wire [N*M-1:0] i_req_flat,
    input  wire [N-1:0]   i_src_bp,
    input  wire [M-1:0]   i_dest_bp,
    output wire [N*M-1:0] o_grant,
    output wire [N-1:0]   o_sv,
    output wire [M-1:0]   o_dv
);
    localparam integer P=(N>M)?N:M, CWP=$clog2(P), NM=N*M;
    genvar k;
    wire [P*NM-1:0] g_bank;
    wire [P*N-1:0]  sv_bank;
    wire [P*M-1:0]  dv_bank;
    generate for (k=0;k<P;k=k+1) begin : gb
        wfa_core_fixed #(.N(N),.M(M),.PTR_RESET(PTR_RESET),
                         .DELTA_VAL(k),.AOI_STYLE(AOI_STYLE)) uc (
            .clk(clk), .rst_n(rst_n), .i_req_flat(i_req_flat),
            .i_src_bp(i_src_bp), .i_dest_bp(i_dest_bp),
            .o_grant_flat(g_bank[k*NM +: NM]),
            .o_src_vld(sv_bank[k*N +: N]),
            .o_dest_vld(dv_bank[k*M +: M])
        );
    end endgenerate

    reg [CWP-1:0] delta;
    wire any_req = |i_req_flat;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) delta <= 0;
        else if (any_req) delta <= (delta==P-1) ? {CWP{1'b0}} : delta+1'b1;
    end
    assign o_grant = g_bank[delta*NM +: NM];
    assign o_sv    = sv_bank[delta*N +: N];
    assign o_dv    = dv_bank[delta*M +: M];
endmodule
`default_nettype wire
