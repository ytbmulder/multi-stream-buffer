module l2_ctrl_top_synth #
(
  // Host parameters
  parameter addr_width                  = 64,                 // Host address width in bits.
  parameter cache_line                  = 128,                // Host cache line size in bytes.
  parameter cache_line_width            = $clog2(cache_line),

  // L1 parameters
  parameter l1_ncl                      = 16,                 // Number of cache lines per stream in L1.
  parameter clid_width                  = $clog2(l1_ncl),

  // Stream cache parameters
  parameter nstrms                      = 64,
  parameter nstrms_width                = $clog2(nstrms),
  parameter l2_nstrms                   = 16,
  parameter l2_nstrms_width             = $clog2(l2_nstrms),
  parameter l2_ncl                      = 256,                // Number of cache lines per stream in L2.
  parameter l2_ncl_width                = $clog2(l2_ncl),
  parameter channels                    = nstrms/l2_nstrms
)
(
  input                                 clk,
  input                                 reset,

  input                                 in,
  output                                out
);

  // FUNCTIONAL STREAM RESET INPUT INTERFACE
  wire  [nstrms-1:0]                   i_rst_v,
  wire [nstrms-1:0]                   i_rst_r,
  wire  [addr_width-1:0]               i_rst_ea_b,
  wire  [addr_width-1:0]               i_rst_ea_e,

  // FUNCTIONAL STREAM RESET OUTPUT INTERFACE
  wire [nstrms-1:0]                   o_rst_v,
  wire [nstrms-1:0]                   o_rst_r,
  wire [nstrms*clid_width-1:0]        o_rst_ea_b,
  wire [nstrms-1:0]                   o_rst_end,

  // L1 REQUEST INTERFACE
  wire [nstrms-1:0]                   i_rd_v,
  wire [nstrms-1:0]                   i_rd_r,

  // L2 URAM READ INTERFACE
  wire [channels-1:0]                 o_addr_v,
  wire [channels-1:0]                 o_addr_r,
  wire [channels*l2_nstrms_width-1:0] o_addr_sid,
  wire [channels*l2_ncl_width-1:0]    o_addr_ptr,

  // HOST REQUEST INTERFACE
  wire                                o_req_v,
  wire                                 o_req_r,
  wire [nstrms_width-1:0]             o_req_sid,
  wire [addr_width-1:0]               o_req_ea,

  // HOST RESPONSE INTERFACE
  wire                                 i_rsp_v,
  wire                                 i_rsp_r,
  wire [nstrms_width-1:0]             i_rsp_sid

  //
	localparam input_width = nstrms+addr_width+addr_width+nstrms+nstrms+channels+nstrms_width+2;
	base_input_lat # (input_width, 1) DIN (clk, in, {i_rst_v, i_rst_ea_b, i_rst_ea_e, o_rst_r, i_rd_v, o_addr_r, o_req_r, i_rsp_v, i_rsp_sid});

  localparam output_width = 4*nstrms+nstrms*clid_width+channels+channels*l2_nstrms_width+channels*l2_ncl_width+1+nstrms_width+addr_width+1;
	base_output_lat # (output_width) DOUT (clk, {i_rst_r, o_rst_v, o_rst_ea_b, o_rst_end, i_rd_r, o_addr_v, o_addr_sid, o_addr_ptr, o_req_v, o_req_sid, o_req_ea, i_rsp_r}, out);

	// Device Under Test (DUT).
	tile_bram # (DATA_WIDTH, RAM_DEPTH, ADDR_WIDTH, WAYS, SLICES, READ_WIDTH) DUT (clk, rst, i_we, i_wa, i_wd, i_re, i_ra_slice, i_ra_line, i_ra_offset, o_rd);

  l2_ctrl_top IDUT (
      .clk        (clk),
      .reset      (reset),

      .i_rst_v    (i_rst_v),
      .i_rst_r    (i_rst_r),
      .i_rst_ea_b (i_rst_ea_b),
      .i_rst_ea_e (i_rst_ea_e),

      .o_rst_v    (o_rst_v),
      .o_rst_r    (o_rst_r),
      .o_rst_ea_b (o_rst_ea_b),
      .o_rst_end  (o_rst_end),

      .i_rd_v     (i_rd_v),
      .i_rd_r     (i_rd_r),

      .o_addr_v   (o_addr_v),
      .o_addr_r   (o_addr_r),
      .o_addr_sid (o_addr_sid),
      .o_addr_ptr (o_addr_ptr),

      .o_req_v    (o_req_v),
      .o_req_r    (o_req_r),
      .o_req_sid  (o_req_sid),
      .o_req_ea   (o_req_ea),

      .i_rsp_v    (i_rsp_v),
      .i_rsp_r    (i_rsp_r),
      .i_rsp_sid  (i_rsp_sid)
  );

endmodule
