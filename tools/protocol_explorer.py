import socket
import os
import array
import struct

print("=== COLD STORAGE MULTI-SERVER PROTOCOL EXPLORER ===")
socket_path = "/Users/ysaxon/Library/Application Support/iTerm2/iterm2-daemon-3.socket"
print(f"Connecting to UNIX domain socket: {socket_path}")

def pack_tagged_int(tag, val, size=4):
    return struct.pack("<i", tag) + struct.pack("<Q", size) + struct.pack("<i" if size==4 else "<q", val)

def parse_tagged_elements(data):
    fields = {}
    offset = 0
    while offset < len(data):
        if offset + 12 > len(data):
            break
        tag = struct.unpack("<i", data[offset:offset+4])[0]
        size = struct.unpack("<Q", data[offset+4:offset+12])[0]
        offset += 12
        if offset + size > len(data):
            break
        val_bytes = data[offset:offset+size]
        fields[tag] = val_bytes
        offset += size
    return fields

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    s.connect(socket_path)
    print("✅ connected() to server socket successfully!")
    
    # ==========================================
    # 1. READ HELLO MESSAGE
    # ==========================================
    prefix = s.recv(8)
    if len(prefix) < 8:
        raise Exception("Failed to read Hello length prefix")
    hello_len = struct.unpack("<Q", prefix)[0]
    hello_body = s.recv(hello_len)
    print(f"✅ Received Hello body ({hello_len} bytes)")
    
    # ==========================================
    # 2. SEND HANDSHAKE REQUEST
    # ==========================================
    tag_type = pack_tagged_int(0, 0) # Tag 0: RPCTypeHandshake (0)
    tag_version = pack_tagged_int(1, 2) # Tag 1: MaximumProtocolVersion (2)
    handshake_body = tag_type + tag_version
    handshake_prefix = struct.pack("<Q", len(handshake_body))
    
    s.sendall(handshake_prefix + handshake_body)
    print("✅ Transmitted conformant Handshake Request (32 body bytes)")
    
    # ==========================================
    # 3. READ HANDSHAKE RESPONSE
    # ==========================================
    resp_prefix = s.recv(8)
    if len(resp_prefix) < 8:
        raise Exception("Failed to read Handshake response length")
    resp_len = struct.unpack("<Q", resp_prefix)[0]
    resp_body = s.recv(resp_len)
    print(f"✅ Received Handshake response body ({resp_len} bytes)")
    print(f"   Raw response hex: {resp_body.hex()}")
    
    resp_fields = parse_tagged_elements(resp_body)
    print(f"   Parsed tags in response: {list(resp_fields.keys())}")
    for k, v in resp_fields.items():
        print(f"     Tag {k} (hex val): {v.hex()}")
    
    # Tag 2: ProtocolVersion, Tag 3: NumChildren, Tag 4: ServerPID
    proto_ver = struct.unpack("<i", resp_fields.get(2, b"\x00\x00\x00\x00"))[0]
    num_children = struct.unpack("<i", resp_fields.get(3, b"\x00\x00\x00\x00"))[0]
    server_pid = struct.unpack("<i", resp_fields.get(4, b"\x00\x00\x00\x00"))[0]
    
    print(f"🎉 Handshake Response parsed successfully!")
    print(f"   Server Protocol Version: {proto_ver}")
    print(f"   Active Child Count: {num_children}")
    print(f"   Server Daemon PID: {server_pid}")
    
    # ==========================================
    # 4. READ CHILD REPORTS
    # ==========================================
    print("\n--- READING CHILD PROCESS REPORTS FROM SERVER ---")
    for i in range(num_children):
        child_prefix = s.recv(8)
        if len(child_prefix) < 8:
            break
        child_len = struct.unpack("<Q", child_prefix)[0]
        
        # Read child report body and the tty master FD via ancillary data SCM_RIGHTS!
        fds = array.array("i")
        child_body, ancdata, flags, addr = s.recvmsg(child_len, socket.CMSG_LEN(fds.itemsize))
        child_fields = parse_tagged_elements(child_body)
        
        # Tag 41: Child PID, Tag 48: Child TTY (null-terminated string!)
        child_pid = struct.unpack("<i", child_fields.get(41, b"\x00\x00\x00\x00"))[0]
        child_tty_raw = child_fields.get(48, b"unknown\x00")
        child_tty = child_tty_raw.decode("utf-8", errors="ignore").rstrip("\x00")
        
        print(f"\n[Child {i+1}/{num_children}]")
        print(f"   Child Process PID: {child_pid}")
        print(f"   Child Terminal TTY: {child_tty}")
        
        # Unpack the received TTY file descriptor!
        received_fds = []
        for cmsg_level, cmsg_type, cmsg_data in ancdata:
            if cmsg_level == socket.SOL_SOCKET and cmsg_type == socket.SCM_RIGHTS:
                fds.frombytes(cmsg_data[:len(cmsg_data) - (len(cmsg_data) % fds.itemsize)])
                received_fds = list(fds)
                print(f"   🎉 SUCCESS: Natively received TTY master FD: {received_fds}")
                
        # Clean up the descriptor on our side
        for fd in received_fds:
            try:
                os.close(fd)
                print(f"   Closed received master FD {fd} cleanly.")
            except Exception:
                pass
                
except Exception as e:
    print(f"❌ Error during handshake: {e}")
finally:
    s.close()
    print("\n=== EXPLORATION COMPLETE ===")
