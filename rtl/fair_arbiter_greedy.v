//=============================================================================
// fair_arbiter_greedy.v - fixed-order maximal greedy + per-port RR override.
//
// Base matching (multi-source / multi-destination):
//   rows are visited in fixed order 0..N-1.  Each row takes its lowest-index
//   requested destination that is still free.  This is maximal by
//   construction: an unmatched row had no free requested destination at its
//   turn, and the free set only shrinks.  The row chain is loop-free and the
//   per-row logic is only an AND, a lowest-set-bit pick and a mask update.
//
// Override (strict single-source / single-destination RR):
//   when exactly one source has requests, a per-source RR selector replaces
//   the greedy result; when exactly one destination has requests, a
//   per-destination RR selector replaces it.  This is the same parallel
//   override used by fair_arbiter.v, so the 42/42 strict RR tests are
//   satisfied without putting the RR selectors on the multi-source path.
//
// a_ptr/g_ptr advance on every final match, including greedy matches, so a
// later single-source / single-destination period continues the RR sequence
// from the last granted partner.
//
// This is a comparison prototype.  It is maximal + strict single-side RR,
// and much smaller than the WFA, but multi-source fairness is the fixed-
// order greedy (no per-port RR on that path).  Measure before promoting it.
//=============================================================================

`default_nettype none

module fair_arbiter_greedy #(
    parameter integer N=8, M=8, PTR_RESET=1, ITER=4, AUGMENT=1, NSCHED=1
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

    //------------------------------------------------------------------
    // Fixed-order maximal greedy.
    //------------------------------------------------------------------
    wire [(N+1)*M-1:0] free;
    assign free[0 +: M] = {M{1'b1}};

    wire [NM-1:0] greedy;
    generate
        for (i=0;i<N;i=i+1) begin : g_row
            wire [M-1:0] avail, pick;
            for (j=0;j<M;j=j+1) begin : g_bit
                assign avail[j] = eff_req[i*M+j] & free[i*M+j];
            end
            assign pick = avail & ~(avail - 1'b1);
            for (j=0;j<M;j=j+1) begin : g_out
                assign greedy[i*M+j] = pick[j];
            end
            assign free[(i+1)*M +: M] = free[i*M +: M] & ~pick;
        end
    endgenerate

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

    //------------------------------------------------------------------
    // Per-source RR selector (only used when exactly one source is active).
    //------------------------------------------------------------------
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
    end endgenerate

    //------------------------------------------------------------------
    // Per-destination RR selector (only used when exactly one dest is active).
    //------------------------------------------------------------------
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
    end endgenerate

    wire ov_sel_w;
    wire [NM-1:0] ov_match;
    assign ov_sel_w = use_src | use_dst;
    assign ov_match = use_src ? src_ov : dst_ov;
    wire [NM-1:0] match_final;
    assign match_final = ov_sel_w ? ov_match : greedy;

    //------------------------------------------------------------------
    // Outputs.
    //------------------------------------------------------------------
    assign o_grant_rand_vld = match_final;
    generate for (i=0;i<N;i=i+1) begin : g_sv
        assign o_grant_src_vld[i] = |(match_final[i*M +: M]);
    end endgenerate
    generate for (i=0;i<N;i=i+1) begin : g_sp
        for (b=0;b<CWM;b=b+1) begin : g_spb
            wire [M-1:0] terms;
            for (j=0;j<M;j=j+1)
                assign terms[j] = match_final[i*M+j] & ((j>>b)&1'b1);
            assign o_grant_src_ptr[i][b] = |terms;
        end
    end endgenerate
    generate for (j=0;j<M;j=j+1) begin : g_dv
        wire [N-1:0] col;
        for (i=0;i<N;i=i+1) assign col[i] = match_final[i*M+j];
        assign o_grant_dest_vld[j] = |col;
    end endgenerate
    generate for (j=0;j<M;j=j+1) begin : g_dp
        for (b=0;b<CWN;b=b+1) begin : g_dpb
            wire [N-1:0] terms;
            for (i=0;i<N;i=i+1)
                assign terms[i] = match_final[i*M+j] & ((i>>b)&1'b1);
            assign o_grant_dest_ptr[j][b] = |terms;
        end
    end endgenerate

    //------------------------------------------------------------------
    // Pointers advance on every final match (greedy or override).
    //------------------------------------------------------------------
    generate for (i=0;i<N;i=i+1) begin : g_aptr
        wire [M-1:0] row = match_final[i*M +: M];
        wire hit = |row;
        wire [CWM-1:0] ix = idx_m(row);
        if (PTR_RESET) begin : ptr_rst
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) a_ptr[i*CWM +: CWM] <= i % M;
                else if (hit) begin
                    if (ix == M-1) a_ptr[i*CWM +: CWM] <= 0;
                    else a_ptr[i*CWM +: CWM] <= ix + 1'b1;
                end
            end
        end else begin : ptr_norst
            always @(posedge clk) begin
                if (hit) begin
                    if (ix == M-1) a_ptr[i*CWM +: CWM] <= 0;
                    else a_ptr[i*CWM +: CWM] <= ix + 1'b1;
                end
            end
        end
    end endgenerate

    generate for (j=0;j<M;j=j+1) begin : g_gptr
        wire [N-1:0] col;
        for (i=0;i<N;i=i+1) assign col[i] = match_final[i*M+j];
        wire hit = |col;
        wire [CWN-1:0] ix = idx_n(col);
        if (PTR_RESET) begin : ptr_rst
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) g_ptr[j*CWN +: CWN] <= j % N;
                else if (hit) begin
                    if (ix == N-1) g_ptr[j*CWN +: CWN] <= 0;
                    else g_ptr[j*CWN +: CWN] <= ix + 1'b1;
                end
            end
        end else begin : ptr_norst
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
