module uram_slice #
(
  parameter   DATA_WIDTH              = 8*8,              // 8 bytes per element
  parameter   RAM_DEPTH               = 4096,             // double pump -> 2048 16B entries
  parameter   ADDR_WIDTH              = $clog2(RAM_DEPTH),
  parameter   WAYS                    = 8, // number of BRAMs needed to make a cache line
  parameter   WAYS_WIDTH              = $clog2(WAYS)
)
(
  //input                               clk1x,
  input                               clk2x,
  input                               reset,

  // Write interface
  input                               i_we,
  input  [ADDR_WIDTH-1:0]             i_wa,
  input  [WAYS*DATA_WIDTH-1:0]        i_wd,

  // Read interface
  input                               i_re,
  input  [ADDR_WIDTH-1:0]             i_ra,
  output [WAYS*DATA_WIDTH-1:0]        o_rd
);

  wire [WAYS*DATA_WIDTH-1:0] s1_rd;

  genvar i;
  generate
    for (i=0; i<WAYS; i=i+1) begin : GEN_WAYS

      uram_wrapper # (
        .DATA_WIDTH (DATA_WIDTH),
        .RAM_DEPTH  (RAM_DEPTH)
      ) URAM (
        .clk2x  (clk2x),
        .reset  (reset),
        .i_we   (i_we),
        .i_wa   (i_wa),
        .i_wd   (i_wd[(i+1)*DATA_WIDTH-1:i*DATA_WIDTH]),
        .i_re   (i_re),
        .i_ra   (i_ra),
        .o_rd   (s1_rd[(i+1)*DATA_WIDTH-1:i*DATA_WIDTH])
      );

    end
  endgenerate

  assign o_rd = s1_rd;

endmodule
