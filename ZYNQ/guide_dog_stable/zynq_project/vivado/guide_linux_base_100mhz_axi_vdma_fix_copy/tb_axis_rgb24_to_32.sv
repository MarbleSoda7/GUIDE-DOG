`timescale 1ns/1ps
module tb;
  localparam W=4;
  reg clk=0, rstn=0;
  always #5 clk=~clk;
  reg [23:0] sd=0; reg sv=0, su=0, sl=0; wire sr;
  wire [31:0] md; wire mv,mu,ml; reg mr=0;
  wire f,fs,fe; wire [159:0] dc;
  axis_rgb24_to_32_node_diag #(.WIDTH(W), .HEIGHT(2)) dut(clk,rstn,sd,sv,sr,su,sl,md,mv,mr,mu,ml,f,fs,fe,dc);
  integer frame=0,line=0,beat=0,expected=0,cycles=0;
  reg [7:0] expbytes[0:2*2*W*3-1];
  reg was_stalled=0; reg [34:0] held_axis;
  always @(posedge clk) if(rstn) begin
    if(was_stalled && {mv,mu,ml,md} !== held_axis) $fatal(1,"AXIS payload/control changed while stalled");
    was_stalled <= mv && !mr;
    if(mv && !mr) held_axis <= {mv,mu,ml,md};
  end
  always @(negedge clk) begin
    cycles=cycles+1;
    mr = (cycles%7!=0 && cycles%11!=0);
  end
  always @(posedge clk) if(rstn && mv && mr) begin
    if(beat>=3) $fatal(1,"extra beat");
    if(md[7:0]!==expbytes[expected] || md[15:8]!==expbytes[expected+1] || md[23:16]!==expbytes[expected+2] || md[31:24]!==expbytes[expected+3]) $fatal(1,"bad AXIS word at byte %0d got %h expected %h%h%h%h",expected,md,expbytes[expected+3],expbytes[expected+2],expbytes[expected+1],expbytes[expected]);
    expected=expected+4;
    if(ml !== (beat==2)) $fatal(1,"TLAST wrong frame=%0d line=%0d beat=%0d",frame,line,beat);
    if(mu !== (line==0 && beat==0)) $fatal(1,"TUSER wrong frame=%0d line=%0d beat=%0d mu=%b outbyte=%0d line_sof=%b",frame,line,beat,mu,dut.out_byte,dut.line_sof);
    beat=beat+1;
    if(ml) begin beat=0; line=line+1; if(line==2) begin line=0; frame=frame+1; end end
  end
  task sendpix(input integer fr,input integer ln,input integer px);
    reg [23:0] v;
    begin
      v={8'(fr*64+ln*16+px),8'(fr*32+ln*8+px),8'(fr*16+ln*4+px)};
      @(negedge clk); sv=1; sd=v; su=(ln==0 && px==0); sl=(px==W-1);
      while(1) begin @(posedge clk); if(sr) begin @(negedge clk); sv=0; su=0; sl=0; disable sendpix; end end
    end
  endtask
  integer fr,ln,px,b;
  initial begin
    for(fr=0;fr<2;fr=fr+1) for(ln=0;ln<2;ln=ln+1) for(px=0;px<W;px=px+1) begin
      b=((fr*2*W+ln*W+px)*3);
      expbytes[b]=8'(fr*16+ln*4+px); expbytes[b+1]=8'(fr*32+ln*8+px); expbytes[b+2]=8'(fr*64+ln*16+px);
    end
    repeat(4) @(posedge clk); rstn=1;
    for(fr=0;fr<2;fr=fr+1) for(ln=0;ln<2;ln=ln+1) for(px=0;px<W;px=px+1) sendpix(fr,ln,px);
    wait(expected==2*2*W*3); repeat(5) @(posedge clk);
    if(f || fs || fe) $fatal(1,"fault flags raised f=%b sof=%b eol=%b",f,fs,fe);
    $display("PASS: 2 frames x 2 lines, 3 beats/line, byte order and SOF/EOL stable under backpressure"); $finish;
  end
  initial begin #200000; $fatal(1,"timeout"); end
endmodule
