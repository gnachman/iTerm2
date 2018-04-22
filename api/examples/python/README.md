# iTerm2 API

This is an example of how to use the iTerm2 API in Python. It sets up a
websocket connection, sends an RPC to subscribe to notifications about changes
to the current username, hostname, or working directory. It prints incoming
notifications.

## Installation

First, install the dependencies.

### Using virtualenv

```
sudo pip install virtualenv  # Just do this the first time
cd ~  # or wherever you'd like to create the virtual environment
virtualenv -p python3.6 iterm2api
pip3 install iterm2
source iterm2api/bin/activate  # for bash. Other shells use different activate scripts in the same directory.
```

Then `cd iterm2/api/examples/python`. There are several example programs:

#### it2api

This example shows a CLI for manipulating iTerm2. It uses the Python library to
make API calls into iTerm2 to list sessions, create windows, and so on. Run
`it2api -h` for help on its command line arguments.

#### remote_control.py

This demonstrates a long-running server that handles "custom escape sequences".
A custom escape sequence is sent as `esc ] 1337 ; Custom=id:payload` where `id`
identifies the sender of the escape sequence (which could be a shared secret
between a server like remote_control.py and the code sending the sequence), and
`payload` is any string. Custom escape sequences are useful because they
provide a channel of communication between any program running in iTerm2 that
produces output and a server which is capable of making API calls. For example,
the server could accept a custom escape sequence to create a new window with a
passed-in profile. This mechanism enables you to define how you'd like to
control iTerm2 from the command line, even when sshed.

The `remote_control.py` script can be tested by running `it2custom` (also in
this directory), which sends a custom escape sequence. It takes two arguments:
the sender and the payload.

## Writing your own app

There are two ways to write your own app, depending on its complexity.

If it has no dependencies outside of the `iterm2` Python library, place it in
`~/Library/Application Support/iTerm2/Scripts`. You can run it from the
**Scripts** menu in iTerm2. To view its output, open the Script Console from
**Scripts > Script Console** before starting it.

If you script has outside dependencies, it's best to create a virtualenv by
following the steps in the **Using virtualenv** section.
