//
//  legacy_server.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/6/20.
//

#ifndef legacy_server_h
#define legacy_server_h

#include <sys/types.h>
#include <sys/socket.h>

#define NUM_FILE_DESCRIPTORS_TO_PASS_TO_SERVER 4

// Run a server that launches the program in argv[0] and creates a FileDescriptorServer.
int iterm2_server(int argc, char *const *argv);

#endif /* legacy_server_h */
