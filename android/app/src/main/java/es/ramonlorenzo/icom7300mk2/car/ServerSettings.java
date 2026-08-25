package es.ramonlorenzo.icom7300mk2.car;

import android.content.Context;
import android.content.SharedPreferences;

final class ServerSettings {
    private static final String PREFERENCES = "icom_server";
    private ServerSettings() {}

    static String url(Context context) {
        return preferences(context).getString("url", "http://192.168.1.100:7300");
    }
    static String token(Context context) {
        return preferences(context).getString("token", "");
    }
    static void save(Context context, String url, String token) {
        preferences(context).edit().putString("url", normalizeUrl(url))
            .putString("token", token.trim().toUpperCase()).apply();
    }
    static String normalizeUrl(String value) {
        String result = value.trim();
        while (result.endsWith("/")) result = result.substring(0, result.length() - 1);
        return result;
    }
    private static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE);
    }
}
