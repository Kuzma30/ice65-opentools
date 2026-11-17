`timescale 1ns/1ps
// Checks lib/ram4096_l04.v (RAM4096_L04) against a plain 4096 x 18 array.
module ram_tb;
  reg wclk = 0, nrclk = 1, we = 0; reg [11:0] wa = 0, ra = 0; reg [17:0] din = 0;
  wire [17:0] dout; reg [17:0] model [0:4095]; reg [17:0] rout; reg written [0:4095];
  reg rvalid = 0;
  RAM4096_L04 #(.WIDTH(18)) dut (.Wclk(wclk), .We(we), .Waddr(wa), .Din(din), .nRclk(nrclk), .Raddr(ra), .Dout(dout));
  always @(posedge wclk) if (we) begin model[wa] <= din; written[wa] <= 1; end
  always @(negedge nrclk) begin rout <= model[ra]; rvalid <= (written[ra] === 1'b1); end
  integer i, seed = 7, errors = 0, checks = 0;
  initial begin
    for (i = 0; i < 400000; i = i + 1) begin
      we = ($random(seed) & 3) != 0; wa = (i < 5000) ? i : $random(seed); din = $random(seed);
      #1 wclk = 1; #1 wclk = 0;
      if (($random(seed) & 1) == 0) begin
        ra = $random(seed); #1 nrclk = 0; #1;
        if (rvalid) begin checks = checks + 1; if (dout !== rout) begin errors = errors + 1; if (errors < 10) $display("MISMATCH ra=%h dout=%h model=%h", ra, dout, rout); end end
        nrclk = 1;
      end
    end
    $display("ram checks=%0d errors=%0d", checks, errors); $finish;
  end
endmodule
