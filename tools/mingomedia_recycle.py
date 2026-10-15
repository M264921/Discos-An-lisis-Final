"""Windows recycle-only operations. There is deliberately no delete fallback."""
from contextlib import contextmanager
import ctypes
from ctypes import wintypes
import os
from pathlib import Path
import uuid


@contextmanager
def protected_read(path, allow_recycle=False):
    """Deny changes; keepers also deny renaming/deletion until the group finishes."""
    if os.name != 'nt':
        raise OSError('La retirada protegida requiere Windows.')
    import msvcrt
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    create = kernel.CreateFileW
    create.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                       ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
    create.restype = wintypes.HANDLE
    handle = create(str(Path(path).absolute()), 0x80000000, 5 if allow_recycle else 1,
                    None, 3, 0x08000000, None)
    if handle == ctypes.c_void_p(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        descriptor = msvcrt.open_osfhandle(handle, os.O_RDONLY | os.O_BINARY)
    except Exception:
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        kernel.CloseHandle(handle)
        raise
    with os.fdopen(descriptor, 'rb') as stream:
        yield stream


class GUID(ctypes.Structure):
    _fields_ = [('data1', wintypes.DWORD), ('data2', wintypes.WORD),
                ('data3', wintypes.WORD), ('data4', ctypes.c_ubyte * 8)]

    @classmethod
    def of(cls, value):
        return cls.from_buffer_copy(uuid.UUID(value).bytes_le)


def recycle_file(path):
    """ITransferSource.RecycleItem: unsupported volumes fail without deleting."""
    if os.name != 'nt':
        raise OSError('La Papelera requiere Windows.')
    path = Path(path).absolute()
    ole = ctypes.OleDLL('ole32')
    shell = ctypes.OleDLL('shell32')
    pointers = []
    initialized = False

    def check(hr):
        if hr < 0:
            raise OSError(f'Windows no pudo enviar el archivo a la Papelera (0x{hr & 0xffffffff:08X}). Se conserva en su ubicación si sigue disponible.')

    def call(pointer, index, arguments, *values):
        table = ctypes.cast(pointer, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
        fn = ctypes.WINFUNCTYPE(ctypes.c_long, ctypes.c_void_p, *arguments)(table[index])
        return fn(pointer, *values)

    iid = GUID.of('43826d1e-e718-42ee-bc55-a1e261c37bfe')
    transfer_iid = GUID.of('00adb003-bde9-45c6-8e29-d09f9353e108')
    bhid = GUID.of('d5e346a1-f753-4932-b403-4574800e2498')
    shell.SHCreateItemFromParsingName.argtypes = [wintypes.LPCWSTR, ctypes.c_void_p,
                                                ctypes.POINTER(GUID), ctypes.POINTER(ctypes.c_void_p)]
    shell.SHCreateItemFromParsingName.restype = ctypes.c_long
    ole.CoInitializeEx.argtypes = [ctypes.c_void_p, wintypes.DWORD]
    ole.CoInitializeEx.restype = ctypes.c_long
    ole.CoTaskMemFree.argtypes = [ctypes.c_void_p]

    def item(name):
        pointer = ctypes.c_void_p()
        check(shell.SHCreateItemFromParsingName(str(name), None, ctypes.byref(iid), ctypes.byref(pointer)))
        pointers.append(pointer)
        return pointer

    try:
        check(ole.CoInitializeEx(None, 2))
        initialized = True
        source = item(path)
        parent = item(path.parent)
        bin_item = item('::{645FF040-5081-101B-9F08-00AA002F954E}')
        transfer = ctypes.c_void_p()
        check(call(parent, 3, [ctypes.c_void_p, ctypes.POINTER(GUID), ctypes.POINTER(GUID), ctypes.POINTER(ctypes.c_void_p)],
                   None, ctypes.byref(bhid), ctypes.byref(transfer_iid), ctypes.byref(transfer)))
        pointers.append(transfer)
        recycled = ctypes.c_void_p()
        # Vtable slot 8 is RecycleItem. RemoveItem (permanent) is never used.
        check(call(transfer, 8, [ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(ctypes.c_void_p)],
                   source, bin_item, 0, ctypes.byref(recycled)))
        if recycled.value:
            pointers.append(recycled)
        if not recycled.value or path.exists():
            raise OSError('Windows no confirmó el traslado a la Papelera. Revisa el resultado antes de reintentar.')
        location = ctypes.c_void_p()
        hr = call(recycled, 5, [wintypes.DWORD, ctypes.POINTER(ctypes.c_void_p)], 0x80058000, ctypes.byref(location))
        try:
            return ctypes.wstring_at(location) if hr >= 0 and location.value else ''
        finally:
            if location.value:
                ole.CoTaskMemFree(location)
    finally:
        for pointer in reversed(pointers):
            if pointer.value:
                call(pointer, 2, [])
        if initialized:
            ole.CoUninitialize()
