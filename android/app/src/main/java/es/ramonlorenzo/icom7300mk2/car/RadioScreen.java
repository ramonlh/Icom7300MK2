package es.ramonlorenzo.icom7300mk2.car;

import androidx.annotation.NonNull;
import androidx.car.app.CarContext;
import androidx.car.app.Screen;
import androidx.car.app.model.*;
import androidx.core.graphics.drawable.IconCompat;
import androidx.lifecycle.DefaultLifecycleObserver;
import androidx.lifecycle.LifecycleOwner;
import android.text.SpannableString;
import android.text.Spanned;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

final class RadioScreen extends Screen {
    private static final String[] MODES = {"LSB", "USB", "CW", "RTTY", "AM", "FM", "CW-R", "RTTY-R"};
    private final ScheduledExecutorService executor = Executors.newSingleThreadScheduledExecutor();
    private final AtomicBoolean requestInProgress = new AtomicBoolean();
    private volatile ScheduledFuture<?> autoRefresh;
    private volatile RadioState state;
    private volatile String liveMeter = "—";
    private volatile int liveMeterPercent;
    private volatile long lastFullStateUpdate;
    private volatile String error;
    private volatile boolean loading = true;

    RadioScreen(CarContext carContext) {
        super(carContext);
        getLifecycle().addObserver(new DefaultLifecycleObserver() {
            @Override public void onStart(@NonNull LifecycleOwner owner) {
                if (autoRefresh == null || autoRefresh.isCancelled()) {
                    autoRefresh = executor.scheduleWithFixedDelay(
                        () -> loadState(false), 250, 250, TimeUnit.MILLISECONDS);
                }
            }
            @Override public void onStop(@NonNull LifecycleOwner owner) {
                if (autoRefresh != null) autoRefresh.cancel(false);
            }
            @Override public void onDestroy(@NonNull LifecycleOwner owner) {
                executor.shutdownNow();
            }
        });
        refresh();
    }
    @NonNull @Override public Template onGetTemplate() {
        if (loading && state == null) {
            Pane loadingPane = new Pane.Builder()
                .addRow(new Row.Builder().setTitle("Actualizando…").build())
                .build();
            return new PaneTemplate.Builder(loadingPane).setTitle("IC-7300MK2")
                .setHeaderAction(Action.APP_ICON).build();
        }
        if (error != null && state == null) {
            Pane.Builder pane = new Pane.Builder()
                .addRow(new Row.Builder().setTitle("Sin conexión").addText(shortError(error)).build())
                .addAction(action("REINTENTAR", R.drawable.ic_refresh, this::refresh, true,
                    CarColor.BLUE));
            return new PaneTemplate.Builder(pane.build()).setTitle("IC-7300MK2")
                .setHeaderAction(Action.APP_ICON).build();
        }
        RadioState current = state;
        boolean enabled = current.connected && !current.transmitting && !current.busy;
        String connection = !current.connected ? "RADIO DESCONECTADA"
            : current.transmitting ? "TX · CONTROLES BLOQUEADOS"
            : current.busy ? "RX · CI-V OCUPADO" : "RX · " + current.meter;
        if (error != null) connection += " · SIN ACTUALIZAR";

        Row frequency = new Row.Builder()
            .setTitle(current.frequencyText)
            .addText(current.mode + " · " + current.filter + " · " + current.band)
            .addText(meterBar(connection, current, liveMeter, liveMeterPercent))
            .build();
        Row.Builder filter = new Row.Builder()
            .setTitle(current.mode + " · " + current.filter + " · " + current.band)
            .addText(enabled ? "Controles disponibles" : "Control no disponible");

        Pane pane = new Pane.Builder()
            .addRow(frequency)
            .addRow(filter.build())
            .addAction(action("−1 kHz", R.drawable.ic_tune_down, () -> tune(-1000), enabled,
                CarColor.BLUE))
            .addAction(action("+1 kHz", R.drawable.ic_tune_up, () -> tune(1000), enabled,
                CarColor.GREEN))
            .build();
        return new PaneTemplate.Builder(pane)
            .setTitle("IC-7300MK2")
            .setHeaderAction(Action.APP_ICON)
            .setActionStrip(new ActionStrip.Builder()
                .addAction(headerAction(R.drawable.ic_mode,
                    () -> getScreenManager().push(new ControlsScreen(getCarContext())), enabled))
                .build())
            .build();
    }

