// TODO: extend pointer to be 64 bits long and hold the EA of a stream.
// TODO: add agate modules, see handwritten notes.
// TODO: reset to specific pointer based on 64b address.

module l2_stream_ptr #
(
  // Host parameters
  parameter addr_width        = 64,               // Host address width.

  // Stream cache parameters
  parameter l2_ncl            = 256,              // Number of cache lines per stream in L2.
  parameter l2_ncl_width      = $clog2(l2_ncl),
  parameter l2_req_ncl_width  = $clog2(l2_ncl+1)  // Up to l2_ncl outstanding requests.
)
(
  input                       clk,
  input                       reset,

  // FUNCTIONAL STREAM RESET INPUT INTERFACE
  input                       i_rst_v,
  output                      i_rst_r,

  // FUNCTIONAL STREAM RESET OUTPUT INTERFACE
  output                      o_rst_v,
  input                       o_rst_r,

  // L1 REQUEST INTERFACE
  input                       i_rd_v,
  output                      i_rd_r,

  // L2 URAM READ INTERFACE
  output                      o_addr_v,
  input                       o_addr_r,
  output [l2_ncl_width-1:0]   o_addr_ptr,

  // HOST REQUEST INTERFACE
  output                      o_req_v,
  input                       o_req_r,

  // HOST RESPONSE INTERFACE
  input                       i_rsp_v,
  output                      i_rsp_r
);

  // FUNCTIONAL RESET INTERFACE
  // Only allow functional reset if there are no outstanding requests.
  // TODO: add: only functinally reset if s0_ncl_req_zero & if this stream has ended.
  wire s0_en_rst = s0_ncl_req_zero;
  base_agate # (.width(1)) is0_reset_agate (
    .i_v  (i_rst_v),
    .i_r  (i_rst_r),
    .o_v  (o_rst_v),
    .o_r  (o_rst_r),
    .en   (s0_en_rst)
  );

  // STREAM POINTER UPDATE AND ADDRESS CALCULATION
  // Only allow a read if a cache line is valid and the module is not in a reset state.
  localparam l2_min_cl = 1;
  wire [l2_req_ncl_width-1:0] s0_ncl_valid;
  wire s0_en = (s0_ncl_valid >= l2_min_cl) & ~o_rst_v;
  wire s0_rd_v, s0_rd_r;
  base_agate # (.width(1)) is0_igt (
    .i_v  (i_rd_v),
    .i_r  (i_rd_r),
    .o_v  (s0_rd_v),
    .o_r  (s0_rd_r),
    .en   (s0_en)
  );

  // Update the stream pointer when a read is serviced.
  wire s0_rd_act = s0_rd_v & s0_rd_r;
  wire [l2_ncl_width-1:0] s0_clid;
  wire [l2_ncl_width-1:0] s0_clid_nxt = s0_clid + 1'b1;
  base_vlat_en # (.width(l2_ncl_width),.rstv(0)) is0_clid_lat (
    .clk      (clk),
    .reset    (reset),
    .enable   (s0_rd_act),
    .din      (s0_clid_nxt),
    .q        (s0_clid)
  );
  base_areg # (.width(l2_ncl_width),.lbl(3'b110)) is0_output_reg (
    .clk    (clk),
    .reset  (reset),
    .i_v    (s0_rd_v),
    .i_r    (s0_rd_r),
    .i_d    (s0_clid),
    .o_v    (o_addr_v),
    .o_r    (o_addr_r),
    .o_d    (o_addr_ptr)
  );

  // OUTSTANDING REQUESTS AND VALID CACHE LINES COUNTERS
  localparam [l2_req_ncl_width-1:0] ncl0 = 0;
  localparam [l2_req_ncl_width-1:0] xl2_ncl = l2_ncl;
  wire s0_rst_act = o_rst_v & o_rst_r;

  wire s0_rsp_act = i_rsp_v & i_rsp_r;
  wire s0_ncl_valid_inc = s0_rsp_act;
  wire s0_ncl_valid_dec = s0_rd_act;

  wire [l2_req_ncl_width-1:0] s0_ncl_req;
  wire s0_ncl_req_inc = s0_rd_act;
  wire s0_req_act = o_req_v & o_req_r;
  wire s0_ncl_req_dec = s0_req_act;
  wire s0_ncl_req_zero;

  // increment decrement the number of valid cache lines in this stream.
  base_incdec # (
    .width    (l2_req_ncl_width), // $clog2(256+1)
    .rstv     (0) // 256 - power on reset, all lines are valid. thus no requests will be made to OpenCAPI. In idle state.
    // should reset to 0 instead of l2_ncl. There are no valid cache lines and this will fix the i_rd_r signal, which will not be high anymore before executing a functional reset.
    ) is0_ncl_valid_incdec (
    .clk      (clk),
    .reset    (reset),
    .i_set_v  (s0_rst_act), // overwrite the output value at any time. this is the enable signal
    .i_set_d  (ncl0),       // overwrite the output value at any time. this is the data signal
    .i_inc    (s0_ncl_valid_inc),
    .i_dec    (s0_ncl_valid_dec),
    .o_cnt    (s0_ncl_valid),
    .o_zero   ()
  );

  // increment decrement outstanding number of cache line requests to OpenCAPI 3.0.
  // Purpose of this counter is to check if we are in a clean state, without any outstanding requests, in order to be able to do a safe functional reset.
  base_incdec # (
    .width    (l2_req_ncl_width),
    .rstv     (0) // power on reset, no outstanding requests to OpenCAPI. In idle state.
    ) is0_ncl_req_incdec (
    .clk      (clk),
    .reset    (reset),
    .i_set_v  (s0_rst_act), // overwrite the output value at any time. this is the enable signal
    .i_set_d  (xl2_ncl), // overwrite the output value at any time. this is the data signal
    .i_inc    (s0_ncl_req_inc),
    .i_dec    (s0_ncl_req_dec),
    .o_cnt    (s0_ncl_req),
    .o_zero   (s0_ncl_req_zero)
  );

  assign o_req_v = ~s0_ncl_req_zero;
  assign i_rsp_r = 1'b1; // This module is always ready to accept a response.

endmodule // l2_stream_ptr
