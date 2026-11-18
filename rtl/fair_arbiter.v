//=============================================================================
// fair_arbiter.v - top-level N-to-M fair arbiter.
//
// TOP-LEVEL INTERFACE (exactly the required signals; DO NOT RENAME/CHANGE):
//   input  clk
//   input  rst_n
//   input  [N-1:0][M-1:0]       i_src_dest_req
//   input  [N-1:0]              i_src_bp
//   input  [M-1:0]              i_dest_bp
//   output [N-1:0][M-1:0]       o_grant_rand_vld
//   output [N-1:0]              o_grant_src_vld
//   output [N-1:0][clog2(M)-1:0] o_grant_src_ptr
//   output [M-1:0]              o_grant_dest_vld
//   output [M-1:0][clog2(N)-1:0] o_grant_dest_ptr
//
// Internals:
//   - fair_arbiter : this wrapper; for N>M it transposes the request so the
//                    core always runs with Nc=min(N,M), Mc=max(N,M).
//   - wfa_core     : P=max(Nc,Mc) torus wavefront (rtl/wfa_core.v).
//
// The wrapper does not change the required port names, widths or directions.
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

`default_nettype wire
