#!/usr/bin/env python3
"""Name the dylib behind an unslid address, straight from a dyld shared cache.

Needed because "ipsw dyld" wants <cache>.symbols, and the iOS 16.5 cryptex keeps that file
decmpfs-compressed (type 0x0e), which no tool here can inflate.

The image array is located by scanning for dyld_cache_image_info records instead of trusting the
header offsets: a record is 32 bytes (address u64, modTime u64, inode u64, pathFileOffset u32,
pad u32) and the addresses increase, so the array is the longest run of them.

usage: dscimg.py CACHE [ADDR ...]
"""
import struct
import sys

LOW, HIGH = 0x180000000, 0x300000000


def path_at(buf, off):
    if not 0 <= off < len(buf) or buf[off] != 0x2F:
        return None
    end = buf.find(b'\0', off, off + 256)
    if end < 0 or end - off < 4:
        return None
    s = buf[off:end]
    if any(c < 0x20 or c > 0x7E for c in s):
        return None
    return s.decode()


def record(buf, off):
    if off < 0 or off + 32 > len(buf):
        return None
    addr, _mod, _inode, path_off, _pad = struct.unpack_from('<QQQII', buf, off)
    if not LOW <= addr < HIGH:
        return None
    path = path_at(buf, path_off)
    if path is None:
        return None
    return addr, path


def find_array(buf):
    best, best_len = None, 0
    for start in range(0, len(buf) - 32, 8):
        first = record(buf, start)
        if first is None:
            continue
        n, last = 0, None
        while True:
            rec = record(buf, start + 32 * n)
            if rec is None:
                break
            n += 1
            last = rec
        if n > best_len:
            best, best_len = start, n
        # nothing is 8-byte aligned inside a run: skip past what was walked
        if n > 2:
            start += 32 * n
    return best, best_len


def main():
    buf = open(sys.argv[1], 'rb').read()
    start, count = find_array(buf)
    if not count:
        sys.exit('dscimg.py: no image array found in this cache file')
    images = [record(buf, start + 32 * i) for i in range(count)]
    images = [(a, p) for a, p in images if a is not None]
    images.sort()
    if len(sys.argv) == 2:
        print(f'{len(images)} images, array at {start:#x}')
        for addr, path in images[:8]:
            print(f'  {addr:#012x} {path}')
        return
    addrs = [int(a, 16) for a in sys.argv[2:]]
    for a in addrs:
        lo, hi, found = 0, len(images) - 1, None
        while lo <= hi:
            mid = (lo + hi) // 2
            if images[mid][0] <= a:
                found, lo = mid, mid + 1
            else:
                hi = mid - 1
        if found is None:
            print(f'{a:#x} below the first image')
            continue
        addr, path = images[found]
        print(f'{a:#x} {path} +{a - addr:#x}')


if __name__ == '__main__':
    main()
