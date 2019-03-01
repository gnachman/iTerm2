void iTermFileDescriptorServerLog(char *format, ...);
void iTermFileDescriptorServerLogError(char *format, ...);


void MyLoginTTY(int master, int slave, int serverSocketFd, int deadMansPipeWriteEnd);

int MyForkPty(int *amaster,
              iTermTTYState *ttyState,
              int serverSocketFd,
              int deadMansPipeWriteEnd);
