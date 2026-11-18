//=============================================================================
// fair_arbiter.v  (default: Wavefront / WWFA implementation)
//
// N-to-M work-conserving crossbar arbiter using the classic WRAPPED WAVEFRONT
// (WWFA) diagonal scan of Tamir & Chi, implemented with P = max(N,M) stages.
//
// This is the default implementation:
//   - request matrix padded to P x P;
//   - P torus diagonals, each with P cells (one per row/column);
//   - a single rotating column offset delta gives every cell top priority in
//     turn;
//   - P wavefront stages instead of N+M-1 and instead of a serial fill chain.
//
// Cell (i, j) of a diagonal grants when
//     G = R & row_free(i) & col_free(j)
// and clears row i and column j for the later diagonals.  The wave visits every
// crosspoint once, so no requested pair can remain with both ends idle: this is
// a MAXIMAL (work-conserving) matching.  It is not a maximum-cardinality
// matching, which is exactly the allowed behaviour.
//
// Depth: P wavefront stages plus a column-rotation mux before the array and
// its inverse after the array.  For P <= 10 this is around 40 generic gate
// levels; for larger P the output encoders / rotation can be pipelined or the
// wavefront can be split.  The only state is delta (one small register).
//
// Parameters ITER and AUGMENT are accepted for compatibility and ignored.
//=============================================================================

