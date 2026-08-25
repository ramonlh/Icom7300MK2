package es.ramonlorenzo.icom7300mk2.car;

import android.content.Intent;
import androidx.annotation.NonNull;
import androidx.car.app.CarContext;
import androidx.car.app.Screen;
import androidx.car.app.Session;

public final class IcomSession extends Session {
    @NonNull @Override public Screen onCreateScreen(@NonNull Intent intent) {
        return new RadioScreen(getCarContext());
    }
}
