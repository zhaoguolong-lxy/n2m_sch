//=============================================================================
// fair_arbiter.v
//
// N-to-M fair crossbar arbiter (iSLIP scheduler, ITER iterations).
//
// Produces, every clock cycle, an orthogonal (one-to-one) matching between
// N sources and M destinations.  Round-robin fairness is maintained on both
// sides by two sets of pointers:
//
//   g_ptr : destination-side grant pointer  (fair among the sources)
//   a_ptr : source-side      accept pointer (fair among the destinations)
//
// One scheduling pass is: request -> grant -> accept.  All of it is purely
// combinational (continuous assignments + generate loops), so the grant for
// a request presented in cycle T is available in cycle T (zero latency,
// "same-cycle result").  The pointers are the only sequential elements and
// update at posedge clk.
//
// Scheduling efficiency (matching quality) is parameterized by ITER:
//   A single pass can leave a source/destination idle even though a match was
//   possible (e.g. all destinations grant the same "hot" source, which accepts
//   only one of them).  With ITER > 1, additional request->grant->accept
//   passes run combinationally over the still-unmatched sources/destinations,
//   producing a larger (closer to maximal) matching.  ITER = 1 is the
//   area/delay-optimal variant; larger ITER improves throughput toward a
//   maximal matching at roughly linear area/depth cost.  Pointers advance only
//   on the first pass (the standard iSLIP rule), preserving fairness.
//
// Round-robin selection hardware (per arbiter), for a request vector req and
// priority pointer ptr:
//   mask_hi[k] = (k >= ptr)                     // high-priority half
//   req_hi = req & mask_hi ; req_lo = req & ~mask_hi
//   grant  = (|req_hi) ? lowest_set(req_hi) : lowest_set(req_lo)
//   lowest_set(x) = x & ~(x - 1)                // arithmetic find-first-one
//
// Fairness:
//   - From the source side, one source that requests several destinations is
//     served in round-robin order over successive cycles (a_ptr).
//   - From the destination side, several sources contending for one
//     destination are served in round-robin order (g_ptr).
//
// Orthogonality:
//   - Each destination grants at most one source (grant stage is one-hot),
//     and each source accepts at most one destination (accept stage is
//     one-hot), so the match has no duplicated source or destination.
//
// Backpressure:
//   - i_src_bp[n] = 1 : source n requests are dropped this cycle.
//   - i_dest_bp[m] = 1 : all requests toward destination m are dropped.
//
// Reset:
//   - rst_n is an active-low asynchronous reset that gates the outputs to 0
//     while asserted (via eff_req).
//   - The round-robin pointers are no-reset by default (PTR_RESET = 0)
//     because round-robin fairness is invariant to their initial value; set
//     PTR_RESET = 1 to add an async reset for deterministic simulation.
//
// Implementation notes:
//   - Internal request/grant/accept matrices are carried as flat 1-D vectors
//     (bit (i,j) = i*M+j, or (j,i) = j*N+i for the destination-side views)
//     because synthesis tools handle flat vectors inside generate loops more
//     reliably than 2-D packed arrays.
//   - Two small one-hot-to-binary functions are used sparingly, only on the
//     pointer-update path.  ASCII only.
//=============================================================================

