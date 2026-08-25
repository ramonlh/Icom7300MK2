package es.ramonlorenzo.icom7300mk2.car;

import org.json.JSONObject;
import java.io.*;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

final class RadioApi {
    private final String baseUrl, token;
    RadioApi(String baseUrl, String token) {
        this.baseUrl = ServerSettings.normalizeUrl(baseUrl);
        this.token = token.trim().toUpperCase();
    }
    RadioState state() throws IOException {
        JSONObject json = request("GET", "/api/state", null);
        return new RadioState(json.optBoolean("connected"), json.optBoolean("transmitting"),
            json.optBoolean("busy"), Math.round(json.optDouble("frequencyHz", 0)),
            json.optString("frequencyText", "—"), json.optString("mode", "—"),
            json.optString("filter", "—"), json.optString("band", "—"),
            json.optString("sMeterText", "—"),
            json.optString("actionStatus", json.optString("status", "")));
    }
    void setFrequency(long frequencyHz) throws IOException {
        JSONObject body = new JSONObject();
        body.put("command", "frequency"); body.put("value", frequencyHz);
        request("POST", "/api/command", body);
    }
    private JSONObject request(String method, String path, JSONObject body) throws IOException {
        if (baseUrl.isEmpty() || token.length() != 8)
            throw new IOException("Configure la URL y la clave en el teléfono");
        HttpURLConnection connection = (HttpURLConnection) new URL(baseUrl + path).openConnection();
        connection.setConnectTimeout(4000); connection.setReadTimeout(5000);
        connection.setRequestMethod(method);
        connection.setRequestProperty("Authorization", "Bearer " + token);
        connection.setRequestProperty("Accept", "application/json");
        if (body != null) {
            byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);
            connection.setDoOutput(true);
            connection.setRequestProperty("Content-Type", "application/json");
            connection.setFixedLengthStreamingMode(bytes.length);
            try (OutputStream output = connection.getOutputStream()) { output.write(bytes); }
        }
        int status = connection.getResponseCode();
        InputStream stream = status >= 200 && status < 300
            ? connection.getInputStream() : connection.getErrorStream();
        String response = readAll(stream); connection.disconnect();
        if (status < 200 || status >= 300) {
            String message = "HTTP " + status;
            try { message = new JSONObject(response).optString("message", message); }
            catch (Exception ignored) {}
            throw new IOException(message);
        }
        try { return new JSONObject(response); }
        catch (Exception error) { throw new IOException("Respuesta no válida del servidor", error); }
    }
    private static String readAll(InputStream stream) throws IOException {
        if (stream == null) return "";
        StringBuilder result = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(
            new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            String line; while ((line = reader.readLine()) != null) result.append(line);
        }
        return result.toString();
    }
}
