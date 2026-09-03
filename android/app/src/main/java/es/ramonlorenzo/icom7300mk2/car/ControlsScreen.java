package es.ramonlorenzo.icom7300mk2.car;

import androidx.annotation.NonNull;
import androidx.car.app.CarContext;
import androidx.car.app.Screen;
import androidx.car.app.model.*;
import androidx.core.graphics.drawable.IconCompat;
import androidx.lifecycle.DefaultLifecycleObserver;
import androidx.lifecycle.LifecycleOwner;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class ControlsScreen extends Screen {
    private static final String[] MODES = {"LSB", "USB", "CW", "RTTY", "AM", "FM", "CW-R", "RTTY-R"};
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private volatile RadioState state;
    private volatile String error;
    private volatile boolean loading = true;

    ControlsScreen(CarContext context) {
        super(context);
        getLifecycle().addObserver(new DefaultLifecycleObserver() {
            @Override public void onDestroy(@NonNull LifecycleOwner owner) { executor.shutdownNow(); }
        });
        load();
    }

    @NonNull @Override public Template onGetTemplate() {
        if (loading && state == null) {
            return new GridTemplate.Builder().setTitle("Ajustes de recepción")
                .setHeaderAction(Action.BACK).setLoading(true).build();
        }
        ItemList.Builder items = new ItemList.Builder();
        if (state == null) {
            items.addItem(tile("SIN CONEXIÓN", error == null ? "" : error,
                R.drawable.ic_connection, this::load));
        } else {
            boolean enabled = state.connected && !state.transmitting && !state.busy && !loading;
            items.addItem(tile(state.mode, "MODO", R.drawable.ic_mode,
                enabled ? this::nextMode : null));
            items.addItem(tile(state.filter, "FILTRO", R.drawable.ic_filter,
                enabled ? this::nextFilter : null));
            items.addItem(tile(state.band, "BANDA", R.drawable.ic_band,
                enabled ? () -> getScreenManager().push(new BandScreen(getCarContext())) : null));
        }
        return new GridTemplate.Builder().setTitle(error == null ? "Ajustes de recepción" : "Sin actualizar")
            .setHeaderAction(Action.BACK).setSingleList(items.build()).build();
    }

    private GridItem tile(String title, String text, int icon, OnClickListener listener) {
        GridItem.Builder item = new GridItem.Builder().setTitle(title).setText(text)
            .setImage(new CarIcon.Builder(IconCompat.createWithResource(getCarContext(), icon)).build(),
                GridItem.IMAGE_TYPE_ICON);
        if (listener != null) item.setOnClickListener(listener);
        return item.build();
    }

    private void load() {
        loading = true;
        invalidate();
        executor.execute(() -> {
            try { state = api().state(); error = null; }
            catch (Exception exception) { state = null; error = message(exception); }
            finally { loading = false; getCarContext().getMainExecutor().execute(this::invalidate); }
        });
    }

    private void nextMode() {
        int next = 0;
        for (int i = 0; i < MODES.length; i++) {
            if (MODES[i].equalsIgnoreCase(state.mode)) { next = (i + 1) % MODES.length; break; }
        }
        final String value = MODES[next];
        execute(api -> api.setMode(value));
    }

    private void nextFilter() {
        String value = state.filter.toUpperCase(Locale.ROOT);
        int next = value.contains("1") ? 2 : value.contains("2") ? 3 : 1;
        execute(api -> api.setFilter(next));
    }

    private void execute(Command command) {
        loading = true;
        invalidate();
        executor.execute(() -> {
            try { RadioApi api = api(); command.run(api); state = api.state(); error = null; }
            catch (Exception exception) { error = message(exception); }
            finally { loading = false; getCarContext().getMainExecutor().execute(this::invalidate); }
        });
    }

    private RadioApi api() {
        return new RadioApi(ServerSettings.url(getCarContext()), ServerSettings.token(getCarContext()));
    }
    private static String message(Exception error) {
        return error.getMessage() == null ? "Error de comunicación" : error.getMessage();
    }
    private interface Command { void run(RadioApi api) throws Exception; }
}
