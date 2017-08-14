module l1_stream_ptr_tb;
   reg clk;

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
	#100000;
	$finish;
     end

   wire reset;
   base_reset#(.t1(2),.t2(2)) ireset(.clk(clk),.reset(reset));

   wire req_v, req_r, rsp_v, rsp_r;
   base_areg#(.lbl(3'b111)) irsp_reg(.clk(clk),.reset(reset),.i_v(req_v),.i_r(req_r),.i_d(1'b0),.o_v(rsp_v),.o_r(rsp_r),.o_d());



   reg [7:0] rd_v;
   wire [7:0] rd_r;
   always@(posedge clk)
      rd_v <= $random;

   localparam rstcnt_width=8;
   wire [rstcnt_width-1:0] rst_cnt;
   wire 		   rst_v = ~(|rst_cnt);
   wire rst_r;
   base_vlat_en#(.width(rstcnt_width)) irstcnt_lat(.clk(clk),.reset(reset),.din(rst_cnt+1'b1),.q(rst_cnt),.enable(~rst_v | rst_r));

   l1_stream_ptr idut(.clk(clk),.reset(reset),.i_rd_v(rd_v),.i_rd_r(rd_r),.i_rst_v(rst_v),.i_rst_r(rst_r),.i_clrsp_v(rsp_v),.i_clrsp_r(rsp_r),.o_clreq_v(req_v),.o_clreq_r(req_r));

endmodule // l1_stream_ptr_tb
