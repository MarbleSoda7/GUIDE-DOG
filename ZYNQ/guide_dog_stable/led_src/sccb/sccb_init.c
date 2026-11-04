
#include"sccb_init.h"

#define  GPIOPS_ID  XPAR_XGPIOPS_0_BASEADDR

static  XGpioPs  Gpiops;

/*初始化sccb引脚*/
void SCCB_Init(void)
{

	XGpioPs_Config *Psgpio_ptr; 	//配置指针

	Psgpio_ptr = XGpioPs_LookupConfig(GPIOPS_ID);
	XGpioPs_CfgInitialize(&Gpiops, Psgpio_ptr, Psgpio_ptr->BaseAddr);

	/*输出模式*/
	XGpioPs_SetDirectionPin(&Gpiops, SCCB_SCL, 1);
	XGpioPs_SetDirectionPin(&Gpiops, SCCB_SDA, 1);

	/*设置输出模式使能*/
	XGpioPs_SetOutputEnablePin(&Gpiops, SCCB_SCL, 1);
	XGpioPs_SetOutputEnablePin(&Gpiops, SCCB_SDA, 1);

	/*初始值为高电平*/
	XGpioPs_WritePin(&Gpiops, SCCB_SCL, 1);
	XGpioPs_WritePin(&Gpiops, SCCB_SDA, 1);
}

/*sccb起始信号*/
void SCCB_Start(void)
{
	XGpioPs_WritePin(&Gpiops, SCCB_SCL, 1);
	XGpioPs_WritePin(&Gpiops, SCCB_SDA, 1);

	usleep(4);

 	XGpioPs_WritePin(&Gpiops, SCCB_SDA, 0);

 	usleep(4);

 	XGpioPs_WritePin(&Gpiops, SCCB_SCL, 0);

}

/*sccb停止信号*/
void SCCB_Stop(void)
{

	XGpioPs_WritePin(&Gpiops, SCCB_SCL, 0);

	usleep(4);

	XGpioPs_WritePin(&Gpiops,SCCB_SDA, 0);

 	usleep(4);

	XGpioPs_WritePin(&Gpiops, SCCB_SCL, 1);

	usleep(4);

	XGpioPs_WritePin(&Gpiops, SCCB_SDA, 1);

}

/*sccb发送字节*/
void SCCB_Send_byte(u8 SendByte)
{
    u8 t = 8;

    while(t--)
    {
    	XGpioPs_WritePin(&Gpiops, SCCB_SCL, 0);
    	usleep(4);

    	 if(SendByte&0x80)
    		XGpioPs_WritePin(&Gpiops, SCCB_SDA, 1);
    	 else
    		XGpioPs_WritePin(&Gpiops, SCCB_SDA, 0);
		SendByte<<=1;
		usleep(4);
		XGpioPs_WritePin(&Gpiops, SCCB_SCL, 1);
		usleep(4);
    }
    XGpioPs_WritePin(&Gpiops, SCCB_SCL, 0);
}

/*sccb接收一个字节*/
u8  SCCB_Rece_byte(void)
{
	unsigned char i=0 , rece=0;

	XGpioPs_SetOutputEnablePin(&Gpiops, SCCB_SDA, 0);
	XGpioPs_SetDirectionPin(&Gpiops, SCCB_SDA, 0);

	XGpioPs_WritePin(&Gpiops, SCCB_SDA, 1);

	for(i=0;i<8;i++ )
	{
		rece <<= 1;
        XGpioPs_WritePin(&Gpiops, SCCB_SCL, 0);
        usleep(4);
        XGpioPs_WritePin(&Gpiops, SCCB_SCL, 1);
        usleep(4);
        if( XGpioPs_ReadPin(&Gpiops, SCCB_SDA) ) {
        	rece = rece | 0x01;
        }
		XGpioPs_WritePin(&Gpiops, SCCB_SCL, 0);
    }

	XGpioPs_WritePin(&Gpiops, SCCB_SCL, 0);

	XGpioPs_SetDirectionPin(&Gpiops, SCCB_SDA, 1);
	XGpioPs_SetOutputEnablePin(&Gpiops, SCCB_SDA, 1);

    return rece;

}


void SCCB_Ack(void)
{
	XGpioPs_WritePin(&Gpiops, SCCB_SCL, 0);
	usleep(4);
	XGpioPs_WritePin(&Gpiops, SCCB_SDA, 0);
	usleep(4);
	XGpioPs_WritePin(&Gpiops, SCCB_SCL, 1);
	usleep(4);
	XGpioPs_WritePin(&Gpiops, SCCB_SCL, 0);
	usleep(4);
}

/*应答信号*/
void  SCCB_NoAck(void)
{
	XGpioPs_WritePin(&Gpiops, SCCB_SCL, 0);
	usleep(4);
	XGpioPs_WritePin(&Gpiops, SCCB_SDA, 1);
	usleep(4);
	XGpioPs_WritePin(&Gpiops, SCCB_SCL, 1);
	usleep(4);
	XGpioPs_WritePin(&Gpiops, SCCB_SCL, 0);
}


void sccb_write_reg16(u16 addr , u8 data)
{
	SCCB_Start();

	SCCB_Send_byte(OV5640_Addr);
	SCCB_NoAck();

	SCCB_Send_byte(addr >> 8);
	SCCB_NoAck();

	SCCB_Send_byte(addr & 0x00FF);
	SCCB_NoAck();

	SCCB_Send_byte(data);
	SCCB_NoAck();

  	SCCB_Stop();
}


u8 sccb_read_reg16(u16 addr )
{
	u8 date;

	SCCB_Start();

	SCCB_Send_byte(OV5640_Addr);
	SCCB_NoAck();

	SCCB_Send_byte(addr >> 8);
	SCCB_NoAck();

	SCCB_Send_byte(addr & 0x00FF);
	SCCB_NoAck();

  	SCCB_Stop();

  	SCCB_Start();

	SCCB_Send_byte(OV5640_Addr | 0x01);
	SCCB_NoAck();

	date = SCCB_Rece_byte();
	SCCB_Ack();

  	SCCB_Stop();

  	return  date ;
}