    private Action headerAction(int icon, OnClickListener listener, boolean enabled) {
        Action.Builder action = new Action.Builder()
            .setIcon(new CarIcon.Builder(IconCompat.createWithResource(getCarContext(), icon)).build())
            .setEnabled(enabled);
        if (enabled) action.setOnClickListener(listener);
        return action.build();
    }

    private static CharSequence coloredStatus(String value, RadioState state) {
        SpannableString text = new SpannableString(value);
        CarColor color = !state.connected || state.transmitting ? CarColor.RED
            : state.busy ? CarColor.YELLOW : CarColor.GREEN;
        text.setSpan(ForegroundCarColorSpan.create(color), 0, value.length(),
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        return text;
    }

    private static CharSequence meterBar(String connection, RadioState state,
                                         String meter, int meterPercent) {
        if (!state.connected || state.transmitting) return coloredStatus(connection, state);
        final int segments = 12;
        int filled = Math.max(0, Math.min(segments,
            Math.round(meterPercent * segments / 100f)));
        String prefix = state.busy ? "CI-V  " : "RX  ";
        StringBuilder value = new StringBuilder(prefix);
        for (int i = 0; i < segments; i++) value.append(i < filled ? '▮' : '▯');
        value.append("  ").append(meter);

        SpannableString bar = new SpannableString(value.toString());
        CarColor color = state.busy ? CarColor.YELLOW
            : meterPercent >= 85 ? CarColor.RED
            : meterPercent >= 60 ? CarColor.YELLOW : CarColor.GREEN;
        int barStart = prefix.length();
        bar.setSpan(ForegroundCarColorSpan.create(color), 0, barStart + filled,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        return bar;
    }

    private Action action(String title, int icon, OnClickListener listener, boolean enabled,
                          CarColor color) {
        Action.Builder action = new Action.Builder()
            .setTitle(title)
            .setIcon(new CarIcon.Builder(IconCompat.createWithResource(getCarContext(), icon)).build())
            .setBackgroundColor(color)
            .setEnabled(enabled);
        if (enabled) action.setOnClickListener(listener);
        return action.build();
    }

    private static String shortError(String value) {
        return value.length() <= 35 ? value : value.substring(0, 32) + "…";
    }

    private void refresh() {
        loading = true;
        invalidate();
        executor.execute(() -> loadState(true));
    }

    private void loadState(boolean userRequested) {
        if (!requestInProgress.compareAndSet(false, true)) return;
        try {
            CarContext context = getCarContext();
            RadioState latest = new RadioApi(
                ServerSettings.url(context), ServerSettings.token(context)).state();
            liveMeter = latest.meter;
            liveMeterPercent = latest.meterPercent;
            long now = System.currentTimeMillis();
            if (userRequested || state == null || now - lastFullStateUpdate >= 1000) {
                state = latest;
                lastFullStateUpdate = now;
            }
            error = null;
        } catch (Exception exception) {
            error = message(exception);
            if (userRequested) state = null;
        } finally {
            loading = false;
            requestInProgress.set(false);
            getCarContext().getMainExecutor().execute(this::invalidate);
        }
    }

    private void tune(long deltaHz) {
        RadioState current = state;
        if (current == null || !current.connected || current.transmitting || current.busy) return;
        execute(api -> api.setFrequency(current.frequencyHz + deltaHz));
    }

    private void execute(ApiCommand command) {
        if (!requestInProgress.compareAndSet(false, true)) return;
        loading = true;
        invalidate();
        executor.execute(() -> {
            try {
                RadioApi api = api();
                command.run(api);
                state = api.state();
                liveMeter = state.meter;
                liveMeterPercent = state.meterPercent;
                lastFullStateUpdate = System.currentTimeMillis();
                error = null;
            } catch (Exception exception) {
                error = message(exception);
            } finally {
                loading = false;
                requestInProgress.set(false);
                getCarContext().getMainExecutor().execute(this::invalidate);
            }
        });
    }

    private RadioApi api() {
        return new RadioApi(ServerSettings.url(getCarContext()), ServerSettings.token(getCarContext()));
    }

    private static String message(Exception exception) {
        return exception.getMessage() == null ? "Error de comunicación" : exception.getMessage();
    }

    private interface ApiCommand { void run(RadioApi api) throws Exception; }
}
