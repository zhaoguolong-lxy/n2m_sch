//=============================================================================
// wfa_core_pipe.v - pipelined wavefront matching core (throughput 1/cycle).
//
// The P-stage wavefront is cut after SPLIT stages: the free tokens and the
// partial grants are registered, the remaining stages run in the next cycle.
// A new request can be accepted every cycle, so the throughput is unchanged;
// only the latency grows by one cycle.
//
// The delta register lives here (it advances on any request), and the value
// used by the second half is captured in the pipeline register.
//=============================================================================

`default_nettype none

module wfa_core_pipe #(
    parameter integer N         = 8,
    parameter integer M         = 8,
    parameter integer PTR_RESET = 1,
    parameter integer SPLIT     = 0
) (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire [N*M-1:0]            i_req_flat,
    input  wire [N-1:0]              i_src_bp,
    input  wire [M-1:0]              i_dest_bp,
    output wire [N*M-1:0]            o_grant_flat,
    output wire [N-1:0]              o_src_vld,
    output wire [M-1:0]              o_dest_vld
);

    localparam integer CWN = $clog2(N);
    localparam integer CWM = $clog2(M);
    localparam integer NM  = N * M;
    localparam integer P   = (N > M) ? N : M;
    localparam integer CWP = $clog2(P);
    localparam integer PP  = P * P;
    // Auto split: ~70% of the stages in the first half balances the two
    // pipeline legs for P=8..11 (8x8 prefers 6, the P=10/11 shapes 7).
    localparam integer SP_AUTO = (P <= 8) ? 6 : 7;
    localparam integer SP  = (SPLIT < 1) ? ((SP_AUTO > P - 1) ? P - 1 : SP_AUTO)
                          : (SPLIT > P - 1 ? P - 1 : SPLIT);

    genvar i, j, d;

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

    reg [CWP-1:0] delta;
    wire any_req;
    assign any_req = |req_pad;

    generate
        if (PTR_RESET) begin : gen_d_rst
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    delta <= {CWP{1'b0}};
                end else if (any_req) begin
                    if (delta == P - 1) delta <= {CWP{1'b0}};
                    else delta <= delta + 1'b1;
                end
            end
        end else begin : gen_d_norst
            always @(posedge clk) begin
                if (any_req) begin
                    if (delta == P - 1) delta <= {CWP{1'b0}};
                    else delta <= delta + 1'b1;
                end
            end
        end
    endgenerate

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

    //-------------------------------------------------------------------------
    // First half: stages 0 .. SP-1 (combinational, cycle A).
    //-------------------------------------------------------------------------
    wire [2*P*(SP+1)-1:0] free_a;
    assign free_a[0 +: P] = {P{1'b1}};
    assign free_a[P +: P] = {P{1'b1}};

    wire [SP*P-1:0] grant_a;
    generate
        for (d = 0; d < SP; d = d + 1) begin : gen_stage_a
            wire [P-1:0] rf;
            wire [P-1:0] cf;
            assign rf = free_a[d*2*P +: P];
            assign cf = free_a[d*2*P+P +: P];
            for (i = 0; i < P; i = i + 1) begin : gen_cell_a
                localparam integer J = (i + d) % P;
                assign grant_a[d*P + i] = req_w[i*P + J] & rf[i] & cf[J];
                assign free_a[(d+1)*2*P + i] = rf[i]
                                             & ~(req_w[i*P + J] & cf[J]);
                assign free_a[(d+1)*2*P + P + J] = cf[J]
                                             & ~(req_w[i*P + J] & rf[i]);
            end
        end
    endgenerate

    //-------------------------------------------------------------------------
    // Pipeline registers.
    //-------------------------------------------------------------------------
    reg [2*P-1:0] mid_tok;
    reg [SP*P-1:0] grant_a_r;
    reg [CWP-1:0] delta_r;
    reg [PP-1:0] req_w_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mid_tok   <= {2*P{1'b1}};
            grant_a_r <= {SP*P{1'b0}};
            delta_r   <= {CWP{1'b0}};
            req_w_r   <= {PP{1'b0}};
        end else begin
            mid_tok   <= free_a[SP*2*P +: 2*P];
            grant_a_r <= grant_a;
            delta_r   <= delta;
            req_w_r   <= req_w;
        end
    end

    //-------------------------------------------------------------------------
    // Second half: stages SP .. P-1 (combinational, cycle B).
    //-------------------------------------------------------------------------
    wire [2*P*(P-SP+1)-1:0] free_b;
    assign free_b[0 +: 2*P] = mid_tok;

    wire [PP-1:0] grant_w;
    generate
        // first-half grants come from the pipeline register
        for (d = 0; d < SP; d = d + 1) begin : gen_grant_a
            for (i = 0; i < P; i = i + 1) begin : gen_ga
                localparam integer J = (i + d) % P;
                assign grant_w[i*P + J] = grant_a_r[d*P + i];
            end
        end
        for (d = SP; d < P; d = d + 1) begin : gen_stage_b
            wire [P-1:0] rf;
            wire [P-1:0] cf;
            assign rf = free_b[(d-SP)*2*P +: P];
            assign cf = free_b[(d-SP)*2*P+P +: P];
            for (i = 0; i < P; i = i + 1) begin : gen_cell_b
                localparam integer J = (i + d) % P;
                assign grant_w[i*P + J] = req_w_r[i*P + J] & rf[i] & cf[J];
                assign free_b[(d-SP+1)*2*P + i] = rf[i]
                                                & ~(req_w_r[i*P + J] & cf[J]);
                assign free_b[(d-SP+1)*2*P + P + J] = cf[J]
                                                & ~(req_w_r[i*P + J] & rf[i]);
            end
        end
    endgenerate

    wire [P-1:0] row_free_final;
    wire [P-1:0] col_free_final;
    assign row_free_final = free_b[(P-SP)*2*P +: P];
    assign col_free_final = free_b[(P-SP)*2*P + P +: P];

    wire [P-1:0] dest_vld_w;
    assign dest_vld_w = rot_minus(col_free_final, delta_r);

    wire [PP-1:0] grant_rot;
    generate
        for (i = 0; i < N; i = i + 1) begin : gen_inv_row
            assign grant_rot[i*P +: P] = rot_minus(grant_w[i*P +: P], delta_r);
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

    assign o_grant_flat = match_accept;

    generate
        for (i = 0; i < N; i = i + 1) begin : gen_out_src_vld
            assign o_src_vld[i] = ~row_free_final[i];
        end
    endgenerate

    generate
        for (j = 0; j < M; j = j + 1) begin : gen_out_dest_vld
            assign o_dest_vld[j] = ~dest_vld_w[j];
        end
    endgenerate

endmodule

`default_nettype wire
