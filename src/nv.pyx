#
# Copyright (c) 2016 Jakub Klama <jceel@FreeBSD.org>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#

import os
import enum
cimport defs
from libc.errno cimport errno

class NVType(enum.IntEnum):
    NONE = defs.NV_TYPE_NONE
    NIL = defs.NV_TYPE_NULL
    BOOL = defs.NV_TYPE_BOOL
    NUMBER = defs.NV_TYPE_NUMBER
    STRING = defs.NV_TYPE_STRING
    NVLIST = defs.NV_TYPE_NVLIST
    DESCRIPTOR = defs.NV_TYPE_DESCRIPTOR
    BINARY = defs.NV_TYPE_BINARY


cdef class NVList(object):
    cdef defs.nvlist_t *nvlist
    cdef NVList parent

    def __init__(self, d=None, ignore_case=False):
        self.nvlist = defs.nvlist_create(0)
        self.parent = None

        if d:
            if isinstance(d, dict):
                for k, v in d.items():
                    self[k] = v

            if isinstance(d, list):
                for idx, i in enumerate(d):
                    self[str(idx)] = i

    def __dealloc__(self):
        if self.parent is None:
            defs.nvlist_destroy(self.nvlist)

    def __getitem__(self, item):
        for t in NVType.__members__.values():
            try:
                return self.get(item, t)
            except KeyError:
                continue

        raise KeyError(item)

    def __setitem__(self, key, value):
        cdef NVList nvl

        if isinstance(value, bool):
            defs.nvlist_add_bool(self.nvlist, key, value)
            return

        if isinstance(value, int):
            defs.nvlist_add_number(self.nvlist, key, value)
            return

        if isinstance(value, str):
            defs.nvlist_add_string(self.nvlist, key, value)
            return

        if isinstance(value, (dict, list)):
            nvl = <NVList>NVList(value)
            defs.nvlist_add_nvlist(self.nvlist, key, nvl.nvlist)
            return

        if isinstance(value, NVList):
            nvl = <NVList>value
            defs.nvlist_add_nvlist(self.nvlist, key, nvl.nvlist)
            return

    def __contains__(self, item):
        return defs.nvlist_exists(self.nvlist, item)

    def get(self, key, type, default=None):
        cdef NVList nvl
        cdef size_t sizep

        if not defs.nvlist_exists_type(self.nvlist, key, type):
            raise KeyError(key)

        if type == NVType.NONE:
            raise KeyError(key)

        if type == NVType.NIL:
            return None

        if type == NVType.BOOL:
            return defs.nvlist_get_bool(self.nvlist, key)

        if type == NVType.NUMBER:
            return defs.nvlist_get_number(self.nvlist, key)

        if type == NVType.STRING:
            return defs.nvlist_get_string(self.nvlist, key)

        if type == NVType.NVLIST:
            nvl = NVList.__new__(NVList)
            nvl.parent = self
            nvl.nvlist = defs.nvlist_get_nvlist(self.nvlist, key)
            return nvl

        if type == NVType.BINARY:
            pass

        raise ValueError('Invalid type {0}'.format(type))

    def dump(self, f):
        if hasattr(f, 'fileno'):
            f = f.fileno()

        defs.nvlist_dump(self.nvlist, f)

    def send(self, sock):
        if hasattr(sock, 'fileno'):
            sock = sock.fileno()

        if defs.nvlist_send(sock, self.nvlist) < 0:
            raise OSError(errno, os.strerror(errno))

    @staticmethod
    def recv(sock):
        cdef NVList result
        cdef defs.nvlist_t *nvl

        if hasattr(sock, 'fileno'):
            sock = sock.fileno()

        nvl = defs.nvlist_recv(sock)
        if nvl == NULL:
            return None

        result = NVList.__new__(NVList)
        result.parent = None
        result.nvlist = nvl
        return result
