module l2_ctrl_top_tb;

  // Host parameters
  parameter addr_width                = 64;                 // Host address width in bits.
  parameter cache_line                = 128;                // Host cache line size in bytes.
  parameter cache_line_width          = $clog2(cache_line);

  // Stream cache parameters
  parameter nstrms                    = 64;
  parameter nstrms_width              = $clog2(nstrms);
  parameter l2_nstrms                 = 16;
  parameter l2_nstrms_width           = $clog2(l2_nstrms);
  parameter l2_ncl                    = 256;                // Number of cache lines per stream in L2.
  parameter l2_ncl_width              = $clog2(l2_ncl);
  parameter channels                  = nstrms/l2_nstrms;

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
        #1300;
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
            $dumpfile("l2_ctrl_top_tb.vcd");
            $dumpvars(0, l2_ctrl_top_tb);
        `endif
    end

    // SIGNAL DECLARATIONS
    // FUNCTIONAL STREAM RESET INPUT INTERFACE
	reg [nstrms-1:0] 								i_rst_v;
	wire [nstrms-1:0] 								i_rst_r;
  reg [addr_width-1:0]        i_rst_ea;

    // FUNCTIONAL STREAM RESET OUTPUT INTERFACE
    wire [nstrms-1:0]				    o_rst_v;
    reg  [nstrms-1:0]				    o_rst_r;

	// L1 REQUEST INTERFACE
	reg  [nstrms-1:0]				    i_rd_v;
	wire [nstrms-1:0]				    i_rd_r;

	// L2 URAM READ INTERFACE
	wire [channels-1:0]					o_addr_v;
	reg  [channels-1:0]					o_addr_r;
	wire [channels*l2_nstrms_width-1:0]	o_addr_sid;
	wire [channels*l2_ncl_width-1:0] 	    o_addr_ptr;

    // OPENCAPI 3.0 REQUEST INTERFACE
    wire 					            o_req_v;
    reg  				                o_req_r;
    wire [nstrms_width-1:0]	o_req_sid;
    wire [addr_width-1:0] o_req_ea;

    // OPENCAPI 3.0 RESPONSE INTERFACE
    reg  				                i_rsp_v;
    wire 				                i_rsp_r;
    reg  [nstrms_width-1:0]	            i_rsp_sid;

    // after reg
    wire [nstrms-1:0] 								s0_rst_v;
    wire [addr_width-1:0]       s0_rst_ea;
    wire  [nstrms-1:0]				    s0_rst_r;
	wire  [nstrms-1:0]				    s0_rd_v;
	wire  [channels-1:0]					s0_addr_r;

    // REGISTER INPUTS
    base_delay # (
        .width(nstrms+addr_width+nstrms+channels+nstrms),
        .n(1)
    ) is0_input_delay (
        .clk (clk),
        .reset (reset),
        .i_d ({ i_rst_v,  i_rst_ea,  o_rst_r,  i_rd_v,  o_addr_r}),
        .o_d ({s0_rst_v, s0_rst_ea, s0_rst_r, s0_rd_v, s0_addr_r})
    );

    // Loop back req and rsp for OpenCAPI 3.0.
    wire                       s1_req_v;
    wire                       s1_req_r;
    wire [nstrms_width-1:0]    s1_req_sid;

    wire                       s2_rsp_v;
    wire                       s2_rsp_r;
    wire [nstrms_width-1:0]    s2_rsp_sid;

    // Loop request to response interface.
    base_areg # ( .lbl(3'b110),.width(nstrms_width)) is0_req_reg (
        .clk(clk),.reset(reset),
        .i_v(s1_req_v),.i_r(s1_req_r),.i_d(s1_req_sid),
        .o_v(s2_rsp_v),.o_r(s2_rsp_r),.o_d(s2_rsp_sid)
    );

    // DUT
    l2_ctrl_top IDUT (
        .clk        (clk),
        .reset      (reset),

        .i_rst_v    (s0_rst_v), // TODO: use decoder to make writing tb easier
        .i_rst_r    (i_rst_r),
        .i_rst_ea   (s0_rst_ea),

        .o_rst_v    (o_rst_v),
        .o_rst_r    (s0_rst_r),

        .i_rd_v     (s0_rd_v),
        .i_rd_r     (i_rd_r),

        .o_addr_v   (o_addr_v),
        .o_addr_r   (s0_addr_r),
        .o_addr_sid (o_addr_sid),
        .o_addr_ptr (o_addr_ptr),

        .o_req_v    (s1_req_v),
        .o_req_r    (s1_req_r),
        .o_req_sid  (s1_req_sid),
        .o_req_ea   (o_req_ea),

        .i_rsp_v    (s2_rsp_v),
        .i_rsp_r    (s2_rsp_r),
        .i_rsp_sid  (s2_rsp_sid)
    );

  // DRIVE INPUTS - best practise to change them on a negative edge.
  initial begin
    // Initially everything is set to zero.
    i_rst_v         <= 64'h0000000000000000;
    i_rst_ea        <= 0;
    o_rst_r         <= 64'h0000000000000000;
    i_rd_v          <= 64'h0000000000000000;
    o_addr_r        <= 4'b0000;
    #102;

    // Set interfaces to be ready.
    o_rst_r         <= 64'hFFFFFFFFFFFFFFFF;
    o_addr_r        <= 4'b1111;
    #8;

    // Read from stream 1 (i_rd_v is one-hot signal).
    // Nothing happens as expected since stream has not been reset.
    i_rd_v          <= 2;
    #8;
    i_rd_v          <= 64'h0000000000000000;

    // Reset stream 1.
    i_rst_v         <= 64'h0000000000000002;
    i_rst_ea        <= 4;
    #4;

    // Reset stream 17.
    i_rst_v         <= 64'h0000000000020000;
    i_rst_ea        <= 8;
    #4;

    // Reset stream 2.
    i_rst_v         <= 64'h0000000000000004;
    i_rst_ea        <= 16;
    #4;

    // Reset stream 1 again. This reset is not accepted as expected.
    i_rst_v         <= 64'h0000000000000002;
    i_rst_ea        <= 32;
    #4;
    i_rst_v         <= 64'h0000000000000000;
    i_rst_ea        <= 0;
    #100;

    // Read from stream 1 (i_rd_v is one-hot signal).
    i_rd_v          <= 2;
    #8;

    // Read from stream 2 (i_rd_v is one-hot signal).
    i_rd_v          <= 4;
    #8;
    i_rd_v          <= 64'h0000000000000000;
    #16;

    // Terminate testbench.
    i_rst_v         <= 64'h0000000000000000;
    i_rst_ea        <= 0;
    o_rst_r         <= 64'h0000000000000000;
    i_rd_v          <= 64'h0000000000000000;
    o_addr_r        <= 4'b0000;
  end

endmodule // l2_ctrl_new_top_tb
