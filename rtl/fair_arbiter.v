//=============================================================================
// fair_arbiter.v
//
// Default N-to-M crossbar arbiter: WRAPPED WAVEFRONT (WFA/WWFA).
//
// Structure:
//   fair_arbiter : port wrapper; if N > M it transposes the request matrix so
//                  the core always sees Nc=min(N,M), Mc=max(N,M).  The
//                  transpose is pure wiring, no gates.
//   wfa_core     : P = max(Nc,Mc) torus diagonals, P wavefront stages.
//
// Cell:
//     G = R & N & W
//     S = N & ~G
//     E = W & ~G
//
// The wavefront visits every crosspoint once, so the output is a MAXIMAL
// matching: no requested pair is left with both source and destination idle.
// It is not a MAXIMUM-cardinality matching; that is the accepted requirement.
//
// Implementation optimizations (versus the first WFA version):
//   - logarithmic cyclic rotators for the delta priority (P*logP muxes/row
//     instead of a runtime modulo + P-way mux per bit);
//   - N>M transpose wrapper (the symmetric algorithm always runs with the
//     smaller dimension as rows, saving rotation/encoder logic);
//   - reset gating on match is only instantiated for PTR_RESET=0 (the default
//     async-reset version has no redundant output AND gates).
//
// Parameters ITER and AUGMENT are accepted for compatibility with the older
// testbenches but are ignored.
//=============================================================================

