//=============================================================================
// fair_arbiter.v - top-level N-to-M fair arbiter (default: replicate/bank).
//
// TOP-LEVEL INTERFACE (exactly the required signals; DO NOT RENAME/CHANGE):
//   input  clk
//   input  rst_n
//   input  [N-1:0][M-1:0]        i_src_dest_req
//   input  [N-1:0]               i_src_bp
//   input  [M-1:0]               i_dest_bp
//   output [N-1:0][M-1:0]        o_grant_rand_vld
//   output [N-1:0]               o_grant_src_vld
//   output [N-1:0][clog2(M)-1:0] o_grant_src_ptr
//   output [M-1:0]               o_grant_dest_vld
//   output [M-1:0][clog2(N)-1:0] o_grant_dest_ptr
//
// Architecture (default, depth-first):
//   - P = max(N,M) fixed-delta wavefront cores run in parallel.  Each core's
//     diagonal rotation is compile-time wiring (0 logic levels), so there is
//     no runtime input/output barrel rotator.  A registered one-hot bank
//     select (delta_oh) drives a flat AND-OR mux (~2 levels).
//   - delta rotates once per granted cycle.  The optional wavefront+ skip is
//     computed on the registered next-state path only, so current requests
//     never enter the output select path.
//   - delta_oh intentionally lags delta by one cycle: it captures the current
//     delta at the clock edge.  This keeps the select path to a 1-bit AND +
//     OR reduction instead of putting the next-state priority logic in front
//     of it.  The schedule is the same rotating diagonal order, phase-shifted
//     by one cycle.
//   - Single-source / single-destination override and pointer outputs are the
//     same as the legacy top; strict per-port RR is preserved by the override.
//
// NSCHED is accepted for source compatibility but ignored: the bank is a
// single-schedule architecture.  The legacy rotating multi-schedule core
// (NSCHED=1..4) is kept in rtl/reference/fair_arbiter_rot.v.
// SEL_OH=0 selects the old binary variable-part-select for comparison; the
// default SEL_OH=1 is the registered one-hot select.
//
// Area/depth target: 10x10 is the design point; 8x8..11x9 are supported.
// 16x16 is not a target for this variant.
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
    localparam integer CWN=$clog2(N), CWM=$clog2(M), NM=N*M;
    localparam integer NC=(N<M)?N:M, MC=(N>M)?N:M;
    localparam integer P=MC, CWP=$clog2(P);
    genvar i,j,b,k;

    wire [NM-1:0] eff_req;

    wire [P*NM-1:0] wfa_match_s;
    wire [P*N-1:0]  wfa_sv_s;
    wire [P*M-1:0]  wfa_dv_s;
    generate
        for (k=0;k<P;k=k+1) begin : g_bank
            wire [NC*MC-1:0] core_req_s, core_grant_s;
            wire [NC-1:0] core_src_bp_s, core_src_vld_s;
            wire [MC-1:0] core_dest_bp_s, core_dest_vld_s;
            wfa_core_fixed #(.N(NC),.M(MC),.PTR_RESET(PTR_RESET),
                             .DELTA_VAL(k),.AOI_STYLE(AOI_STYLE)) u_core (
                .clk(clk), .rst_n(rst_n), .i_req_flat(core_req_s),
                .i_src_bp(core_src_bp_s), .i_dest_bp(core_dest_bp_s),
                .o_grant_flat(core_grant_s), .o_src_vld(core_src_vld_s),
                .o_dest_vld(core_dest_vld_s)
            );
            if (N <= M) begin : gen_direct
                for (i=0;i<NC;i=i+1) for (j=0;j<MC;j=j+1) begin : g_req
                    assign core_req_s[i*MC+j] = i_src_dest_req[i][j];
                end
                for (i=0;i<NC;i=i+1) begin : g_bp
                    assign core_src_bp_s[i] = i_src_bp[i];
                end
                assign core_dest_bp_s = i_dest_bp;
                for (i=0;i<NC;i=i+1) for (j=0;j<MC;j=j+1) begin : g_grant
                    assign wfa_match_s[k*NM + i*M + j] = core_grant_s[i*MC+j];
                end
                for (i=0;i<NC;i=i+1) begin : g_sv
                    assign wfa_sv_s[k*N + i] = core_src_vld_s[i];
                end
                assign wfa_dv_s[k*M +: M] = core_dest_vld_s;
            end else begin : gen_trans
                for (i=0;i<NC;i=i+1) for (j=0;j<MC;j=j+1) begin : g_req
                    assign core_req_s[i*MC+j] = i_src_dest_req[j][i];
                end
                for (i=0;i<NC;i=i+1) begin : g_bp
                    assign core_src_bp_s[i] = i_dest_bp[i];
                end
                assign core_dest_bp_s = i_src_bp;
                for (i=0;i<NC;i=i+1) for (j=0;j<MC;j=j+1) begin : g_grant
                    assign wfa_match_s[k*NM + j*M + i] = core_grant_s[i*MC+j];
                end
                for (j=0;j<MC;j=j+1) begin : g_sv
                    assign wfa_sv_s[k*N + j] = core_dest_vld_s[j];
                end
                for (i=0;i<NC;i=i+1) begin : g_dv
                    assign wfa_dv_s[k*M + i] = core_src_vld_s[i];
                end
            end
        end
    endgenerate

    wire [NM-1:0] wfa_match;
    wire [N-1:0] wfa_src_vld;
    wire [M-1:0] wfa_dest_vld;
    reg [CWP-1:0] delta;
    reg [P-1:0] delta_oh;
    generate
        if (SEL_OH) begin : g_sel_oh
            for (i=0;i<NM;i=i+1) begin : g_m
                wire [P-1:0] t;
                for (k=0;k<P;k=k+1) assign t[k] = wfa_match_s[k*NM+i] & delta_oh[k];
                assign wfa_match[i] = |t;
            end
            for (i=0;i<N;i=i+1) begin : g_s
                wire [P-1:0] t;
                for (k=0;k<P;k=k+1) assign t[k] = wfa_sv_s[k*N+i] & delta_oh[k];
                assign wfa_src_vld[i] = |t;
            end
            for (j=0;j<M;j=j+1) begin : g_d
                wire [P-1:0] t;
                for (k=0;k<P;k=k+1) assign t[k] = wfa_dv_s[k*M+j] & delta_oh[k];
                assign wfa_dest_vld[j] = |t;
            end
        end else begin : g_sel_bin
            assign wfa_match    = wfa_match_s[delta*NM +: NM];
            assign wfa_src_vld  = wfa_sv_s[delta*N +: N];
            assign wfa_dest_vld = wfa_dv_s[delta*M +: M];
        end
    endgenerate

    wire any_req_w = |eff_req;

    // Wavefront+ bank select (square only): skip to the diagonal after the
    // first diagonal that has any request.  Registered, off the critical path.
    wire [P-1:0] diag_pres;
    generate
        if (N == M) begin : g_pres_sq
            for (k=0;k<P;k=k+1) begin : g_pk
                wire [N-1:0] terms;
                for (i=0;i<N;i=i+1)
                    assign terms[i] = eff_req[i*M + ((i+k)%N)];
                assign diag_pres[k] = |terms;
            end
        end else begin : g_pres_ns
            assign diag_pres = {P{1'b1}};
        end
    endgenerate

    function automatic [CWP-1:0] next_delta;
        input [CWP-1:0] cur;
        integer off, kk; reg [CWP-1:0] r; reg found;
        begin
            r = (cur==P-1) ? {CWP{1'b0}} : cur+1'b1;
            if (WAVEFRONT_PLUS && (N==M)) begin
                found = 0;
                for (off=0; off<P; off=off+1) begin
                    kk = (cur+off)%P;
                    if (!found && diag_pres[kk]) begin
                        r = ((kk+1)%P);
                        found = 1;
                    end
                end
            end
            next_delta = r;
        end
    endfunction

    // delta is the rotating schedule state (binary, next-state path only).
    // delta_oh is the registered select state and lags delta by one cycle.
    // PTR_RESET is tested inside the reset branch instead of around the
    // always block: a generate-wrapped flop costs 3 extra mapped levels in
    // yosys/ABC, while this constant-folds to the same reset flop.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if (PTR_RESET) begin
                delta <= 0;
                delta_oh <= {{(P-1){1'b0}}, 1'b1};
            end
        end else begin
            if (any_req_w) delta <= next_delta(delta);
            delta_oh <= ({{(P-1){1'b0}}, 1'b1} << delta);
        end
    end

    // ---- override + outputs (identical to fair_arbiter) ----
    generate for (i=0;i<N;i=i+1) begin : g_eff_row
        for (j=0;j<M;j=j+1) begin : g_eff_bit
            assign eff_req[i*M+j] = i_src_dest_req[i][j] & rst_n
                                  & ~i_src_bp[i] & ~i_dest_bp[j];
        end
    end endgenerate

    wire [N-1:0] src_any;
    wire [M-1:0] dst_any;
    generate for (i=0;i<N;i=i+1) begin : g_sa
        assign src_any[i] = |(eff_req[i*M +: M]);
    end endgenerate
    generate for (j=0;j<M;j=j+1) begin : g_da
        wire [N-1:0] col;
        for (i=0;i<N;i=i+1) assign col[i] = eff_req[i*M+j];
        assign dst_any[j] = |col;
    end endgenerate

    wire src_onehot = (|src_any) && ((src_any & (src_any - 1'b1)) == 0);
    wire dst_onehot = (|dst_any) && ((dst_any & (dst_any - 1'b1)) == 0);
    wire use_src = src_onehot;
    wire use_dst = (~src_onehot) && dst_onehot;

    function automatic [CWN-1:0] idx_n;
        input [N-1:0] oh; integer t; reg [CWN-1:0] v;
        begin v=0; for (t=0;t<N;t=t+1) if (oh[t]) v=t; idx_n=v; end
    endfunction
    function automatic [CWM-1:0] idx_m;
        input [M-1:0] oh; integer t; reg [CWM-1:0] v;
        begin v=0; for (t=0;t<M;t=t+1) if (oh[t]) v=t; idx_m=v; end
    endfunction

    reg [N*CWM-1:0] a_ptr;
    reg [M*CWN-1:0] g_ptr;

    wire [NM-1:0] src_ov;
    generate for (i=0;i<N;i=i+1) begin : g_sov_row
        wire [M-1:0] row_req_i, s_mask_i, s_hi_i, s_lo_i, s_pick_i;
        for (j=0;j<M;j=j+1) begin : g_sov_bit
            assign row_req_i[j] = eff_req[i*M+j];
            assign s_mask_i[j]  = (j >= a_ptr[i*CWM +: CWM]);
            assign s_hi_i[j]    = row_req_i[j] & s_mask_i[j];
            assign s_lo_i[j]    = row_req_i[j] & ~s_mask_i[j];
        end
        assign s_pick_i = (|s_hi_i) ? (s_hi_i & ~(s_hi_i - 1'b1))
                                    : (s_lo_i & ~(s_lo_i - 1'b1));
        for (j=0;j<M;j=j+1) begin : g_sov_out
            assign src_ov[i*M+j] = s_pick_i[j];
        end
        wire [CWM-1:0] ix_s = idx_m(s_pick_i);
        if (PTR_RESET) begin : ptr_rst
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) a_ptr[i*CWM +: CWM] <= i % M;
                else if (use_src && src_any[i]) begin
                    if (ix_s == M-1) a_ptr[i*CWM +: CWM] <= 0;
                    else a_ptr[i*CWM +: CWM] <= ix_s + 1'b1;
                end
            end
        end else begin : ptr_norst
            always @(posedge clk) begin
                if (use_src && src_any[i]) begin
                    if (ix_s == M-1) a_ptr[i*CWM +: CWM] <= 0;
                    else a_ptr[i*CWM +: CWM] <= ix_s + 1'b1;
                end
            end
        end
    end endgenerate

    wire [NM-1:0] dst_ov;
    generate for (j=0;j<M;j=j+1) begin : g_dov_col
        wire [N-1:0] col_req_j, d_mask_j, d_hi_j, d_lo_j, d_pick_j;
        for (i=0;i<N;i=i+1) begin : g_dov_bit
            assign col_req_j[i] = eff_req[i*M+j];
            assign d_mask_j[i]  = (i >= g_ptr[j*CWN +: CWN]);
            assign d_hi_j[i]    = col_req_j[i] & d_mask_j[i];
            assign d_lo_j[i]    = col_req_j[i] & ~d_mask_j[i];
        end
        assign d_pick_j = (|d_hi_j) ? (d_hi_j & ~(d_hi_j - 1'b1))
                                    : (d_lo_j & ~(d_lo_j - 1'b1));
        for (i=0;i<N;i=i+1) begin : g_dov_out
            assign dst_ov[i*M+j] = d_pick_j[i];
        end
        wire [CWN-1:0] ix_d = idx_n(d_pick_j);
        if (PTR_RESET) begin : ptr_rst
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) g_ptr[j*CWN +: CWN] <= j % N;
                else if (use_dst && dst_any[j]) begin
                    if (ix_d == N-1) g_ptr[j*CWN +: CWN] <= 0;
                    else g_ptr[j*CWN +: CWN] <= ix_d + 1'b1;
                end
            end
        end else begin : ptr_norst
            always @(posedge clk) begin
                if (use_dst && dst_any[j]) begin
                    if (ix_d == N-1) g_ptr[j*CWN +: CWN] <= 0;
                    else g_ptr[j*CWN +: CWN] <= ix_d + 1'b1;
                end
            end
        end
    end endgenerate

    wire ov_sel_w = use_src | use_dst;
    wire [NM-1:0] ov_match = use_src ? src_ov : dst_ov;
    wire [NM-1:0] match_final = ov_sel_w ? ov_match : wfa_match;

    localparam FUSE_VLD = ((N >= 10) || (M >= 10));
    generate
        if (FUSE_VLD) begin : gen_vld_fused
            wire [N-1:0] dst_ov_sv;
            wire [M-1:0] src_ov_dv;
            for (i=0;i<N;i=i+1) begin : g_ov_sv
                assign dst_ov_sv[i] = |(dst_ov[i*M +: M]);
            end
            for (j=0;j<M;j=j+1) begin : g_ov_dv
                wire [N-1:0] cs;
                for (i=0;i<N;i=i+1) begin : g_col
                    assign cs[i] = src_ov[i*M+j];
                end
                assign src_ov_dv[j] = |cs;
            end
            for (i=0;i<N;i=i+1) begin : g_sv
                assign o_grant_src_vld[i] = use_dst ? dst_ov_sv[i] : wfa_src_vld[i];
            end
            for (j=0;j<M;j=j+1) begin : g_dv
                assign o_grant_dest_vld[j] = use_src ? src_ov_dv[j] : wfa_dest_vld[j];
            end
        end
    endgenerate

    assign o_grant_rand_vld = match_final;
    generate
        if (!FUSE_VLD) begin : gen_vld_plain_src
            for (i=0;i<N;i=i+1) begin : g_sv
                assign o_grant_src_vld[i] = |(match_final[i*M +: M]);
            end
        end
    endgenerate
    generate for (i=0;i<N;i=i+1) begin : g_sp
        for (b=0;b<CWM;b=b+1) begin : g_spb
            wire [M-1:0] terms;
            for (j=0;j<M;j=j+1) assign terms[j] = match_final[i*M+j] & ((j>>b)&1'b1);
            assign o_grant_src_ptr[i][b] = |terms;
        end
    end endgenerate
    generate
        if (!FUSE_VLD) begin : gen_vld_plain_dst
            for (j=0;j<M;j=j+1) begin : g_dv
                wire [N-1:0] col;
                for (i=0;i<N;i=i+1) assign col[i] = match_final[i*M+j];
                assign o_grant_dest_vld[j] = |col;
            end
        end
    endgenerate
    generate for (j=0;j<M;j=j+1) begin : g_dp
        for (b=0;b<CWN;b=b+1) begin : g_dpb
            wire [N-1:0] terms;
            for (i=0;i<N;i=i+1) assign terms[i] = match_final[i*M+j] & ((i>>b)&1'b1);
            assign o_grant_dest_ptr[j][b] = |terms;
        end
    end endgenerate
endmodule
`default_nettype wire
