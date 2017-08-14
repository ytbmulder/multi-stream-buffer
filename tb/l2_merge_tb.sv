module l2_merge_tb;
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
        #1000;
        $finish;
    end

    initial begin
        reset = 1;
        #100;
        reset = 0;
    end

    reg [15:0] clreq_v;
    integer i;
    initial begin
        // dump waveform files
        // dumpvars = dumps ALL the variables of that module and all the variables in ALL lower level modules instantiated by this top module
        `ifdef VCD
            $dumpfile("l2_merge_tb.vcd");
            $dumpvars(0, l2_merge_tb);
        `endif

        // Initial reset state value of zero.
        clreq_v <= 0;
        #100;

        // Loop through all single valid request combinations.
        for(i=0; i<16; i=i+1)
        begin
            clreq_v <= 2**i;
            #4;
        end

        // Have no requests for some cycles.
        clreq_v <= 0;
        #12;

        // Test two valid requests for different Round-Robin MUXs.
        clreq_v <= 16'h0022;
        #4;

        // Have no requests for some cycles.
        clreq_v <= 0;
        #12;

        // Test two valid requests for the same Round-Robin MUX.
        clreq_v <= 16'h0006;
        #4;

        // Have no requests for some cycles.
        clreq_v <= 0;
        #12;

        // Combine previous two tests.
        clreq_v <= 16'h0066;
        #8;

        // Have no requests for some cycles.
        clreq_v <= 0;
        #12;

        //TODO: have all valid requests.
        clreq_v <= 16'hFFFF;
        //#64; // 4 steps per cycle times 16 requests.
        #8;

        clreq_v <= 0;

    end

  // TODO: update this testbench with new IDUT and setup like in newer testbenches.
  // TODO: have input vlat for inputs.
  // TODO: to avoid simulator conflicts (X's like in Vivado), declare input signal changes on falling edge of the clock.

    // outputs
    wire [15:0] clreq_r;
    wire o_v;
    wire [3:0] clid_req; // output of interest.
    l2_merge IDUT (
        .clk        (clk),
        .reset      (reset),
        .i_clreq_v  (clreq_v), // 16 bits
        .i_clreq_r  (clreq_r), // 16 bits
        .o_v        (o_v),
        .o_r        (1'b1), // always accept a new request
        .o_clid_req (clid_req) // 4 bits
    );

endmodule // test_top
