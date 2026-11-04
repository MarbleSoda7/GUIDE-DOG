`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/10/16 09:12:39
// Design Name: 
// Module Name: hdmi_transmitter
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module hdmi_transmitter(
    input        pclk,           // pixel clock
    input        pclk_x5,        // pixel clock x5
    input        rst_n,          // reset
    
    input [23:0] video_din,      // RGB888 video in
    input        video_hsync,    // hsync data
    input        video_vsync,    // vsync data
    input        video_de,       // data enable
    
    output       tmds_clk_p,    // TMDS 时钟通道
    output       tmds_clk_n,
    output [2:0] tmds_data_p,   // TMDS 数据通道
    output [2:0] tmds_data_n,
    output       tmds_oen       // TMDS 输出使能

    );


wire [9:0]   blue_10bit;
wire [9:0]   green_10bit;
wire [9:0]   red_10bit; 


assign tmds_oen = 1'b1; 



//对三个颜色通道进行编码
encode encode_b (
    .sys_clk        (pclk),
    .sys_rst_n      (rst_n),    
    .data_in        (video_din[7:0]),
    .c0         	(video_hsync),
    .c1         	(video_vsync),
    .de         	(video_de),
     
    .data_out   	(blue_10bit)
    ) ;
    
encode encode_g (
    .sys_clk    (pclk),
    .sys_rst_n  (rst_n),    
    .data_in    (video_din[15:8]),
    .c0       	(video_hsync),
    .c1       	(video_vsync),
    .de       	(video_de),
     
    .data_out 	(green_10bit)
    ) ;

encode encode_r (
    .sys_clk    (pclk),
    .sys_rst_n  (rst_n),    
    .data_in    (video_din[23:16]),
    .c0       	(video_hsync),
    .c1       	(video_vsync),
    .de       	(video_de),
     
    .data_out 	(red_10bit)
    ) ;

//对编码后的数据进行并串转换
par_to_ser par_to_ser_b
(
    .clk_5x     (pclk_x5   ),   //输入系统时钟
    .par_data   (blue_10bit),   //输入并行数据

    .ser_data_p (tmds_data_p[0]),   //输出串行差分数据
    .ser_data_n (tmds_data_n[0])    //输出串行差分数据
);
par_to_ser par_to_ser_g
(
    .clk_5x     (pclk_x5   ),   //输入系统时钟
    .par_data   (green_10bit),   //输入并行数据

    .ser_data_p (tmds_data_p[1]),   //输出串行差分数据
    .ser_data_n (tmds_data_n[1])    //输出串行差分数据
);
par_to_ser par_to_ser_r
(
    .clk_5x     (pclk_x5   ),   //输入系统时钟
    .par_data   (red_10bit ),   //输入并行数据

    .ser_data_p (tmds_data_p[2]),   //输出串行差分数据
    .ser_data_n (tmds_data_n[2])    //输出串行差分数据
);  
par_to_ser  par_to_ser_clk
(
    .clk_5x      (pclk_x5       ),
    .par_data    (10'b1111100000),

    .ser_data_p  (tmds_clk_p    ),
    .ser_data_n  (tmds_clk_n    )
);
  
endmodule
