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

final class BandScreen extends Screen {
    private static final String[][] BANDS = {
        {"3.5", "80 m"}, {"7", "40 m"}, {"14", "20 m"},
        {"21", "15 m"}, {"28", "10 m"}, {"50", "6 m"}
    };
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private volatile boolean loading;
    private volatile String error;

    BandScreen(CarContext carContext) {
        super(carContext);
        getLifecycle().addObserver(new DefaultLifecycleObserver() {
            @Override public void onDestroy(@NonNull LifecycleOwner owner) { executor.shutdownNow(); }
        });
    }

    @NonNull @Override public Template onGetTemplate() {
        ItemList.Builder items = new ItemList.Builder();
        for (String[] band : BANDS) {
            GridItem.Builder item = new GridItem.Builder()
                .setTitle(band[1])
                .setText(band[0] + " MHz")
                .setImage(new CarIcon.Builder(IconCompat.createWithResource(
                    getCarContext(), R.drawable.ic_band)).build(), GridItem.IMAGE_TYPE_ICON);
            if (!loading) item.setOnClickListener(() -> select(band[0]));
            items.addItem(item.build());
        }
        return new GridTemplate.Builder()
            .setTitle(loading ? "Cambiando banda…"
                : error == null ? "Seleccionar banda" : "No se cambió la banda")
            .setHeaderAction(Action.BACK)
            .setSingleList(items.build())
            .build();
    }

    private void select(String band) {
        loading = true;
        error = null;
        invalidate();
        executor.execute(() -> {
            try {
                new RadioApi(ServerSettings.url(getCarContext()), ServerSettings.token(getCarContext())).setBand(band);
                getCarContext().getMainExecutor().execute(() -> getScreenManager().pop());
            } catch (Exception exception) {
                error = exception.getMessage() == null ? "Error de comunicación" : exception.getMessage();
                loading = false;
                getCarContext().getMainExecutor().execute(this::invalidate);
            }
        });
    }
}
