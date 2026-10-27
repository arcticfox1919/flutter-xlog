#!/usr/bin/env python3
"""Decode (decompress) mars/xlog .xlog files into plain text.

This is a Python 3 port of the upstream `decode_mars_nocrypt_log_file.py`,
for logs written WITHOUT encryption (empty pub_key). It supports both the
zlib and zstd compression formats used by xlog.

zstd-compressed logs additionally require the `zstandard` package
(`pip install zstandard`); zlib logs need only the standard library.

Usage:
    python decode_xlog.py <file.xlog>           # -> <file.xlog>.log
    python decode_xlog.py <file.xlog> <out.log> # explicit output path
    python decode_xlog.py <dir>                 # decode every *.xlog in dir
    python decode_xlog.py                       # decode *.xlog in cwd
"""

import sys
import os
import glob
import zlib
import struct
import traceback

try:
    import zstandard as zstd
except ImportError:
    zstd = None

MAGIC_NO_COMPRESS_START = 0x03
MAGIC_NO_COMPRESS_START1 = 0x06
MAGIC_NO_COMPRESS_NO_CRYPT_START = 0x08
MAGIC_COMPRESS_START = 0x04
MAGIC_COMPRESS_START1 = 0x05
MAGIC_COMPRESS_START2 = 0x07
MAGIC_COMPRESS_NO_CRYPT_START = 0x09

MAGIC_SYNC_ZSTD_START = 0x0A
MAGIC_SYNC_NO_CRYPT_ZSTD_START = 0x0B
MAGIC_ASYNC_ZSTD_START = 0x0C
MAGIC_ASYNC_NO_CRYPT_ZSTD_START = 0x0D

MAGIC_END = 0x00

lastseq = 0

# Magic bytes that imply a 4-byte crypt key field in the header.
_KEY_LEN_4 = {
    MAGIC_NO_COMPRESS_START,
    MAGIC_COMPRESS_START,
    MAGIC_COMPRESS_START1,
}
# Magic bytes that imply a 64-byte crypt key field in the header.
_KEY_LEN_64 = {
    MAGIC_COMPRESS_START2,
    MAGIC_NO_COMPRESS_START1,
    MAGIC_NO_COMPRESS_NO_CRYPT_START,
    MAGIC_COMPRESS_NO_CRYPT_START,
    MAGIC_SYNC_ZSTD_START,
    MAGIC_SYNC_NO_CRYPT_ZSTD_START,
    MAGIC_ASYNC_ZSTD_START,
    MAGIC_ASYNC_NO_CRYPT_ZSTD_START,
}
_ALL_MAGIC_START = _KEY_LEN_4 | _KEY_LEN_64


def _crypt_key_len(magic_start):
    if magic_start in _KEY_LEN_4:
        return 4
    if magic_start in _KEY_LEN_64:
        return 64
    return None


def is_good_log_buffer(buf, offset, count):
    """Validate that a record (and `count-1` following records) is well formed."""
    if offset == len(buf):
        return (True, '')

    crypt_key_len = _crypt_key_len(buf[offset])
    if crypt_key_len is None:
        return (False, 'buf[%d]:%d != MAGIC_NUM_START' % (offset, buf[offset]))

    header_len = 1 + 2 + 1 + 1 + 4 + crypt_key_len

    if offset + header_len + 1 + 1 > len(buf):
        return (False, 'offset:%d > len(buffer):%d' % (offset, len(buf)))

    length = struct.unpack_from('I', buf, offset + header_len - 4 - crypt_key_len)[0]
    if offset + header_len + length + 1 > len(buf):
        return (False, 'log length:%d, end pos %d > len(buffer):%d'
                % (length, offset + header_len + length + 1, len(buf)))
    if MAGIC_END != buf[offset + header_len + length]:
        return (False, 'log length:%d, buffer[%d]:%d != MAGIC_END'
                % (length, offset + header_len + length, buf[offset + header_len + length]))

    if count <= 1:
        return (True, '')
    return is_good_log_buffer(buf, offset + header_len + length + 1, count - 1)


def get_log_start_pos(buf, count):
    """Scan forward for the first offset that begins a valid record run."""
    offset = 0
    while offset < len(buf):
        if buf[offset] in _ALL_MAGIC_START and is_good_log_buffer(buf, offset, count)[0]:
            return offset
        offset += 1
    return -1


