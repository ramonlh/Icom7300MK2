package es.ramonlorenzo.icom7300mk2.car;

import androidx.annotation.NonNull;
import androidx.car.app.CarAppService;
import androidx.car.app.Session;
import androidx.car.app.validation.HostValidator;

public final class IcomCarAppService extends CarAppService {
    @NonNull @Override public Session onCreateSession() { return new IcomSession(); }
    @NonNull @Override public HostValidator createHostValidator() {
        // Para desarrollo con Desktop Head Unit; antes de publicar se limitarán los hosts.
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR;
    }
}
