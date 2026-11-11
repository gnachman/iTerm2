#include "iTermRequiredDirectory.h"
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static void launch(const char *directory, int expectedError) {
    iTermRequiredDirectoryChannel channel;
    assert(iTermRequiredDirectoryOpenChannel(1, &channel) == 0);
    int output[2];
    assert(pipe(output) == 0);
    pid_t child = fork();
    assert(child >= 0);
    if (!child) {
        close(output[0]);
        iTermRequiredDirectoryEnterInChild(directory, channel);
        char cwd[4096];
        assert(getcwd(cwd, sizeof(cwd)));
        assert(write(output[1], cwd, strlen(cwd)) >= 0);
        _exit(0);
    }
    close(output[1]);
    int unusedMaster = -1;
    int result = iTermRequiredDirectoryFinishInParent(channel, &child, &unusedMaster);
    assert(result == expectedError);
    char cwd[4096] = {0};
    ssize_t count = read(output[0], cwd, sizeof(cwd) - 1);
    close(output[0]);
    if (expectedError) {
        assert(child == -1);
        assert(count == 0); // No child program reached after a failed required chdir.
    } else {
        char resolved[4096];
        assert(realpath(directory, resolved));
        assert(strcmp(cwd, resolved) == 0);
        int status;
        assert(waitpid(child, &status, 0) == child);
        assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    }
}

int main(void) {
    char path[] = "/tmp/iterm-required-directory.XXXXXX";
    assert(mkdtemp(path));
    assert(iTermRequiredDirectoryValidate(path) == 0);
    launch(path, 0);
    assert(chmod(path, 0400) == 0);
    assert(iTermRequiredDirectoryValidate(path) == EACCES);
    launch(path, EACCES);
    assert(chmod(path, 0700) == 0);
    // Simulate removal after successful UI/preflight validation and before child launch.
    assert(iTermRequiredDirectoryValidate(path) == 0);
    assert(rmdir(path) == 0);
    launch(path, ENOENT);
    assert(iTermRequiredDirectoryValidate(path) == ENOENT);
    assert(iTermRequiredDirectoryValidate("relative") == EINVAL);
    iTermRequiredDirectoryChannel disabled;
    assert(iTermRequiredDirectoryOpenChannel(0, &disabled) == 0);
    assert(disabled.readFD == -1 && disabled.writeFD == -1);
    puts("Required directory: valid, permission denied, disappeared, missing, relative and default cases passed");
}