`default_nettype none

//-----------------------------------------------------------------------------
// Core: N sources, M destinations (normally N <= M).  Flat request vector:
// bit i*M+j = source i requests destination j.
//-----------------------------------------------------------------------------
module wfa_core #(
    parameter integer N         = 8,
    parameter integer M         = 8,
    parameter integer PTR_RESET = 1
) (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire [N*M-1:0]            i_req_flat,
    input  wire [N-1:0]              i_src_bp,
    input  wire [M-1:0]              i_dest_bp,
    output wire [N*M-1:0]            o_grant_flat,
    output wire [N-1:0]              o_src_vld,
    output wire [N-1:0][$clog2(M)-1:0] o_src_ptr,
    output wire [M-1:0]              o_dest_vld,
    output wire [M-1:0][$clog2(N)-1:0] o_dest_ptr
);

    localparam integer CWN = $clog2(N);
    localparam integer CWM = $clog2(M);
    localparam integer NM  = N * M;
    localparam integer P   = (N > M) ? N : M;
    localparam integer CWP = $clog2(P);
    localparam integer PP  = P * P;

    genvar i, j, d, b;

    //=========================================================================
    // Logarithmic cyclic rotators.  Each set bit k of delta applies a fixed
    // rotation by 2^k mod P; composition gives +delta / -delta.  A stage is
    // P 2:1 muxes per row, so the cost is N*P*CWP muxes instead of a runtime
    // modulo plus a P-way mux for every output bit.
    //=========================================================================
    function automatic [P-1:0] rot_plus;
        input [P-1:0] v;
        input [CWP-1:0] sel;
        reg [P-1:0] w;
        reg [P-1:0] t;
        integer kk, jj;
        begin
            w = v;
            for (kk = 0; kk < CWP; kk = kk + 1) begin
                for (jj = 0; jj < P; jj = jj + 1)
                    t[jj] = sel[kk] ? w[(jj + (1 << kk)) % P] : w[jj];
                w = t;
            end
            rot_plus = w;
        end
    endfunction

    function automatic [P-1:0] rot_minus;
        input [P-1:0] v;
        input [CWP-1:0] sel;
        reg [P-1:0] w;
        reg [P-1:0] t;
        integer kk, jj;
        begin
            w = v;
            for (kk = 0; kk < CWP; kk = kk + 1) begin
                for (jj = 0; jj < P; jj = jj + 1)
                    t[jj] = sel[kk] ? w[(jj - (1 << kk) + P) % P] : w[jj];
                w = t;
            end
            rot_minus = w;
        end
    endfunction

    //=========================================================================
    // Padded request matrix (P x P).  Backpressure and reset are folded in.
    //=========================================================================
    wire [PP-1:0] req_pad;
    generate
        for (i = 0; i < P; i = i + 1) begin : gen_pad_row
            for (j = 0; j < P; j = j + 1) begin : gen_pad_bit
                if ((i < N) && (j < M)) begin : gen_real
                    assign req_pad[i*P + j] = i_req_flat[i*M + j] & rst_n
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
    // Request rotation: logical column j reads physical column (j+delta)%P.
    // Dummy rows are driven to 0 and do not instantiate a rotator.
    //=========================================================================
    wire [PP-1:0] req_w;
    generate
        for (i = 0; i < P; i = i + 1) begin : gen_rot_row
            if (i < N) begin : gen_rot_real
                assign req_w[i*P +: P] = rot_plus(req_pad[i*P +: P], delta);
            end else begin : gen_rot_dummy
                assign req_w[i*P +: P] = {P{1'b0}};
            end
        end
    endgenerate

    //=========================================================================
    // P-stage torus wavefront.  Stage d visits cells (i, (i+d)%P).  Each stage
    // has one cell per row and per column, so all P cells are independent.
    //=========================================================================
    wire [2*P*(P+1)-1:0] free_stage;
    assign free_stage[0 +: P] = {P{1'b1}};
    assign free_stage[P +: P] = {P{1'b1}};

    wire [PP-1:0] grant_w;
    generate
        for (d = 0; d < P; d = d + 1) begin : gen_stage
            wire [P-1:0] rf;
            wire [P-1:0] cf;
            assign rf = free_stage[d*2*P +: P];
            assign cf = free_stage[d*2*P+P +: P];

            for (i = 0; i < P; i = i + 1) begin : gen_cell
                localparam integer J = (i + d) % P;
                assign grant_w[i*P + J] = req_w[i*P + J] & rf[i] & cf[J];
                assign free_stage[(d+1)*2*P + i] = rf[i]
                                                 & ~(req_w[i*P + J] & cf[J]);
                assign free_stage[(d+1)*2*P + P + J] = cf[J]
                                                 & ~(req_w[i*P + J] & rf[i]);
            end
        end
    endgenerate

    //=========================================================================
    // Inverse rotation: physical (i,j) <- logical (i,(j-delta)%P).
    // The reset AND is only needed for the no-reset-pointer configuration;
    // with PTR_RESET=1 the delta register is reset and req_pad is already 0.
    //=========================================================================
    wire [PP-1:0] grant_rot;
    generate
        for (i = 0; i < N; i = i + 1) begin : gen_inv_row
            assign grant_rot[i*P +: P] = rot_minus(grant_w[i*P +: P], delta);
        end
    endgenerate

    wire [NM-1:0] match_raw;
    generate
        for (i = 0; i < N; i = i + 1) begin : gen_match_row
            for (j = 0; j < M; j = j + 1) begin : gen_match_bit
                assign match_raw[i*M + j] = grant_rot[i*P + j];
            end
        end
    endgenerate

    wire [NM-1:0] match_accept;
    generate
        if (PTR_RESET) begin : gen_match_rst
            assign match_accept = match_raw;
        end else begin : gen_match_norst
            assign match_accept = match_raw & {NM{rst_n}};
        end
    endgenerate

    assign any_grant = |match_accept;

    //=========================================================================
    // Outputs.
    //=========================================================================
    assign o_grant_flat = match_accept;

    generate
        for (i = 0; i < N; i = i + 1) begin : gen_out_src_vld
            assign o_src_vld[i] = |(match_accept[i*M +: M]);
        end
    endgenerate

    generate
        for (i = 0; i < N; i = i + 1) begin : gen_out_src_ptr
            for (b = 0; b < CWM; b = b + 1) begin : gen_out_src_ptr_bit
                wire [M-1:0] terms;
                for (j = 0; j < M; j = j + 1) begin : gen_out_src_ptr_term
                    assign terms[j] = match_accept[i*M + j]
                                    & ((j >> b) & 1'b1);
                end
                assign o_src_ptr[i][b] = |terms;
            end
        end
    endgenerate

    generate
        for (j = 0; j < M; j = j + 1) begin : gen_out_dest_vld
            wire [N-1:0] col;
            for (i = 0; i < N; i = i + 1) begin : gen_out_dest_vld_bit
                assign col[i] = match_accept[i*M + j];
            end
            assign o_dest_vld[j] = |col;
        end
    endgenerate

    generate
        for (j = 0; j < M; j = j + 1) begin : gen_out_dest_ptr
            for (b = 0; b < CWN; b = b + 1) begin : gen_out_dest_ptr_bit
                wire [N-1:0] terms;
                for (i = 0; i < N; i = i + 1) begin : gen_out_dest_ptr_term
                    assign terms[i] = match_accept[i*M + j]
                                    & ((i >> b) & 1'b1);
                end
                assign o_dest_ptr[j][b] = |terms;
            end
        end
    endgenerate

endmodule

//-----------------------------------------------------------------------------
// Top wrapper: symmetrize the problem (Nc=min, Mc=max) by transposing N>M.
// The transpose is pure wiring; the core always runs with the smaller
// dimension as its source rows.
//-----------------------------------------------------------------------------
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

    localparam integer NC = (N < M) ? N : M;   // core sources
    localparam integer MC = (N > M) ? N : M;   // core destinations

    wire [NC*MC-1:0] core_req;
    wire [NC-1:0]    core_src_bp;
    wire [MC-1:0]    core_dest_bp;
    wire [NC*MC-1:0] core_grant;
    wire [NC-1:0]    core_src_vld;
    wire [NC-1:0][$clog2(MC)-1:0] core_src_ptr;
    wire [MC-1:0]    core_dest_vld;
    wire [MC-1:0][$clog2(NC)-1:0] core_dest_ptr;

    genvar i, j;

    wfa_core #(.N(NC), .M(MC), .PTR_RESET(PTR_RESET)) u_core (
        .clk(clk), .rst_n(rst_n),
        .i_req_flat(core_req),
        .i_src_bp(core_src_bp), .i_dest_bp(core_dest_bp),
        .o_grant_flat(core_grant),
        .o_src_vld(core_src_vld), .o_src_ptr(core_src_ptr),
        .o_dest_vld(core_dest_vld), .o_dest_ptr(core_dest_ptr)
    );

    generate
        if (N <= M) begin : gen_direct
            // core sources = original sources; core dests = original dests
            for (i = 0; i < N; i = i + 1) begin : gen_req_row
                for (j = 0; j < M; j = j + 1) begin : gen_req_bit
                    assign core_req[i*M + j] = i_src_dest_req[i][j];
                end
            end
            assign core_src_bp = i_src_bp;
            assign core_dest_bp = i_dest_bp;

            for (i = 0; i < N; i = i + 1) begin : gen_grant_row
                for (j = 0; j < M; j = j + 1) begin : gen_grant_bit
                    assign o_grant_rand_vld[i][j] = core_grant[i*M + j];
                end
            end
            for (i = 0; i < N; i = i + 1) begin : gen_src_out
                assign o_grant_src_vld[i] = core_src_vld[i];
                assign o_grant_src_ptr[i] = core_src_ptr[i];
            end
            for (j = 0; j < M; j = j + 1) begin : gen_dst_out
                assign o_grant_dest_vld[j] = core_dest_vld[j];
                assign o_grant_dest_ptr[j] = core_dest_ptr[j];
            end
        end else begin : gen_trans
            // core source i = original dest i; core dest j = original source j
            for (i = 0; i < NC; i = i + 1) begin : gen_req_row
                for (j = 0; j < MC; j = j + 1) begin : gen_req_bit
                    assign core_req[i*MC + j] = i_src_dest_req[j][i];
                end
            end
            assign core_src_bp = i_dest_bp;
            assign core_dest_bp = i_src_bp;

            for (i = 0; i < N; i = i + 1) begin : gen_grant_row
                for (j = 0; j < M; j = j + 1) begin : gen_grant_bit
                    assign o_grant_rand_vld[i][j] = core_grant[j*MC + i];
                end
            end
            for (i = 0; i < N; i = i + 1) begin : gen_src_out
                assign o_grant_src_vld[i] = core_dest_vld[i];
                assign o_grant_src_ptr[i] = core_dest_ptr[i];
            end
            for (j = 0; j < M; j = j + 1) begin : gen_dst_out
                assign o_grant_dest_vld[j] = core_src_vld[j];
                assign o_grant_dest_ptr[j] = core_src_ptr[j];
            end
        end
    endgenerate

endmodule

`default_nettype wire
