//=============================================================================
// wfa_core_fixed.v - SPIKE: wavefront core with a CONSTANT diagonal offset.
//
// Identical matching to wfa_core, but delta is the compile-time DELTA_VAL, so
// the input/output "rotation" is pure wiring (0 logic levels) and there is no
// delta register / barrel shifter.  Used by the replicate/bank spike to test
// whether removing the runtime rotators reduces depth.  Throwaway reference.
//=============================================================================
`default_nettype none
module wfa_core_fixed #(
    parameter integer N = 8, M = 8, PTR_RESET = 1,
    parameter integer DELTA_VAL = 0,
    parameter integer AOI_STYLE = 1
) (
    input  wire           clk, rst_n,
    input  wire [N*M-1:0] i_req_flat,
    input  wire [N-1:0]   i_src_bp,
    input  wire [M-1:0]   i_dest_bp,
    output wire [N*M-1:0] o_grant_flat,
    output wire [N-1:0]   o_src_vld,
    output wire [M-1:0]   o_dest_vld
);
    localparam integer P=(N>M)?N:M, CWP=$clog2(P), PP=P*P;
    localparam integer DV=((DELTA_VAL%P)+P)%P;
    genvar i,j,d;

    wire [PP-1:0] req_pad;
    generate for (i=0;i<P;i=i+1) begin : gr
        for (j=0;j<P;j=j+1) begin : gc
            if ((i<N)&&(j<M)) begin : rl
                assign req_pad[i*P+j] = i_req_flat[i*M+j] & rst_n
                                      & ~i_src_bp[i] & ~i_dest_bp[j];
            end else begin : dm
                assign req_pad[i*P+j] = 1'b0;
            end
        end
    end endgenerate

    // constant rotation = wiring
    wire [PP-1:0] req_w;
    generate for (i=0;i<P;i=i+1) begin : rw
        for (j=0;j<P;j=j+1) begin : rc
            assign req_w[i*P+j] = req_pad[i*P + ((j+DV)%P)];
        end
    end endgenerate

    wire [2*P*(P+1)-1:0] free_stage;
    assign free_stage[0 +: P] = {P{1'b1}};
    assign free_stage[P +: P] = {P{1'b1}};
    wire [PP-1:0] grant_w;
    generate for (d=0;d<P;d=d+1) begin : st
        wire [P-1:0] rf = free_stage[d*2*P +: P];
        wire [P-1:0] cf = free_stage[d*2*P+P +: P];
        for (i=0;i<P;i=i+1) begin : ce
            localparam integer J=(i+d)%P;
            wire rc = req_w[i*P+J];
            assign grant_w[i*P+J] = rc & rf[i] & cf[J];
            if (AOI_STYLE) begin : aoi
                assign free_stage[(d+1)*2*P+i]     = ~((rc & cf[J]) | ~rf[i]);
                assign free_stage[(d+1)*2*P+P+J]   = ~((rc & rf[i]) | ~cf[J]);
            end else begin : an
                assign free_stage[(d+1)*2*P+i]     = rf[i] & ~(rc & cf[J]);
                assign free_stage[(d+1)*2*P+P+J]   = cf[J] & ~(rc & rf[i]);
            end
        end
    end endgenerate

    // constant inverse rotation = wiring
    wire [PP-1:0] grant_rot;
    generate for (i=0;i<P;i=i+1) begin : ir
        for (j=0;j<P;j=j+1) begin : ic
            assign grant_rot[i*P+j] = grant_w[i*P + ((j-DV+P)%P)];
        end
    end endgenerate

    generate for (i=0;i<N;i=i+1) begin : og
        for (j=0;j<M;j=j+1) begin : ob
            assign o_grant_flat[i*M+j] = grant_rot[i*P+j];
        end
    end endgenerate
    generate for (i=0;i<N;i=i+1) begin : sv
        assign o_src_vld[i] = ~free_stage[P*2*P + i];
    end endgenerate
    generate for (j=0;j<M;j=j+1) begin : dv
        assign o_dest_vld[j] = ~free_stage[P*2*P + P + ((j-DV+P)%P)];
    end endgenerate
endmodule
`default_nettype wire
