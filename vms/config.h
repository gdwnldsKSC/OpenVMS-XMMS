/* Native OpenVMS Alpha configuration.  No Unix configure program is needed.
 * Build with VSI/Compaq C, 32-bit pointers and IEEE floating point, matching
 * the native GTK+ 1.2 port.  Optional Unix-only plugins are not built.
 */
#ifndef XMMS_VMS_CONFIG_H
#define XMMS_VMS_CONFIG_H
#define PACKAGE "xmms"
#define PACKAGE_NAME "XMMS"
#define PACKAGE_TARNAME "xmms"
#define PACKAGE_VERSION "1.2.11"
#define PACKAGE_STRING "XMMS 1.2.11 for OpenVMS"
#define PACKAGE_BUGREPORT ""
#define VERSION "1.2.11"
#define XMMS_STATIC_PLUGINS 1
#define XMMS_NO_REMOTE_CONTROL 1
#define DISABLE_USER_PLUGIN_DIR 1
#define DATA_DIR "/XMMS_ROOT"
#define PLUGIN_DIR "/XMMS_ROOT/plugins"
#define PLUGINSUBS 0
#define LOCALEDIR "/XMMS_ROOT/locale"
#define STDC_HEADERS 1
#define SIZEOF_LONG 4
#define HAVE_FCNTL_H 1
#define HAVE_GETCWD 1
#define HAVE_GETEGID 1
#define HAVE_GETEUID 1
#define HAVE_GETGID 1
#define HAVE_GETPAGESIZE 1
#define HAVE_GETUID 1
#define HAVE_LIMITS_H 1
#define HAVE_LOCALE_H 1
#define HAVE_LONG_LONG 1
#define HAVE_MEMORY_H 1
#define HAVE_NL_TYPES_H 1
#define HAVE_PUTENV 1
#define HAVE_SETENV 1
#define HAVE_SETLOCALE 1
#define HAVE_SNPRINTF 1
#define HAVE_STDDEF_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRCASECMP 1
#define HAVE_STRDUP 1
#define HAVE_STRINGS_H 1
#define HAVE_STRING_H 1
#define HAVE_STRTOUL 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_TYPES_H 1
#define TIME_WITH_SYS_TIME 1
#define HAVE_UNISTD_H 1
#define HAVE_UNSIGNED_LONG_LONG 1
#define HAVE_WCHAR_H 1
#define HAVE_WCHAR_T 1
#define HAVE_WCSLEN 1
#define HAVE_WINT_T 1
#define HAVE_NANOSLEEP 1
#ifndef __cplusplus
#define inline __inline
#endif
/* Use the bundled mkdtemp and getopt implementations. */
#endif
