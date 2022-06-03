//
//  main.m
//  ShellLauncher
//
//  Created by George Nachman on 12/6/20.
//

#import "shell_launcher.h"

int main(int argc, const char * argv[]) {
    if (argc >= 3) {
        return launch_shell(argv[2],
                            argc - 3,
                            &argv[3]);
    } else {
        return launch_shell(argc > 2 ? argv[2] : NULL,
                            0,
                            NULL);
    }
}
