//=============================================================================
// fair_arbiter_wtf.v - WTF-style prototype: iSLIP first pass + row waterfall.
//
// This is a comparison prototype, NOT a bit-exact reproduction of the WTF
// paper (Liu/Jantsch/Lu, TVLSI 2014).  The published paper is only four pages
// and the cell-level detail is not public; this module captures the
// algorithm-level idea described in the paper and in Liu's KTH thesis:
//
//   1. A first iSLIP grant/accept pass with per-destination g_ptr and
//      per-source a_ptr.  This gives strict single-source / single-destination
//      RR and the per-port priority layer.
//   2. A row-serial "waterfall" fill on the residual: unmatched rows are
//      visited in a rotating order, each picks the first free requested
//      destination from its a_ptr, and the free set shrinks as it flows down
//      the rows.  This is maximal by construction and loop-free.
//   3. a_ptr/g_ptr advance on the final match; the fill start row rotates
//      every cycle with a grant.
//
// The point of the prototype is to compare this O(N) row-ripple fill against
// the O(N) wavefront fill of fair_arbiter_fair.v at the same interface:
// maximality, strict 42/42 RR, Jain fairness, area and depth.
//
// MEASURED (Yosys generic, 2026-11):
//   8x8  : 3100 cells / 122 levels   (FILL=0: 1467 / 27, but 394/773 non-max)
//   10x10: 6924 cells / 187 levels   (FILL=0: 2564 / 32, but 476/773 non-max)
//   strict RR 42/42, maximality 18/18 shapes, K-regular Jain 1.000.
// The row-ripple fill dominates the depth, so this prototype is NOT a
// replacement for the 31/35-level WFA; it is a fairness/maximality reference.
// See docs/literature.md section 4.2.
//=============================================================================

`default_nettype none

module fair_arbiter_wtf #(
    parameter integer N=8, M=8, PTR_RESET=1, ITER=4, AUGMENT=1, NSCHED=1,
    parameter integer FILL=1
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
    genvar i,j,k,b;

    wire [NM-1:0] eff_req;
    generate for (i=0;i<N;i=i+1) begin : gen_eff_row
        for (j=0;j<M;j=j+1) begin : gen_eff_bit
            assign eff_req[i*M+j] = i_src_dest_req[i][j] & rst_n
                                  & ~i_src_bp[i] & ~i_dest_bp[j];
        end
    end endgenerate

    reg [M*CWN-1:0] g_ptr;
    reg [N*CWM-1:0] a_ptr;
    reg [CWN-1:0]   start;

    //------------------------------------------------------------------
    // First iSLIP pass: grant stage.
    //------------------------------------------------------------------
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

    //------------------------------------------------------------------
    // First iSLIP pass: accept stage.
    //------------------------------------------------------------------
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

    // Residual request: both endpoints unmatched after the first pass.
    wire [NM-1:0] res_req;
    generate for (i=0;i<N;i=i+1) begin : gen_res_row
        for (j=0;j<M;j=j+1) begin : gen_res_bit
            assign res_req[i*M+j] = eff_req[i*M+j]
                                  & ~first_src_match[i] & ~first_dst_match[j];
        end
    end endgenerate

    //------------------------------------------------------------------
    // Row waterfall fill.
    //
    // Step k visits row (start+k)%N.  free[k*M +: M] is the destination
    // availability before step k.  Each visited row picks the first free
    // requested destination from its a_ptr; the pick is removed from the
    // free set for all later rows.  Every row is visited exactly once, so
    // an unmatched row had no free requested destination at its turn and
    // cannot gain one later: the result is maximal.
    //------------------------------------------------------------------
    wire [(N+1)*M-1:0] free;
    assign free[0 +: M] = ~first_dst_match;

    wire [NM-1:0] fill_step;
    generate
        for (k=0;k<N;k=k+1) begin : gen_fill
            wire [CWN-1:0] row_k;
            wire [CWM-1:0] ptr_k;
            wire [M-1:0]   avail, mask_hi, hi, lo, pick;
            assign row_k = (start + k >= N) ? (start + k - N)
                                            : (start + k);
            assign ptr_k = a_ptr[row_k*CWM +: CWM];
            for (j=0;j<M;j=j+1) begin : gen_bit
                assign avail[j] = res_req[row_k*M+j] & free[k*M+j]
                                & ~first_src_match[row_k];
                assign mask_hi[j] = (j >= ptr_k);
                assign hi[j] = avail[j] &  mask_hi[j];
                assign lo[j] = avail[j] & ~mask_hi[j];
            end
            assign pick = (|hi) ? (hi & ~(hi-1'b1))
                                : (lo & ~(lo-1'b1));
            assign fill_step[k*M +: M] = pick;
            assign free[(k+1)*M +: M] = free[k*M +: M] & ~pick;
        end
    endgenerate

    // Map step k back to row (start+k)%N.  Each row owns exactly one step.
    wire [NM-1:0] fill_grant;
    generate for (i=0;i<N;i=i+1) begin : gen_fmap
        wire [CWN-1:0] kk;
        assign kk = (i >= start) ? (i - start) : (i + N - start);
        for (j=0;j<M;j=j+1) begin : gen_fmap_bit
            assign fill_grant[i*M+j] = fill_step[kk*M+j];
        end
    end endgenerate

    wire [NM-1:0] match_accept;
    assign match_accept = first_accept | (FILL ? fill_grant : {NM{1'b0}});

    //------------------------------------------------------------------
    // Outputs.
    //------------------------------------------------------------------
    assign o_grant_rand_vld = match_accept;
    generate for (i=0;i<N;i=i+1) begin : gen_sv
        assign o_grant_src_vld[i] = |(match_accept[i*M +: M]);
    end endgenerate
    generate for (i=0;i<N;i=i+1) begin : gen_sp
        for (b=0;b<CWM;b=b+1) begin : gen_spb
            wire [M-1:0] terms;
            for (j=0;j<M;j=j+1)
                assign terms[j] = match_accept[i*M+j] & ((j>>b)&1'b1);
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
            for (i=0;i<N;i=i+1)
                assign terms[i] = match_accept[i*M+j] & ((i>>b)&1'b1);
            assign o_grant_dest_ptr[j][b] = |terms;
        end
    end endgenerate

    //------------------------------------------------------------------
    // State: a_ptr/g_ptr advance on the final match, start row rotates.
    //------------------------------------------------------------------
    function automatic [CWM-1:0] idx_m;
        input [M-1:0] oh;
        integer t; reg [CWM-1:0] v;
        begin
            v=0; for (t=0;t<M;t=t+1) if (oh[t]) v=t; idx_m=v;
        end
    endfunction
    function automatic [CWN-1:0] idx_n;
        input [N-1:0] oh;
        integer t; reg [CWN-1:0] v;
        begin
            v=0; for (t=0;t<N;t=t+1) if (oh[t]) v=t; idx_n=v;
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

    generate
        if (PTR_RESET) begin : gen_start_rst
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) start <= 0;
                else if (|match_accept) begin
                    if (start == N-1) start <= 0;
                    else start <= start + 1'b1;
                end
            end
        end else begin : gen_start_norst
            always @(posedge clk) begin
                if (|match_accept) begin
                    if (start == N-1) start <= 0;
                    else start <= start + 1'b1;
                end
            end
        end
    endgenerate

endmodule

`default_nettype wire
