This is an example of how to use the iTerm2 API in Python. It sets up a
websocket connection, sends an RPC to subscribe to notifications about changes
to the current username, hostname, or working directory. It prints incoming
notifications.

## Installation

First, install the dependencies.

```
sudo /usr/bin/python -m pip install websocket-client
sudo /usr/bin/python -m pip install protobuf

```

Then `cd api/examples/python` and then `./iterm2.py` to run the program.

This silly way of running pip is needed if you have more than one version of
python installed.

Now you can run `iTerm2/api/examples/python`.

## Writing your own app

To write your own app, copy `api_pb2.py` from `iTerm2/api/examples/python` to
your source directory and follow the model of the example.

Documentation is in the proto file in `proto/api.proto`.
