// TODO: change module to only have control and memories. Interface can be attached seperately to easily change between OpenCAPI 3.0 and AXI for example.
// TODO: add reset out to AFU interface. Also on L1 control and AFU interface (8x read port & this reset interface decoded)

module apl_top #
(
  // Host parameters
  parameter addr_width                  = 64,                 // Host address width in bits.
  parameter cache_line                  = 128,                // Host cache line size in bytes.
  parameter cache_line_width            = $clog2(cache_line),

  // Stream cache parameters
  parameter nstrms                      = 64,
  parameter nstrms_width                = $clog2(nstrms),
  parameter nports                      = 8,                  // Number of L1 read ports.
  parameter cl_size                     = 8,                  // number of reads per cacheline - must be at least as big as the number of read ports

  // L1 parameters
  parameter l1_ncl                      = 16,                 // Number of L1 cache lines per stream.
  parameter l1_ncl_width                = $clog2(l1_ncl),
  parameter clofs_width                 = $clog2(cl_size),    // number of bits needed to represent an offset within a cacheline
  parameter ptr_width                   = l1_ncl_width+clofs_width, // number of bits needed to represent a stream pointer

  // L2 parameters
  parameter l2_nstrms                   = 16,
  parameter l2_nstrms_width             = $clog2(l2_nstrms),
  parameter l2_ncl                      = 256,                // Number of L2 cache lines per stream.
  parameter l2_ncl_width                = $clog2(l2_ncl),
  parameter channels                    = nstrms/l2_nstrms
)
(
  input                                 clk,
  input                                 reset,

  // FUNCTIONAL STREAM RESET INPUT INTERFACE
  input                                 i_rst_v,
  output                                i_rst_r,
  input  [nstrms_width-1:0]             i_rst_sid,
  input  [addr_width-1:0]               i_rst_ea_b,
  input  [addr_width-1:0]               i_rst_ea_e,

  // FUNCTIONAL STREAM RESET OUTPUT INTERFACE
  output [nstrms-1:0]                   o_rst_v,
  input  [nstrms-1:0]                   o_rst_r,
  output [nstrms-1:0]                   o_rst_end, // TODO: implement in L1

  // AFU READ INTERFACE
  input  [nports-1:0]                   i_rd_v,
  output [nports-1:0]                   i_rd_r,
  input  [nports*nstrms_width-1:0]      i_rd_sid,

  // L1 READ INTERFACE
  output [nports-1:0]                   o_l1_addr_v,
  input  [nports-1:0]                   o_l1_addr_r,
  output [nports*nstrms_width-1:0]      o_l1_addr_sid,
  output [nports*ptr_width-1:0]         o_l1_addr_ptr,

  // L2 READ INTERFACE
  output [channels-1:0]                 o_l2_addr_v,
  input  [channels-1:0]                 o_l2_addr_r,
  output [channels*l2_nstrms_width-1:0] o_l2_addr_sid,
  output [channels*l2_ncl_width-1:0]    o_l2_addr_ptr,

  // HOST REQUEST INTERFACE
  output                                o_req_v,
  input                                 o_req_r,
  output [nstrms_width-1:0]             o_req_sid,
  output [addr_width-1:0]               o_req_ea,

  // HOST RESPONSE INTERFACE
  input                                 i_rsp_v,
  output                                i_rsp_r,
  input  [nstrms_width-1:0]             i_rsp_sid,

  // RESPONSE FROM URAM
  input  [nstrms-1:0]                   i_rsp_uram_v,
  output [nstrms-1:0]                   i_rsp_uram_r
);

  // FUNCTIONAL STREAM RESET INTERFACE
  wire s1_rst_v, s1_rst_r;
  wire [nstrms_width-1:0] s1_rst_sid;
  wire [addr_width-1:0] s1_rst_ea_b, s1_rst_ea_e;
  base_areg # (.lbl(3'b110),.width(nstrms_width+2*addr_width)) is0_rst_reg (
    .clk    (clk),
    .reset  (reset),
    .i_v    (i_rst_v),
    .i_r    (i_rst_r),
    .i_d    ({ i_rst_sid,  i_rst_ea_b,  i_rst_ea_e}),
    .o_v    (s1_rst_v),
    .o_r    (s1_rst_r),
    .o_d    ({s1_rst_sid, s1_rst_ea_b, s1_rst_ea_e})
  );

  // Demux functional reset interface.
  wire [nstrms-1:0] s1_rst_sid_dec, s1_rst_v_dec, s1_rst_r_dec;
  base_decode_le#(.enc_width(nstrms_width),.dec_width(nstrms)) is1_rst_sid_dec(.din(s1_rst_sid),.dout(s1_rst_sid_dec),.en(1'b1));
  base_ademux#(.ways(nstrms)) is1_rst_demux (.i_v(s1_rst_v),.i_r(s1_rst_r),.o_v(s1_rst_v_dec),.o_r(s1_rst_r_dec),.sel(s1_rst_sid_dec));

  // Wires
  wire [nstrms-1:0] s2_rst_v, s2_rst_r;
  wire [nstrms-1:0] s0_req_v, s0_req_r;

  wire [nstrms*l1_ncl_width-1:0] s2_rst_ea_b;

  l1_ctrl_top is0_l1_ctrl_top (
    .clk            (clk),
    .reset          (reset),
    .i_rst_v        (s2_rst_v),
    .i_rst_r        (s2_rst_r),
    .i_rst_ea_b     (s2_rst_ea_b),
    .o_rst_v        (o_rst_v),
    .o_rst_r        (o_rst_r),
    .i_rd_v         (i_rd_v),
    .i_rd_r         (i_rd_r),
    .i_rd_sid       (i_rd_sid),
    .o_addr_v       (o_l1_addr_v),
    .o_addr_r       (o_l1_addr_r),
    .o_addr_sid     (o_l1_addr_sid),
    .o_addr_ptr     (o_l1_addr_ptr),
    .o_req_v        (s0_req_v),
    .o_req_r        (s0_req_r),
    .i_rsp_v        (i_rsp_uram_v),
    .i_rsp_r        (i_rsp_uram_r)
  );

  l2_ctrl_top # (
    .addr_width     (addr_width),
    .cache_line     (cache_line),
    .nstrms         (nstrms),
    .l1_ncl         (l1_ncl),
    .l2_nstrms      (l2_nstrms),
    .l2_ncl         (l2_ncl)
    ) is0_l2_ctrl_top (
    .clk            (clk),
    .reset          (reset),
    .i_rst_v        (s1_rst_v_dec),
    .i_rst_r        (s1_rst_r_dec),
    .i_rst_ea_b     (s1_rst_ea_b),
    .i_rst_ea_e     (s1_rst_ea_e),
    .o_rst_v        (s2_rst_v),
    .o_rst_r        (s2_rst_r),
    .o_rst_ea_b     (s2_rst_ea_b),
    .o_rst_end      (o_rst_end),
    .i_rd_v         (s0_req_v),
    .i_rd_r         (s0_req_r),
    .o_addr_v       (o_l2_addr_v),
    .o_addr_r       (o_l2_addr_r),
    .o_addr_sid     (o_l2_addr_sid),
    .o_addr_ptr     (o_l2_addr_ptr),
    .o_req_v        (o_req_v),
    .o_req_r        (o_req_r),
    .o_req_sid      (o_req_sid),
    .o_req_ea       (o_req_ea),
    .i_rsp_v        (i_rsp_v),
    .i_rsp_r        (i_rsp_r),
    .i_rsp_sid      (i_rsp_sid)
  );

endmodule
