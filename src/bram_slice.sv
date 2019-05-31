// TODO: Call this module l1_bram and the current module with that name l1_bram_slice

module bram_slice #
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

  // Write interface
  input                               i_we,
  input  [ADDR_WIDTH-1:0]             i_wa,
  input  [WAYS*DATA_WIDTH-1:0]        i_wd,

  // Read interface
  input                               i_re,
  input  [WAYS_WIDTH+ADDR_WIDTH-1:0]  i_ra, // CHANNEL, STREAM, LINE, OFFSET
  output [DATA_WIDTH-1:0]             o_rd
);

  // TODO: make cache line wide memory using bram_wrapper


  wire [WAYS*DATA_WIDTH-1:0] s1_rd;

  genvar i;
  generate
    for (i=0; i<WAYS; i=i+1) begin : GEN_WAYS

      bram_wrapper # (
        .DATA_WIDTH (DATA_WIDTH),
        .RAM_DEPTH  (RAM_DEPTH),
        .ADDR_WIDTH (ADDR_WIDTH)
      ) BRAM (
        .clk2x  (clk2x),
        .reset  (reset),
        .i_we   (i_we),
        .i_wa   (i_wa),
        .i_wd   (i_wd[(i+1)*DATA_WIDTH-1:i*DATA_WIDTH]),
        .i_re   (i_re),
        .i_ra   (i_ra[WAYS_WIDTH+ADDR_WIDTH-1:WAYS_WIDTH]),
        .o_rd   (s1_rd[(i+1)*DATA_WIDTH-1:i*DATA_WIDTH])
      );
    end
  endgenerate

  // TODO: add generate, if WAYS > 1, generate MUX. Else not.

  // Delay MUX select signal.
  wire [WAYS_WIDTH-1:0] sel;
  base_vlat # (
    .width  (WAYS_WIDTH)
    ) MUX (
    .clk    (clk1x),
    .reset  (reset),
    .din    (i_ra[WAYS_WIDTH-1:0]),
    .q      (sel)
  );

  wire [DATA_WIDTH-1:0] s1a_rd, s1b_rd;

  // MUX for element select.
  base_emux_le # (
    .width  (DATA_WIDTH),
    .ways   (WAYS)
    ) MUXLE (
    .din    (s1_rd),
    .sel    (sel),
    .dout   (s1a_rd)
  );

  // Additional regs for timing closure. Especially for configurations with four channels.
  base_vlat # (
    .width  (DATA_WIDTH)
    ) OUTPUT_REG_1 (
    .clk    (clk2x),
    .reset  (reset),
    .din    (s1a_rd),
    .q      (s1b_rd)
  );

  base_vlat # (
    .width  (DATA_WIDTH)
    ) OUTPUT_REG_2 (
    .clk    (clk2x),
    .reset  (reset),
    .din    (s1b_rd),
    .q      (o_rd)
  );

endmodule
