module l2_stream_ptr #
(
  // Host parameters
  parameter addr_width        = 64,                 // Host address width in bits.
  parameter cache_line        = 128,                // Host cache line size in bytes.
  parameter cache_line_width  = $clog2(cache_line),

  // L1 parameters
  parameter l1_ncl            = 16,                 // Number of cache lines per stream in L1.
  parameter clid_width        = $clog2(l1_ncl),

  // L2 parameters
  parameter l2_ncl            = 256,                // Number of cache lines per stream in L2.
  parameter l2_ncl_width      = $clog2(l2_ncl),
  parameter l2_req_ncl_width  = $clog2(l2_ncl+1)    // Up to l2_ncl outstanding requests.
)
(
  input                       clk,
  input                       reset,

  // FUNCTIONAL STREAM RESET INPUT INTERFACE
  input                       i_rst_v,
  output                      i_rst_r,
  input  [addr_width-1:0]     i_rst_ea_b,           // Begin EA.
  input  [addr_width-1:0]     i_rst_ea_e,           // End EA (this addr will not be requested).

  // FUNCTIONAL STREAM RESET OUTPUT INTERFACE
  output                      o_rst_v,
  input                       o_rst_r,
  output [clid_width-1:0]     o_rst_ea_b,
  output                      o_rst_end,            // End of stream is high, otherwise low.

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
  output [addr_width-1:0]     o_req_ea,

  // HOST RESPONSE INTERFACE
  input                       i_rsp_v,
  output                      i_rsp_r
);

  // FUNCTIONAL RESET INTERFACE
  // Only allow functional reset if there are no outstanding requests & when the stream has ended & when there are no more valid lines (everything has been read).
  // Functionally resetting a stream has priority over reading a stream.
  wire s0_en_rst = s0_ncl_req_zero & s0_strm_end & s0_ncl_valid_zero;
  base_agate # (.width(1)) is0_reset_agate (
    .i_v      (i_rst_v),
    .i_r      (i_rst_r),
    .o_v      (o_rst_v),
    .o_r      (o_rst_r),
    .en       (s0_en_rst)
  );

  wire s0_rst_act = o_rst_v & o_rst_r;
  assign o_rst_ea_b = s0_rst_act ? i_rst_ea_b[clid_width+cache_line_width-1:cache_line_width] : {clid_width{1'b0}};

  // STREAM POINTER UPDATE AND ADDRESS CALCULATION
  // Only allow a read if a cache line is valid.
  localparam l2_min_cl = 1;
  wire [l2_req_ncl_width-1:0] s0_ncl_valid;
  wire s0_en = (s0_ncl_valid >= l2_min_cl);
  wire s0_rd_v, s0_rd_r;
  base_agate # (.width(1)) is0_igt (
    .i_v      (i_rd_v),
    .i_r      (i_rd_r),
    .o_v      (s0_rd_v),
    .o_r      (s0_rd_r),
    .en       (s0_en)
  );

  // Update the stream pointer when a functional reset or read is serviced.
  wire s0_rd_act = s0_rd_v & s0_rd_r;
  wire s0_vlat_en = s0_rst_act | s0_rd_act;
  wire [l2_ncl_width-1:0] s0_clid;
  wire [l2_ncl_width-1:0] s0_clid_nxt = o_rst_v ? i_rst_ea_b[l2_ncl_width+cache_line_width-1:cache_line_width] : s0_clid + 1'b1; // TODO: use o_rst_act instead of o_rst_v?
  base_vlat_en # (.width(l2_ncl_width),.rstv(0)) is0_clid_lat (
    .clk      (clk),
    .reset    (reset),
    .enable   (s0_vlat_en),
    .din      (s0_clid_nxt),
    .q        (s0_clid)
  );
  base_areg # (.width(l2_ncl_width),.lbl(3'b110)) is0_output_reg (
    .clk      (clk),
    .reset    (reset),
    .i_v      (s0_rd_v),
    .i_r      (s0_rd_r),
    .i_d      (s0_clid[l2_ncl_width-1:0]),
    .o_v      (o_addr_v),
    .o_r      (o_addr_r),
    .o_d      (o_addr_ptr)
  );

  // OUTSTANDING REQUEST AND VALID CACHE LINE COUNTERS
  // Increment and decrement the number of valid cache lines in this stream.
  // Initially rstv was l2_ncl, which means that all cache lines are valid.
  // Prevented immediate requesting of cache lines, but this is not the case anymore.
  // Now it is zero, such that the i_rd_r signal is low before a functional reset occurs.
  localparam [l2_req_ncl_width-1:0] ncl0 = 0;
  wire s0_rsp_act = i_rsp_v & i_rsp_r;
  wire s0_ncl_valid_inc = s0_rsp_act;
  wire s0_ncl_valid_dec = s0_rd_act;
  wire s0_ncl_valid_zero;
  base_incdec # (
    .width    (l2_req_ncl_width),
    .rstv     (0)                 // rstv is the power on reset output value.
    ) is0_ncl_valid_incdec (
    .clk      (clk),
    .reset    (reset),
    .i_set_v  (s0_rst_act),       // Enable overwrite the output value at any time.
    .i_set_d  (ncl0),             // Data overwrite the output value at any time.
    .i_inc    (s0_ncl_valid_inc),
    .i_dec    (s0_ncl_valid_dec),
    .o_cnt    (s0_ncl_valid),
    .o_zero   (s0_ncl_valid_zero)
  );

  // Increment and decrement the outstanding number of cache line requests.
  // Purpose of this counter is to check if we are in a clean state, without any outstanding requests, in order to do a safe functional reset.
  localparam [l2_req_ncl_width-1:0] xl2_ncl = l2_ncl;
  wire s0_req_act = o_req_v & o_req_r;
  wire [l2_req_ncl_width-1:0] s0_ncl_req;
  wire s0_ncl_req_inc = s0_rd_act & ~s0_strm_end; // increase if a read is serviced and the stream has not yet ended.
  wire s0_ncl_req_dec = s0_req_act | (~s0_ncl_req_zero & s0_strm_end); // decrease if req is serviced or if a req is made during the end of a stream until there are no more outstanding requests.
  wire s0_ncl_req_zero;
  base_incdec # (
    .width    (l2_req_ncl_width),
    .rstv     (0)
    ) is0_ncl_req_incdec (
    .clk      (clk),
    .reset    (reset),
    .i_set_v  (s0_rst_act),
    .i_set_d  (xl2_ncl),
    .i_inc    (s0_ncl_req_inc),
    .i_dec    (s0_ncl_req_dec),
    .o_cnt    (s0_ncl_req),
    .o_zero   (s0_ncl_req_zero)
  );

  // Output request effective address (EA).
  // If a functional reset is serviced or a request is made, the EA has to be updated.
  wire s0_ea_en = s0_rst_act | s0_req_act;
  wire [addr_width-1:0] s0_ea;
  wire [addr_width-1:0] s0_ea_nxt = s0_rst_act ? i_rst_ea_b : s0_ea + cache_line; // TODO: addition will always add cache_line. All bits smaller than cache_line do not have to be added.
  base_vlat_en # (.width(addr_width),.rstv(0)) is0_ea_lat (
    .clk      (clk),
    .reset    (reset),
    .enable   (s0_ea_en),
    .din      (s0_ea_nxt),
    .q        (s0_ea)
  );

  // Register to store the end EA.
  wire s0_ea_e_en = s0_rst_act;
  wire [addr_width-1:0] s0_ea_e;
  wire [addr_width-1:0] s0_ea_e_nxt = i_rst_ea_e;
  base_vlat_en # (.width(addr_width),.rstv(0)) is0_ea_end_lat (
    .clk      (clk),
    .reset    (reset),
    .enable   (s0_ea_e_en),
    .din      (s0_ea_e_nxt),
    .q        (s0_ea_e)
  );

  wire s0_strm_end = (s0_ea >= s0_ea_e); // If current EA is larger or equal to end EA, the stream has ended. If it has ended, you may reset. It is larger or equal because if a stream is smaller than the number of cache lines, requests will be sent out until all cache lines have been requested.
  assign o_req_v = ~s0_ncl_req_zero & ~s0_strm_end; //s0_strm_end is here to stop making requests when the end of a stream is reached.
  assign o_req_ea = s0_ea;
  assign i_rsp_r = 1'b1; // This module is always ready to accept a response.

  // Real end of stream valid signal. No outstanding reqs nor valid lines available.
  // Add register to reduce critical path.
  base_vlat # (
      .width  (1)
  ) is1_rst_lat (
      .clk    (clk),
      .reset  (reset),
      .din    (s0_en_rst),
      .q      (o_rst_end)
  );
  //assign o_rst_end = s0_en_rst;

endmodule // l2_stream_ptr
