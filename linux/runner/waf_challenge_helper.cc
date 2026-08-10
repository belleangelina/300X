#include <ctime>
#include <cstring>
#include <iostream>

#include <gtk/gtk.h>
#include <libsoup/soup.h>
#include <webkit2/webkit2.h>

namespace
{

constexpr char kForumUri[] = "https://bbs.yamibo.com/";
constexpr char kWafCookieName[] = "nox_jst_v1";
constexpr gint64 kChallengeTimeoutMicroseconds = 20 * G_USEC_PER_SEC;

GMainLoop* loop = nullptr;
WebKitCookieManager* cookie_manager = nullptr;
gint64 deadline = 0;
int exit_status = 1;

gboolean poll_cookies(gpointer);

void cookies_ready(GObject* source, GAsyncResult* result, gpointer)
{
    g_autoptr(GError) error = nullptr;
    GList* cookies = webkit_cookie_manager_get_cookies_finish(
        WEBKIT_COOKIE_MANAGER(source), result, &error);
    if (error != nullptr)
    {
        std::cerr << "cookie query failed\n";
        g_main_loop_quit(loop);
        return;
    }

    for (GList* item = cookies; item != nullptr; item = item->next)
    {
        SoupCookie* cookie = static_cast<SoupCookie*>(item->data);
        if (g_strcmp0(soup_cookie_get_name(cookie), kWafCookieName) != 0)
        {
            continue;
        }
        SoupDate* expires = soup_cookie_get_expires(cookie);
        const time_t expires_at = expires == nullptr
            ? std::time(nullptr) + 30 * 60
            : soup_date_to_time_t(expires);
        const gchar* value = soup_cookie_get_value(cookie);
        g_autofree gchar* encoded_value = g_base64_encode(
            reinterpret_cast<const guchar*>(value),
            strlen(value));
        std::cout << soup_cookie_get_name(cookie) << '\n'
                  << encoded_value << '\n'
                  << soup_cookie_get_domain(cookie) << '\n'
                  << soup_cookie_get_path(cookie) << '\n'
                  << static_cast<int64_t>(expires_at) * 1000 << '\n';
        std::cout.flush();
        exit_status = 0;
        g_list_free_full(
            cookies,
            reinterpret_cast<GDestroyNotify>(soup_cookie_free));
        g_main_loop_quit(loop);
        return;
    }
    g_list_free_full(
        cookies,
        reinterpret_cast<GDestroyNotify>(soup_cookie_free));

    if (g_get_monotonic_time() >= deadline)
    {
        std::cerr << "challenge timeout\n";
        g_main_loop_quit(loop);
        return;
    }
    g_timeout_add(250, poll_cookies, nullptr);
}

gboolean poll_cookies(gpointer)
{
    webkit_cookie_manager_get_cookies(
        cookie_manager,
        kForumUri,
        nullptr,
        cookies_ready,
        nullptr);
    return G_SOURCE_REMOVE;
}

}  // namespace

int main(int argc, char** argv)
{
    g_setenv("WEBKIT_DISABLE_DMABUF_RENDERER", "1", FALSE);
    gtk_init(&argc, &argv);
    loop = g_main_loop_new(nullptr, FALSE);
    deadline = g_get_monotonic_time() + kChallengeTimeoutMicroseconds;

    g_autoptr(WebKitWebContext) context = webkit_web_context_new_ephemeral();
    GtkWidget* window = gtk_offscreen_window_new();
    GtkWidget* web_view = webkit_web_view_new_with_context(context);
    gtk_container_add(GTK_CONTAINER(window), web_view);
    gtk_widget_show_all(window);

    WebKitWebsiteDataManager* data_manager =
        webkit_web_view_get_website_data_manager(WEBKIT_WEB_VIEW(web_view));
    cookie_manager = webkit_website_data_manager_get_cookie_manager(
        data_manager);
    webkit_web_view_load_uri(WEBKIT_WEB_VIEW(web_view), kForumUri);
    g_timeout_add(250, poll_cookies, nullptr);
    g_main_loop_run(loop);

    gtk_widget_destroy(window);
    g_main_loop_unref(loop);
    return exit_status;
}
