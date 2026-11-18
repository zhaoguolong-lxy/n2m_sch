//=============================================================================
// fair_arbiter.v - top-level N-to-M fair arbiter.
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
// Design:
//   - General traffic: WFA/WWFA core (rtl/wfa_core.v), maximal/no-waste.
//   - Single-source case (only one source has effective requests): a per-source
//     RR override selects the first requested destination at/after a_ptr and
//     grants exactly that pair.  The source sequence is strict RR.
//   - Single-destination case (only one destination has effective requests):
//     a per-destination RR override selects the first requested source at/after
//     g_ptr and grants exactly that pair.  The destination sequence is strict RR.
//   - The override runs in parallel with the WFA and is selected by
//     use_src/use_dst; the WFA path remains the critical path.
//   - a_ptr/g_ptr advance only on an override grant; during mixed traffic they
//     hold.  This keeps the single-side fairness state stable and avoids adding
//     a long feedback path through the WFA.
//
// Area/depth target: 10x10 is the design point; 8x8..11x9 are supported.
// 16x16 is not a target for this variant.
//=============================================================================

`default_nettype none

module fair_arbiter #(
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
    localparam integer NC=(N<M)?N:M, MC=(N>M)?N:M;
    genvar i,j,b;

    // WFA core (general traffic, maximal/no-waste)
    wire [NC*MC-1:0] core_req, core_grant;
    wire [NC-1:0] core_src_bp, core_src_vld;
    wire [MC-1:0] core_dest_bp, core_dest_vld;
    wire [NC-1:0][$clog2(MC)-1:0] core_src_ptr;
    wire [MC-1:0][$clog2(NC)-1:0] core_dest_ptr;
    wfa_core #(.N(NC),.M(MC),.PTR_RESET(PTR_RESET)) u_core (
        .clk(clk), .rst_n(rst_n), .i_req_flat(core_req),
        .i_src_bp(core_src_bp), .i_dest_bp(core_dest_bp),
        .o_grant_flat(core_grant), .o_src_vld(core_src_vld),
        .o_src_ptr(core_src_ptr), .o_dest_vld(core_dest_vld),
        .o_dest_ptr(core_dest_ptr)
    );

    wire [NM-1:0] wfa_match;
    wire [N-1:0] wfa_src_vld;
    wire [M-1:0] wfa_dest_vld;
    wire [N-1:0][CWM-1:0] wfa_src_ptr;
    wire [M-1:0][CWN-1:0] wfa_dest_ptr;
    generate
        if (N <= M) begin : gen_direct
            for (i=0;i<N;i=i+1) for (j=0;j<M;j=j+1) begin : g_req
                assign core_req[i*M+j] = i_src_dest_req[i][j];
            end
            assign core_src_bp = i_src_bp;
            assign core_dest_bp = i_dest_bp;
            for (i=0;i<N;i=i+1) for (j=0;j<M;j=j+1) begin : g_grant
                assign wfa_match[i*M+j] = core_grant[i*M+j];
            end
            assign wfa_src_vld = core_src_vld;
            assign wfa_dest_vld = core_dest_vld;
            assign wfa_src_ptr = core_src_ptr;
            assign wfa_dest_ptr = core_dest_ptr;
        end else begin : gen_trans
            for (i=0;i<NC;i=i+1) for (j=0;j<MC;j=j+1) begin : g_req
                assign core_req[i*MC+j] = i_src_dest_req[j][i];
            end
            assign core_src_bp = i_dest_bp;
            assign core_dest_bp = i_src_bp;
            for (i=0;i<N;i=i+1) for (j=0;j<M;j=j+1) begin : g_grant
                assign wfa_match[i*M+j] = core_grant[j*MC+i];
            end
            for (i=0;i<N;i=i+1) begin : g_sv_map
                assign wfa_src_vld[i] = core_dest_vld[i];
            end
            for (j=0;j<M;j=j+1) begin : g_dv_map
                assign wfa_dest_vld[j] = core_src_vld[j];
            end
            for (i=0;i<N;i=i+1) begin : g_sp_map
                assign wfa_src_ptr[i] = core_dest_ptr[i];
            end
            for (j=0;j<M;j=j+1) begin : g_dp_map
                assign wfa_dest_ptr[j] = core_src_ptr[j];
            end
        end
    endgenerate

    // Effective request / row/col activity
    wire [NM-1:0] eff_req;
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
        input [N-1:0] oh; integer k; reg [CWN-1:0] v;
        begin v=0; for (k=0;k<N;k=k+1) if (oh[k]) v=k; idx_n=v; end
    endfunction
    function automatic [CWM-1:0] idx_m;
        input [M-1:0] oh; integer k; reg [CWM-1:0] v;
        begin v=0; for (k=0;k<M;k=k+1) if (oh[k]) v=k; idx_m=v; end
    endfunction

    reg [N*CWM-1:0] a_ptr;
    reg [M*CWN-1:0] g_ptr;

    // Selected indices, also used by the fused pointer outputs.
    wire [N*CWM-1:0] ix_s_all;
    wire [M*CWN-1:0] ix_d_all;

    // source single-active override: one RR selector per source, no index mux
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
            assign src_ov[i*M+j] = src_any[i] & s_pick_i[j];
        end
        assign ix_s_all[i*CWM +: CWM] = idx_m(s_pick_i);
        if (PTR_RESET) begin : ptr_rst
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) a_ptr[i*CWM +: CWM] <= i % M;
                else if (use_src && src_any[i]) begin
                    if (ix_s_all[i*CWM +: CWM] == M-1) a_ptr[i*CWM +: CWM] <= 0;
                    else a_ptr[i*CWM +: CWM] <= ix_s_all[i*CWM +: CWM] + 1'b1;
                end
            end
        end else begin : ptr_norst
            always @(posedge clk) begin
                if (use_src && src_any[i]) begin
                    if (ix_s_all[i*CWM +: CWM] == M-1) a_ptr[i*CWM +: CWM] <= 0;
                    else a_ptr[i*CWM +: CWM] <= ix_s_all[i*CWM +: CWM] + 1'b1;
                end
            end
        end
    end endgenerate

    // destination single-active override: one RR selector per destination
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
            assign dst_ov[i*M+j] = dst_any[j] & d_pick_j[i];
        end
        assign ix_d_all[j*CWN +: CWN] = idx_n(d_pick_j);
        if (PTR_RESET) begin : ptr_rst
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) g_ptr[j*CWN +: CWN] <= j % N;
                else if (use_dst && dst_any[j]) begin
                    if (ix_d_all[j*CWN +: CWN] == N-1) g_ptr[j*CWN +: CWN] <= 0;
                    else g_ptr[j*CWN +: CWN] <= ix_d_all[j*CWN +: CWN] + 1'b1;
                end
            end
        end else begin : ptr_norst
            always @(posedge clk) begin
                if (use_dst && dst_any[j]) begin
                    if (ix_d_all[j*CWN +: CWN] == N-1) g_ptr[j*CWN +: CWN] <= 0;
                    else g_ptr[j*CWN +: CWN] <= ix_d_all[j*CWN +: CWN] + 1'b1;
                end
            end
        end
    end endgenerate

    wire [NM-1:0] match_final;
    assign match_final = use_src ? src_ov : (use_dst ? dst_ov : wfa_match);

    localparam FUSE_VLD = ((N >= 10) || (M >= 10));

    // Index of the only active source / destination (meaningful when
    // src_onehot / dst_onehot), used by the fused pointer outputs.
    wire [CWM-1:0] dst_idx;
    wire [CWN-1:0] src_idx;
    generate
        for (b=0;b<CWM;b=b+1) begin : g_dst_idx
            wire [M-1:0] t;
            for (j=0;j<M;j=j+1) assign t[j] = dst_any[j] & ((j>>b) & 1'b1);
            assign dst_idx[b] = |t;
        end
        for (b=0;b<CWN;b=b+1) begin : g_src_idx
            wire [N-1:0] t;
            for (i=0;i<N;i=i+1) assign t[i] = src_any[i] & ((i>>b) & 1'b1);
            assign src_idx[b] = |t;
        end
    endgenerate

    // Output-side vld fusion (P >= 10 design point): valid bits are selected
    // per path after the path's own OR instead of after the full match mux.
    // src_ov row i = src_any[i] & s_pick_i with s_pick_i one-hot, so its row
    // OR is exactly src_any; same for dst_ov / dst_any.  Only the two
    // cross-direction ORs need reduction trees, and wfa_core provides its
    // vlds from the final free tokens (no post-wavefront OR).
    //
    // Under use_src the WFA necessarily grants the only requesting source, so
    // wfa_src_vld already equals src_any; likewise under use_dst the WFA
    // grants the only active destination.  That removes one mux level.
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
            // Pointer fusion: the override answer is computed in parallel
            // (RR index or the single active partner) and the WFA pointer goes
            // through only one 2:1 select.  The override pointer does not
            // depend on the matcher, so it settles long before the WFA side.
            wire ov_sel;
            assign ov_sel = use_src | use_dst;
            for (i=0;i<N;i=i+1) begin : g_sp
                wire [CWM-1:0] ov_ptr;
                assign ov_ptr = use_src ? ix_s_all[i*CWM +: CWM]
                                        : ({CWM{dst_ov_sv[i]}} & dst_idx);
                for (b=0;b<CWM;b=b+1) begin : g_spb
                    assign o_grant_src_ptr[i][b] =
                        (wfa_src_ptr[i][b] & ~ov_sel) | (ov_ptr[b] & ov_sel);
                end
            end
            for (j=0;j<M;j=j+1) begin : g_dp
                wire [CWN-1:0] ov_ptr;
                assign ov_ptr = use_dst ? ix_d_all[j*CWN +: CWN]
                                        : ({CWN{src_ov_dv[j]}} & src_idx);
                for (b=0;b<CWN;b=b+1) begin : g_dpb
                    assign o_grant_dest_ptr[j][b] =
                        (wfa_dest_ptr[j][b] & ~ov_sel) | (ov_ptr[b] & ov_sel);
                end
            end
        end
    endgenerate

    // outputs
    assign o_grant_rand_vld = match_final;
    generate
        if (!FUSE_VLD) begin : gen_vld_plain_src
            for (i=0;i<N;i=i+1) begin : g_sv
                assign o_grant_src_vld[i] = |(match_final[i*M +: M]);
            end
        end
    endgenerate
    generate
        if (!FUSE_VLD) begin : gen_ptr_plain_src
            for (i=0;i<N;i=i+1) begin : g_sp
                for (b=0;b<CWM;b=b+1) begin : g_spb
                    wire [M-1:0] terms;
                    for (j=0;j<M;j=j+1) assign terms[j] = match_final[i*M+j] & ((j>>b)&1'b1);
                    assign o_grant_src_ptr[i][b] = |terms;
                end
            end
        end
    endgenerate
    generate
        if (!FUSE_VLD) begin : gen_vld_plain_dst
            for (j=0;j<M;j=j+1) begin : g_dv
                wire [N-1:0] col;
                for (i=0;i<N;i=i+1) assign col[i] = match_final[i*M+j];
                assign o_grant_dest_vld[j] = |col;
            end
        end
    endgenerate
    generate
        if (!FUSE_VLD) begin : gen_ptr_plain_dst
            for (j=0;j<M;j=j+1) begin : g_dp
                for (b=0;b<CWN;b=b+1) begin : g_dpb
                    wire [N-1:0] terms;
                    for (i=0;i<N;i=i+1) assign terms[i] = match_final[i*M+j] & ((i>>b)&1'b1);
                    assign o_grant_dest_ptr[j][b] = |terms;
                end
            end
        end
    endgenerate

endmodule

`default_nettype wire
