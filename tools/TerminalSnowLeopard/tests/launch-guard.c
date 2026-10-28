/* Development launcher: stop only our child if a test exhausts memory/disk. */
#include <libc.h>
#include <mach/mach.h>
#include <sys/wait.h>
#include <sys/mount.h>
#include <sys/resource.h>
#include <signal.h>

int main(int argc, char **argv) {
    int child;
    union wait status;
    port_t task = PORT_NULL;
    struct rlimit limit;
    status.w_status = 0;
    if (argc < 2)
        return 2;
    limit.rlim_cur = limit.rlim_max = 0;
    setrlimit(RLIMIT_CORE, &limit);
    child = fork();
    if (child < 0) {
        perror("fork");
        return 1;
    }
    if (!child) {
        execv(argv[1], argv + 1);
        perror("execv");
        _exit(127);
    }
    fprintf(stderr, "SNOW guarded pid %d\n", child);
    while (wait4(child, &status, WNOHANG, 0) == 0) {
        struct task_basic_info info;
        unsigned count = TASK_BASIC_INFO_COUNT;
        struct statfs disk;
        int stop = 0;
        if (task == PORT_NULL)
            task_by_unix_pid(task_self(), child, &task);
        if (task != PORT_NULL &&
            task_info(task, TASK_BASIC_INFO, (task_info_t)&info, &count) == KERN_SUCCESS) {
            if (info.virtual_size > 128 * 1024 * 1024 || info.resident_size > 96 * 1024 * 1024) {
                fprintf(stderr, "SNOW test memory limit: virtual %u resident %u\n",
                        info.virtual_size, info.resident_size);
                stop = 1;
            }
        }
        if (!statfs(".", &disk) && (double)disk.f_bavail * disk.f_bsize < 128 * 1024 * 1024) {
            fprintf(stderr, "SNOW test stopped: less than 128 MiB disk space\n");
            stop = 1;
        }
        if (stop) {
            kill(child, SIGKILL);
            wait4(child, &status, 0, 0);
            break;
        }
        sleep(1);
    }
    if (task != PORT_NULL)
        port_deallocate(task_self(), task);
    if (WIFSIGNALED(status))
        fprintf(stderr, "SNOW child stopped by signal %d\n", status.w_termsig);
    else
        fprintf(stderr, "SNOW child exited %d\n", status.w_retcode);
    return WIFSIGNALED(status) ? 128 + status.w_termsig : status.w_retcode;
}
