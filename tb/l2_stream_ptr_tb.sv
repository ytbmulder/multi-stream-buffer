module l2_stream_ptr_tb;

  // Host parameters
  parameter addr_width        = 64;               // Host address width.

  // Stream cache parameters
  parameter l2_ncl            = 256;              // Number of cache lines per stream in L2.
  parameter l2_ncl_width      = $clog2(l2_ncl);

  // SETUP
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
    #3000;
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
      $dumpfile("l2_stream_ptr_tb.vcd");
      $dumpvars(0, l2_stream_ptr_tb);
    `endif
  end

  // SIGNAL DECLARATIONS
  // FUNCTIONAL STREAM RESET INTERFACE
  reg                     i_rst_v;
  wire                    i_rst_r;
  reg  [addr_width-1:0]   i_rst_ea;

  wire                    o_rst_v;
  reg                     o_rst_r;

  // L1 REQUEST INTERFACE
  reg                     i_rd_v;
  wire                    i_rd_r;

  // L2 URAM READ INTERFACE
  wire                    o_addr_v;
  reg                     o_addr_r;
  wire [l2_ncl_width-1:0] o_addr_ptr;

  // OPENCAPI 3.0 REQUEST INTERFACE
  wire                    o_req_v;
  reg                     o_req_r;

  // OPENCAPI 3.0 RESPONSE INTERFACE
  reg                     i_rsp_v;
  wire                    i_rsp_r;

  // after reg
  wire                    s0_rst_v;
  wire [addr_width-1:0]   s0_rst_ea;
  wire                    s0_rst_r;
  wire                    s0_rd_v;
  wire                    s0_addr_r;
  wire                    s0_req_r;
  wire                    s0_rsp_v;

  // REGISTER INPUTS
  base_delay # (
    .width(6+addr_width),
    .n(1)
  ) is0_input_delay (
    .clk (clk),
    .reset (reset),
    .i_d ({ i_rst_v,  i_rst_ea,  o_rst_r,  i_rd_v,  o_addr_r,  o_req_r,  i_rsp_v}),
    .o_d ({s0_rst_v, s0_rst_ea, s0_rst_r, s0_rd_v, s0_addr_r, s0_req_r, s0_rsp_v})
  );

  // Loop back req and rsp for OpenCAPI 3.0.
  wire s1_req_v, s1_req_r;
  wire s2_rsp_v, s2_rsp_r;

  // Loop request to response interface.
  base_areg # ( .lbl(3'b110),.width(1)) is0_req_reg (
    .clk(clk),.reset(reset),
    .i_v(s1_req_v),.i_r(s1_req_r),.i_d(1'b0),
    .o_v(s2_rsp_v),.o_r(s2_rsp_r),.o_d()
  );

  // DUT
  l2_stream_ptr IDUT (
    .clk        (clk),
    .reset      (reset),

    .i_rst_v    (s0_rst_v),
    .i_rst_r    (i_rst_r),
    .i_rst_ea   (s0_rst_ea),

    .o_rst_v    (o_rst_v),
    .o_rst_r    (s0_rst_r),

    .i_rd_v     (s0_rd_v),
    .i_rd_r     (i_rd_r),

    .o_addr_v   (o_addr_v),
    .o_addr_r   (s0_addr_r),
    .o_addr_ptr (o_addr_ptr),

    .o_req_v    (s1_req_v),
    .o_req_r    (s1_req_r),

    .i_rsp_v    (s2_rsp_v),
    .i_rsp_r    (s2_rsp_r)
  );

  // DRIVE INPUTS - best practise to change them on a negative edge.
  initial begin
    // Initially everything is set to zero.
    i_rst_v         <= 0;
    i_rst_ea        <= 0;
    o_rst_r         <= 0;
    i_rd_v          <= 0;
    o_addr_r        <= 0;
    o_req_r         <= 0;
    i_rsp_v         <= 0;
    #102;

    // Set interfaces to be ready.
    o_rst_r         <= 1;
    o_addr_r        <= 1;
    o_req_r         <= 1;
    #8;

    // Functionally reset this stream.
    i_rst_v         <= 1;
    i_rst_ea        <= 128*256; // 32768 mod 128 = 0
    #4;
    i_rst_v         <= 0;
    i_rst_ea        <= 0;
    #8;

    // Read from this stream.
    i_rd_v          <= 1;
    #4;
    i_rd_v          <= 0;
    #8;
    i_rd_v          <= 1;
    #4;
    i_rd_v          <= 0;
    #4;

    // Test second functional reset. Nothing happens as expected because there are outstanding requests.
    i_rst_v   <= 1;
    i_rst_ea  <= 128*3;
    #4;
    i_rst_v   <= 0;
    i_rst_ea  <= 0;
    #4;

    // Test third functional reset. Happens as expected since there are no outstanding requests.
    #1100;
    i_rst_v   <= 1;
    i_rst_ea  <= 128*4;
    #4;
    i_rst_v   <= 0;
    i_rst_ea  <= 0;
    #16;

    // Read from this stream.
    i_rd_v    <= 1;
    #4;
    i_rd_v    <= 0;
    #8;

    // Terminate testbench.
    i_rst_v         <= 0;
    i_rst_ea        <= 0;
    o_rst_r         <= 0;
    i_rd_v          <= 0;
    o_addr_r        <= 0;
    o_req_r         <= 0;
    i_rsp_v         <= 0;
  end

endmodule // l2_stream_ptr_tb