`default_nettype none

module fair_arbiter #(
    parameter integer N         = 8,    // number of sources      (>= 2)
    parameter integer M         = 8,    // number of destinations (>= 2)
    parameter integer PTR_RESET = 0,    // 0 = no-reset pointers, 1 = async reset
    parameter integer ITER      = 2     // number of matching iterations (>= 1)
) (
    input  wire                      clk,      // clock input
    input  wire                      rst_n,    // async reset, active low
    input  wire [N-1:0][M-1:0]       i_src_dest_req,  // source n requests dest m
    input  wire [N-1:0]              i_src_bp,        // backpressure on source n
    input  wire [M-1:0]              i_dest_bp,       // backpressure on dest m
    output wire [N-1:0][M-1:0]       o_grant_rand_vld, // granted match (n -> m)
    output wire [N-1:0]              o_grant_src_vld,  // source n got a grant
    output wire [N-1:0][$clog2(M)-1:0] o_grant_src_ptr, // dest index for source n
    output wire [M-1:0]              o_grant_dest_vld, // dest m got a grant
    output wire [M-1:0][$clog2(N)-1:0] o_grant_dest_ptr  // source index for dest m
);

    localparam integer CLOG2N = $clog2(N);   // bits to encode a source index
    localparam integer CLOG2M = $clog2(M);   // bits to encode a dest index

    genvar i, j, k, t, b;

    //=========================================================================
    // Round-robin state (the ONLY sequential elements).
    //
    // g_ptr : at destination j, the source with highest priority this cycle.
    // a_ptr : at source i,      the destination with highest priority.
    //
    // Both are flat vectors so each pointer element is a contiguous slice
    // (also lets a testbench $deposit the whole vector to initialize a
    // no-reset instance in simulation):
    //   g_ptr[j] = g_ptr[j*CLOG2N +: CLOG2N]
    //   a_ptr[i] = a_ptr[i*CLOG2M +: CLOG2M]
    //
    // They are deliberately no-reset by default: any initial value yields a
    // valid round-robin order, so reset logic would only add area/power.
    //=========================================================================
    reg [M*CLOG2N-1:0] g_ptr;
    reg [N*CLOG2M-1:0] a_ptr;

    //=========================================================================
    // Effective request (flat: bit i*M+j = source i -> dest j).  A request
    // survives only if the source and destination are not backpressured and
    // reset is not asserted (which drives all outputs to 0 during reset and
    // avoids X propagation when pointers are uninitialized).
    //=========================================================================
    wire [N*M-1:0] eff_req;
    generate
        for (i = 0; i < N; i = i + 1) begin : gen_eff_req
            for (j = 0; j < M; j = j + 1) begin : gen_eff_req_bit
                assign eff_req[i*M + j] = i_src_dest_req[i][j]
                                        & ~i_src_bp[i]
                                        & ~i_dest_bp[j]
                                        & rst_n;
            end
        end
    endgenerate

    //=========================================================================
    // Matching passes (parameterized by ITER).
    //
    // Pass t considers only sources/destinations still unmatched after passes
    // 0..t-1, runs one request->grant->accept, and records which sources and
    // destinations it matched.  The round-robin pointers are the same in every
    // pass (they only advance on the clock edge, after the first pass).
    //
    // Flat vectors used inside this loop:
    //   eff_req_t[i*M+j] : source i -> dest j (effective for this pass)
    //   grant[j*N+i]     : dest j granted source i (one-hot per dest)
    //   accept[i*M+j]    : source i accepted dest j (one-hot per source)
    //   dst_col[j*N+i]   : = accept[i*M+j] (destination-side transposed view)
    //=========================================================================
    generate
        for (t = 0; t < ITER; t = t + 1) begin : gen_pass

            // ---- availability: unmatched at the start of pass t ----
            wire [N-1:0] src_avail;
            wire [M-1:0] dst_avail;
            if (t == 0) begin : gen_avail0
                assign src_avail = {N{1'b1}};
                assign dst_avail = {M{1'b1}};
            end else begin : gen_avail
                for (i = 0; i < N; i = i + 1) begin : gen_src_avail
                    assign src_avail[i] = gen_pass[t-1].src_avail[i]
                                        & ~gen_pass[t-1].src_match[i];
                end
                for (j = 0; j < M; j = j + 1) begin : gen_dst_avail
                    assign dst_avail[j] = gen_pass[t-1].dst_avail[j]
                                        & ~gen_pass[t-1].dst_match[j];
                end
            end

            // ---- effective request for this pass ----
            wire [N*M-1:0] eff_req_t;
            for (i = 0; i < N; i = i + 1) begin : gen_eff_t
                for (j = 0; j < M; j = j + 1) begin : gen_eff_t_bit
                    assign eff_req_t[i*M + j] = eff_req[i*M + j]
                                              & src_avail[i]
                                              & dst_avail[j];
                end
            end

            // ---- grant stage (destination side) ----
            wire [M*N-1:0] grant;
            for (j = 0; j < M; j = j + 1) begin : gen_grant
                wire [N-1:0] col_req;
                for (i = 0; i < N; i = i + 1) begin : gen_grant_col
                    assign col_req[i] = eff_req_t[i*M + j];
                end
                wire [N-1:0] mask_hi;
                wire [N-1:0] req_hi;
                wire [N-1:0] req_lo;
                for (i = 0; i < N; i = i + 1) begin : gen_grant_mask
                    assign mask_hi[i] = (i >= g_ptr[j*CLOG2N +: CLOG2N]);
                    assign req_hi[i]  = col_req[i] &  mask_hi[i];
                    assign req_lo[i]  = col_req[i] & ~mask_hi[i];
                end
                assign grant[j*N +: N] = (|req_hi) ? (req_hi & ~(req_hi - 1'b1))
                                                   : (req_lo & ~(req_lo - 1'b1));
            end

            // ---- accept stage (source side) ----
            wire [N*M-1:0] accept;
            for (i = 0; i < N; i = i + 1) begin : gen_accept
                wire [M-1:0] row_grant;
                for (j = 0; j < M; j = j + 1) begin : gen_accept_row
                    assign row_grant[j] = grant[j*N + i];
                end
                wire [M-1:0] mask_hi;
                wire [M-1:0] req_hi;
                wire [M-1:0] req_lo;
                for (j = 0; j < M; j = j + 1) begin : gen_accept_mask
                    assign mask_hi[j] = (j >= a_ptr[i*CLOG2M +: CLOG2M]);
                    assign req_hi[j]  = row_grant[j] &  mask_hi[j];
                    assign req_lo[j]  = row_grant[j] & ~mask_hi[j];
                end
                assign accept[i*M +: M] = (|req_hi) ? (req_hi & ~(req_hi - 1'b1))
                                                    : (req_lo & ~(req_lo - 1'b1));
            end

            // ---- match flags for this pass ----
            wire [N-1:0] src_match;
            wire [M-1:0] dst_match;
            wire [M*N-1:0] dst_col;   // dst_col[j*N+i] = source i accepted dest j
            for (i = 0; i < N; i = i + 1) begin : gen_src_match
                assign src_match[i] = |(accept[i*M +: M]);
            end
            for (j = 0; j < M; j = j + 1) begin : gen_dst_col
                for (i = 0; i < N; i = i + 1) begin : gen_dst_col_bit
                    assign dst_col[j*N + i] = accept[i*M + j];
                end
            end
            for (j = 0; j < M; j = j + 1) begin : gen_dst_match
                assign dst_match[j] = |(dst_col[j*N +: N]);
            end
        end
    endgenerate

    //=========================================================================
    // Final match = union of all passes (passes are disjoint, so OR is exact).
    //=========================================================================
    wire [N*M-1:0] final_accept;
    generate
        for (k = 0; k < N*M; k = k + 1) begin : gen_final_accept
            wire [ITER-1:0] acc_bits;
            for (t = 0; t < ITER; t = t + 1) begin : gen_final_accept_t
                assign acc_bits[t] = gen_pass[t].accept[k];
            end
            assign final_accept[k] = |acc_bits;
        end
    endgenerate

    //=========================================================================
    // Outputs.
    //=========================================================================
    assign o_grant_rand_vld = final_accept;   // flat -> 2-D port, bit (i,j)=i*M+j

    generate
        for (i = 0; i < N; i = i + 1) begin : gen_out_src_vld
            assign o_grant_src_vld[i] = |(final_accept[i*M +: M]);
        end
    endgenerate

    generate
        for (i = 0; i < N; i = i + 1) begin : gen_out_src_ptr
            for (b = 0; b < CLOG2M; b = b + 1) begin : gen_out_src_ptr_bit
                wire [M-1:0] terms;
                for (j = 0; j < M; j = j + 1) begin : gen_out_src_ptr_term
                    assign terms[j] = final_accept[i*M + j] & ((j >> b) & 1'b1);
                end
                assign o_grant_src_ptr[i][b] = |terms;
            end
        end
    endgenerate

    generate
        for (j = 0; j < M; j = j + 1) begin : gen_out_dest_vld
            wire [N-1:0] col;
            for (i = 0; i < N; i = i + 1) begin : gen_out_dest_vld_bit
                assign col[i] = final_accept[i*M + j];
            end
            assign o_grant_dest_vld[j] = |col;
        end
    endgenerate

    generate
        for (j = 0; j < M; j = j + 1) begin : gen_out_dest_ptr
            for (b = 0; b < CLOG2N; b = b + 1) begin : gen_out_dest_ptr_bit
                wire [N-1:0] terms;
                for (i = 0; i < N; i = i + 1) begin : gen_out_dest_ptr_term
                    assign terms[i] = final_accept[i*M + j] & ((i >> b) & 1'b1);
                end
                assign o_grant_dest_ptr[j][b] = |terms;
            end
        end
    endgenerate

    //=========================================================================
    // Pointer update (one always block per pointer element).
    //
    // A pointer advances ONLY on the first-pass match, and to "one past" the
    // matched partner.  A partner granted but not accepted stays at the head
    // of the line for the next cycle, keeping contention fair and minimizing
    // reordering.  Later-pass matches do not advance pointers (standard iSLIP).
    //=========================================================================
    generate
        for (j = 0; j < M; j = j + 1) begin : gen_g_ptr
            if (PTR_RESET) begin : gen_g_ptr_rst
                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        g_ptr[j*CLOG2N +: CLOG2N] <= {CLOG2N{1'b0}};
                    end else if ((|gen_pass[0].dst_col[j*N +: N]) && (onehot_idx_n(gen_pass[0].dst_col[j*N +: N]) == (N-1))) begin
                        g_ptr[j*CLOG2N +: CLOG2N] <= {CLOG2N{1'b0}};        // wrap
                    end else if (|gen_pass[0].dst_col[j*N +: N]) begin
                        g_ptr[j*CLOG2N +: CLOG2N] <= onehot_idx_n(gen_pass[0].dst_col[j*N +: N]) + 1'b1; // advance
                    end
                end
            end else begin : gen_g_ptr_norst
                always @(posedge clk) begin
                    if ((|gen_pass[0].dst_col[j*N +: N]) && (onehot_idx_n(gen_pass[0].dst_col[j*N +: N]) == (N-1))) begin
                        g_ptr[j*CLOG2N +: CLOG2N] <= {CLOG2N{1'b0}};        // wrap
                    end else if (|gen_pass[0].dst_col[j*N +: N]) begin
                        g_ptr[j*CLOG2N +: CLOG2N] <= onehot_idx_n(gen_pass[0].dst_col[j*N +: N]) + 1'b1; // advance
                    end
                end
            end
        end
    endgenerate

    generate
        for (i = 0; i < N; i = i + 1) begin : gen_a_ptr
            if (PTR_RESET) begin : gen_a_ptr_rst
                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        a_ptr[i*CLOG2M +: CLOG2M] <= {CLOG2M{1'b0}};
                    end else if ((|gen_pass[0].accept[i*M +: M]) && (onehot_idx_m(gen_pass[0].accept[i*M +: M]) == (M-1))) begin
                        a_ptr[i*CLOG2M +: CLOG2M] <= {CLOG2M{1'b0}};        // wrap
                    end else if (|gen_pass[0].accept[i*M +: M]) begin
                        a_ptr[i*CLOG2M +: CLOG2M] <= onehot_idx_m(gen_pass[0].accept[i*M +: M]) + 1'b1; // advance
                    end
                end
            end else begin : gen_a_ptr_norst
                always @(posedge clk) begin
                    if ((|gen_pass[0].accept[i*M +: M]) && (onehot_idx_m(gen_pass[0].accept[i*M +: M]) == (M-1))) begin
                        a_ptr[i*CLOG2M +: CLOG2M] <= {CLOG2M{1'b0}};        // wrap
                    end else if (|gen_pass[0].accept[i*M +: M]) begin
                        a_ptr[i*CLOG2M +: CLOG2M] <= onehot_idx_m(gen_pass[0].accept[i*M +: M]) + 1'b1; // advance
                    end
                end
            end
        end
    endgenerate

    //=========================================================================
    // One-hot to binary index (used only on the pointer-update path, and only
    // two of them, so kept as small functions for readability).  onehot has at
    // most one bit set; returns its index (0 if none).
    //=========================================================================
    function automatic [CLOG2N-1:0] onehot_idx_n;
        input [N-1:0] onehot;
        integer k;
        reg [CLOG2N-1:0] idx;
        begin
            idx = {CLOG2N{1'b0}};
            for (k = 0; k < N; k = k + 1)
                if (onehot[k])
                    idx = k;
            onehot_idx_n = idx;
        end
    endfunction

    function automatic [CLOG2M-1:0] onehot_idx_m;
        input [M-1:0] onehot;
        integer k;
        reg [CLOG2M-1:0] idx;
        begin
            idx = {CLOG2M{1'b0}};
            for (k = 0; k < M; k = k + 1)
                if (onehot[k])
                    idx = k;
            onehot_idx_m = idx;
        end
    endfunction

endmodule

`default_nettype wire
