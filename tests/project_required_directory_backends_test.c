// Exercise the actual RPC codec and both multi-server child launch implementations without a UI.
#define main iTermProjectTestUnusedServerMain
#include "iTermFileDescriptorMultiServer.c"
#undef main
#include <sys/stat.h>
#include <assert.h>
#include <sys/wait.h>

static void launchThroughProtocol(const char *directory, int required, int expectedError, int spawnMode) {
    char *argv[] = { "/bin/pwd", NULL };
    char *environment[] = { "PATH=/usr/bin:/bin", NULL };
    iTermMultiServerClientOriginatedMessage request = {
        .type = iTermMultiServerRPCTypeLaunch,
        .payload.launch = {
            .path = "/bin/pwd", .argv = argv, .argc = 1, .envp = environment, .envc = 1,
            .columns = 80, .rows = 24, .pwd = directory, .uniqueId = 123,
            .requiresInitialDirectory = required
        }
    };
    iTermClientServerProtocolMessage wire;
    iTermClientServerProtocolMessageInitialize(&wire);
    assert(iTermMultiServerProtocolEncodeMessageFromClient(&request, &wire) == 0);
    iTermMultiServerClientOriginatedMessage decoded = {0};
    assert(iTermMultiServerProtocolParseMessageFromClient(&wire, &decoded) == 0);
    assert(decoded.payload.launch.requiresInitialDirectory == required);
    iTermForkState child = {0};
    iTermTTYState tty;
    int error = 0;
    use_spawn = spawnMode;
    const int fd = Launch(&decoded.payload.launch, &child, &tty, &error);
    assert(error == expectedError);
    if (expectedError) {
        assert(fd == -1 && child.pid == -1);
        int sockets[2];
        assert(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
        assert(HandleLaunchRequest(sockets[0], &decoded.payload.launch) == 0);
        iTermClientServerProtocolMessage responseWire;
        assert(iTermMultiServerRead(sockets[1], &responseWire) == 0);
        iTermMultiServerServerOriginatedMessage response = {0};
        const int parseError = iTermMultiServerProtocolParseMessageFromServer(&responseWire, &response);
        assert(parseError == 0);
        assert(response.type == iTermMultiServerRPCTypeLaunch);
        assert(response.payload.launch.status == expectedError);
        assert(response.payload.launch.pid == 0);
        assert(numberOfChildren == 0);
        iTermMultiServerServerOriginatedMessageFree(&response);
        iTermClientServerProtocolMessageFree(&responseWire);
        close(sockets[0]);
        close(sockets[1]);
    } else {
        assert(fd >= 0 && child.pid > 0);
        char output[4096] = {0};
        const ssize_t count = read(fd, output, sizeof(output) - 1);
        assert(count > 0);
        char expected[4096];
        if (required) { assert(realpath(directory, expected)); }
        else { assert(getcwd(expected, sizeof(expected))); }
        assert(strncmp(output, expected, strlen(expected)) == 0);
        int status;
        assert(waitpid(child.pid, &status, 0) == child.pid);
        assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
        close(fd);
    }
    iTermMultiServerClientOriginatedMessageFree(&decoded);
    iTermClientServerProtocolMessageFree(&wire);
}

int main(void) {
    char path[] = "/tmp/iterm-project-backends.XXXXXX";
    assert(mkdtemp(path));
    for (int mode = 0; mode < 2; mode++) {
        launchThroughProtocol(path, 1, 0, mode);
        assert(chmod(path, 0400) == 0);
        launchThroughProtocol(path, 1, EACCES, mode);
        assert(chmod(path, 0700) == 0);
    }
    assert(rmdir(path) == 0);
    for (int mode = 0; mode < 2; mode++) {
        launchThroughProtocol(path, 1, ENOENT, mode);
        launchThroughProtocol(path, 0, 0, mode); // Ordinary v2 requests retain cwd fallback.
    }
    puts("RPC codec and actual fork/exec + spawn backends: eight strict/default cases and four RPC error replies passed");
}
