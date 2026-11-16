"""Minimal RFB (VNC) client: connect, handshake, request a framebuffer update
and save it as a PNG. No external dependencies beyond the stdlib."""
import socket
import struct
import sys
import zlib


def recvall(s, n):
    buf = b''
    while len(buf) < n:
        chunk = s.recv(n - len(buf))
        if not chunk:
            raise EOFError('connection closed (wanted %d, got %d)' % (n, len(buf)))
        buf += chunk
    return buf


class RFB:
    def __init__(self, host, port=5900):
        self.s = socket.create_connection((host, port), timeout=20)
        self.s.settimeout(20)

    def handshake(self):
        ver = recvall(self.s, 12)
        print('  server version:', ver.decode().strip())
        self.s.sendall(b'RFB 003.008\n')
        n = self.s.recv(1)[0]
        if n == 0:
            raise RuntimeError('server refused connection')
        types = recvall(self.s, n)
        print('  security types:', list(types))
        if 1 in types:
            self.s.sendall(bytes([1]))          # None auth
        elif 2 in types:
            self.s.sendall(bytes([2]))          # VNC auth
            chal = recvall(self.s, 16)
            self.s.sendall(bytes(16))           # (would need DES; skip)
        else:
            raise RuntimeError('no supported security type')
        res = struct.unpack('>I', recvall(self.s, 4))[0]
        print('  security result:', res)
        if res != 0:
            raise RuntimeError('auth failed')
        # ClientInit (shared=1)
        self.s.sendall(bytes([1]))

    def init(self):
        w, h = struct.unpack('>HH', recvall(self.s, 4))
        pf = recvall(self.s, 16)
        nlen = struct.unpack('>I', recvall(self.s, 4))[0]
        name = recvall(self.s, nlen).decode('latin1')
        print('  framebuffer: %dx%d  name=%r' % (w, h, name))
        bpp, depth, big, true = pf[0], pf[1], pf[2], pf[3]
        rmax, gmax, bmax = struct.unpack('>HHH', pf[4:10])
        rsh, gsh, bsh = pf[10], pf[11], pf[12]
        print('  bpp=%d depth=%d truecolor=%s shifts=%d/%d/%d' % (bpp, depth, true, rsh, gsh, bsh))
        self.w, self.h = w, h
        self.bpp, self.true = bpp, true
        self.rsh, self.gsh, self.bsh = rsh, gsh, bsh
        return w, h

    def set_pixfmt(self):
        # SetPixelFormat: force 32bpp truecolor RGBA, little endian
        bpp, depth, big, true = 32, 24, 0, 1
        rmax, gmax, bmax = 255, 255, 255
        rsh, gsh, bsh = 16, 8, 0
        data = struct.pack('>BBBBHHHBBBxxx', bpp, depth, big, true,
                           rmax, gmax, bmax, rsh, gsh, bsh)
        # SetPixelFormat message: type(1) + padding(3) + length(4) + payload
        self.s.sendall(b'\x00\x00\x00\x00' + struct.pack('>I', len(data)) + data)

    def request_update(self, incremental=0):
        self.s.sendall(struct.pack('>BBHHHH', 3, incremental, 0, 0, self.w, self.h))

    def read_update(self):
        """Read one FramebufferUpdate, return (x, y, w, h, raw RGB bytes)."""
        msg = recvall(self.s, 1)[0]
        if msg != 0:
            raise RuntimeError('unexpected server msg type %d' % msg)
        recvall(self.s, 1)                       # padding
        nrects = struct.unpack('>H', recvall(self.s, 2))[0]
        print('  update: %d rect(s)' % nrects)
        x = y = w = h = 0
        pixels = bytearray(self.w * self.h * 3)
        for _ in range(nrects):
            rx, ry, rw, rh, enc = struct.unpack('>HHHHi', recvall(self.s, 12))
            print('    rect %dx%d at (%d,%d) enc=%d' % (rw, rh, rx, ry, enc))
            if enc == 0:                          # Raw
                data = recvall(self.s, rw * rh * 4)
                for row in range(rh):
                    base = row * rw * 4
                    dbase = (ry + row) * self.w * 3
                    for col in range(rw):
                        o = base + col * 4
                        # server format is 32bpp with shifts R=16 G=8 B=0 -> bytes are B,G,R,X
                        b = data[o]; g = data[o + 1]; r = data[o + 2]
                        d = dbase + (rx + col) * 3
                        pixels[d] = r; pixels[d + 1] = g; pixels[d + 2] = b
                x, y, w, h = rx, ry, rw, rh
            elif enc == 1:                        # CopyRect
                sx, sy, w, h = struct.unpack('>HHH', recvall(self.s, 6)) + (rw, rh)
                print('      (copyrect skipped)')
            else:
                raise RuntimeError('unsupported encoding %d' % enc)
        return x, y, w, h, bytes(pixels)

    def close(self):
        try:
            self.s.close()
        except Exception:
            pass


def write_png(path, w, h, rgb):
    raw = b''.join(b'\x00' + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))

    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(raw, 6))
           + chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(png)


if __name__ == '__main__':
    host = sys.argv[1] if len(sys.argv) > 1 else '172.25.81.151'
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 5900
    out = sys.argv[3] if len(sys.argv) > 3 else 'vnc_screen.png'
    print('connecting to %s:%d' % (host, port))
    c = RFB(host, port)
    c.handshake()
    c.init()
    c.request_update(0)
    x, y, w, h, px = c.read_update()
    write_png(out, c.w, c.h, px)
    print('saved %s (%dx%d)' % (out, c.w, c.h))
    c.close()