def decode_buffer(buf, offset, out):
    """Decode a single record at `offset`, append to `out`, return next offset."""
    if offset >= len(buf):
        return -1

    ret = is_good_log_buffer(buf, offset, 1)
    if not ret[0]:
        fixpos = get_log_start_pos(buf[offset:], 1)
        if fixpos == -1:
            return -1
        out.extend(('[F]decode_xlog.py decode error len=%d, result:%s \n'
                    % (fixpos, ret[1])).encode())
        offset += fixpos

    magic_start = buf[offset]
    crypt_key_len = _crypt_key_len(magic_start)
    if crypt_key_len is None:
        out.extend(('in decode_buffer buf[%d]:%d != MAGIC_NUM_START'
                    % (offset, magic_start)).encode())
        return -1

    header_len = 1 + 2 + 1 + 1 + 4 + crypt_key_len
    length = struct.unpack_from('I', buf, offset + header_len - 4 - crypt_key_len)[0]

    seq = struct.unpack_from('H', buf, offset + header_len - 4 - crypt_key_len - 2 - 2)[0]

    global lastseq
    if seq != 0 and seq != 1 and lastseq != 0 and seq != (lastseq + 1):
        out.extend(('[F]decode_xlog.py log seq:%d-%d is missing\n'
                    % (lastseq + 1, seq - 1)).encode())
    if seq != 0:
        lastseq = seq

    data = bytes(buf[offset + header_len:offset + header_len + length])

    try:
        if magic_start in (MAGIC_NO_COMPRESS_START1, MAGIC_COMPRESS_START2,
                           MAGIC_SYNC_ZSTD_START, MAGIC_ASYNC_ZSTD_START):
            out.extend(b'use wrong decode script (encrypted log)\n')
            return -1
        elif magic_start in (MAGIC_SYNC_NO_CRYPT_ZSTD_START,
                             MAGIC_ASYNC_NO_CRYPT_ZSTD_START):
            if zstd is None:
                raise RuntimeError('zstd log needs `pip install zstandard`')
            data = zstd.ZstdDecompressor().decompress(data)
        elif magic_start in (MAGIC_COMPRESS_START, MAGIC_COMPRESS_NO_CRYPT_START):
            data = zlib.decompressobj(-zlib.MAX_WBITS).decompress(data)
        elif magic_start == MAGIC_COMPRESS_START1:
            # A sequence of length-prefixed log fragments, then zlib-compressed.
            merged = bytearray()
            view = bytearray(data)
            while len(view) > 0:
                single = struct.unpack_from('H', view, 0)[0]
                merged.extend(view[2:single + 2])
                view = view[single + 2:]
            data = zlib.decompressobj(-zlib.MAX_WBITS).decompress(bytes(merged))
        else:
            # No-compress variants: data is already plain text.
            pass
    except Exception as e:
        traceback.print_exc()
        out.extend(('[F]decode_xlog.py decompress err, ' + str(e) + '\n').encode())
        return offset + header_len + length + 1

    out.extend(data)
    return offset + header_len + length + 1


def parse_file(in_path, out_path):
    with open(in_path, 'rb') as fp:
        buf = bytearray(fp.read())

    startpos = get_log_start_pos(buf, 2)
    if startpos == -1:
        print('%s: no valid log start found' % in_path)
        return

    out = bytearray()
    while True:
        startpos = decode_buffer(buf, startpos, out)
        if startpos == -1:
            break

    if len(out) == 0:
        print('%s: decoded 0 bytes' % in_path)
        return

    with open(out_path, 'wb') as fp:
        fp.write(out)
    print('%s -> %s (%d bytes)' % (in_path, out_path, len(out)))


def main(args):
    global lastseq
    if len(args) == 1:
        if os.path.isdir(args[0]):
            for path in glob.glob(os.path.join(args[0], '*.xlog')):
                lastseq = 0
                parse_file(path, path + '.log')
        else:
            parse_file(args[0], args[0] + '.log')
    elif len(args) == 2:
        parse_file(args[0], args[1])
    else:
        for path in glob.glob('*.xlog'):
            lastseq = 0
            parse_file(path, path + '.log')


if __name__ == '__main__':
    main(sys.argv[1:])
