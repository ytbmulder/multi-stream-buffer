//use urandom to randomise order of requests

//use 2d array to generate a predefined (parameter) number of data points (elements) and keep them in an array here so it can be used to verify against by just selecting the right offset from a certain cache line per stream.

//write functions/tasks for AFU read ports

module wd_driver #
(
  parameter width = 8*8, // Data element width.
  parameter ways  = 10,  // Number of data elements.
  parameter ways_width = $clog2(ways)
)
(
  input               clk,
  input               reset,

  input               i_v,
  output              i_r,

  output              o_v,
//input               o_r, // TODO
  output [width-1:0]  o_d
);

  // Generate o_d on the negative clock edge such that no transitions occur on a rising clock edge from the point of view of the DUT.
  wire clk_inv = ~clk;

  assign i_r = 1'b1; // This module is always ready.
  wire i_act = i_v & i_r;

  reg [width-1:0] data [0:ways-1];

  // Generate data set.
  integer i;
  initial begin
    for( i=0; i<ways; i=i+1 ) begin
      data[i] = i + 1;
      //$display("data[%0d] = %d", i, data[i]);
    end
  end

  // Index counter.
  wire [ways_width-1:0] index;
  wire [ways_width-1:0] s0_count_new = index + 1;
  base_vlat_en # (
    .width  (ways_width),
    .rstv   (0)
    ) is0_counter (
    .clk    (clk_inv),
    .reset  (reset),
    .enable (i_act),
    .din    (s0_count_new),
    .q      (index)
  );

  // Assign output data.
  base_areg # (
    .width  (width),
    .lbl    (3'b110)
    ) is0_areg (
    .clk    (clk_inv),
    .reset  (reset),
    .i_v    (i_act),
    .i_r    (), // TODO: use this for back pressure on is0_counter.
    .i_d    (data[index]),
    .o_v    (o_v),
    .o_r    (1'b1), // Always ready.
    .o_d    (o_d)
  );

endmodule
