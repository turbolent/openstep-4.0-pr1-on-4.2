/* Append after abi.m; exercise shell startup and canonical erase on real PTYs. */
#include <sys/wait.h>

static int runShellCase(const char *shell, const char *term, int nested) {
    int master, pid, tick, n, total = 0, done = 0, passed;
    union wait status;
    char output[8192];
    struct winsize size = {24, 80, 480, 336};
    fflush(stdout);
    pid = Tigerforkpty(&master, NULL, NULL, &size);
    if (pid == 0) {
        TigerTermios settings;
        struct termios native;
        Tigertcgetattr(0, &settings);
        settings.input = 0x2b02;
        settings.output = 3;
        settings.control = (settings.control & 0x8000) | 0x4b00;
        settings.local = (settings.local & 0x80400267) | 0x5cb;
        settings.chars[3] = 127;
        Tigertcsetattr(0, 0, &settings);
        ioctl(0, TIOCGETA, &native);
        fprintf(stderr, "NATIVE flags=%lx erase=%d\n", native.c_lflag, native.c_cc[VERASE]);
        Tigersetenv("TERM", term, 1);
        if (shell) {
            execl(shell, shell, (char *)0);
            perror("exec");
            _exit(126);
        }
        write(1, "READY\n", 6);
        n = read(0, output, sizeof(output) - 1);
        if (n > 0) {
            output[n] = 0;
            printf("INPUT=%s", output);
            fflush(stdout);
        }
        _exit(n == 3 && !memcmp(output, "ab\n", 3) ? 0 : 1);
    }
    if (pid < 0) {
        perror("forkpty");
        return 1;
    }
    fcntl(master, F_SETFL, FNDELAY);
    for (tick = 0; tick < 80; tick++) {
        while (total < sizeof(output) - 1 &&
               (n = read(master, output + total, sizeof(output) - 1 - total)) > 0)
            total += n;
        if (nested && tick == 3) {
            char launch[512];
            const char *path = getenv("TEST_ZSH_PATH");
            if (!path)
                path = "/usr/local/bin/zsh";
            sprintf(launch, "%s; echo ZSH_EXIT=$?\r", path);
            write(master, launch, strlen(launch));
        }
        if (tick == 10) {
            const char *input =
                shell
                    ? "/bin/echo EXTERNAL_OK\r/bin/echo PIPE_OK | /bin/cat\r/bin/sleep 1 &\rwait\recho JOBS_OK\rexit\r"
                    : "abc\177\r";
            if (nested || (shell && strstr(shell, "zsh"))) {
                const char *version = "echo PORT_ZSH_VERSION=$ZSH_VERSION\r";
                write(master, version, strlen(version));
            }
            write(master, input, strlen(input));
        }
        if (nested && tick == 40)
            write(master, "echo PARENT_RESUMED\rexit\r", 25);
        if (wait4(pid, &status, WNOHANG, NULL) == pid) {
            done = 1;
            break;
        }
        Tigerusleep(100000);
    }
    while (total < sizeof(output) - 1 &&
           (n = read(master, output + total, sizeof(output) - 1 - total)) > 0)
        total += n;
    output[total] = 0;
    passed = done && WIFEXITED(status) && status.w_retcode == 0;
    if (!shell)
        passed = passed && strstr(output, "abc\b \b\r\nINPUT=ab\r\n") != NULL;
    else
        passed = passed && strstr(output, "EXTERNAL_OK\r\n") && strstr(output, "PIPE_OK\r\n") &&
                 strstr(output, "JOBS_OK\r\n") && !strstr(output, "error on TTY read");
    if (nested)
        passed = passed && strstr(output, "PORT_ZSH_VERSION=5.9\r\n") &&
                 strstr(output, "ZSH_EXIT=0\r\n") && strstr(output, "PARENT_RESUMED\r\n");
    printf("CASE shell=%s term=%s nested=%d done=%d status=%x bytes=%d PASS=%d\n",
           shell ? shell : "canonical", term, nested, done, done ? status.w_status : 0, total,
           passed);
    for (tick = 0; tick < total; tick++) {
        unsigned c = (unsigned char)output[tick];
        if (c >= 32 && c < 127)
            putchar(c);
        else
            printf("<%02x>", c);
    }
    putchar('\n');
    if (!done) {
        kill(pid, SIGKILL);
        wait4(pid, &status, 0, NULL);
    }
    Tigerclose(master);
    return !passed;
}
int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int failures = 0;
    TigerInitializeCABI();
    if (argc > 1) {
        struct termios settings;
        int fd = open(argv[1], O_RDONLY);
        if (fd >= 0 && !ioctl(fd, TIOCGETA, &settings))
            printf("LIVE flags input=%lx output=%lx control=%lx local=%lx erase=%u\n",
                   settings.c_iflag, settings.c_oflag, settings.c_cflag, settings.c_lflag,
                   settings.c_cc[VERASE]);
        if (fd >= 0)
            close(fd);
    }
    failures += runShellCase(NULL, "vt100", 0);
    failures += runShellCase("/usr/local/bin/zsh", "xterm-color", 0);
    failures += runShellCase("/usr/local/bin/zsh", "vt100", 0);
    failures += runShellCase("/usr/bin/zsh", "xterm-color", 0);
    failures += runShellCase("/bin/csh", "vt100", 0);
    failures += runShellCase("/usr/local/bin/bash", "vt100", 0);
    failures += runShellCase("/bin/sh", "vt100", 1);
    printf("7 shell checks, %d failures\n", failures);
    [pool release];
    return failures ? 1 : 0;
}
