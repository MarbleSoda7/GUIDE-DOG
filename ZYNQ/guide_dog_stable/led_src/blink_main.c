#include "xil_io.h"

#define LED_GPIO_BASEADDR 0x41200000

static void delay(unsigned n)
{
	volatile unsigned i = n;
	while (i--) { __asm volatile("nop"); }
}

int main(void)
{
	/* TRI = 0 : 全输出 */
	Xil_Out32(LED_GPIO_BASEADDR + 0x4, 0x0);
	Xil_Out32(LED_GPIO_BASEADDR + 0x0, 0x0);

	unsigned i = 0;
	while (1) {
		Xil_Out32(LED_GPIO_BASEADDR + 0x0, i & 0xF);
		delay(8000000);
		i++;
	}
	return 0;
}
