module bram_top #
(
  parameter   DATA_WIDTH              = 8*8,              // 8 bytes per element
  parameter   RAM_DEPTH               = 512,              // double pump -> 256 16B entries
  parameter   ADDR_WIDTH              = $clog2(RAM_DEPTH),
  parameter   WAYS                    = 8, // number of BRAMs needed to make a cache line
  parameter   WAYS_WIDTH              = $clog2(WAYS)
)
(
  input                               clk1x,
  input                               clk2x,
  input                               reset,

  // Input read interface.
  input                               i_v,
  output                              i_r,
  input  [WAYS_WIDTH+ADDR_WIDTH-2:0]  i_d, // = read address

  // Output read interface.
  output                              o_v,
  input                               o_r,
  output [2*DATA_WIDTH-1:0]           o_d,

  // Input write interface.
  input                               i_we,
  input  [ADDR_WIDTH-1:0]             i_wa,
  input  [WAYS*DATA_WIDTH-1:0]        i_wd
);

  // Input register.
  wire s1_v, s1_r;
  wire [WAYS_WIDTH+ADDR_WIDTH-2:0] s1_d;
  base_areg # (
    .width  (WAYS_WIDTH+ADDR_WIDTH-1),
    .lbl    (3'b110)
    ) S1_FF (
    .clk    (clk1x),
    .reset  (reset),
    .i_v    (i_v),
    .i_r    (i_r),
    .i_d    (i_d),
    .o_v    (s1_v),
    .o_r    (s1_r),
    .o_d    (s1_d)
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

  wire [WAYS_WIDTH+ADDR_WIDTH-1:0] s1_ra = {s1_d[WAYS_WIDTH+ADDR_WIDTH-2:WAYS_WIDTH], q, s1_d[WAYS_WIDTH-1:0]};

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


  wire [DATA_WIDTH-1:0] s2_rd;

/*
  bram_wrapper # (
    .DATA_WIDTH (DATA_WIDTH),
    .RAM_DEPTH  (RAM_DEPTH)
    ) BRAM (
    .clk2x  (clk2x),
    .reset  (reset),
    .i_we   (i_we),
    .i_wa   (i_wa),
    .i_wd   (i_wd),
    .i_re   (s1_re),
    .i_ra   (s1_ra),
    .o_rd   (s2_rd)
  );
*/

  // Contains 16 128B cache lines for 16 streams. Equals one channel.
  l1_bram_slice # (
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
    .o_d (o_d)
  );

endmodule
