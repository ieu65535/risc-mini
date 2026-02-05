#ifndef MINI_IO_H
#define MINI_IO_H

#include <stdio.h>
#include <stdint.h>

#define F_CPU 50000000

#define IO_BASE 0x40000000

#define MMIO32(addr) (*(volatile uint32_t *)(IO_BASE+(addr)))
#define MMIO16(addr) (*(volatile uint16_t *)(IO_BASE+(addr)))
#define MMIO8(addr)  (*(volatile uint8_t  *)(IO_BASE+(addr)))

#define IO_BASE_UART0 0x00
#define IO_BASE_PORT0 0x04

// UART registers
#define USR  MMIO32(IO_BASE_UART0+0x00)
#define UDR  MMIO32(IO_BASE_UART0+0x04)
#define UBRR MMIO32(IO_BASE_UART0+0x08)
#define UCR1 MMIO32(IO_BASE_UART0+0x0C)

// USR bits
#define USR_RXNE 5
#define USR_TC   6

void uart_init(int baudrate);
int uart_putc(char c, struct __file *stream);

#endif // MINI_IO_H