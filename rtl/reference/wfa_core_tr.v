//=============================================================================
// wfa_core_tr.v - classic token-ring Wavefront Arbiter core (reference).
//
// The request matrix is fixed; no input/output data rotation.  A one-hot
// column token (pc_oh) and a one-hot row token (pr_oh) select the top-priority
// cell (pr,pc).  North/west tokens propagate south/east through the PxP cell
// array:
//
//   g(i,j) = req(i,j) & n(i,j) & w(i,j)
//   s(i,j) = n(i,j) & ~g(i,j)
//   e(i,j) = w(i,j) & ~g(i,j)
//
// The array is acyclic: n/w come from above/left, s/e go down/right.  The
// priority cell advances row-major (pc every cycle, pr every P cycles).
//
// This is the classic WFA (Tamir & Chi), (2P-1) cell stages.  It removes the
// data rotators of the torus core, but has nearly twice the wavefront stages.
//
// STATUS: incomplete / negative-result reference.  The naive top/left
// boundary injection used here is not maximal for an arbitrary priority cell:
// the tokens can be consumed by cells above/left before reaching (pr,pc).
// Measured on the maximality bench: 10x10 average size 0.51/10 (5.1%), with
// 763/773 non-maximal cycles.  The correct classic WFA needs wrap-around
// edges (which introduce combinational loops) or a data permutation.  This
// file is kept to document why the current torus uses data rotation; it is
// NOT integrated into fair_arbiter.
//=============================================================================

`default_nettype none

module wfa_core_tr #(
    parameter integer N = 8,
    parameter integer M = 8,
    parameter integer PTR_RESET = 1
) (
    input  wire           clk,
    input  wire           rst_n,
    input  wire [N*M-1:0] i_req_flat,
    input  wire [N-1:0]   i_src_bp,
    input  wire [M-1:0]   i_dest_bp,
    output wire [N*M-1:0] o_grant_flat,
    output wire [N-1:0]   o_src_vld,
    output wire [M-1:0]   o_dest_vld
);
    localparam integer P  = (N > M) ? N : M;
    localparam integer PP = P * P;
    genvar i, j;

    wire [PP-1:0] req_pad;
    generate
        for (i = 0; i < P; i = i + 1) begin : g_pad_row
            for (j = 0; j < P; j = j + 1) begin : g_pad_col
                if ((i < N) && (j < M)) begin : g_real
                    assign req_pad[i*P+j] = i_req_flat[i*M+j] & rst_n
                                          & ~i_src_bp[i] & ~i_dest_bp[j];
                end else begin : g_dummy
                    assign req_pad[i*P+j] = 1'b0;
                end
            end
        end
    endgenerate

    // Row-major priority cell: pc advances every cycle, pr every P cycles.
    // One-hot shift registers avoid binary comparators at the boundaries.
    reg [P-1:0] pc_oh;
    reg [P-1:0] pr_oh;
    wire any_req;
    assign any_req = |req_pad;

    generate
        if (PTR_RESET) begin : g_pri_rst
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    pc_oh <= {{(P-1){1'b0}}, 1'b1};
                    pr_oh <= {{(P-1){1'b0}}, 1'b1};
                end else if (any_req) begin
                    pc_oh <= {pc_oh[P-2:0], pc_oh[P-1]};
                    if (pc_oh[P-1])
                        pr_oh <= {pr_oh[P-2:0], pr_oh[P-1]};
                end
            end
        end else begin : g_pri_norst
            always @(posedge clk) begin
                if (any_req) begin
                    pc_oh <= {pc_oh[P-2:0], pc_oh[P-1]};
                    if (pc_oh[P-1])
                        pr_oh <= {pr_oh[P-2:0], pr_oh[P-1]};
                end
            end
        end
    endgenerate

    // Token network.  n/w are the tokens entering from north/west; s/e leave
    // south/east.  Top boundary is the one-hot column token; left boundary is
    // the one-hot row token.
    wire [PP-1:0] n_tok, w_tok, s_tok, e_tok, grant;
    generate
        for (i = 0; i < P; i = i + 1) begin : g_row
            for (j = 0; j < P; j = j + 1) begin : g_cell
                wire n_in = (i == 0) ? pc_oh[j]
                                     : s_tok[(i-1)*P+j];
                wire w_in = (j == 0) ? pr_oh[i]
                                     : e_tok[i*P+(j-1)];
                assign n_tok[i*P+j] = n_in;
                assign w_tok[i*P+j] = w_in;
                assign grant[i*P+j] = req_pad[i*P+j] & n_in & w_in;
                assign s_tok[i*P+j] = n_in & ~grant[i*P+j];
                assign e_tok[i*P+j] = w_in & ~grant[i*P+j];
            end
        end
    endgenerate

    generate
        for (i = 0; i < N; i = i + 1) begin : g_out_row
            for (j = 0; j < M; j = j + 1) begin : g_out_col
                assign o_grant_flat[i*M+j] = grant[i*P+j];
            end
            assign o_src_vld[i] = |grant[i*P +: M];
        end
    endgenerate
    generate
        for (j = 0; j < M; j = j + 1) begin : g_out_col
            wire [N-1:0] col;
            for (i = 0; i < N; i = i + 1)
                assign col[i] = grant[i*P+j];
            assign o_dest_vld[j] = |col;
        end
    endgenerate

endmodule

`default_nettype wire
