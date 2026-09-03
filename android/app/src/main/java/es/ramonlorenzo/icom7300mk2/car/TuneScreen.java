package es.ramonlorenzo.icom7300mk2.car;

import androidx.annotation.NonNull;
import androidx.car.app.CarContext;
import androidx.car.app.Screen;
import androidx.car.app.model.*;
import androidx.core.graphics.drawable.IconCompat;
import androidx.lifecycle.DefaultLifecycleObserver;
import androidx.lifecycle.LifecycleOwner;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class TuneScreen extends Screen {
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private volatile RadioState state;
    private volatile boolean loading = true;
    private volatile String error;

    TuneScreen(CarContext context) {
        super(context);
        getLifecycle().addObserver(new DefaultLifecycleObserver() {
            @Override public void onDestroy(@NonNull LifecycleOwner owner) { executor.shutdownNow(); }
        });
        refresh();
    }

    @NonNull @Override public Template onGetTemplate() {
        if (loading && state == null) {
            return new GridTemplate.Builder().setTitle("Sintonía")
                .setHeaderAction(Action.BACK).setLoading(true).build();
        }
        ItemList.Builder items = new ItemList.Builder();
        if (state == null) {
            items.addItem(tile("REINTENTAR", error == null ? "Sin conexión" : error,
                R.drawable.ic_refresh, this::refresh));
        } else {
            boolean enabled = state.connected && !state.transmitting && !state.busy && !loading;
            items.addItem(tile("− 1 kHz", "BAJAR", R.drawable.ic_tune_down,
                enabled ? () -> tune(-1000) : null));
            items.addItem(tile("+ 1 kHz", "SUBIR", R.drawable.ic_tune_up,
                enabled ? () -> tune(1000) : null));
        }
        String title = state == null ? "Sintonía"
            : state.frequencyText + (loading ? " · …" : "");
        return new GridTemplate.Builder().setTitle(title)
            .setHeaderAction(Action.BACK).setSingleList(items.build()).build();
    }

    private GridItem tile(String title, String text, int icon, OnClickListener listener) {
        GridItem.Builder item = new GridItem.Builder().setTitle(title).setText(text)
            .setImage(new CarIcon.Builder(IconCompat.createWithResource(getCarContext(), icon)).build(),
                GridItem.IMAGE_TYPE_ICON);
        if (listener != null) item.setOnClickListener(listener);
        return item.build();
    }

    private void refresh() {
        loading = true;
        invalidate();
        executor.execute(() -> {
            try { state = api().state(); error = null; }
            catch (Exception exception) { state = null; error = message(exception); }
            finally { loading = false; getCarContext().getMainExecutor().execute(this::invalidate); }
        });
    }

    private void tune(long delta) {
        RadioState current = state;
        if (current == null || loading) return;
        loading = true;
        invalidate();
        executor.execute(() -> {
            try {
                RadioApi api = api();
                api.setFrequency(current.frequencyHz + delta);
                state = api.state();
                error = null;
            } catch (Exception exception) { error = message(exception); }
            finally { loading = false; getCarContext().getMainExecutor().execute(this::invalidate); }
        });
    }

    private RadioApi api() {
        return new RadioApi(ServerSettings.url(getCarContext()), ServerSettings.token(getCarContext()));
    }
    private static String message(Exception error) {
        return error.getMessage() == null ? "Error de comunicación" : error.getMessage();
    }
}
