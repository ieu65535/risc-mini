#include "mini_io.h"

void uart_init(int baudrate)
{
    UBRR = (F_CPU / baudrate) - 1;
}

int uart_putc(char c, struct __file *stream)
{
    while (!(USR & (1 << USR_TC)));
    UDR = c;
    return 0;
}

FILE __stdio = FDEV_SETUP_STREAM(uart_putc,
            NULL,
            NULL,
            _FDEV_SETUP_WRITE);

FILE *const stdin = &__stdio;
__strong_reference(stdin, stdout);
__strong_reference(stdin, stderr);