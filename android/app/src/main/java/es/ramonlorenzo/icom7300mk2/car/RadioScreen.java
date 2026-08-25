package es.ramonlorenzo.icom7300mk2.car;

import androidx.annotation.NonNull;
import androidx.car.app.CarContext;
import androidx.car.app.Screen;
import androidx.car.app.model.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class RadioScreen extends Screen {
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private volatile RadioState state; private volatile String error; private volatile boolean loading = true;
    RadioScreen(CarContext carContext) { super(carContext); refresh(); }
    @NonNull @Override public Template onGetTemplate() {
        ItemList.Builder items = new ItemList.Builder();
        if (loading && state == null) {
            return new ListTemplate.Builder().setTitle("IC-7300MK2")
                .setHeaderAction(Action.APP_ICON).setLoading(true).build();
        }
        if (error != null && state == null) {
            items.addItem(new Row.Builder().setTitle("Sin conexión").addText(error).build());
            items.addItem(new Row.Builder().setTitle("Reintentar").setOnClickListener(this::refresh).build());
        } else if (state != null) {
            String connection = !state.connected ? "RADIO DESCONECTADA"
                : state.transmitting ? "TX · controles bloqueados"
                : state.busy ? "RX · CI-V ocupado" : "RX · disponible";
            items.addItem(new Row.Builder().setTitle(state.frequencyText)
                .addText(state.mode + " · " + state.filter + " · " + state.band)
                .addText(connection + " · " + state.meter).build());
            boolean enabled = state.connected && !state.transmitting && !state.busy;
            Row.Builder down = new Row.Builder().setTitle("Bajar 1 kHz");
            Row.Builder up = new Row.Builder().setTitle("Subir 1 kHz");
            if (enabled) { down.setOnClickListener(() -> tune(-1000)); up.setOnClickListener(() -> tune(1000)); }
            items.addItem(down.build()); items.addItem(up.build());
            items.addItem(new Row.Builder().setTitle(loading ? "Actualizando…" : "Actualizar estado")
                .setOnClickListener(this::refresh).build());
        }
        return new ListTemplate.Builder().setTitle("IC-7300MK2 · control seguro")
            .setHeaderAction(Action.APP_ICON).setSingleList(items.build()).build();
    }
    @Override protected void onDestroy() { executor.shutdownNow(); super.onDestroy(); }
    private void refresh() {
        loading = true; invalidate();
        executor.execute(() -> {
            try {
                CarContext context = getCarContext();
                state = new RadioApi(ServerSettings.url(context), ServerSettings.token(context)).state(); error = null;
            } catch (Exception exception) { error = exception.getMessage(); state = null; }
            finally { loading = false; getCarContext().getMainExecutor().execute(this::invalidate); }
        });
    }
    private void tune(long deltaHz) {
        RadioState current = state;
        if (current == null || !current.connected || current.transmitting || current.busy) return;
        loading = true; invalidate();
        executor.execute(() -> {
            try {
                RadioApi api = new RadioApi(ServerSettings.url(getCarContext()), ServerSettings.token(getCarContext()));
                api.setFrequency(current.frequencyHz + deltaHz); state = api.state(); error = null;
            } catch (Exception exception) { error = exception.getMessage(); }
            finally { loading = false; getCarContext().getMainExecutor().execute(this::invalidate); }
        });
    }
}
