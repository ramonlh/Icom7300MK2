package es.ramonlorenzo.icom7300mk2.car;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.text.InputType;
import android.view.ViewGroup;
import android.widget.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity {
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private EditText url, token; private TextView result;
    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        LinearLayout root = new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(48, 48, 48, 48); root.setBackgroundColor(Color.rgb(236, 244, 246));
        TextView title = new TextView(this); title.setText("IC-7300MK2 · Android Auto");
        title.setTextSize(24); title.setTextColor(Color.rgb(16, 32, 39)); root.addView(title, matchWrap());
        TextView explanation = new TextView(this);
        explanation.setText("Configure aquí el servidor del programa Linux. Use solamente una red local o una VPN privada.");
        explanation.setTextSize(16); explanation.setPadding(0, 20, 0, 28); root.addView(explanation, matchWrap());
        url = field("URL del servidor", ServerSettings.url(this));
        url.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI); root.addView(url, matchWrap());
        token = field("Clave de 8 caracteres", ServerSettings.token(this)); token.setAllCaps(true); root.addView(token, matchWrap());
        Button save = new Button(this); save.setText("Guardar y probar conexión");
        save.setOnClickListener(view -> saveAndTest()); root.addView(save, matchWrap());
        result = new TextView(this); result.setText("La pantalla del coche no permite PTT ni TUNE.");
        result.setTextSize(16); result.setPadding(0, 28, 0, 0); root.addView(result, matchWrap());
        setContentView(root);
    }
    @Override protected void onDestroy() { executor.shutdownNow(); super.onDestroy(); }
    private void saveAndTest() {
        String serverUrl = ServerSettings.normalizeUrl(url.getText().toString());
        String accessToken = token.getText().toString().trim().toUpperCase();
        if (!(serverUrl.startsWith("http://") || serverUrl.startsWith("https://"))) {
            result.setText("La URL debe comenzar por http:// o https://"); return;
        }
        if (!accessToken.matches("[A-Z0-9]{8}")) {
            result.setText("La clave debe contener exactamente 8 letras o números."); return;
        }
        ServerSettings.save(this, serverUrl, accessToken); result.setText("Conectando…");
        executor.execute(() -> {
            try {
                RadioState state = new RadioApi(serverUrl, accessToken).state();
                runOnUiThread(() -> result.setText(state.connected
                    ? "Radio conectada · " + state.frequencyText + " · " + state.mode
                    : "Servidor accesible, radio desconectada"));
            } catch (Exception error) {
                runOnUiThread(() -> result.setText("Error: " + error.getMessage()));
            }
        });
    }
    private EditText field(String hint, String value) {
        EditText field = new EditText(this); field.setHint(hint); field.setText(value); field.setSingleLine(true); return field;
    }
    private static LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }
}
