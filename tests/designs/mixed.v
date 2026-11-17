// Test design: block RAM with initial contents, carry chains, three clock
// domains (MCI, SCK, nRD) and a tri-state bus on the DS203 pins.
module mixed(input MCI, NE1, nRD, H_L, SDA, SCK, CTr, DTr, input [7:0] AQ, BQ,
           output CKA, CKB, nPD, inout [15:0] DB);
  reg [23:0] cnt = 0;
  reg [15:0] dn = 16'h1234;
  reg [15:0] mem [0:255];
  reg [15:0] rdata;
  reg [7:0] sh = 0;
  reg [3:0] rdcnt = 0;
  integer k;
  initial for (k = 0; k < 256; k = k + 1) mem[k] = k * 16'h0123 + 16'h4567;
  always @(posedge MCI) begin
    cnt <= cnt + 1;
    dn <= dn - 16'd1 - {8'd0, AQ};
    mem[cnt[7:0]] <= {BQ, AQ} ^ dn;
  end
  always @(posedge SCK) sh <= {sh[6:0], SDA};
  always @(negedge nRD) begin rdata <= mem[sh]; rdcnt <= rdcnt + 1; end
  wire [15:0] status = {cnt[23:14], rdcnt, DTr, CTr};
  assign DB = (NE1 & ~nRD) ? (H_L ? rdata : status) : 16'bz;
  assign CKA = cnt[0];
  assign CKB = cnt[1] ^ sh[7];
  assign nPD = cnt[23] | dn[15];
endmodule
