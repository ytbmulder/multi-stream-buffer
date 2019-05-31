module wd_driver_tb;

  parameter width = 8*8;
  parameter ways  = 8;

  reg clk;
  reg reset;

  always
  begin
    clk <= 1'b1;
    #(2.0);
    clk <= 1'b0;
    #(2.0);
  end

  initial
  begin
    clk = 0;
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
      $dumpfile("wd_driver_tb.vcd");
      $dumpvars(0, wd_driver_tb);
    `endif
  end

  // Signals.
  reg               i_v;
  wire              i_r;

  wire              o_v;
  reg               o_r;
  wire [width-1:0]  o_d;

  wd_driver IDUT (
    .clk    (clk),
    .reset  (reset),

    .i_v    (i_v),
    .i_r    (i_r),

    .o_v    (o_v),
    //.o_r    (o_r),
    .o_d    (o_d)
  );

  initial begin
    // Initially everything is set to zero.
    i_v <= 0;
    //o_r <= 0;
    #102;

    // Set interfaces to be ready.
    i_v <= 0;
    //o_r <= 1;
    #8;



    repeat( 5 ) begin
      // Request data.
      i_v <= 1;
      //o_r <= 1;
      #4;
    end

    // Request data.
    i_v <= 0;
    #4;

    // Request data.
    i_v <= 1;
    #4;



    // Rest.
    i_v <= 0;
    //o_r <= 1;
    #8;

    // Terminate testbench.
    i_v <= 0;
    //o_r <= 0;
    #8;
  end

endmodule
