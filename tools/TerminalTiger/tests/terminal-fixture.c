/* Output exercised through the original Terminal PTY and VT100 engine. */
#include <stdio.h>
#include <unistd.h>
#include <sys/ioctl.h>
int main(int argc, char **argv) {
    struct winsize size;
    int i;
    if (argc > 1) {
        for (i = 0; i < 80; i++)
            printf("SCROLL %03d\n", i);
        printf("SCROLL_OK\n");
        fflush(stdout);
        return 0;
    }
    printf("\033[2J\033[HASCII: ABCDEFGHIJKLMNOPQRSTUVWXYZ gjpqy\n");
    printf("\033[31mRED \033[32mGREEN \033[34mBLUE\033[0m NORMAL\n");
    printf("\033[1mBOLD\033[0m \033[4mUNDERLINE\033[0m\n");
    printf("UTF-8: caf\303\251 Gr\303\274\303\237e \342\202\254\n");
    printf("REPLACE: bad\033[3Dgood\033[K\n");
    if (ioctl(0, TIOCGWINSZ, &size) == 0)
        printf("SIZE: %u columns x %u rows\n", size.ws_col, size.ws_row);
    printf("SPLIT UTF-8: \303");
    fflush(stdout);
    usleep(100000);
    printf("\251\nFIXTURE_OK\n");
    fflush(stdout);
    return 0;
}
