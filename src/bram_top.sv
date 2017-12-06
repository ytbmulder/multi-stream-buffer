module bram_top #
(
  parameter   DATA_WIDTH              = 8*8,              // 8 bytes per element
  parameter   RAM_DEPTH               = 512,              // double pump -> 256 16B entries
  parameter   ADDR_WIDTH              = $clog2(RAM_DEPTH),
  parameter   WAYS                    = 8, // number of BRAMs needed to make a cache line
  parameter   WAYS_WIDTH              = $clog2(WAYS),
//parameter   channels                = 2,
//parameter   channels_width          = $clog2(channels)
)
(
  input                               clk1x,
  input                               clk2x,
  input                               reset,

  // Input read interface.
  input                               i_v,
  output                              i_r,
//input  [WAYS_WIDTH+ADDR_WIDTH-2:0]  i_ra, // = read address
  //input  [channels_width-1:0]         i_ra_ch, // Channel
  input  [$clog2(16)-1:0]             i_ra_st, // Stream
  input  [$clog2(16)-1:0]             i_ra_cl, // Cache line
  input  [WAYS_WIDTH-1:0]             i_ra_of, // Offset

  // Output read interface.
  output                              o_v,
  input                               o_r,
  output [2*DATA_WIDTH-1:0]           o_rd,

  // Input write interface.
  input                               i_we,
  input  [ADDR_WIDTH-1:0]             i_wa,
  input  [WAYS*DATA_WIDTH-1:0]        i_wd
);

  wire [WAYS_WIDTH+ADDR_WIDTH-2:0] i_ra = {i_ra_st, i_ra_cl, i_ra_of};

  // Input register.
  wire s1_v, s1_r;
  //wire [WAYS_WIDTH+ADDR_WIDTH-2:0] s1_ra_pre;

  wire [$clog2(16)-1:0] s1_ra_st;
  wire [$clog2(16)-1:0] s1_ra_cl;
  wire [WAYS_WIDTH-1:0] s1_ra_of;

  base_areg # (
    .width  (WAYS_WIDTH+ADDR_WIDTH-1),
    .lbl    (3'b110)
    ) S1_FF (
    .clk    (clk1x),
    .reset  (reset),
    .i_v    (i_v),
    .i_r    (i_r),
    .i_d    (i_ra),
    .o_v    (s1_v),
    .o_r    (s1_r),
    .o_d    ({s1_ra_st, s1_ra_cl, s1_ra_of}) //(s1_ra_pre)
  );

  localparam crdts = 6; //TODO: lower results in not being able to handle read bursts.
  wire st_v, st_r;
  wire s1_credit;
  base_acredit_src # (
    .credits (crdts)
    ) SRC (
    .clk (clk1x),
    .reset (reset),
    .i_v (s1_v),
    .i_r (s1_r),
    .o_v (st_v),
    .o_r (st_r),
    .o_c (s1_credit)
  );

  //wire s1_act = s1_v & s1_r;
  wire st_act = st_v & st_r; // BRAM always ready.
  wire s1_re = st_act;

  // T flip flop
  reg q;
  always @ (posedge clk2x)
    if (reset) begin
      q <= 1'b0;
    end else if (st_act) begin
      q <= !q;
  end

  // BRAM control path.
  wire s2_v;
  wire s2_r = 1'b1; // always ready, taken care of by credits
  base_areg # (
    .width  (1),
    .lbl    (3'b110)
    ) S1B_FF (
    .clk    (clk1x),
    .reset  (reset),
    .i_v    (st_v),
    .i_r    (st_r),
    .i_d    (1'b0),
    .o_v    (s2_v),
    .o_r    (s2_r),
    .o_d    ()
  );



  // BRAM primitive instantiation.
  //wire [WAYS_WIDTH+ADDR_WIDTH-1:0] s1_ra = {s1_ra_pre[WAYS_WIDTH+ADDR_WIDTH-2:WAYS_WIDTH], q, s1_ra_pre[WAYS_WIDTH-1:0]};
  wire [WAYS_WIDTH+ADDR_WIDTH-1:0] s1_ra = {s1_ra_st, s1_ra_cl, q, s1_ra_of}; // q is cl lsb
  wire [DATA_WIDTH-1:0] s2_rd;

  // Contains 16 128B cache lines for 16 streams. Equals one channel.
  bram_slice # (
    .DATA_WIDTH (DATA_WIDTH),
    .RAM_DEPTH  (RAM_DEPTH),
    .WAYS       (WAYS)
    ) SLICE (
    .clk1x      (clk1x),
    .clk2x      (clk2x),
    .reset      (reset),
    .i_we       (i_we),
    .i_wa       (i_wa),
    .i_wd       (i_wd),
    .i_re       (s1_re),
    .i_ra       (s1_ra),
    .o_rd       (s2_rd)
  );



  // Alignment reigster.
  wire [DATA_WIDTH-1:0] s2b_rd;
  base_vlat # (
    .width  (DATA_WIDTH)
    ) FF (
    .clk    (clk2x),
    .reset  (reset),
    .din    (s2_rd),
    .q      (s2b_rd)
  );

  wire [2*DATA_WIDTH-1:0] s3_rd = {s2_rd, s2b_rd};

  // Sink
  base_acredit_snk # (
    .credits    (crdts),
    .width      (2*DATA_WIDTH),
    .output_reg (0)
    ) SINK (
    .clk (clk1x),
    .reset (reset),
    .i_v (s2_v),
    .i_d (s3_rd),
    .i_c (s1_credit),
    .o_v (o_v),
    .o_r (o_r),
    .o_d (o_rd)
  );

endmodule
