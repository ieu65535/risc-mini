#include "mini_io.h"

void sleep(int ms) {
    volatile int i;
    for(i = 0; i < ms * 5555; i++);
    printf("Slept for %d cycles\n", i);
}

int main() {
    uart_init(115200);
    while(1){
        printf("Hello, World!\n");
        PORT_OUT = 0x01;
        sleep(500);
        PORT_OUT = 0x02;
        sleep(500);
    }
    return 0;
}