`default_nettype none

module fair_arbiter #(
    parameter integer N         = 8,
    parameter integer M         = 8,
    parameter integer PTR_RESET = 1,
    parameter integer ITER      = 4,    // legacy, ignored
    parameter integer AUGMENT   = 1     // legacy, ignored
) (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire [N-1:0][M-1:0]       i_src_dest_req,
    input  wire [N-1:0]              i_src_bp,
    input  wire [M-1:0]              i_dest_bp,
    output wire [N-1:0][M-1:0]       o_grant_rand_vld,
    output wire [N-1:0]              o_grant_src_vld,
    output wire [N-1:0][$clog2(M)-1:0] o_grant_src_ptr,
    output wire [M-1:0]              o_grant_dest_vld,
    output wire [M-1:0][$clog2(N)-1:0] o_grant_dest_ptr
);

    localparam integer CWN = $clog2(N);
    localparam integer CWM = $clog2(M);
    localparam integer NM  = N * M;
    localparam integer P   = (N > M) ? N : M;
    localparam integer CWP = $clog2(P);
    localparam integer PP  = P * P;

    genvar i, j, d, b;

    //=========================================================================
    // Padded request matrix (P x P).  Backpressure and reset are folded in.
    //=========================================================================
    wire [PP-1:0] req_pad;
    generate
        for (i = 0; i < P; i = i + 1) begin : gen_pad_row
            for (j = 0; j < P; j = j + 1) begin : gen_pad_bit
                if ((i < N) && (j < M)) begin : gen_real
                    assign req_pad[i*P + j] = i_src_dest_req[i][j] & rst_n
                                            & ~i_src_bp[i] & ~i_dest_bp[j];
                end else begin : gen_dummy
                    assign req_pad[i*P + j] = 1'b0;
                end
            end
        end
    endgenerate

    //=========================================================================
    // Rotating column offset.  delta is the only sequential state.
    //=========================================================================
    reg [CWP-1:0] delta;
    wire any_grant;

    generate
        if (PTR_RESET) begin : gen_d_rst
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    delta <= {CWP{1'b0}};
                end else if (any_grant) begin
                    if (delta == P - 1) begin
                        delta <= {CWP{1'b0}};
                    end else begin
                        delta <= delta + 1'b1;
                    end
                end
            end
        end else begin : gen_d_norst
            always @(posedge clk) begin
                if (any_grant) begin
                    if (delta == P - 1) begin
                        delta <= {CWP{1'b0}};
                    end else begin
                        delta <= delta + 1'b1;
                    end
                end
            end
        end
    endgenerate

    //=========================================================================
    // Column rotation: logical column jp reads physical column (jp+delta)%P.
    // Stage d then visits cells (i, (i+d)%P) of the logical matrix.
    //=========================================================================
    wire [PP-1:0] req_w;
    generate
        for (i = 0; i < P; i = i + 1) begin : gen_rot_row
            for (j = 0; j < P; j = j + 1) begin : gen_rot_bit
                wire [CWP-1:0] pj;
                assign pj = (j + delta >= P) ? (j + delta - P) : (j + delta);
                assign req_w[i*P + j] = req_pad[i*P + pj] & rst_n;
            end
        end
    endgenerate

    //=========================================================================
    // P-stage torus wavefront.  Stage d visits cells (i, (i+d)%P).  Each stage
    // has one cell per row and per column, so all P cells are independent.
    //=========================================================================
    wire [2*P*(P+1)-1:0] free_stage;
    assign free_stage[0 +: P] = {P{1'b1}};          // row_free before stage 0
    assign free_stage[P +: P] = {P{1'b1}};          // col_free before stage 0

    wire [PP-1:0] grant_w;
    generate
        for (d = 0; d < P; d = d + 1) begin : gen_stage
            wire [P-1:0] rf;
            wire [P-1:0] cf;
            assign rf = free_stage[d*2*P +: P];
            assign cf = free_stage[d*2*P+P +: P];

            for (i = 0; i < P; i = i + 1) begin : gen_cell
                localparam integer J = (i + d) % P;
                // grant = R & N & W; token updates are factored so the
                // critical path through a token is only an AND and a NAND.
                assign grant_w[i*P + J] = req_w[i*P + J] & rf[i] & cf[J];
                assign free_stage[(d+1)*2*P + i] = rf[i]
                                                 & ~(req_w[i*P + J] & cf[J]);
                assign free_stage[(d+1)*2*P + P + J] = cf[J]
                                                 & ~(req_w[i*P + J] & rf[i]);
            end
        end
    endgenerate

    //=========================================================================
    // Inverse column rotation: physical (i,j) <- logical (i, (j-delta)%P).
    //=========================================================================
    wire [NM-1:0] match_accept;
    generate
        for (i = 0; i < N; i = i + 1) begin : gen_inv_row
            for (j = 0; j < M; j = j + 1) begin : gen_inv_bit
                wire [CWP-1:0] lj;
                assign lj = (j >= delta) ? (j - delta)
                                         : (j + P - delta);
                assign match_accept[i*M + j] = grant_w[i*P + lj] & rst_n;
            end
        end
    endgenerate

    assign any_grant = |match_accept;

    //=========================================================================
    // Outputs.
    //=========================================================================
    assign o_grant_rand_vld = match_accept;

    generate
        for (i = 0; i < N; i = i + 1) begin : gen_out_src_vld
            assign o_grant_src_vld[i] = |(match_accept[i*M +: M]);
        end
    endgenerate

    generate
        for (i = 0; i < N; i = i + 1) begin : gen_out_src_ptr
            for (j = 0; j < CWM; j = j + 1) begin : gen_out_src_ptr_bit
                wire [M-1:0] terms;
                for (b = 0; b < M; b = b + 1) begin : gen_out_src_ptr_term
                    assign terms[b] = match_accept[i*M + b] & ((b >> j) & 1'b1);
                end
                assign o_grant_src_ptr[i][j] = |terms;
            end
        end
    endgenerate

    generate
        for (j = 0; j < M; j = j + 1) begin : gen_out_dest_vld
            wire [N-1:0] col;
            for (i = 0; i < N; i = i + 1) begin : gen_out_dest_vld_bit
                assign col[i] = match_accept[i*M + j];
            end
            assign o_grant_dest_vld[j] = |col;
        end
    endgenerate

    generate
        for (j = 0; j < M; j = j + 1) begin : gen_out_dest_ptr
            for (b = 0; b < CWN; b = b + 1) begin : gen_out_dest_ptr_bit
                wire [N-1:0] terms;
                for (i = 0; i < N; i = i + 1) begin : gen_out_dest_ptr_term
                    assign terms[i] = match_accept[i*M + j] & ((i >> b) & 1'b1);
                end
                assign o_grant_dest_ptr[j][b] = |terms;
            end
        end
    endgenerate

endmodule

`default_nettype wire
