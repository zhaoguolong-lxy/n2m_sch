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
    parameter integer N=8, M=8, PTR_RESET=1, ITER=4, AUGMENT=1,
    parameter integer NSCHED=4, WAVEFRONT_PLUS=1, AOI_STYLE=1
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
    genvar i,j,b,sc;

    // Masked request matrix for the single-side override.  The WFA core builds
    // its own copy from the raw request and backpressure; sharing one matrix
    // raises the fanout and is slower at small shapes.
    wire [NM-1:0] eff_req;

    // ------------------------------------------------------------------
    // Multi-schedule WFA.  NSCHED wavefronts run in parallel; schedule s
    // permutes the core rows by r -> (c_s*r) mod NC (pure wiring, no mux).
    // The schedule rotates every MC grants.  Each schedule is a different
    // diagonal-priority order, so the long-run grant distribution is much
    // flatter than a single rotating diagonal.
    // ------------------------------------------------------------------
    localparam integer NS = (NSCHED < 1) ? 1 : (NSCHED > 4 ? 4 : NSCHED);

    // The schedule multiplier must be coprime to NC, otherwise the row
    // permutation would repeat/skip rows.  Evaluate the table at elaboration.
    function automatic integer gcd_i;
        input integer a, b;
        integer x, y, t;
        begin
            x = a; y = b;
            while (y != 0) begin t = x % y; x = y; y = t; end
            gcd_i = x;
        end
    endfunction

    function automatic integer perm_mul;
        input integer sl;
        input integer n;
        integer c, sel, mul, found;
        begin
            sel = sl; mul = 1; found = 0;
            for (c = 1; c < n && !found; c = c + 1) begin
                if (gcd_i(c, n) == 1) begin
                    if (sel == 0) begin mul = c; found = 1; end
                    else sel = sel - 1;
                end
            end
            perm_mul = mul;
        end
    endfunction

    wire [NS*NM-1:0] wfa_match_s;
    wire [NS*N-1:0]  wfa_sv_s;
    wire [NS*M-1:0]  wfa_dv_s;

    generate
        for (sc=0; sc<NS; sc=sc+1) begin : g_sched
            localparam integer CMUL = perm_mul(sc, NC);
            wire [NC*MC-1:0] core_req_s, core_grant_s;
            wire [NC-1:0] core_src_bp_s, core_src_vld_s;
            wire [MC-1:0] core_dest_bp_s, core_dest_vld_s;

            wfa_core #(.N(NC),.M(MC),.PTR_RESET(PTR_RESET),
                       .WAVEFRONT_PLUS(WAVEFRONT_PLUS),
                       .AOI_STYLE(AOI_STYLE)) u_core (
                .clk(clk), .rst_n(rst_n), .i_req_flat(core_req_s),
                .i_src_bp(core_src_bp_s), .i_dest_bp(core_dest_bp_s),
                .o_grant_flat(core_grant_s), .o_src_vld(core_src_vld_s),
                .o_dest_vld(core_dest_vld_s)
            );

            if (N <= M) begin : gen_direct
                for (i=0;i<NC;i=i+1) for (j=0;j<MC;j=j+1) begin : g_req
                    assign core_req_s[i*MC+j] = i_src_dest_req[(CMUL*i)%NC][j];
                end
                for (i=0;i<NC;i=i+1) begin : g_bp
                    assign core_src_bp_s[i] = i_src_bp[(CMUL*i)%NC];
                end
                assign core_dest_bp_s = i_dest_bp;
                for (i=0;i<NC;i=i+1) for (j=0;j<MC;j=j+1) begin : g_grant
                    assign wfa_match_s[sc*NM + ((CMUL*i)%NC)*M + j] = core_grant_s[i*MC+j];
                end
                for (i=0;i<NC;i=i+1) begin : g_sv
                    assign wfa_sv_s[sc*N + ((CMUL*i)%NC)] = core_src_vld_s[i];
                end
                assign wfa_dv_s[sc*M +: M] = core_dest_vld_s;
            end else begin : gen_trans
                for (i=0;i<NC;i=i+1) for (j=0;j<MC;j=j+1) begin : g_req
                    assign core_req_s[i*MC+j] = i_src_dest_req[j][(CMUL*i)%NC];
                end
                for (i=0;i<NC;i=i+1) begin : g_bp
                    assign core_src_bp_s[i] = i_dest_bp[(CMUL*i)%NC];
                end
                assign core_dest_bp_s = i_src_bp;
                for (i=0;i<NC;i=i+1) for (j=0;j<MC;j=j+1) begin : g_grant
                    assign wfa_match_s[sc*NM + j*M + ((CMUL*i)%NC)] = core_grant_s[i*MC+j];
                end
                for (j=0;j<MC;j=j+1) begin : g_sv
                    assign wfa_sv_s[sc*N + j] = core_dest_vld_s[j];
                end
                for (i=0;i<NC;i=i+1) begin : g_dv
                    assign wfa_dv_s[sc*M + ((CMUL*i)%NC)] = core_src_vld_s[i];
                end
            end
        end
    endgenerate

    wire [NM-1:0] wfa_match;
    wire [N-1:0] wfa_src_vld;
    wire [M-1:0] wfa_dest_vld;
    reg [1:0] sched;
    assign wfa_match    = wfa_match_s[sched*NM +: NM];
    assign wfa_src_vld  = wfa_sv_s[sched*N +: N];
    assign wfa_dest_vld = wfa_dv_s[sched*M +: M];

    // Schedule counter: advance every MC grants.
    wire any_req_w;
    assign any_req_w = |eff_req;
    reg [CWM:0] scnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scnt  <= 0;
            sched <= 0;
        end else if (any_req_w) begin
            if (scnt == MC-1) begin
                scnt <= 0;
                if (sched == NS-1) sched <= 0;
                else sched <= sched + 1'b1;
            end else begin
                scnt <= scnt + 1'b1;
            end
        end
    end

    // Effective request / row/col activity
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
            // s_pick_i is zero when the row has no request, so the row-any
            // AND is redundant.
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
            // d_pick_j is zero when the column has no request.
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

    // Keep the WFA data on the fast input of the output mux: the override
    // selects are ready early, so the WFA result only pays one select.
    wire ov_sel_w;
    wire [NM-1:0] ov_match;
    assign ov_sel_w = use_src | use_dst;
    assign ov_match = use_src ? src_ov : dst_ov;
    wire [NM-1:0] match_final;
    assign match_final = ov_sel_w ? ov_match : wfa_match;

    localparam FUSE_VLD = ((N >= 10) || (M >= 10));

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
