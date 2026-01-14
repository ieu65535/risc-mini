#ifndef MINI_IO_H
#define MINI_IO_H

#include <stdio.h>

void uart_init(int baudrate);
int uart_putc(char c, struct __file *stream);

// extern FILE __stdio;

#endif // MINI_IO_H