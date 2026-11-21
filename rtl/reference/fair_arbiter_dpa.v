//=============================================================================
// fair_arbiter_dpa.v - single-pass Diagonal Priority Arbiter (per-port RR).
//
// Every source keeps a destination pointer a_ptr[i], every destination a
// source pointer g_ptr[j].  A cell is granted when it is both the row's
// first request from a_ptr[i] and the column's first request from g_ptr[j]:
//
//   row_pick[i][j] = eff_req[i][j] & (j == first requested from a_ptr[i])
//   col_pick[i][j] = eff_req[i][j] & (i == first requested from g_ptr[j])
//   grant[i][j]    = row_pick[i][j] & col_pick[i][j]
//
// This is the single-pass DPA.  It is NOT maximal: a source whose top
// destination loses the column to another source is not re-tried on its
// second choice.  Measured on the maximality bench (10x10, random traffic):
// 630/773 cycles non-maximal, only 2.20/10 grants per cycle (22%), with
// 31k wasted pairs.  It is kept as a reference/comparison only; the shipped
// design is rtl/fair_arbiter.v (maximal WFA + single-side RR override).
//=============================================================================

`default_nettype none

module fair_arbiter_dpa #(
    parameter integer N=8, M=8, PTR_RESET=1, ITER=4, AUGMENT=1
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
    localparam integer CWN=$clog2(N), CWM=$clog2(M), NM=N*M;
    genvar i,j,b;

    wire [NM-1:0] eff_req;
    generate for (i=0;i<N;i=i+1) begin : g_eff_row
        for (j=0;j<M;j=j+1) begin : g_eff_bit
            assign eff_req[i*M+j] = i_src_dest_req[i][j] & rst_n
                                  & ~i_src_bp[i] & ~i_dest_bp[j];
        end
    end endgenerate

    reg [N*CWM-1:0] a_ptr;
    reg [M*CWN-1:0] g_ptr;

    function automatic [CWN-1:0] idx_n;
        input [N-1:0] oh; integer k; reg [CWN-1:0] v;
        begin v=0; for (k=0;k<N;k=k+1) if (oh[k]) v=k; idx_n=v; end
    endfunction
    function automatic [CWM-1:0] idx_m;
        input [M-1:0] oh; integer k; reg [CWM-1:0] v;
        begin v=0; for (k=0;k<M;k=k+1) if (oh[k]) v=k; idx_m=v; end
    endfunction

    // Row best: first requested destination from a_ptr[i].
    wire [NM-1:0] row_pick;
    generate for (i=0;i<N;i=i+1) begin : g_row
        wire [M-1:0] row_req, mask_i, hi_i, lo_i, pick_i;
        for (j=0;j<M;j=j+1) begin : g_bit
            assign row_req[j] = eff_req[i*M+j];
            assign mask_i[j]  = (j >= a_ptr[i*CWM +: CWM]);
            assign hi_i[j]    = row_req[j] & mask_i[j];
            assign lo_i[j]    = row_req[j] & ~mask_i[j];
        end
        assign pick_i = (|hi_i) ? (hi_i & ~(hi_i - 1'b1))
                                : (lo_i & ~(lo_i - 1'b1));
        for (j=0;j<M;j=j+1) begin : g_out
            assign row_pick[i*M+j] = pick_i[j];
        end
    end endgenerate

    // Column best: first requesting source from g_ptr[j].
    wire [NM-1:0] col_pick;
    generate for (j=0;j<M;j=j+1) begin : g_col
        wire [N-1:0] col_req, mask_j, hi_j, lo_j, pick_j;
        for (i=0;i<N;i=i+1) begin : g_bit
            assign col_req[i] = eff_req[i*M+j];
            assign mask_j[i]  = (i >= g_ptr[j*CWN +: CWN]);
            assign hi_j[i]    = col_req[i] & mask_j[i];
            assign lo_j[i]    = col_req[i] & ~mask_j[i];
        end
        assign pick_j = (|hi_j) ? (hi_j & ~(hi_j - 1'b1))
                                : (lo_j & ~(lo_j - 1'b1));
        for (i=0;i<N;i=i+1) begin : g_out
            assign col_pick[i*M+j] = pick_j[i];
        end
    end endgenerate

    wire [NM-1:0] grant;
    assign grant = row_pick & col_pick;

    // Pointer updates: advance past the granted partner.
    generate for (i=0;i<N;i=i+1) begin : g_ap
        wire [CWM-1:0] ix = idx_m(row_pick[i*M +: M]);
        if (PTR_RESET) begin : ptr_rst
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) a_ptr[i*CWM +: CWM] <= i % M;
                else if (|(grant[i*M +: M])) begin
                    if (ix == M-1) a_ptr[i*CWM +: CWM] <= 0;
                    else a_ptr[i*CWM +: CWM] <= ix + 1'b1;
                end
            end
        end else begin : ptr_norst
            always @(posedge clk) begin
                if (|(grant[i*M +: M])) begin
                    if (ix == M-1) a_ptr[i*CWM +: CWM] <= 0;
                    else a_ptr[i*CWM +: CWM] <= ix + 1'b1;
                end
            end
        end
    end endgenerate

    generate for (j=0;j<M;j=j+1) begin : g_gp
        wire [N-1:0] col_g;
        for (i=0;i<N;i=i+1) begin : g_cg
            assign col_g[i] = grant[i*M+j];
        end
        wire [CWN-1:0] ix = idx_n(col_g);
        if (PTR_RESET) begin : ptr_rst
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) g_ptr[j*CWN +: CWN] <= j % N;
                else if (|col_g) begin
                    if (ix == N-1) g_ptr[j*CWN +: CWN] <= 0;
                    else g_ptr[j*CWN +: CWN] <= ix + 1'b1;
                end
            end
        end else begin : ptr_norst
            always @(posedge clk) begin
                if (|col_g) begin
                    if (ix == N-1) g_ptr[j*CWN +: CWN] <= 0;
                    else g_ptr[j*CWN +: CWN] <= ix + 1'b1;
                end
            end
        end
    end endgenerate

    assign o_grant_rand_vld = grant;
    generate for (i=0;i<N;i=i+1) begin : g_sv
        assign o_grant_src_vld[i] = |(grant[i*M +: M]);
    end endgenerate
    generate for (i=0;i<N;i=i+1) begin : g_sp
        for (b=0;b<CWM;b=b+1) begin : g_spb
            wire [M-1:0] terms;
            for (j=0;j<M;j=j+1) assign terms[j] = grant[i*M+j] & ((j>>b)&1'b1);
            assign o_grant_src_ptr[i][b] = |terms;
        end
    end endgenerate
    generate for (j=0;j<M;j=j+1) begin : g_dv
        wire [N-1:0] col;
        for (i=0;i<N;i=i+1) assign col[i] = grant[i*M+j];
        assign o_grant_dest_vld[j] = |col;
    end endgenerate
    generate for (j=0;j<M;j=j+1) begin : g_dp
        for (b=0;b<CWN;b=b+1) begin : g_dpb
            wire [N-1:0] terms;
            for (i=0;i<N;i=i+1) assign terms[i] = grant[i*M+j] & ((i>>b)&1'b1);
            assign o_grant_dest_ptr[j][b] = |terms;
        end
    end endgenerate

endmodule

`default_nettype wire
