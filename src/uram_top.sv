module uram_top #
(
  //parameter   L2_DATA_WIDTH           = 128*8,            // 128 byte cache line.
  parameter   l2_ncl                  = 128,              // TODO: future set to 256
  parameter   l2_ncl_width            = $clog2(l2_ncl),
  parameter   channels                = 2,                // Number of L2 write channels.
  parameter   channels_width          = $clog2(channels),
  parameter   nstrms                  = 32,               // Total number of streams.
  parameter   l2_nstrms               = nstrms/channels,  // TODO: l1 and l2 nstrms are equal. make a single parameter.
  parameter   l2_nstrms_width         = $clog2(l2_nstrms),

  // L2 parameters.
  parameter L2_RAM_DEPTH              = 4096,
  parameter L2_RAM_DEPTH_WIDTH        = $clog2(L2_RAM_DEPTH),
  parameter l1_ncl                    = 16,
  parameter l1_ncl_width              = $clog2(l1_ncl),

  // L1 parameters.
  parameter DATA_WIDTH                  = 8*8,                // 8 bytes per element
  parameter RAM_DEPTH                   = 512,                // double pump -> 256 16B
  parameter ADDR_WIDTH                  = $clog2(RAM_DEPTH),
  parameter WAYS                        = 8                   // Number of BRAMs per cache line.
)
(
  input                                 clk1x,
  input                                 clk2x,
  input                                 reset,

  // L2 INPUT READ INTERFACE
  input                                 i_l2_addr_v,
  output                                i_l2_addr_r,
  input  [l2_nstrms_width-1:0]          i_l2_addr_sid,
  input  [l2_ncl_width-1:0]             i_l2_addr_ptr,

  // L2 RESPONSE INTERFACE
  output [l2_nstrms-1:0]                o_rsp_v,
  input  [l2_nstrms-1:0]                o_rsp_r,

  // L1 WRITE INTERFACE
  output                                o_we,
  output [ADDR_WIDTH-1:0]               o_wa,
  output [WAYS*DATA_WIDTH-1:0]          o_wd,

  // HOST WRITE INTERFACE
  input                                 i_we,
  input  [L2_RAM_DEPTH_WIDTH-1:0]       i_wa,
  input  [WAYS*DATA_WIDTH-1:0]          i_wd
);

  // TODO: built an interface where i_l2_, o_rsp and o_w* are synchronized.
  // Currently it doesnt matter since ready signals are high for both outputs.

  // L2 input register.
  wire s1_l2_addr_v, s1_l2_addr_r;
  wire [l2_nstrms_width-1:0] s1_l2_addr_sid;
  wire [l2_ncl_width-1:0]    s1_l2_addr_ptr;
  base_areg # (
    .lbl(3'b110),
    .width(l2_nstrms_width+l2_ncl_width)
    ) is0_l2_addr_reg (
    .clk    (clk1x),
    .reset  (reset),
    .i_v    (i_l2_addr_v),
    .i_r    (i_l2_addr_r),
    .i_d    ({i_l2_addr_sid, i_l2_addr_ptr}),
    .o_v    (s1_l2_addr_v),
    .o_r    (s1_l2_addr_r),
    .o_d    ({s1_l2_addr_sid, s1_l2_addr_ptr})
  );

  wire s1_act = s1_l2_addr_v & s1_l2_addr_r; // URAM read enable

  // T flip flop
  reg q;
  always @ (posedge clk2x)
    if (reset) begin
      q <= 1'b0;
    end else if (s1_act) begin
      q <= !q;
  end



  // URAM control path.
  wire [l1_ncl_width-1:0]     s1_l1_ptr = s1_l2_addr_ptr[l1_ncl_width-1:0]; // only LSB are required to write into L1 BRAM.

  wire s2_v, s2_r;
  wire [l2_nstrms_width-1:0]  s2_l2_addr_sid;
  wire [l1_ncl_width-1:0]     s2_l1_ptr;
  base_areg # (
    .lbl(3'b111),
    .width(l2_nstrms_width+l1_ncl_width)
    ) control_path_reg (
    .clk    (clk1x),
    .reset  (reset),
    .i_v    (s1_l2_addr_v),
    .i_r    (s1_l2_addr_r),
    .i_d    ({s1_l2_addr_sid, s1_l1_ptr}),
    .o_v    (s2_v),
    .o_r    (s2_r),
    .o_d    ({s2_l2_addr_sid, s2_l1_ptr})
  );

  // URAM slice.
  wire [L2_RAM_DEPTH_WIDTH-1:0] s1_ra = {s1_l2_addr_sid, s1_l2_addr_ptr, q};
  wire [WAYS*DATA_WIDTH-1:0] s2_rd;
  uram_slice # (
    .DATA_WIDTH (DATA_WIDTH),
    .RAM_DEPTH  (L2_RAM_DEPTH),
    .WAYS       (WAYS)
    ) URAM (
    //.clk1x  (clk1x),
    .clk2x  (clk2x),
    .reset  (reset),
    .i_we   (i_we),
    .i_wa   (i_wa),
    .i_wd   (i_wd),
    .i_re   (s1_act),
    .i_ra   (s1_ra),
    .o_rd   (s2_rd)
  );

  // Delay q with two half cycles.
  wire q1, qd; // delayed q
  wire q2, q3;
  base_vlat # (
    .width  (1)
    ) QD1 (
    .clk    (clk2x),
    .reset  (reset),
    .din    (q),
    .q      (q1)
  );

  base_vlat # (
    .width  (1)
    ) QD2 (
    .clk    (clk2x),
    .reset  (reset),
    .din    (q1),
    .q      (q2)
  );

  // Additional routing cycle.
  wire [WAYS*DATA_WIDTH-1:0] s2a_rd, s3_rd;
  base_vlat # (
    .width  (WAYS*DATA_WIDTH+1)
    ) QD3 (
    .clk    (clk2x),
    .reset  (reset),
    .din    ({q2, s2_rd}),
    .q      ({q3, s2a_rd})
  );

  base_vlat # (
    .width  (WAYS*DATA_WIDTH+1)
    ) QD4 (
    .clk    (clk2x),
    .reset  (reset),
    .din    ({q3, s2a_rd}),
    .q      ({qd, s3_rd})
  );

  wire s2_act = s2_v & s2_r; // = o_we
  assign o_we = s2_act;
  assign o_wa = {s2_l2_addr_sid, s2_l1_ptr, qd};
  assign o_wd = s3_rd;



  // L1 response logic.
  wire [l2_nstrms-1:0] s1_rsp_sid_dec;
  base_decode_le#(.enc_width(l2_nstrms_width),.dec_width(l2_nstrms)) is1_rsp_dec (
    .din        (s2_l2_addr_sid),
    .dout       (s1_rsp_sid_dec),
    .en         (1'b1)
  );

  // Send response to L1 stream from L2 URAM.
  base_ademux # (
    .ways(l2_nstrms)
  ) is1_rsp_demux_bla (
    .i_v(s2_v),
    .i_r(s2_r),
    .sel(s1_rsp_sid_dec),
    .o_v(o_rsp_v),
    .o_r(o_rsp_r)
  );

endmodule // uram_top
