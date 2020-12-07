//
//  main.m
//  ShellLauncher
//
//  Created by George Nachman on 12/6/20.
//

#import "shell_launcher.h"

int main(int argc, const char * argv[]) {
    return launch_shell(argc > 2 ? argv[2] : NULL);
}
