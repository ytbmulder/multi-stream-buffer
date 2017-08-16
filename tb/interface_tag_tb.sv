module interface_tag_tb;

  // OpenCAPI 3.0 parameters
  parameter addr_width      = 64; // OpenCAPI 3.0 address with to index main memory.
  parameter data_width      = 1024; // OpenCAPI 3.0 data width.

  // Stream cache parameters
  parameter nstrms          = 64;
  parameter nstrms_width    = $clog2(nstrms);
  parameter tag             = 256; // Number of tags to be issued.
  parameter tag_width       = $clog2(tag);
  parameter l2_ncl          = 256;
  parameter l2_ncl_width    = $clog2(l2_ncl);

  // SETUP
  initial begin
    // dump waveform files
    // dumpvars = dumps ALL the variables of that module and all the variables in ALL lower level modules instantiated by this top module
    `ifdef VCD
      $dumpfile("interface_tag_tb.vcd");
      $dumpvars(0, interface_tag_tb);
    `endif

    #1500;
    $finish;
  end

  reg clk, reset;
  initial begin
    clk = 0;
    reset = 1;
    #100;
    reset = 0;
  end

  always
  begin
    clk <= 1'b1;
    #(2.0);
    clk <= 1'b0;
    #(2.0);
  end

    // SIGNAL DECLARATIONS
    // REQUEST INPUT INTERFACE
    reg                     i_req_v;
    wire                    i_req_r;
    reg  [nstrms_width-1:0] i_req_sid;
    reg  [addr_width-1:0]   i_req_ea;

    // RESPONSE OUTPUT INTERFACE
    wire                    o_rsp_v;
    reg                     o_rsp_r;
    wire [data_width-1:0]   o_rsp_data;
    wire [nstrms_width-1:0] o_rsp_sid;
    wire [l2_ncl_width-1:0] o_rsp_ptr;

    // REQUEST OUTPUT INTERFACE
//    wire                    o_req_v;
//    reg                     o_req_r;
    wire [addr_width-1:0]   o_req_ea;
//    wire [tag_width-1:0]    o_req_tag;

    // RESPONSE INPUT INTERFACE
//    reg                     i_rsp_v;
//    wire                    i_rsp_r;
//    reg  [tag_width-1:0]    i_rsp_tag;
    reg  [data_width-1:0]   i_rsp_data;



    // after reg
    wire                     s0_req_v;
    wire  [nstrms_width-1:0] s0_req_sid;
    wire  [addr_width-1:0]   s0_req_ea;
    wire                     s0_rsp_r;
//    wire                     s0_req_r;
//    wire                     s0_rsp_v;
//    wire  [tag_width-1:0]    s0_rsp_tag;
    wire  [data_width-1:0]   s0_rsp_data;

    // REGISTER INPUTS
    base_delay # (
        .width(2+nstrms_width+addr_width+data_width),
        .n(1)
    ) is0_input_delay (
        .clk (clk),
        .reset (reset),
        .i_d ({i_req_v, i_req_sid, i_req_ea, o_rsp_r, /*o_req_r, i_rsp_v, i_rsp_tag,*/ i_rsp_data}),
        .o_d ({s0_req_v, s0_req_sid, s0_req_ea, s0_rsp_r, /*s0_req_r, s0_rsp_v, s0_rsp_tag,*/ s0_rsp_data})
    );

    // Loop back req and rsp for OpenCAPI 3.0.
    wire                       s1_req_v;
    wire                       s1_req_r;
    wire [tag_width-1:0]       s1_req_tag;

    wire                       s2_rsp_v;
    wire                       s2_rsp_r;
    wire [tag_width-1:0]       s2_rsp_tag;

    // Loop request to response interface.
    // Two cycle delay, otherwise the write is not yet finished before the read.
    base_areg # ( .lbl(3'b111),.width(tag_width)) is0_req_reg (
        .clk(clk),.reset(reset),
        .i_v(s1_req_v),.i_r(s1_req_r),.i_d(s1_req_tag),
        .o_v(s2_rsp_v),.o_r(s2_rsp_r),.o_d(s2_rsp_tag)
    );

    // DUT
    interface_tag IDUT (
      .clk        (clk),
      .reset      (reset),

      .i_req_v (s0_req_v),
      .i_req_r (i_req_r),
      .i_req_sid (s0_req_sid),
      .i_req_ea (s0_req_ea),

      .o_rsp_v (o_rsp_v),
      .o_rsp_r (s0_rsp_r),
      .o_rsp_data (o_rsp_data),
      .o_rsp_sid (o_rsp_sid),
      .o_rsp_ptr (o_rsp_ptr),

      .o_req_v   (s1_req_v), //(o_req_v),
      .o_req_r   (s1_req_r), //(s0_req_r),
      .o_req_ea  (o_req_ea),
      .o_req_tag (s1_req_tag), //(o_req_tag),

      .i_rsp_v    (s2_rsp_v), //(s0_rsp_v),
      .i_rsp_r    (s2_rsp_r), //(i_rsp_r),
      .i_rsp_tag  (s2_rsp_tag), //(s0_rsp_tag),
      .i_rsp_data (s0_rsp_data)
    );

    // DRIVE INPUTS - best practise to change them on a negative edge.
    initial begin
        i_req_v    <= 0;
        i_req_sid  <= 0;
        i_req_ea   <= 0;
        o_rsp_r    <= 0;
        i_rsp_data <= 0;
        #102;

        // NOTE: RESET TEST
        #8;

        // request ea 2 from sid 1
        i_req_v    <= 1;
        i_req_sid  <= 1;
        i_req_ea   <= 64'h0000000000000002;
        o_rsp_r    <= 1;
        i_rsp_data <= 0;
        #4;

        // request nothing but keep rsp ready
        i_req_v    <= 0;
        i_req_sid  <= 0;
        i_req_ea   <= 0;
        o_rsp_r    <= 1;
        i_rsp_data <= 0;
        #8;

        // request ea 4 from sid 1
        i_req_v    <= 1;
        i_req_sid  <= 1;
        i_req_ea   <= 64'h0000000000000004;
        o_rsp_r    <= 1;
        i_rsp_data <= 0;
        #4;

        // request ea 5 from sid 1
        i_req_v    <= 1;
        i_req_sid  <= 1;
        i_req_ea   <= 64'h0000000000000005;
        o_rsp_r    <= 1;
        i_rsp_data <= 0;
        #4;

        // request ea 6 from sid 1
        i_req_v    <= 1;
        i_req_sid  <= 1;
        i_req_ea   <= 64'h0000000000000006;
        o_rsp_r    <= 1;
        i_rsp_data <= 0;
        #4;

        // request nothing but keep rsp ready
        i_req_v    <= 0;
        i_req_sid  <= 0;
        i_req_ea   <= 0;
        o_rsp_r    <= 1;
        i_rsp_data <= 0;
        #32;

        // Terminate testbench.
        i_req_v    <= 0;
        i_req_sid  <= 0;
        i_req_ea   <= 0;
        o_rsp_r    <= 0;
        i_rsp_data <= 0;
    end

endmodule
