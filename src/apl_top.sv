// TODO: change module to only have control and memories. Interface can be attached seperately to easily change between OpenCAPI 3.0 and AXI for example.

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
  parameter channels_width              = $clog2(channels),
  parameter ra_out_width                = channels_width+l2_nstrms_width, // o_ra width. // TODO: is equal to nstrms_width

  parameter L2_RAM_DEPTH                = 4096,
  parameter L2_RAM_DEPTH_WIDTH          = $clog2(L2_RAM_DEPTH)
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
  output [nstrms-1:0]                   o_rst_end,

  // AFU READ INTERFACE
  input  [nports-1:0]                   i_rd_v,
  output [nports-1:0]                   i_rd_r,
  input  [nports*nstrms_width-1:0]      i_rd_sid,

  // AFU READ DATA INTERFACE
  output [nports-1:0]                   o_rd_v,
  input  [nports-1:0]                   o_rd_r,
  output [nports*2*DATA_WIDTH-1:0]      o_rd_d,
  output [nports*ra_out_width-1:0]      o_rd_sid,

  // HOST REQUEST INTERFACE
  output                                o_req_v,
  input                                 o_req_r,
  output [nstrms_width-1:0]             o_req_sid,
  output [addr_width-1:0]               o_req_ea,

  // HOST RESPONSE INTERFACE
  input                                 i_rsp_v,
  output                                i_rsp_r,
  input  [nstrms_width-1:0]             i_rsp_sid,

  // L2 WRITE INTERFACE
  input                                         i_we,
  input [L2_RAM_DEPTH_WIDTH+channels_width-1:0] i_wa,
  input [WAYS*DATA_WIDTH-1:0]                   i_wd
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

  // BRAM wires
  wire [nports-1:0]               s1_l1_addr_v;
  wire [nports-1:0]               s1_l1_addr_r;
  wire [nports*nstrms_width-1:0]  s1_l1_addr_sid;
  wire [nports*ptr_width-1:0]     s1_l1_addr_ptr;

  // BRAM rewiring.
  wire [nports*channels_width-1:0]  s1_l1_addr_ch;
  wire [nports*l2_nstrms_width-1:0] s1_l1_addr_st;
  wire [nports*l1_ncl_width-1:0]    s1_l1_addr_cl;
  wire [nports*clofs_width-1:0]     s1_l1_addr_of;
  genvar rr;
  generate
    for(rr=0; rr<nports; rr=rr+1) begin : GEN_L1_WIRES

      assign s1_l1_addr_ch[(rr+1)*channels_width-1:rr*channels_width] = s1_l1_addr_sid[(rr+1)*nstrms_width-1:rr*nstrms_width+l2_nstrms_width];
      assign s1_l1_addr_st[(rr+1)*l2_nstrms_width-1:rr*l2_nstrms_width] = s1_l1_addr_sid[rr*nstrms_width+l2_nstrms_width-1:rr*nstrms_width];
      assign s1_l1_addr_cl[(rr+1)*l1_ncl_width-1:rr*l1_ncl_width] = s1_l1_addr_ptr[(rr+1)*ptr_width-1:rr*ptr_width+clofs_width];
      assign s1_l1_addr_of[(rr+1)*clofs_width-1:rr*clofs_width] = s1_l1_addr_ptr[rr*ptr_width+clofs_width-1:rr*ptr_width];

    end
  endgenerate

  wire [nstrms-1:0] i_rsp_uram_v, i_rsp_uram_r;
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
    .o_rst_end      (o_rst_end),
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

  // Write signals.
  input  [channels-1:0]                 s1_l1_we;
  input  [channels*ADDR_WIDTH-1:0]      s1_l1_wa;
  input  [channels*WAYS*DATA_WIDTH-1:0] s1_l1_wd;

  bram_top_wrapper # (
    .nports     (nports),
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
    .o_ra       (o_rd_sid),
    .i_we       (s1_l1_we),
    .i_wa       (s1_l1_wa),
    .i_wd       (s1_l1_wd)
  );

  // L2 READ INTERFACE
  wire [channels-1:0]                 o_l2_addr_v;
  wire [channels-1:0]                 o_l2_addr_r;
  wire [channels*l2_nstrms_width-1:0] o_l2_addr_sid;
  wire [channels*l2_ncl_width-1:0]    o_l2_addr_ptr;

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

  // L2 write interface register and MUX.
  wire [L2_RAM_DEPTH_WIDTH+channels_width-1:0] s1_wa;
  wire [WAYS*DATA_WIDTH-1:0] s1_wd;
  wire s1_reg_v, s1_reg_r;
  base_areg # ( .lbl(3'b110),.width(L2_RAM_DEPTH_WIDTH+channels_width+WAYS*DATA_WIDTH)) write_reg (
      .clk(clk2x),.reset(reset),
      .i_v(i_we),.i_r(),
      .i_d({i_wa, i_wd}),
      .o_v(s1_reg_v),.o_r(s1_reg_r),
      .o_d({s1_wa, s1_wd})
  );

  // Select decode module for the MUX.
  wire [channels-1:0] s1_ch_dec;
  base_decode_le#(.enc_width(channels_width),.dec_width(channels)) is1_rsp_dec (
    .din        (s1_wa[L2_RAM_DEPTH_WIDTH+channels_width-1:L2_RAM_DEPTH_WIDTH]),
    .dout       (s1_ch_dec),
    .en         (1'b1)
  );

  // Send response to L1 stream from L2 URAM.
  wire [channels-1:0] i_we_dec;
  base_ademux # (
    .ways(channels)
  ) is1_rsp_demux_bla (
    .i_v(s1_reg_v),
    .i_r(s1_reg_r),
    .sel(s1_ch_dec),
    .o_v(i_we_dec),
    .o_r({channels{1'b1}})
  );

  // Generate URAM modules for L2.
  wire [channels-1:0] s1_l1_we;
  wire [channels*ADDR_WIDTH-1:0] s1_l1_wa;
  wire [channels*WAYS*DATA_WIDTH-1:0] s1_l1_wd;
  genvar gg;
  generate
    for(gg=0; gg<channels; gg=gg+1) begin : GEN_URAM
      uram_top IDUT (
        .clk1x          (clk1x),
        .clk2x          (clk2x),
        .reset          (reset),

        .i_l2_addr_v    (o_l2_addr_v[gg]),
        .i_l2_addr_r    (o_l2_addr_r[gg]),
        .i_l2_addr_sid  (o_l2_addr_sid[(gg+1)*l2_nstrms_width-1:gg*l2_nstrms_width]),
        .i_l2_addr_ptr  (o_l2_addr_ptr[(gg+1)*l2_ncl_width-1:gg*l2_ncl_width]),

        .o_rsp_v        (i_rsp_uram_v[(gg+1)*l2_nstrms-1:gg*l2_nstrms]),
        .o_rsp_r        (i_rsp_uram_r[(gg+1)*l2_nstrms-1:gg*l2_nstrms]),

        .o_we           (s1_l1_we[gg]),
        .o_wa           (s1_l1_wa[(gg+1)*ADDR_WIDTH-1:gg*ADDR_WIDTH]),
        .o_wd           (s1_l1_wd[(gg+1)*WAYS*DATA_WIDTH-1:gg*WAYS*DATA_WIDTH]),

        .i_we           (i_we_dec[gg]),
        .i_wa           (s1_wa[L2_RAM_DEPTH_WIDTH-1:0]),
        .i_wd           (s1_wd)
      );
    end
  endgenerate

endmodule
