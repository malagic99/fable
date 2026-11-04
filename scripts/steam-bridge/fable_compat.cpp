/* Fable's native Steam bridge — Unix-side helpers.
 *
 * The Unix half is built with WINE_NO_INLINE_STRING (otherwise winbase.h
 * poisons wcsncpy, which clashes with the macOS SDK's <wchar.h>), so
 * winbase.h no longer inlines these two — and a Unix-side library has no
 * kernel32 to import them from. Same semantics as Wine's inline versions. */
#include <stdarg.h>
#include <windef.h>
#include <winbase.h>

LPSTR WINAPI lstrcpynA( LPSTR dst, LPCSTR src, INT n )
{
    LPSTR d = dst;
    LPCSTR s = src;
    UINT count = n;

    while ((count > 1) && *s)
    {
        count--;
        *d++ = *s++;
    }
    if (count) *d = 0;
    return dst;
}

INT WINAPI lstrlenW( LPCWSTR str )
{
    const WCHAR *s = str;
    if (!str) return 0;
    while (*s) s++;
    return s - str;
}
