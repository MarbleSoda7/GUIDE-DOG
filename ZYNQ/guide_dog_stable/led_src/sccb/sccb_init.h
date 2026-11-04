
#include"xgpiops.h"
#include"xparameters.h"
#include"sleep.h"

#ifndef SCCB_INIT_H_
#define SCCB_INIT_H_

#define SCCB_SCL 54
#define SCCB_SDA 55

#define  OV7725_Addr    0x42   //OV7725器件地址
#define  OV5640_Addr    0x78   //OV5640器件地址

void SCCB_Init(void);
void SCCB_Start(void);
void SCCB_Stop(void);
void SCCB_Ack(void);
void SCCB_WaitAck(void);
void SCCB_Send_byte(u8 SendByte);
void sccb_write_reg16(u16 addr , u8 data);
u8  SCCB_Rece_byte(void);
u8 sccb_read_reg16(u16 addr );

#endif
