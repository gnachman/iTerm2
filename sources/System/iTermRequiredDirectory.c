#include "iTermRequiredDirectory.h"
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

int iTermRequiredDirectoryValidate(const char *path) {
    if (!path || path[0] != '/') { return EINVAL; }
    struct stat info;
    if (stat(path, &info)) { return errno; }
    if (!S_ISDIR(info.st_mode)) { return ENOTDIR; }
    return access(path, R_OK | X_OK) == 0 ? 0 : errno;
}

int iTermRequiredDirectoryOpenChannel(int required, iTermRequiredDirectoryChannel *channel) {
    channel->readFD = channel->writeFD = -1;
    if (!required) { return 0; }
    int pipeFDs[2];
    if (pipe(pipeFDs)) { return errno; }
    // Mono-server login remaps descriptors 0–3. Keep the acknowledgement clear of that range.
    channel->readFD = fcntl(pipeFDs[0], F_DUPFD_CLOEXEC, 10);
    channel->writeFD = fcntl(pipeFDs[1], F_DUPFD_CLOEXEC, 10);
    const int error = (channel->readFD < 0 || channel->writeFD < 0) ? errno : 0;
    close(pipeFDs[0]);
    close(pipeFDs[1]);
    if (error) {
        if (channel->readFD >= 0) { close(channel->readFD); }
        if (channel->writeFD >= 0) { close(channel->writeFD); }
        channel->readFD = channel->writeFD = -1;
    }
    return error;
}

void iTermRequiredDirectoryEnterInChild(const char *path, iTermRequiredDirectoryChannel channel) {
    if (channel.writeFD < 0) { return; }
    close(channel.readFD);
    const int error = (!path || path[0] != '/') ? EINVAL : (chdir(path) == 0 ? 0 : errno);
    const char *bytes = (const char *)&error;
    size_t remaining = sizeof(error);
    while (remaining) {
        const ssize_t count = write(channel.writeFD, bytes, remaining);
        if (count < 0 && errno == EINTR) { continue; }
        if (count <= 0) { _exit(127); }
        bytes += count;
        remaining -= count;
    }
    close(channel.writeFD);
    if (error) { _exit(127); }
}

int iTermRequiredDirectoryFinishInParent(iTermRequiredDirectoryChannel channel, pid_t *pid, int *masterFD) {
    if (channel.readFD < 0) { return 0; }
    const int forkError = errno;
    close(channel.writeFD);
    int error = 0;
    if (*pid < 0) {
        close(channel.readFD);
        return forkError;
    }
    char *bytes = (char *)&error;
    size_t remaining = sizeof(error);
    while (remaining) {
        const ssize_t count = read(channel.readFD, bytes, remaining);
        if (count < 0 && errno == EINTR) { continue; }
        if (count <= 0) { error = EIO; break; }
        bytes += count;
        remaining -= count;
    }
    close(channel.readFD);
    if (error) {
        if (*masterFD >= 0) { close(*masterFD); *masterFD = -1; }
        // Explicit failures exit in the child. A broken acknowledgement must not leave an
        // untracked shell running, even if the child advanced past the directory operation.
        if (remaining) { kill(*pid, SIGKILL); }
        while (waitpid(*pid, NULL, 0) < 0 && errno == EINTR) {}
        *pid = -1;
    }
    return error;
}
