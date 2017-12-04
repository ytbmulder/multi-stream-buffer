module bram_top_tb;

  parameter   DATA_WIDTH              = 8*8;             // 8 bytes per element
  parameter   RAM_DEPTH               = 512;              // double pump -> 256 16B entries
  parameter   ADDR_WIDTH              = $clog2(RAM_DEPTH);
  parameter   WAYS                    = 8;                // 8x 36K BRAM instances.
  parameter   WAYS_WIDTH              = $clog2(WAYS);



  // TODO: move this function to separate simulation library file.
  // TODO: put it within a module with parameters.
  // Unsigned random number generator.
  localparam PRODUCT = WAYS*DATA_WIDTH;
  function [PRODUCT-1:0] urandom;
    input [31:0] seed; // $urandom requires a 32 bit seed.

    integer i;
    for(i = 0; i < PRODUCT; i = i + 1) begin
      urandom[i] = $urandom(seed);
    end

  endfunction

  wire [31:0] seed = 4'b1011;

  initial begin
    $display( "urandom=%b", urandom(seed) );
  end



  // SETUP
  reg clk1x;
  reg clk2x;
  reg reset;

  integer i; // for read burst for loop

  always
  begin
    clk1x <= 1'b1;
    #(2.0);
    clk1x <= 1'b0;
    #(2.0);
  end

  always
  begin
    clk2x <= 1'b1;
    #(1.0);
    clk2x <= 1'b0;
    #(1.0);
  end

  initial
  begin
    clk1x = 0;
    clk2x = 0;
    #2000;
    $finish;
  end

  initial begin
    reset = 1;
    #102;
    reset = 0;
  end

  initial begin
    // dump waveform files
    // dumpvars = dumps ALL the variables of that module and all the variables in ALL lower level modules instantiated by this top module
    `ifdef VCD
      $dumpfile("bram_top_tb.vcd");
      $dumpvars(0, bram_top_tb);
    `endif
  end

  // SIGNAL DECLARATIONS
  // Input read interface.
  reg   i_v;
  wire  i_r;
  reg   [WAYS_WIDTH+ADDR_WIDTH-2:0] i_d;

  // Output read interface.
  wire  o_v;
  reg   o_r;
  wire  [2*DATA_WIDTH-1:0] o_d;

  // Input write interface.
  reg  i_we;
  reg  [ADDR_WIDTH-1:0] i_wa;
  reg  [WAYS*DATA_WIDTH-1:0] i_wd;

  // DUT
  //sdp_test_rv IDUT ( // credit interface
  //bram_test_rv_oe IDUT ( // 128 bit output
  //bram_test_rv_oe_2x IDUT ( // 64 bit output
  bram_top IDUT (
    .clk1x (clk1x),
    .clk2x (clk2x),
    .reset (reset),

    .i_v  (i_v),
    .i_r  (i_r),
    .i_d  (i_d),

    .o_v  (o_v),
    .o_r  (o_r),
    .o_d  (o_d),

    .i_we (i_we),
    .i_wa (i_wa),
    .i_wd (i_wd)
  );

  // DRIVE INPUTS - best practise to change them on a negative edge.
  initial begin
    // Initially everything is set to zero.
    i_v <= 0;
    i_d <= 0;
    o_r <= 0;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #102;

    // Set interfaces to be ready.
    i_v <= 0;
    i_d <= 0;
    o_r <= 1;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #8;



    // Write 100 to address 40.
    i_v <= 0;
    i_d <= 0;
    o_r <= 1;
    i_we <= 1;
    i_wa <= 9'b000101000;
    i_wd <= $urandom; //100;
    #2;

    // Write 200 to address 41.
    i_v <= 0;
    i_d <= 0;
    o_r <= 1;
    i_we <= 1;
    i_wa <= 9'b000101001;
    i_wd <= $urandom; //200;
    #2;

    // Write 300 to address 50.
    i_v <= 0;
    i_d <= 0;
    o_r <= 1;
    i_we <= 1;
    i_wa <= 9'b001010000;
    i_wd <= urandom(seed); //300;
    #2;

    // Write 400 to address 51.
    i_v <= 0;
    i_d <= 0;
    o_r <= 1;
    i_we <= 1;
    i_wa <= 9'b001010001;
    i_wd <= 400;
    #2;



    // Read from address 20.
    i_v <= 1;
    i_d <= 11'b00010100000; //20; // NOTE: Last three bits are for element offset within cache line.
    o_r <= 1;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #4;

    // Read from address 40.
    i_v <= 1;
    i_d <= 11'b00101000000; //40;
    o_r <= 1;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #4;

    // Read from address 20.
    i_v <= 1;
    i_d <= 11'b00010100000; //20;
    o_r <= 1;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #4;

    // Rest
    i_v <= 0;
    i_d <= 0;
    o_r <= 0;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #8;

    // Read from address 40.
    i_v <= 1;
    i_d <= 11'b00101000000; //40;
    o_r <= 0;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #4;

/*
    // TODO: adding this results in reverse reading of this address.
    // Probably because previous read has extra half cycle, therefore toggle is offset.
    i_v <= 1;
    i_d <= 11'b00010100000; //20;
    o_r <= 0;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #4;
*/



    // Rest
    i_v <= 0;
    i_d <= 0;
    o_r <= 0;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #4;

    // Rest
    i_v <= 0;
    i_d <= 0;
    o_r <= 1;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #4;

    // Rest
    i_v <= 0;
    i_d <= 0;
    o_r <= 1;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #64;



    // Continuous read test.
    repeat (10) begin

      // Read from address 20.
      i_v <= 1;
      i_d <= 11'b00010100000; //20;
      o_r <= 1;
      i_we <= 0;
      i_wa <= 0;
      i_wd <= 0;
      #4;

      // Read from address 40.
      i_v <= 1;
      i_d <= 11'b00101000000; //40;
      o_r <= 1;
      i_we <= 0;
      i_wa <= 0;
      i_wd <= 0;
      #4;

    end



    // Rest
    i_v <= 0;
    i_d <= 0;
    o_r <= 1;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #4;

    // Rest - not ready
    i_v <= 0;
    i_d <= 0;
    o_r <= 1;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #8;

    // Rest
    i_v <= 0;
    i_d <= 0;
    o_r <= 1;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #40;




    // Terminate testbench.
    i_v <= 0;
    i_d <= 0;
    o_r <= 0;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
  end

endmodule // bram_test_tb
