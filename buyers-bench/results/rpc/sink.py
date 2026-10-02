import socket, sys, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind((sys.argv[1], 50099)); s.listen(1)
for _ in range(1):
    c, _ = s.accept(); n = 0; t = time.time()
    while True:
        b = c.recv(1 << 20)
        if not b: break
        n += len(b)
    print(f"{sys.argv[1]}: {n/1e6:.0f} MB in {time.time()-t:.1f}s = {n/1e6/(time.time()-t):.1f} MB/s", flush=True); c.close()
