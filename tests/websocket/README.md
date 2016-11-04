This is based on https://github.com/dcodeIO/protobuf.js/tree/master/examples/websocket

First, launch iTerm2. Then, on the same host:

````
npm install
node server.js
````

This will open a web browser. You can type in some JSON that gets turned into a Request protobuf (see iTerm2/proto/api.proto). Press *Send* and you should see a response written to the "log" textarea.

