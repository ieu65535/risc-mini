#include "mini_io.h"

int main() {
    uart_init(115200);
    while(1){
        printf("Hello, World!\n");
        PORT_OUT = 0x01;
        for(int i = 0; i < 10000000; i++);
        PORT_OUT = 0x02;
        for(int i = 0; i < 10000000; i++);
    }
    return 0;
}