module l2_ctrl_top_tb;

    parameter nstrms 			= 64;
    parameter nstrms_width		= $clog2(nstrms);
    parameter l2_ncl 			= 256;
    parameter l2_ncl_width 		= $clog2(l2_ncl);
    parameter l2_nstrms			= 16;
    parameter l2_nstrms_width	= $clog2(l2_nstrms);
    parameter TILES 			= nstrms/l2_nstrms;

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
        #100;
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
	reg 								i_rst_v;
	wire 								i_rst_r;
	reg  [nstrms_width-1:0]			    i_rst_sid;

    // FUNCTIONAL STREAM RESET OUTPUT INTERFACE
    wire [nstrms-1:0]				    o_rst_v;
    reg  [nstrms-1:0]				    o_rst_r;

	// L1 REQUEST INTERFACE
	reg  [nstrms-1:0]				    i_rd_v;
	wire [nstrms-1:0]				    i_rd_r;

	// L2 URAM READ INTERFACE
	wire [TILES-1:0]					o_addr_v;
	reg  [TILES-1:0]					o_addr_r;
	wire [TILES*l2_nstrms_width-1:0]	o_addr_sid;
	wire [TILES*l2_ncl_width-1:0] 	    o_addr_ptr;

    // OPENCAPI 3.0 REQUEST INTERFACE
    wire 					            o_req_v;
    reg  				                o_req_r;
    wire [nstrms_width-1:0]	o_req_sid;

    // OPENCAPI 3.0 RESPONSE INTERFACE
    reg  				                i_rsp_v;
    wire 				                i_rsp_r;
    reg  [nstrms_width-1:0]	            i_rsp_sid;

    // after reg
    wire 								s0_rst_v;
    wire  [nstrms-1:0]				    s0_rst_r;
	wire  [nstrms_width-1:0]			s0_rst_sid;
	wire  [nstrms-1:0]				    s0_rd_v;
	wire  [TILES-1:0]					s0_addr_r;

    // REGISTER INPUTS
    base_delay # (
        .width(1+nstrms_width+nstrms+TILES+nstrms),
        .n(1)
    ) is0_input_delay (
        .clk (clk),
        .reset (reset),
        .i_d ({ i_rst_v,  o_rst_r,  i_rst_sid,  i_rd_v,  o_addr_r}), //,  o_req_r,  i_rsp_v}),
        .o_d ({s0_rst_v, s0_rst_r, s0_rst_sid, s0_rd_v, s0_addr_r}) //, s0_req_r, s0_rsp_v})
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

        .i_rst_v    (s0_rst_v),
        .i_rst_r    (i_rst_r),
        .i_rst_sid  (s0_rst_sid),

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

        .i_rsp_v    (s2_rsp_v),
        .i_rsp_r    (s2_rsp_r),
        .i_rsp_sid  (s2_rsp_sid)
    );

    // DRIVE INPUTS - best practise to change them on a negative edge.
    initial begin
        i_rst_v         <= 0;
        o_rst_r         <= 64'hFFFFFFFFFFFFFFFF;
        i_rst_sid       <= 0;
        i_rd_v          <= 0;
        o_addr_r        <= 4'b1111;
        #102;

        i_rst_v         <= 1;
        i_rst_sid       <= 1;
        #4;

        i_rst_v         <= 1;
        i_rst_sid       <= 17;
        #4;

        i_rst_v         <= 1;
        i_rst_sid       <= 2;
        #4;

        i_rst_v         <= 1;
        i_rst_sid       <= 1;
        #4;

        i_rst_v         <= 0;
        i_rst_sid       <= 0;
        #100;

        i_rd_v          <= 2; // one-hot thus stream 1
        #8;

        // Terminate testbench.
        i_rd_v          <= 0;
    end

endmodule // l2_ctrl_new_top_tb
