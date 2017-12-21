module bram_top_wrapper #
(
  parameter   nports                  = 8,
  parameter   DATA_WIDTH              = 8*8,              // 8 bytes per element
  parameter   RAM_DEPTH               = 512,              // double pump -> 256 16B entries
  parameter   ADDR_WIDTH              = $clog2(RAM_DEPTH),
  parameter   WAYS                    = 8,                // Number of BRAMs per cache line.
  parameter   WAYS_WIDTH              = $clog2(WAYS),
  parameter   channels                = 2,                // Number of L2 write channels.
  parameter   channels_width          = $clog2(channels),
  parameter   nstrms                  = 32,               // Total number of streams.
  parameter   l1_nstrms               = nstrms/channels,  // Number of streams per channel.
  parameter   l1_nstrms_width         = $clog2(l1_nstrms),
  parameter   l1_ncl                  = 16,               // Number of cache lines per stream.
  parameter   l1_ncl_width            = $clog2(l1_ncl),
  parameter   ra_out_width            = channels_width+l1_nstrms_width // o_ra width.
)
(
  input                               clk1x,
  input                               clk2x,
  input                               reset,

  // Input read interface.
  input  [nports-1:0]                 i_v,
  output [nports-1:0]                 i_r,
  input  [nports*channels_width-1:0]  i_ra_ch, // Channel
  input  [nports*l1_nstrms_width-1:0] i_ra_st, // Stream
  input  [nports*l1_ncl_width-1:0]    i_ra_cl, // Cache line
  input  [nports*WAYS_WIDTH-1:0]      i_ra_of, // Offset

  // Output read interface.
  output [nports-1:0]                 o_v,
  input  [nports-1:0]                 o_r,
  output [nports*2*DATA_WIDTH-1:0]    o_rd,
  output [nports*ra_out_width-1:0]    o_ra,

  // Input write interface.
  input  [channels-1:0]               i_we,
  input  [channels*ADDR_WIDTH-1:0]    i_wa,
  input  [channels*WAYS*DATA_WIDTH-1:0] i_wd
);

  genvar i;
  generate
    for(i=0; i<nports; i=i+1) begin : GEN_bram_top
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
        .i_v        ( i_v[i] ),
        .i_r        ( i_r[i] ),
        .i_ra_ch    ( i_ra_ch[(i+1)*channels_width-1:i*channels_width] ),
        .i_ra_st    ( i_ra_st[(i+1)*l1_nstrms_width-1:i*l1_nstrms_width] ),
        .i_ra_cl    ( i_ra_cl[(i+1)*l1_ncl_width-1:i*l1_ncl_width] ),
        .i_ra_of    ( i_ra_of[(i+1)*WAYS_WIDTH-1:i*WAYS_WIDTH] ),
        .o_v        ( o_v[i] ),
        .o_r        ( o_r[i] ),
        .o_rd       ( o_rd[(i+1)*(2*DATA_WIDTH)-1:i*(2*DATA_WIDTH)] ),
        .o_ra       ( o_ra[(i+1)*ra_out_width-1:i*ra_out_width] ),
        .i_we       (i_we),
        .i_wa       (i_wa),
        .i_wd       (i_wd)
      );
    end
  endgenerate

endmodule //bram_top_wrapper
