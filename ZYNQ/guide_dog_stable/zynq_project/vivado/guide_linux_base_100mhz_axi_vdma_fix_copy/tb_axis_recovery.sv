`timescale 1ns/1ps
module tb_recovery;
reg clk=0,rstn=0; always #5 clk=~clk;
reg [23:0] sd; reg sv=0,su=0,sl=0; wire sr;
wire [31:0] md; wire mv,mu,ml; reg mr=1;
wire f,fs,fe; wire [159:0] dc;
axis_rgb24_to_32_node_diag #(.WIDTH(4),.HEIGHT(2)) dut(clk,rstn,sd,sv,sr,su,sl,md,mv,mr,mu,ml,f,fs,fe,dc);
integer beats=0,lines=0; reg expect_sof=1;
reg stalled=0; reg [34:0] held;
always @(posedge clk) if(rstn) begin
 if(stalled && {mv,mu,ml,md} !== held) $fatal(1,"stall stability");
 stalled <= mv&&!mr; if(mv&&!mr) held<={mv,mu,ml,md};
 if(mv&&mr) begin
  case(beats%3)
   0: if(md!==32'h01030201) $fatal(1,"corrupt first word %h",md);
   1: if(md!==32'h02010302) $fatal(1,"corrupt second word %h",md);
   2: if(md!==32'h03020103) $fatal(1,"corrupt last word %h",md);
  endcase
  if(ml !== (beats%3==2)) $fatal(1,"EOL");
  if(mu !== (expect_sof && beats%3==0)) $fatal(1,"SOF");
  beats=beats+1; if(ml) lines=lines+1;
 end
end
task pixel(input [23:0] data,input sof,input eol);
begin
 @(negedge clk); sd=data;sv=1;su=sof;sl=eol;
 do @(posedge clk); while(!sr);
 @(negedge clk);sv=0;su=0;sl=0;
end endtask
task goodline(input sof);
begin
 pixel(24'h030201,sof,0);pixel(24'h030201,0,0);pixel(24'h030201,0,0);pixel(24'h030201,0,1);
end endtask
task settle; begin repeat(12) @(negedge clk);end endtask
initial begin
 repeat(4) @(negedge clk);rstn=1;
 // Reset mid-frame: input without SOF must never escape.
 repeat(8) pixel(24'habcdef,0,0);settle();if(beats!=0)$fatal(1,"unsynced leak");
 // Early EOL: reject complete malformed line, then discard until SOF.
 pixel(24'habcdef,1,0);pixel(24'habcdef,0,1);
 repeat(8) pixel(24'habcdef,0,0);settle();if(beats!=0)$fatal(1,"short line leak");
 goodline(1);settle();if(beats!=3||!f||!fe)$fatal(1,"early EOL recovery");
 // Missing EOL at the fourth pixel must not be fabricated.
 pixel(24'habcdef,0,0);pixel(24'habcdef,0,0);pixel(24'habcdef,0,0);pixel(24'habcdef,0,0);
 pixel(24'habcdef,0,1);settle();if(beats!=3)$fatal(1,"long line leak");
 goodline(1);settle();if(beats!=6)$fatal(1,"missing EOL recovery");
 // Unexpected SOF must replace the partial line, not tag stale bytes.
 pixel(24'habcdef,0,0);pixel(24'habcdef,0,0);goodline(1);settle();if(beats!=9||!fs)$fatal(1,"midline SOF recovery");
 // A valid second line has no SOF. Long output stalls preserve word/control.
 expect_sof=0;mr=0;goodline(0);repeat(100)@(negedge clk);if(beats!=9)$fatal(1,"stall consumed");mr=1;settle();if(beats!=12)$fatal(1,"drain");
 // Extra physical lines after HEIGHT are dropped until next SOF.
 repeat(8) pixel(24'habcdef,0,0);settle();if(beats!=12)$fatal(1,"height overrun");
 expect_sof=1;goodline(1);settle();if(beats!=15)$fatal(1,"next frame");
 $display("PASS recovery: seek SOF, early/missing EOL, midline SOF, height bound, 100-cycle stall");$finish;
end
initial begin #200000; $fatal(1,"timeout");end
endmodule
