//=============================================================================
// fair_arbiter_fair.v - optional fair variant: iSLIP first pass + WFA fill.
//
// This is a separate module from the default fast WFA (rtl/fair_arbiter.v).
// Both have the same top-level interface.
//
// Structure:
//   1. One iSLIP grant/accept pass with per-destination g_ptr and per-source
//      a_ptr.  This is the per-port RR layer for single-source, single-
//      destination and multi-source/multi-destination traffic.
//   2. A cyclic WFA fill on the residual (unmatched sources/destinations).
//      The fill guarantees the maximal / no-wasted-scheduling property.
//   3. a_ptr/g_ptr advance on the final match (first pass or fill).
//
// Tradeoff:
//   - strict single-source / single-destination RR: 42/42 (same test suite)
//   - multi-source fairness: better average Jain index than pure WFA, because
//     the first pass is per-port RR; fill-only ports are still approximate
//   - 10x10: 5415 cells / 74 levels (pure WFA+override: 5200 / 36)
//
// This module is intended as the "fair mode" when multi-source RR matters more
// than the 40-level target.  It is not the default.
//=============================================================================

`default_nettype none
module fair_arbiter_fair #(
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
    localparam integer CWP=$clog2((N>M)?N:M);
    genvar i,j,b;

    wire [NM-1:0] eff_req;
    generate for (i=0;i<N;i=i+1) begin : gen_eff_row
        for (j=0;j<M;j=j+1) begin : gen_eff_bit
            assign eff_req[i*M+j] = i_src_dest_req[i][j] & rst_n
                                  & ~i_src_bp[i] & ~i_dest_bp[j];
        end
    end endgenerate

    reg [M*CWN-1:0] g_ptr;
    reg [N*CWM-1:0] a_ptr;

    // first iSLIP pass: grant stage
    wire [M*N-1:0] grant;
    generate for (j=0;j<M;j=j+1) begin : gen_grant
        wire [N-1:0] col_req, mask_hi, req_hi, req_lo;
        for (i=0;i<N;i=i+1) begin : gen_gcol
            assign col_req[i] = eff_req[i*M+j];
            assign mask_hi[i] = (i >= g_ptr[j*CWN +: CWN]);
            assign req_hi[i]  = col_req[i] &  mask_hi[i];
            assign req_lo[i]  = col_req[i] & ~mask_hi[i];
        end
        assign grant[j*N +: N] = (|req_hi) ? (req_hi & ~(req_hi-1'b1))
                                           : (req_lo & ~(req_lo-1'b1));
    end endgenerate

    // accept stage
    wire [NM-1:0] first_accept;
    generate for (i=0;i<N;i=i+1) begin : gen_accept
        wire [M-1:0] row_grant, mask_hi, req_hi, req_lo;
        for (j=0;j<M;j=j+1) begin : gen_arow
            assign row_grant[j] = grant[j*N+i];
            assign mask_hi[j] = (j >= a_ptr[i*CWM +: CWM]);
            assign req_hi[j]  = row_grant[j] &  mask_hi[j];
            assign req_lo[j]  = row_grant[j] & ~mask_hi[j];
        end
        assign first_accept[i*M +: M] = (|req_hi) ? (req_hi & ~(req_hi-1'b1))
                                                  : (req_lo & ~(req_lo-1'b1));
    end endgenerate

    wire [N-1:0] first_src_match;
    wire [M-1:0] first_dst_match;
    generate for (i=0;i<N;i=i+1) begin : gen_fsm
        assign first_src_match[i] = |(first_accept[i*M +: M]);
    end endgenerate
    generate for (j=0;j<M;j=j+1) begin : gen_fdm
        wire [N-1:0] col;
        for (i=0;i<N;i=i+1) assign col[i] = first_accept[i*M+j];
        assign first_dst_match[j] = |col;
    end endgenerate

    // residual request
    wire [NM-1:0] res_req;
    generate for (i=0;i<N;i=i+1) begin : gen_res_row
        for (j=0;j<M;j=j+1) begin : gen_res_bit
            assign res_req[i*M+j] = eff_req[i*M+j]
                                  & ~first_src_match[i] & ~first_dst_match[j];
        end
    end endgenerate

    // WFA fill on residual (the mask is already folded into res_req)
    wire [NM-1:0] fill_grant;
    wire any_req_fill;
    assign any_req_fill = |res_req;

    reg [CWP-1:0] delta;
    generate
        if (PTR_RESET) begin : gen_delta_rst
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) delta <= 0;
                else if (any_req_fill) begin
                    if (delta == ((N>M)?N:M)-1) delta <= 0;
                    else delta <= delta + 1'b1;
                end
            end
        end else begin : gen_delta_norst
            always @(posedge clk) begin
                if (any_req_fill) begin
                    if (delta == ((N>M)?N:M)-1) delta <= 0;
                    else delta <= delta + 1'b1;
                end
            end
        end
    endgenerate

    wfa_core #(.N(N),.M(M),.PTR_RESET(PTR_RESET),.PRE_MASK(1)) u_fill (
        .rst_n(rst_n), .i_delta(delta),
        .i_req_flat(res_req),
        .i_src_bp({N{1'b0}}), .i_dest_bp({M{1'b0}}),
        .o_grant_flat(fill_grant),
        .o_src_vld(), .o_dest_vld()
    );

    wire [NM-1:0] match_accept;
    assign match_accept = first_accept | fill_grant;

    assign o_grant_rand_vld = match_accept;
    generate for (i=0;i<N;i=i+1) begin : gen_sv
        assign o_grant_src_vld[i] = |(match_accept[i*M +: M]);
    end endgenerate
    generate for (i=0;i<N;i=i+1) begin : gen_sp
        for (b=0;b<CWM;b=b+1) begin : gen_spb
            wire [M-1:0] terms;
            for (j=0;j<M;j=j+1) assign terms[j] = match_accept[i*M+j] & ((j>>b)&1'b1);
            assign o_grant_src_ptr[i][b] = |terms;
        end
    end endgenerate
    generate for (j=0;j<M;j=j+1) begin : gen_dv
        wire [N-1:0] col;
        for (i=0;i<N;i=i+1) assign col[i] = match_accept[i*M+j];
        assign o_grant_dest_vld[j] = |col;
    end endgenerate
    generate for (j=0;j<M;j=j+1) begin : gen_dp
        for (b=0;b<CWN;b=b+1) begin : gen_dpb
            wire [N-1:0] terms;
            for (i=0;i<N;i=i+1) assign terms[i] = match_accept[i*M+j] & ((i>>b)&1'b1);
            assign o_grant_dest_ptr[j][b] = |terms;
        end
    end endgenerate

    function automatic [CWM-1:0] idx_m;
        input [M-1:0] oh;
        integer k; reg [CWM-1:0] v;
        begin
            v=0; for (k=0;k<M;k=k+1) if (oh[k]) v=k; idx_m=v;
        end
    endfunction
    function automatic [CWN-1:0] idx_n;
        input [N-1:0] oh;
        integer k; reg [CWN-1:0] v;
        begin
            v=0; for (k=0;k<N;k=k+1) if (oh[k]) v=k; idx_n=v;
        end
    endfunction

    generate for (i=0;i<N;i=i+1) begin : gen_aptr
        wire [M-1:0] row = match_accept[i*M +: M];
        wire hit = |row;
        wire [CWM-1:0] ix = idx_m(row);
        if (PTR_RESET) begin : rst
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) a_ptr[i*CWM +: CWM] <= i % M;
                else if (hit) begin
                    if (ix == M-1) a_ptr[i*CWM +: CWM] <= 0;
                    else a_ptr[i*CWM +: CWM] <= ix + 1'b1;
                end
            end
        end else begin : norst
            always @(posedge clk) begin
                if (hit) begin
                    if (ix == M-1) a_ptr[i*CWM +: CWM] <= 0;
                    else a_ptr[i*CWM +: CWM] <= ix + 1'b1;
                end
            end
        end
    end endgenerate

    generate for (j=0;j<M;j=j+1) begin : gen_gptr
        wire [N-1:0] col;
        for (i=0;i<N;i=i+1) assign col[i] = match_accept[i*M+j];
        wire hit = |col;
        wire [CWN-1:0] ix = idx_n(col);
        if (PTR_RESET) begin : rst
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) g_ptr[j*CWN +: CWN] <= j % N;
                else if (hit) begin
                    if (ix == N-1) g_ptr[j*CWN +: CWN] <= 0;
                    else g_ptr[j*CWN +: CWN] <= ix + 1'b1;
                end
            end
        end else begin : norst
            always @(posedge clk) begin
                if (hit) begin
                    if (ix == N-1) g_ptr[j*CWN +: CWN] <= 0;
                    else g_ptr[j*CWN +: CWN] <= ix + 1'b1;
                end
            end
        end
    end endgenerate
endmodule

`default_nettype wire
