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
  parameter DATA_WIDTH                  = 8*8,                // 8 bytes per element
  parameter RAM_DEPTH                   = 512,                // double pump -> 256 16B
  parameter ADDR_WIDTH                  = $clog2(RAM_DEPTH),
  parameter WAYS                        = 8,                  // Number of BRAMs per cache line.

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
  parameter channels                    = 4,                  // nstrms/l2_nstrms
  parameter channels_width              = $clog2(channels)
)
(
  input                                 clk1x,
  input                                 clk2x,
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

  // AFU READ DATA INTERFACE
  output [nports-1:0]                   o_rd_v,
  input  [nports-1:0]                   o_rd_r,
  output [nports*2*DATA_WIDTH-1:0]      o_rd_d,

/*
  // L1 READ INTERFACE
  output [nports-1:0]                   o_l1_addr_v,
  input  [nports-1:0]                   o_l1_addr_r,
  output [nports*nstrms_width-1:0]      o_l1_addr_sid,
  output [nports*ptr_width-1:0]         o_l1_addr_ptr,
*/

  // L1 WRITE INTERFACE
  input  [channels-1:0]                 i_we,
  input  [channels*ADDR_WIDTH-1:0]      i_wa,
  input  [channels*WAYS*DATA_WIDTH-1:0] i_wd,

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
    .clk    (clk1x),
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

  wire [nstrms-1:0] s0_rst_end;
  assign o_rst_end = s0_rst_end; // TODO: should be L1 output.

  // BRAM wires
  wire [nports-1:0]               s1_l1_addr_v;
  wire [nports-1:0]               s1_l1_addr_r;
  wire [nports*nstrms_width-1:0]  s1_l1_addr_sid;
  wire [nports*ptr_width-1:0]     s1_l1_addr_ptr;

  wire [channels_width-1:0]       s1_l1_addr_ch = s1_l1_addr_sid[nstrms_width-1:channels_width];
  wire [l1_ncl_width-1:0]         s1_l1_addr_st = s1_l1_addr_sid[l1_ncl_width-1:0];

  wire [l1_ncl_width-1:0]         s1_l1_addr_cl = s1_l1_addr_ptr[ptr_width-1:clofs_width];
  wire [clofs_width-1:0]          s1_l1_addr_of = s1_l1_addr_ptr[clofs_width-1:0];

  l1_ctrl_top # (
    .nports         (nports),
    .nstrms         (nstrms),
    .ncl            (l1_ncl),
    .cl_size        (cl_size),
    .channels       (channels)
    ) is0_l1_ctrl_top (
    .clk            (clk1x),
    .reset          (reset),
    .i_rst_v        (s2_rst_v),
    .i_rst_r        (s2_rst_r),
    .i_rst_ea_b     (s2_rst_ea_b),
    .i_rst_end      (s0_rst_end),
    .o_rst_v        (o_rst_v),
    .o_rst_r        (o_rst_r),
    //.o_rst_end      (o_rst_end),
    .i_rd_v         (i_rd_v),         // AFU READ INTERFACE
    .i_rd_r         (i_rd_r),
    .i_rd_sid       (i_rd_sid),
    .o_addr_v       (s1_l1_addr_v),   //(o_l1_addr_v), // L1 BRAM READ PORT INTERFACE
    .o_addr_r       (s1_l1_addr_r),   //(o_l1_addr_r),
    .o_addr_sid     (s1_l1_addr_sid), //(o_l1_addr_sid),
    .o_addr_ptr     (s1_l1_addr_ptr), //(o_l1_addr_ptr),
    .o_req_v        (s0_req_v),       // L2 REQUEST INTERFACE
    .o_req_r        (s0_req_r),
    .i_rsp_v        (i_rsp_uram_v),   // L2 RESPONSE INTERFACE
    .i_rsp_r        (i_rsp_uram_r)
  );

  bram_top # (
    .DATA_WIDTH (DATA_WIDTH),
    .RAM_DEPTH  (RAM_DEPTH),
    .WAYS       (WAYS),
    .channels   (channels),
    .nstrms     (nstrms),
    .l1_ncl     (l1_ncl)
    ) is0_bram_top (
    .clk1x      (clk1x),
    .clk2x      (clk2x),
    .reset      (reset),
    .i_v        (s1_l1_addr_v),
    .i_r        (s1_l1_addr_r),
    .i_ra_ch    (s1_l1_addr_ch),
    .i_ra_st    (s1_l1_addr_st),
    .i_ra_cl    (s1_l1_addr_cl),
    .i_ra_of    (s1_l1_addr_of),
    .o_v        (o_rd_v),
    .o_r        (o_rd_r),
    .o_rd       (o_rd_d),
    .i_we       (i_we),
    .i_wa       (i_wa),
    .i_wd       (i_wd)
  );

  l2_ctrl_top # (
    .addr_width     (addr_width),
    .cache_line     (cache_line),
    .nstrms         (nstrms),
    .l1_ncl         (l1_ncl),
    .l2_nstrms      (l2_nstrms),
    .l2_ncl         (l2_ncl)
    ) is0_l2_ctrl_top (
    .clk            (clk1x),
    .reset          (reset),
    .i_rst_v        (s1_rst_v_dec),
    .i_rst_r        (s1_rst_r_dec),
    .i_rst_ea_b     (s1_rst_ea_b),
    .i_rst_ea_e     (s1_rst_ea_e),
    .o_rst_v        (s2_rst_v),
    .o_rst_r        (s2_rst_r),
    .o_rst_ea_b     (s2_rst_ea_b),
    .o_rst_end      (s0_rst_end),
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
