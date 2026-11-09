/* Build-time definitions for the native GTK 1.2 port.
 * Keep identifiers and string literals in C source: DCL /DEFINE otherwise
 * folds an unquoted lowercase logging-domain identifier to uppercase.
 */
#if defined(XMMS_GTK_GLIB)
# define G_LOG_DOMAIN g_log_domain_glib
#elif defined(XMMS_GTK_GMODULE)
# define G_LOG_DOMAIN "GModule"
#elif defined(XMMS_GTK_GTHREAD)
# define G_LOG_DOMAIN "GThread"
#elif defined(XMMS_GTK_GDK)
# define G_LOG_DOMAIN "Gdk"
#elif defined(XMMS_GTK_GTK)
# define G_LOG_DOMAIN "Gtk"
# define GTK_LIBDIR ""
#endif
