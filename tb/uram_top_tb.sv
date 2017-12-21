module uram_top_tb;

  parameter   L2_DATA_WIDTH           = 128*8;            // 128 byte cache line.
  parameter   l2_ncl                  = 128;              // TODO: future set to 256
  parameter   l2_ncl_width            = $clog2(l2_ncl);
  parameter   channels                = 2;                // Number of L2 write channels.
  parameter   channels_width          = $clog2(channels);
  parameter   nstrms                  = 32;               // Total number of streams.
  parameter   l2_nstrms               = nstrms/channels;  // TODO: l1 and l2 nstrms are equal. make a single parameter.
  parameter   l2_nstrms_width         = $clog2(l2_nstrms);

  // L2 parameters.
  parameter L2_RAM_DEPTH              = 4096;
  parameter L2_RAM_DEPTH_WIDTH        = $clog2(L2_RAM_DEPTH);
  parameter l1_ncl                    = 16;
  parameter l1_ncl_width              = $clog2(l1_ncl);

  // L1 parameters.
  parameter DATA_WIDTH                  = 8*8;                // 8 bytes per element
  parameter RAM_DEPTH                   = 512;                // double pump -> 256 16B
  parameter ADDR_WIDTH                  = $clog2(RAM_DEPTH);
  parameter WAYS                        = 8;                   // Number of BRAMs per cache line.



  // TODO: move this function to separate simulation library file.
  // TODO: put it within a module with parameters.
  // Unsigned random number generator.
  localparam PRODUCT = channels*WAYS*DATA_WIDTH;
  function [PRODUCT-1:0] urandom;
    input [31:0] seed; // $urandom requires a 32 bit seed.

    integer i;
    for(i = 0; i < PRODUCT; i = i + 1) begin
      urandom[i] = $urandom(seed);
    end

  endfunction

  wire [31:0] seed = 4'b1011;

  // Debug urandom function.
  //initial begin
  //  $display( "urandom=%b", urandom(seed) );
  //end



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
      $dumpfile("uram_top_tb.vcd");
      $dumpvars(0, uram_top_tb);
    `endif
  end

  // SIGNAL DECLARATIONS
  // L2 INPUT READ INTERFACE
  reg                                 i_l2_addr_v;
  wire                                i_l2_addr_r;
  reg  [l2_nstrms_width-1:0]          i_l2_addr_sid;
  reg  [l2_ncl_width-1:0]             i_l2_addr_ptr;

  // L2 RESPONSE INTERFACE
  wire [l2_nstrms-1:0]                o_rsp_v;
  reg  [l2_nstrms-1:0]                o_rsp_r;

  // L1 WRITE INTERFACE
  wire                                o_we;
  wire [ADDR_WIDTH-1:0]               o_wa;
  wire [WAYS*DATA_WIDTH-1:0]          o_wd;

  // HOST WRITE INTERFACE
  reg                                 i_we;
  reg  [L2_RAM_DEPTH_WIDTH-1:0]       i_wa;
  reg  [WAYS*DATA_WIDTH-1:0]          i_wd;

/*
  // Functional verification.
  `ifdef VCD
    always begin
      if( i_we[0] == 1'b1 ) begin
        $display("t=%d, i_we = %b, i_wd = %h", $time-1, i_we, i_wd[8*DATA_WIDTH-1:7*DATA_WIDTH]);
      end

      if( i_we[1] == 1'b1 ) begin
        $display("t=%d, i_we = %b, i_wd = %h", $time-1, i_we, i_wd[2*8*DATA_WIDTH-1:(2*7+1)*DATA_WIDTH]);
      end

      if( (o_v && o_r) == 1'b1 ) begin
        $display("t = %d, o_act = %b, o_rd = %h", $time-4, (o_v && o_r), o_rd);
      end
      #2;
    end
  `endif
*/

  // DUT
  uram_top IDUT (
    .clk1x          (clk1x),
    .clk2x          (clk2x),
    .reset          (reset),

    .i_l2_addr_v    (i_l2_addr_v),
    .i_l2_addr_r    (i_l2_addr_r),
    .i_l2_addr_sid  (i_l2_addr_sid),
    .i_l2_addr_ptr  (i_l2_addr_ptr),

    .o_rsp_v        (o_rsp_v),
    .o_rsp_r        (o_rsp_r),

    .o_we           (o_we),
    .o_wa           (o_wa),
    .o_wd           (o_wd),

    .i_we           (i_we),
    .i_wa           (i_wa),
    .i_wd           (i_wd)
  );

  // DRIVE INPUTS - best practise to change them on a negative edge.
  initial begin
    // Initially everything is set to zero.
    i_l2_addr_v     <= 0;
    i_l2_addr_sid   <= 0;
    i_l2_addr_ptr   <= 0;
    o_rsp_r         <= 0;
    i_we            <= 0;
    i_wa            <= 0;
    i_wd            <= 0;
    #102;

    // Set interfaces to be ready.
    i_l2_addr_v     <= 0;
    i_l2_addr_sid   <= 0;
    i_l2_addr_ptr   <= 0;
    o_rsp_r         <= {l2_nstrms{1'b1}};
    i_we            <= 0;
    i_wa            <= 0;
    i_wd            <= 0;
    #7;



    // Write to stream 1 - double pump 0.
    i_l2_addr_v     <= 0;
    i_l2_addr_sid   <= 0;
    i_l2_addr_ptr   <= 0;
    o_rsp_r         <= {l2_nstrms{1'b1}};
    i_we            <= 1;
    i_wa            <= 12'b0001_0000000_0;
    i_wd            <= $urandom;
    #2;

    // Write to stream 1 - double pump 1.
    i_l2_addr_v     <= 0;
    i_l2_addr_sid   <= 0;
    i_l2_addr_ptr   <= 0;
    o_rsp_r         <= {l2_nstrms{1'b1}};
    i_we            <= 1;
    i_wa            <= 12'b0001_0000000_1;
    i_wd            <= $urandom;
    #2;

    // Write to stream 15 - double pump 0.
    i_l2_addr_v     <= 0;
    i_l2_addr_sid   <= 0;
    i_l2_addr_ptr   <= 0;
    o_rsp_r         <= {l2_nstrms{1'b1}};
    i_we            <= 1;
    i_wa            <= 12'b1111_1111101_0;
    i_wd            <= $urandom;
    #2;

    // Write to stream 15 - double pump 1.
    i_l2_addr_v     <= 0;
    i_l2_addr_sid   <= 0;
    i_l2_addr_ptr   <= 0;
    o_rsp_r         <= {l2_nstrms{1'b1}};
    i_we            <= 1;
    i_wa            <= 12'b1111_1111101_1;
    i_wd            <= $urandom;
    #2;



    // Rest
    i_l2_addr_v     <= 0;
    i_l2_addr_sid   <= 0;
    i_l2_addr_ptr   <= 0;
    o_rsp_r         <= {l2_nstrms{1'b1}};
    i_we            <= 0;
    i_wa            <= 0;
    i_wd            <= 0;
    #5;



    // Read from stream 1.
    i_l2_addr_v     <= 1;
    i_l2_addr_sid   <= 4'b0001;
    i_l2_addr_ptr   <= 7'b0000000;
    o_rsp_r         <= {l2_nstrms{1'b1}};
    i_we            <= 0;
    i_wa            <= 0;
    i_wd            <= 0;
    #4;

    // Read from stream 15.
    i_l2_addr_v     <= 1;
    i_l2_addr_sid   <= 4'b1111;
    i_l2_addr_ptr   <= 7'b1111101;
    o_rsp_r         <= {l2_nstrms{1'b1}};
    i_we            <= 0;
    i_wa            <= 0;
    i_wd            <= 0;
    #4;



/*
    // Read from address 20.
    i_v <= 1;
    i_ra_ch <= 0;
    i_ra_st <= 4'b0001;
    i_ra_cl <= 4'b0100;
    i_ra_of <= 3'b000;
    o_r <= 1;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #4;

    // Read from address 40.
    i_v <= 1;
    i_ra_ch <= 0;
    i_ra_st <= 4'b0010;
    i_ra_cl <= 4'b1000;
    i_ra_of <= 3'b000;
    o_r <= 1;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #4;

    // Read from address 20.
    i_v <= 1;
    i_ra_ch <= 0;
    i_ra_st <= 4'b0001;
    i_ra_cl <= 4'b0100;
    i_ra_of <= 3'b000;
    o_r <= 1;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #4;

    // Rest
    i_v <= 0;
    i_ra_ch <= 0;
    i_ra_st <= 0;
    i_ra_cl <= 0;
    i_ra_of <= 0;
    o_r <= 0;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #8;

    // Read from address 40 on channel 1.
    i_v <= 1;
    i_ra_ch <= 1;
    i_ra_st <= 4'b0010;
    i_ra_cl <= 4'b1000;
    i_ra_of <= 3'b111;
    o_r <= 0;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #4;



    // Rest
    i_v <= 0;
    i_ra_ch <= 0;
    i_ra_st <= 0;
    i_ra_cl <= 0;
    i_ra_of <= 0;
    o_r <= 0;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #4;

    // Rest
    i_v <= 0;
    i_ra_ch <= 0;
    i_ra_st <= 0;
    i_ra_cl <= 0;
    i_ra_of <= 0;
    o_r <= 1;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #4;

    // Rest
    i_v <= 0;
    i_ra_ch <= 0;
    i_ra_st <= 0;
    i_ra_cl <= 0;
    i_ra_of <= 0;
    o_r <= 1;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #64;



    // Continuous read test.
    repeat (10) begin

      // Read from address 20.
      i_v <= 1;
      i_ra_ch <= 0;
      i_ra_st <= 4'b0001;
      i_ra_cl <= 4'b0100;
      i_ra_of <= 3'b000;
      o_r <= 1;
      i_we <= 0;
      i_wa <= 0;
      i_wd <= 0;
      #4;

      // Read from address 40.
      i_v <= 1;
      i_ra_ch <= 0;
      i_ra_st <= 4'b0010;
      i_ra_cl <= 4'b1000;
      i_ra_of <= 3'b000;
      o_r <= 1;
      i_we <= 0;
      i_wa <= 0;
      i_wd <= 0;
      #4;

    end



    // Rest
    i_v <= 0;
    i_ra_ch <= 0;
    i_ra_st <= 0;
    i_ra_cl <= 0;
    i_ra_of <= 0;
    o_r <= 1;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #4;

    // Rest (- not ready)
    i_v <= 0;
    i_ra_ch <= 0;
    i_ra_st <= 0;
    i_ra_cl <= 0;
    i_ra_of <= 0;
    o_r <= 1;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #8;

    // Rest
    i_v <= 0;
    i_ra_ch <= 0;
    i_ra_st <= 0;
    i_ra_cl <= 0;
    i_ra_of <= 0;
    o_r <= 1;
    i_we <= 0;
    i_wa <= 0;
    i_wd <= 0;
    #40;
*/



    // Rest
    i_l2_addr_v     <= 0;
    i_l2_addr_sid   <= 0;
    i_l2_addr_ptr   <= 0;
    o_rsp_r         <= {l2_nstrms{1'b1}};
    i_we            <= 0;
    i_wa            <= 0;
    i_wd            <= 0;
    #100;

    // Terminate testbench.
    i_l2_addr_v     <= 0;
    i_l2_addr_sid   <= 0;
    i_l2_addr_ptr   <= 0;
    o_rsp_r         <= 0;
    i_we            <= 0;
    i_wa            <= 0;
    i_wd            <= 0;

    $finish;
  end

endmodule // uram_top_tb
