package es.ramonlorenzo.icom7300mk2.car;

final class RadioState {
    final boolean connected, transmitting, busy;
    final long frequencyHz;
    final int meterPercent;
    final String frequencyText, mode, filter, band, meter, status;

    RadioState(boolean connected, boolean transmitting, boolean busy, long frequencyHz,
               String frequencyText, String mode, String filter, String band,
               String meter, int meterPercent, String status) {
        this.connected = connected; this.transmitting = transmitting; this.busy = busy;
        this.frequencyHz = frequencyHz; this.frequencyText = frequencyText;
        this.mode = mode; this.filter = filter; this.band = band;
        this.meter = meter; this.meterPercent = meterPercent; this.status = status;
    }
}
