#include "morsetrainer.h"

#include <QAudio>
#include <QAudioSource>
#include <QAudioSink>
#include <QBuffer>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QHash>
#include <QIODevice>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMediaDevices>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <climits>
#include <limits>
#include <numbers>
#include <utility>

namespace
{
constexpr double MinimumDb = -90.0;
constexpr double PassedScore = 90.0;
constexpr int AnalysisFrameMilliseconds = 10;
constexpr int DebounceMilliseconds = 18;

const QStringList &kochSequence()
{
    static const QStringList sequence = {
        QStringLiteral("K"), QStringLiteral("M"),
        QStringLiteral("U"), QStringLiteral("R"),
        QStringLiteral("E"), QStringLiteral("S"),
        QStringLiteral("N"), QStringLiteral("A"),
        QStringLiteral("P"), QStringLiteral("T"),
        QStringLiteral("L"), QStringLiteral("W"),
        QStringLiteral("I"), QStringLiteral("."),
        QStringLiteral("J"), QStringLiteral("Z"),
        QStringLiteral("="), QStringLiteral("F"),
        QStringLiteral("O"), QStringLiteral("Y"),
        QStringLiteral(","), QStringLiteral("V"),
        QStringLiteral("G"), QStringLiteral("5"),
        QStringLiteral("/"), QStringLiteral("Q"),
        QStringLiteral("9"), QStringLiteral("2"),
        QStringLiteral("H"), QStringLiteral("3"),
        QStringLiteral("8"), QStringLiteral("B"),
        QStringLiteral("?"), QStringLiteral("4"),
        QStringLiteral("7"), QStringLiteral("C"),
        QStringLiteral("1"), QStringLiteral("D"),
        QStringLiteral("6"), QStringLiteral("0"),
        QStringLiteral("X")
    };

    return sequence;
}

const QHash<QString, QString> &morseDecodeTable()
{
    static const QHash<QString, QString> table = {
        {QStringLiteral(".-"), QStringLiteral("A")},
        {QStringLiteral("-..."), QStringLiteral("B")},
        {QStringLiteral("-.-."), QStringLiteral("C")},
        {QStringLiteral("-.."), QStringLiteral("D")},
        {QStringLiteral("."), QStringLiteral("E")},
        {QStringLiteral("..-."), QStringLiteral("F")},
        {QStringLiteral("--."), QStringLiteral("G")},
        {QStringLiteral("...."), QStringLiteral("H")},
        {QStringLiteral(".."), QStringLiteral("I")},
        {QStringLiteral(".---"), QStringLiteral("J")},
        {QStringLiteral("-.-"), QStringLiteral("K")},
        {QStringLiteral(".-.."), QStringLiteral("L")},
        {QStringLiteral("--"), QStringLiteral("M")},
        {QStringLiteral("-."), QStringLiteral("N")},
        {QStringLiteral("---"), QStringLiteral("O")},
        {QStringLiteral(".--."), QStringLiteral("P")},
        {QStringLiteral("--.-"), QStringLiteral("Q")},
        {QStringLiteral(".-."), QStringLiteral("R")},
        {QStringLiteral("..."), QStringLiteral("S")},
        {QStringLiteral("-"), QStringLiteral("T")},
        {QStringLiteral("..-"), QStringLiteral("U")},
        {QStringLiteral("...-"), QStringLiteral("V")},
        {QStringLiteral(".--"), QStringLiteral("W")},
        {QStringLiteral("-..-"), QStringLiteral("X")},
        {QStringLiteral("-.--"), QStringLiteral("Y")},
        {QStringLiteral("--.."), QStringLiteral("Z")},
        {QStringLiteral(".----"), QStringLiteral("1")},
        {QStringLiteral("..---"), QStringLiteral("2")},
        {QStringLiteral("...--"), QStringLiteral("3")},
        {QStringLiteral("....-"), QStringLiteral("4")},
        {QStringLiteral("....."), QStringLiteral("5")},
        {QStringLiteral("-...."), QStringLiteral("6")},
        {QStringLiteral("--..."), QStringLiteral("7")},
        {QStringLiteral("---.."), QStringLiteral("8")},
        {QStringLiteral("----."), QStringLiteral("9")},
        {QStringLiteral("-----"), QStringLiteral("0")},
        {QStringLiteral(".-.-.-"), QStringLiteral(".")},
        {QStringLiteral("--..--"), QStringLiteral(",")},
        {QStringLiteral("..--.."), QStringLiteral("?")},
        {QStringLiteral("-..-."), QStringLiteral("/")},
        {QStringLiteral("-...-"), QStringLiteral("=")},
        {QStringLiteral(".--.-"), QStringLiteral("Á")},
        {QStringLiteral("..-.."), QStringLiteral("É")},
        {QStringLiteral("--.--"), QStringLiteral("Ñ")}
    };

    return table;
}

const QHash<QString, QString> &morseEncodeTable()
{
    static const QHash<QString, QString> table = [] {
        QHash<QString, QString> result;
        const auto &decode = morseDecodeTable();
        for (auto iterator = decode.constBegin();
             iterator != decode.constEnd();
             ++iterator) {
            result.insert(iterator.value(), iterator.key());
        }
        return result;
    }();

    return table;
}

QString uniqueDeviceName(const QString &base,
                         const QStringList &existing)
{
    if (!existing.contains(base)) {
        return base;
    }

    int suffix = 2;
    QString candidate;
    do {
        candidate = QStringLiteral("%1 (%2)").arg(base).arg(suffix);
        ++suffix;
    } while (existing.contains(candidate));

    return candidate;
}

double clampedDb(double value)
{
    return std::clamp(value, MinimumDb, 0.0);
}

int audioDevicePreferenceScore(const QAudioDevice &device)
{
    const QString name = device.description().trimmed().toLower();
    int score = 0;

    // Nombres habituales de la interfaz USB de la radio y de los
    // dispositivos C-Media usados como codec USB. El IC-7300MK2 del
    // usuario aparece en PipeWire como "C-Media ... USB Audio Device".
    if (name.contains(QStringLiteral("icom"))) {
        score += 100;
    }
    if (name.contains(QStringLiteral("7300"))) {
        score += 100;
    }
    if (name.contains(QStringLiteral("usb audio codec"))) {
        score += 80;
    }
    if (name.contains(QStringLiteral("usb audio device"))) {
        score += 70;
    }
    if (name.contains(QStringLiteral("c-media"))
        || name.contains(QStringLiteral("cmedia"))) {
        score += 60;
    }
    if (name.contains(QStringLiteral("usb"))) {
        score += 20;
    }

    // Evita preferir por accidente el micrófono integrado del portátil.
    if (name.contains(QStringLiteral("internal"))
        || name.contains(QStringLiteral("integrado"))
        || name.contains(QStringLiteral("dmic"))
        || name.contains(QStringLiteral("sof-hda"))) {
        score -= 40;
    }

    return score;
}

bool isLikelyRadioAudioDevice(const QAudioDevice &device)
{
    return audioDevicePreferenceScore(device) >= 60;
}

QString sampleFormatName(QAudioFormat::SampleFormat format)
{
    switch (format) {
    case QAudioFormat::UInt8:
        return QStringLiteral("UInt8");
    case QAudioFormat::Int16:
        return QStringLiteral("Int16");
    case QAudioFormat::Int32:
        return QStringLiteral("Int32");
    case QAudioFormat::Float:
        return QStringLiteral("Float");
    default:
        return QStringLiteral("desconocido");
    }
}
}

MorseTrainer::MorseTrainer(QObject *parent)
    : QObject(parent)
{
    const QString directory = dataDirectoryPath();
    QDir().mkpath(directory);
    m_statisticsFilePath =
        QDir(directory).filePath(QStringLiteral("morse_history.json"));

    m_receptionCountdownTimer.setInterval(1000);
    m_receptionCountdownTimer.setSingleShot(false);
    connect(
        &m_receptionCountdownTimer,
        &QTimer::timeout,
        this,
        &MorseTrainer::advanceReceptionCountdown
    );

    loadSettings();
    refreshAudioInputs();
    loadStatistics();
    createExercise();
}

MorseTrainer::~MorseTrainer()
{
    stopReceptionPlayback();
    stopCapture();
    saveSettings();
}

QStringList MorseTrainer::audioInputNames() const
{
    return m_audioInputNames;
}

int MorseTrainer::audioInputIndex() const
{
    return m_audioInputIndex;
}

bool MorseTrainer::capturing() const
{
    return m_capturing;
}

QString MorseTrainer::statusText() const
{
    return m_statusText;
}

double MorseTrainer::inputLevelDb() const
{
    return m_inputLevelDb;
}

double MorseTrainer::toneLevelDb() const
{
    return m_toneLevelDb;
}

double MorseTrainer::noiseFloorDb() const
{
    return m_noiseFloorDb;
}

bool MorseTrainer::keyDown() const
{
    return m_keyDown;
}

QString MorseTrainer::currentPattern() const
{
    return m_currentPattern;
}

QString MorseTrainer::decodedText() const
{
    return m_decodedText;
}

int MorseTrainer::toneFrequencyHz() const
{
    return m_toneFrequencyHz;
}

double MorseTrainer::thresholdDb() const
{
    return m_thresholdDb;
}

bool MorseTrainer::automaticThreshold() const
{
    return m_automaticThreshold;
}

int MorseTrainer::lesson() const
{
    return m_lesson;
}

int MorseTrainer::maximumLesson() const
{
    return std::max(1, int(kochSequence().size()) - 1);
}

QString MorseTrainer::lessonCharacters() const
{
    const int count = std::min(int(kochSequence().size()), m_lesson + 1);
    return kochSequence().mid(0, count).join(QStringLiteral(" "));
}

QString MorseTrainer::newestLessonCharacters() const
{
    const int count = std::min(int(kochSequence().size()), m_lesson + 1);
    const int first = std::max(0, count - 2);
    return kochSequence().mid(first, count - first).join(QStringLiteral(" "));
}

int MorseTrainer::characterWpm() const
{
    return m_characterWpm;
}

int MorseTrainer::effectiveWpm() const
{
    return m_effectiveWpm;
}

int MorseTrainer::groupSize() const
{
    return m_groupSize;
}

int MorseTrainer::exerciseGroups() const
{
    return m_exerciseGroups;
}

QString MorseTrainer::targetText() const
{
    return m_targetText;
}

int MorseTrainer::targetCharacterCount() const
{
    return normalizedForScoring(m_targetText).size();
}

bool MorseTrainer::exerciseActive() const
{
    return m_exerciseActive;
}

bool MorseTrainer::receptionPlaying() const
{
    return m_receptionPlaying || m_receptionCountdownActive;
}

bool MorseTrainer::receptionCountdownActive() const
{
    return m_receptionCountdownActive;
}

int MorseTrainer::receptionCountdownRemaining() const
{
    return m_receptionCountdownRemaining;
}

int MorseTrainer::receptionLeadInSeconds() const
{
    return m_receptionLeadInSeconds;
}

bool MorseTrainer::receptionExerciseActive() const
{
    return m_receptionExerciseActive;
}

bool MorseTrainer::receptionTargetRevealed() const
{
    return m_receptionTargetRevealed;
}

QString MorseTrainer::receptionTargetText() const
{
    return m_receptionTargetText;
}

int MorseTrainer::receptionTargetCharacterCount() const
{
    return normalizedForScoring(m_receptionTargetText).size();
}

QString MorseTrainer::receptionCopyText() const
{
    return m_receptionCopyText;
}

QString MorseTrainer::receptionStatusText() const
{
    return m_receptionStatusText;
}

QString MorseTrainer::receptionTargetComparisonHtml() const
{
    return m_receptionTargetComparisonHtml;
}

QString MorseTrainer::receptionCopyComparisonHtml() const
{
    return m_receptionCopyComparisonHtml;
}

double MorseTrainer::receptionAccuracy() const
{
    return m_receptionAccuracy;
}

double MorseTrainer::receptionScore() const
{
    return m_receptionScore;
}

int MorseTrainer::receptionCorrectCharacters() const
{
    return m_receptionCorrectCharacters;
}

int MorseTrainer::receptionErrorCount() const
{
    return m_receptionErrorCount;
}

bool MorseTrainer::referencePlaying() const
{
    return m_referencePlaying;
}

QString MorseTrainer::referenceSymbol() const
{
    return m_referenceSymbol;
}

double MorseTrainer::accuracy() const
{
    return m_accuracy;
}

double MorseTrainer::timingScore() const
{
    return m_timingScore;
}

double MorseTrainer::totalScore() const
{
    return m_totalScore;
}

int MorseTrainer::correctCharacters() const
{
    return m_correctCharacters;
}

int MorseTrainer::errorCount() const
{
    return m_errorCount;
}

int MorseTrainer::totalSessions() const
{
    return m_totalSessions;
}

double MorseTrainer::averageScore() const
{
    return m_averageScore;
}

double MorseTrainer::bestScore() const
{
    return m_bestScore;
}

int MorseTrainer::currentLessonSessions() const
{
    return m_currentLessonSessions;
}

double MorseTrainer::currentLessonBest() const
{
    return m_currentLessonBest;
}

double MorseTrainer::currentLessonAverage() const
{
    return m_currentLessonAverage;
}

bool MorseTrainer::currentLessonPassed() const
{
    return m_currentLessonPassed;
}

QVariantList MorseTrainer::recentSessions() const
{
    return m_recentSessions;
}

QVariantList MorseTrainer::lessonStatistics() const
{
    return m_lessonStatistics;
}

QString MorseTrainer::statisticsFilePath() const
{
    return m_statisticsFilePath;
}

void MorseTrainer::refreshAudioInputs()
{
    QByteArray previousId;
    if (m_audioInputIndex >= 0
        && m_audioInputIndex < m_audioInputDevices.size()) {
        previousId = m_audioInputDevices.at(m_audioInputIndex).id();
    }

    const bool restartCapture = m_capturing;
    if (restartCapture) {
        stopCapture();
    }

    QSettings settings;
    if (previousId.isEmpty()) {
        previousId = QByteArray::fromBase64(
            settings.value(QStringLiteral("morse/audioDeviceId")).toByteArray()
        );
    }

    m_audioInputDevices = QMediaDevices::audioInputs();
    m_audioInputNames.clear();

    for (const QAudioDevice &device : std::as_const(m_audioInputDevices)) {
        QString description = device.description().trimmed();
        if (description.isEmpty()) {
            description = QStringLiteral("Entrada de audio");
        }

        if (device.id() == QMediaDevices::defaultAudioInput().id()) {
            description += QStringLiteral(" · predeterminada");
        }

        m_audioInputNames.append(
            uniqueDeviceName(description, m_audioInputNames)
        );
    }

    int selected = -1;
    if (!previousId.isEmpty()) {
        for (int index = 0; index < m_audioInputDevices.size(); ++index) {
            if (m_audioInputDevices.at(index).id() == previousId) {
                selected = index;
                break;
            }
        }
    }

    // Busca siempre la entrada USB más probable. En versiones anteriores
    // "C-Media ... USB Audio Device" no se reconocía y podía quedar
    // seleccionado el micrófono interno guardado automáticamente.
    int preferredUsbIndex = -1;
    int preferredUsbScore = 0;
    for (int index = 0; index < m_audioInputDevices.size(); ++index) {
        const int score =
            audioDevicePreferenceScore(m_audioInputDevices.at(index));
        if (score > preferredUsbScore) {
            preferredUsbScore = score;
            preferredUsbIndex = index;
        }
    }

    if (preferredUsbIndex >= 0
        && (selected < 0
            || !isLikelyRadioAudioDevice(
                m_audioInputDevices.at(selected)))) {
        selected = preferredUsbIndex;
    }

    if (selected < 0 && !m_audioInputDevices.isEmpty()) {
        selected = 0;
    }

    const bool indexChanged = selected != m_audioInputIndex;
    m_audioInputIndex = selected;

    emit audioInputsChanged();
    if (indexChanged) {
        emit audioInputIndexChanged();
    }

    if (m_audioInputDevices.isEmpty()) {
        setStatusText(QStringLiteral("No hay entradas de audio disponibles"));
    } else if (!m_capturing) {
        setStatusText(
            QStringLiteral("Entrada seleccionada: %1 · pulse ESCUCHAR")
                .arg(m_audioInputNames.value(m_audioInputIndex))
        );
    }

    if (restartCapture && m_audioInputIndex >= 0) {
        startCapture();
    }
}

bool MorseTrainer::startCapture()
{
    if (m_capturing) {
        return true;
    }

    if (m_audioInputIndex < 0
        || m_audioInputIndex >= m_audioInputDevices.size()) {
        setStatusText(QStringLiteral("Seleccione una entrada de audio válida"));
        return false;
    }

    const QAudioDevice device =
        m_audioInputDevices.at(m_audioInputIndex);

    QAudioFormat requested;
    requested.setSampleRate(48000);
    requested.setChannelCount(1);
    requested.setSampleFormat(QAudioFormat::Int16);

    if (!device.isFormatSupported(requested)) {
        requested = device.preferredFormat();
    }

    if (!requested.isValid()
        || requested.sampleRate() <= 0
        || requested.channelCount() <= 0
        || requested.bytesPerFrame() <= 0) {
        setStatusText(QStringLiteral("El formato de audio del dispositivo no es válido"));
        return false;
    }

    m_audioFormat = requested;
    m_analysisFrameSamples = std::max(
        64,
        m_audioFormat.sampleRate() * AnalysisFrameMilliseconds / 1000
    );

    m_audioSource = new QAudioSource(device, m_audioFormat, this);
    const qint64 requestedBufferBytes = std::max<qint64>(
        m_audioFormat.bytesForDuration(200000),
        qint64(m_audioFormat.bytesPerFrame())
            * qint64(m_analysisFrameSamples) * 4
    );
    m_audioSource->setBufferSize(
        int(std::clamp<qint64>(requestedBufferBytes, 4096, INT_MAX))
    );

    connect(
        m_audioSource,
        &QAudioSource::stateChanged,
        this,
        [this](QAudio::State state) {
            handleAudioStateChanged(static_cast<int>(state));
        }
    );

    m_audioDevice = m_audioSource->start();
    if (m_audioDevice == nullptr) {
        setStatusText(QStringLiteral("No se pudo abrir la entrada de audio"));
        delete m_audioSource;
        m_audioSource = nullptr;
        return false;
    }

    connect(
        m_audioDevice,
        &QIODevice::readyRead,
        this,
        &MorseTrainer::processAudioData
    );

    resetDecoderState();
    m_captureClock.restart();
    m_capturing = true;
    QSettings settings;
    settings.setValue(
        QStringLiteral("morse/audioDeviceId"),
        m_audioInputDevices.at(m_audioInputIndex).id().toBase64()
    );
    setStatusText(
        QStringLiteral("Escuchando %1 Hz en %2 · %3 Hz, %4 canal(es), %5")
            .arg(m_toneFrequencyHz)
            .arg(m_audioInputNames.value(m_audioInputIndex))
            .arg(m_audioFormat.sampleRate())
            .arg(m_audioFormat.channelCount())
            .arg(sampleFormatName(m_audioFormat.sampleFormat()))
    );
    emit capturingChanged();
    return true;
}

void MorseTrainer::stopCapture()
{
    // QAudioSource posee el QIODevice devuelto por start(). En algunas
    // plataformas stop() puede cerrar o destruir ese dispositivo de forma
    // inmediata. Por ello se desconectan las señales y se anulan primero
    // los punteros miembro, evitando usar un QIODevice ya invalidado.
    if (m_stoppingCapture) {
        return;
    }

    m_stoppingCapture = true;

    const bool wasCapturing = m_capturing;
    m_capturing = false;

    QAudioSource *audioSource = m_audioSource;
    QIODevice *audioDevice = m_audioDevice;
    m_audioSource = nullptr;
    m_audioDevice = nullptr;

    if (audioDevice != nullptr) {
        disconnect(audioDevice, nullptr, this, nullptr);
    }

    if (audioSource != nullptr) {
        // Impide que StoppedState vuelva a entrar en código asociado a una
        // captura que ya estamos desmontando.
        disconnect(audioSource, nullptr, this, nullptr);
        audioSource->stop();
        audioSource->deleteLater();
    }

    resetDecoderState();
    setStatusText(QStringLiteral("Captura detenida"));

    if (wasCapturing) {
        emit capturingChanged();
    }

    m_stoppingCapture = false;
}

void MorseTrainer::createExercise()
{
    m_targetText = generateExerciseText();
    m_exerciseActive = true;
    clearAttempt();
    emit exerciseChanged();
}

void MorseTrainer::clearAttempt()
{
    m_currentPattern.clear();
    m_decodedText.clear();
    m_accuracy = 0.0;
    m_timingScore = 0.0;
    m_totalScore = 0.0;
    m_correctCharacters = 0;
    m_errorCount = 0;
    m_timingErrorSum = 0.0;
    m_timingErrorCount = 0;
    m_characterFinalizedForGap = false;
    m_wordSpaceFinalizedForGap = false;
    m_keyUpSinceMs = -1;

    emit attemptChanged();
    emit scoreChanged();
}

void MorseTrainer::finishExercise()
{
    if (!m_exerciseActive || m_targetText.trimmed().isEmpty()) {
        return;
    }

    if (!m_currentPattern.isEmpty()) {
        finalizeCurrentCharacter(false);
    }

    evaluateAttempt();

    SessionRecord record;
    record.timestamp = QDateTime::currentDateTime().toString(Qt::ISODate);
    record.lesson = m_lesson;
    record.characterWpm = m_characterWpm;
    record.effectiveWpm = m_effectiveWpm;
    record.target = m_targetText;
    record.decoded = m_decodedText.trimmed();
    record.accuracy = m_accuracy;
    record.timing = m_timingScore;
    record.total = m_totalScore;
    record.correct = m_correctCharacters;
    record.errors = m_errorCount;

    m_history.append(record);
    while (m_history.size() > 5000) {
        m_history.removeFirst();
    }

    m_exerciseActive = false;
    saveStatistics();
    rebuildStatistics();
    emit exerciseChanged();
}

void MorseTrainer::appendWordSpace()
{
    if (!m_currentPattern.isEmpty()) {
        finalizeCurrentCharacter(false);
    }

    if (!m_decodedText.isEmpty()
        && !m_decodedText.endsWith(QLatin1Char(' '))) {
        m_decodedText.append(QLatin1Char(' '));
        evaluateAttempt();
        emit attemptChanged();
    }
}

void MorseTrainer::removeLastDecodedCharacter()
{
    if (!m_currentPattern.isEmpty()) {
        m_currentPattern.chop(1);
    } else if (!m_decodedText.isEmpty()) {
        m_decodedText.chop(1);
    }

    evaluateAttempt();
    emit attemptChanged();
}

bool MorseTrainer::startReceptionExercise()
{
    stopCapture();
    stopReceptionPlayback();

    m_receptionTargetText = generateExerciseText();
    m_receptionCopyText.clear();
    m_receptionTargetComparisonHtml.clear();
    m_receptionCopyComparisonHtml.clear();
    m_receptionExerciseActive = true;
    m_receptionTargetRevealed = false;
    m_receptionAccuracy = 0.0;
    m_receptionScore = 0.0;
    m_receptionCorrectCharacters = 0;
    m_receptionErrorCount = 0;
    m_receptionStatusText = QStringLiteral(
        "Preparando el ejercicio de recepción…"
    );
    emit receptionChanged();
    emit receptionScoreChanged();

    return beginReceptionCountdown();
}

bool MorseTrainer::replayReceptionExercise()
{
    if (m_receptionTargetText.trimmed().isEmpty()) {
        return startReceptionExercise();
    }

    stopCapture();
    stopReceptionPlayback();
    m_receptionTargetRevealed = false;
    m_receptionExerciseActive = true;
    m_receptionStatusText = QStringLiteral("Repitiendo el ejercicio…");
    emit receptionChanged();
    return beginReceptionCountdown();
}

void MorseTrainer::stopReceptionPlayback()
{
    const bool wasBusy = m_receptionPlaying || m_receptionCountdownActive;
    const bool referenceWasPlaying = m_referencePlaying;
    cancelReceptionCountdown();
    releaseReceptionPlayback();

    if (referenceWasPlaying) {
        emit referencePlaybackChanged();
    }

    if (wasBusy) {
        m_receptionStatusText = QStringLiteral(
            "Reproducción detenida. Puede repetir o puntuar la copia."
        );
        emit receptionChanged();
    }
}

bool MorseTrainer::playReferenceSymbol(const QString &symbol)
{
    const QString normalized = symbol.trimmed().toUpper();
    if (!morseEncodeTable().contains(normalized)
        || receptionPlaying()) {
        return false;
    }

    stopReferencePlayback();
    return beginReferencePlayback(normalized);
}

void MorseTrainer::stopReferencePlayback()
{
    if (!m_referencePlaying) {
        return;
    }

    releaseReceptionPlayback();
    emit referencePlaybackChanged();
}

void MorseTrainer::clearReceptionCopy()
{
    if (m_receptionCopyText.isEmpty()
        && m_receptionAccuracy == 0.0
        && m_receptionErrorCount == 0) {
        return;
    }

    m_receptionCopyText.clear();
    m_receptionTargetComparisonHtml.clear();
    m_receptionCopyComparisonHtml.clear();
    m_receptionAccuracy = 0.0;
    m_receptionScore = 0.0;
    m_receptionCorrectCharacters = 0;
    m_receptionErrorCount = 0;
    emit receptionChanged();
    emit receptionScoreChanged();
}

void MorseTrainer::finishReceptionExercise()
{
    if (!m_receptionExerciseActive
        || m_receptionTargetText.trimmed().isEmpty()) {
        return;
    }

    stopReceptionPlayback();
    const ComparisonResult comparison = evaluateReceptionCopy();
    m_receptionExerciseActive = false;
    m_receptionTargetRevealed = true;
    m_receptionStatusText = QStringLiteral(
        "Resultado: %1/%2 correctos · %3 sustituciones · "
        "%4 omitidos · %5 añadidos. Los espacios entre grupos no puntúan. "
        "Después del último símbolo enviado no puede haber nuevos aciertos."
    )
        .arg(comparison.correct)
        .arg(comparison.targetCharacters)
        .arg(comparison.substitutions)
        .arg(comparison.omissions)
        .arg(comparison.extras);

    SessionRecord record;
    record.timestamp = QDateTime::currentDateTime().toString(Qt::ISODate);
    record.lesson = m_lesson;
    record.characterWpm = m_characterWpm;
    record.effectiveWpm = m_effectiveWpm;
    record.target = m_receptionTargetText;
    record.decoded = m_receptionCopyText.trimmed();
    record.mode = QStringLiteral("reception");
    record.accuracy = m_receptionAccuracy;
    record.timing = 0.0;
    record.total = m_receptionScore;
    record.correct = m_receptionCorrectCharacters;
    record.errors = m_receptionErrorCount;

    m_history.append(record);
    while (m_history.size() > 5000) {
        m_history.removeFirst();
    }

    saveStatistics();
    rebuildStatistics();
    emit receptionChanged();
}

void MorseTrainer::resetStatistics()
{
    m_history.clear();
    QFile::remove(m_statisticsFilePath);
    rebuildStatistics();
}

void MorseTrainer::resetCurrentLessonStatistics()
{
    const int selectedLesson = m_lesson;

    m_history.erase(
        std::remove_if(
            m_history.begin(),
            m_history.end(),
            [selectedLesson](const SessionRecord &record) {
                return record.lesson == selectedLesson;
            }
        ),
        m_history.end()
    );

    saveStatistics();
    rebuildStatistics();
}

void MorseTrainer::setAudioInputIndex(int index)
{
    index = std::clamp(index, -1, int(m_audioInputDevices.size()) - 1);
    if (index == m_audioInputIndex) {
        return;
    }

    const bool restart = m_capturing;
    if (restart) {
        stopCapture();
    }

    m_audioInputIndex = index;
    emit audioInputIndexChanged();

    if (index >= 0 && index < m_audioInputDevices.size()) {
        QSettings settings;
        settings.setValue(
            QStringLiteral("morse/audioDeviceId"),
            m_audioInputDevices.at(index).id().toBase64()
        );
    }

    if (restart) {
        startCapture();
    }
}

void MorseTrainer::setToneFrequencyHz(int frequencyHz)
{
    frequencyHz = std::clamp(frequencyHz, 300, 900);
    if (frequencyHz == m_toneFrequencyHz) {
        return;
    }

    m_toneFrequencyHz = frequencyHz;
    saveSettings();
    emit settingsChanged();

    if (m_capturing) {
        setStatusText(
            QStringLiteral("Escuchando tono CW de %1 Hz").arg(m_toneFrequencyHz)
        );
    }
}

void MorseTrainer::setThresholdDb(double thresholdDb)
{
    thresholdDb = std::clamp(thresholdDb, -80.0, -8.0);
    if (qFuzzyCompare(thresholdDb + 100.0, m_thresholdDb + 100.0)) {
        return;
    }

    m_thresholdDb = thresholdDb;
    saveSettings();
    emit settingsChanged();
}

void MorseTrainer::setAutomaticThreshold(bool enabled)
{
    if (enabled == m_automaticThreshold) {
        return;
    }

    m_automaticThreshold = enabled;
    saveSettings();
    emit settingsChanged();
}

void MorseTrainer::setLesson(int lessonValue)
{
    lessonValue = std::clamp(lessonValue, 1, maximumLesson());
    if (lessonValue == m_lesson) {
        return;
    }

    m_lesson = lessonValue;
    saveSettings();
    rebuildStatistics();
    emit trainingSettingsChanged();
    createExercise();
}

void MorseTrainer::setCharacterWpm(int wpm)
{
    wpm = std::clamp(wpm, 6, 60);
    if (wpm == m_characterWpm) {
        return;
    }

    m_characterWpm = wpm;
    if (m_effectiveWpm > m_characterWpm) {
        m_effectiveWpm = m_characterWpm;
    }
    saveSettings();
    emit trainingSettingsChanged();
}

void MorseTrainer::setEffectiveWpm(int wpm)
{
    wpm = std::clamp(wpm, 5, m_characterWpm);
    if (wpm == m_effectiveWpm) {
        return;
    }

    m_effectiveWpm = wpm;
    saveSettings();
    emit trainingSettingsChanged();
}

void MorseTrainer::setGroupSize(int size)
{
    size = std::clamp(size, 1, 10);
    if (size == m_groupSize) {
        return;
    }

    m_groupSize = size;
    saveSettings();
    emit trainingSettingsChanged();
}

void MorseTrainer::setExerciseGroups(int groups)
{
    groups = std::clamp(groups, 1, 20);
    if (groups == m_exerciseGroups) {
        return;
    }

    m_exerciseGroups = groups;
    saveSettings();
    emit trainingSettingsChanged();
}

void MorseTrainer::setReceptionLeadInSeconds(int seconds)
{
    seconds = std::clamp(seconds, 0, 10);
    if (seconds == m_receptionLeadInSeconds) {
        return;
    }

    m_receptionLeadInSeconds = seconds;
    saveSettings();
    emit trainingSettingsChanged();
}

void MorseTrainer::setReceptionCopyText(const QString &text)
{
    QString cleaned = text.toUpper();
    if (cleaned.size() > 4000) {
        cleaned.truncate(4000);
    }

    if (cleaned == m_receptionCopyText) {
        return;
    }

    m_receptionCopyText = cleaned;
    emit receptionChanged();
}

void MorseTrainer::processAudioData()
{
    if (m_audioDevice == nullptr) {
        return;
    }

    consumeAudioBytes(m_audioDevice->readAll());
}

void MorseTrainer::handleAudioStateChanged(int state)
{
    if (m_audioSource == nullptr) {
        return;
    }

    const auto audioState = static_cast<QAudio::State>(state);
    if (audioState == QAudio::StoppedState
        && m_audioSource->error() != QAudio::NoError
        && m_capturing) {
        setStatusText(
            QStringLiteral("Error de captura de audio (%1)")
                .arg(static_cast<int>(m_audioSource->error()))
        );
    }
}

void MorseTrainer::setStatusText(const QString &text)
{
    if (text == m_statusText) {
        return;
    }

    m_statusText = text;
    emit statusTextChanged();
}

void MorseTrainer::resetDecoderState()
{
    m_pendingBytes.clear();
    m_analysisSamples.clear();
    m_inputLevelDb = MinimumDb;
    m_toneLevelDb = MinimumDb;
    m_noiseFloorDb = -70.0;
    m_keyDown = false;
    m_candidateKeyDown = false;
    m_candidateSinceMs = 0;
    m_keyDownSinceMs = 0;
    m_keyUpSinceMs = -1;
    m_characterFinalizedForGap = false;
    m_wordSpaceFinalizedForGap = false;
    m_lastLevelsSignalMs = 0;
    m_processedAudioSamples = 0;
    emit levelsChanged();
    emit keyDownChanged();
}

void MorseTrainer::consumeAudioBytes(const QByteArray &bytes)
{
    if (bytes.isEmpty() || !m_audioFormat.isValid()) {
        return;
    }

    m_pendingBytes.append(bytes);
    const int bytesPerFrame = m_audioFormat.bytesPerFrame();
    if (bytesPerFrame <= 0) {
        return;
    }

    const int completeBytes =
        (m_pendingBytes.size() / bytesPerFrame) * bytesPerFrame;
    if (completeBytes <= 0) {
        return;
    }

    const char *data = m_pendingBytes.constData();
    const int channels = m_audioFormat.channelCount();

    for (int offset = 0; offset < completeBytes; offset += bytesPerFrame) {
        double mono = 0.0;
        for (int channel = 0; channel < channels; ++channel) {
            mono += decodeSample(data + offset, channel);
        }
        mono /= std::max(1, channels);
        m_analysisSamples.append(mono);
    }

    m_pendingBytes.remove(0, completeBytes);

    while (m_analysisSamples.size() >= m_analysisFrameSamples) {
        QVector<double> frame;
        frame.reserve(m_analysisFrameSamples);
        for (int index = 0; index < m_analysisFrameSamples; ++index) {
            frame.append(m_analysisSamples.at(index));
        }
        m_analysisSamples.remove(0, m_analysisFrameSamples);
        analyzeFrame(frame);
    }
}

void MorseTrainer::analyzeFrame(const QVector<double> &samples)
{
    if (samples.isEmpty() || !m_captureClock.isValid()) {
        return;
    }

    double mean = 0.0;
    for (double sample : samples) {
        mean += sample;
    }
    mean /= samples.size();

    const double sampleRate = m_audioFormat.sampleRate();
    const double angularStep =
        2.0 * std::numbers::pi * m_toneFrequencyHz / sampleRate;

    double sumSquares = 0.0;
    double inPhase = 0.0;
    double quadrature = 0.0;

    for (int index = 0; index < samples.size(); ++index) {
        const double sample = samples.at(index) - mean;
        const double angle = angularStep * index;
        sumSquares += sample * sample;
        inPhase += sample * std::cos(angle);
        quadrature -= sample * std::sin(angle);
    }

    const double rms = std::sqrt(sumSquares / samples.size());
    const double amplitude =
        2.0 * std::sqrt(inPhase * inPhase + quadrature * quadrature)
        / samples.size();

    m_inputLevelDb = clampedDb(20.0 * std::log10(std::max(rms, 1.0e-9)));
    m_toneLevelDb = clampedDb(20.0 * std::log10(std::max(amplitude, 1.0e-9)));

    const double purity = amplitude / std::max(rms, 1.0e-9);

    // La entrada USB/ALSA suele entregar el audio en bloques grandes
    // (por ejemplo, periodos de 125 ms). No se puede usar el reloj de
    // pared mientras se recorren los fotogramas del bloque: todos se
    // procesan casi en el mismo instante y un punto de 60 ms termina
    // midiendo 125 ms o más, por lo que se clasifica erróneamente como
    // raya. El tiempo del decodificador debe avanzar con las muestras
    // de audio realmente consumidas.
    m_processedAudioSamples += samples.size();
    const qint64 now = static_cast<qint64>(std::llround(
        1000.0 * static_cast<double>(m_processedAudioSamples)
        / sampleRate));

    const double activeThreshold = m_automaticThreshold
        ? std::clamp(m_noiseFloorDb + 13.0, -65.0, -18.0)
        : m_thresholdDb;

    const double hysteresisThreshold =
        m_keyDown ? activeThreshold - 4.0 : activeThreshold;
    const double minimumPurity = m_keyDown ? 0.35 : 0.55;
    const bool detected =
        m_toneLevelDb >= hysteresisThreshold && purity >= minimumPurity;

    if (!m_keyDown && !detected) {
        m_noiseFloorDb = std::clamp(
            m_noiseFloorDb * 0.985 + m_toneLevelDb * 0.015,
            MinimumDb,
            -8.0
        );
    }

    updateToneState(detected, now);
    processIdleGap(now);

    if (now - m_lastLevelsSignalMs >= 40) {
        m_lastLevelsSignalMs = now;
        emit levelsChanged();
    }
}

double MorseTrainer::decodeSample(const char *frameData, int channel) const
{
    const int bytesPerSample = m_audioFormat.bytesPerSample();
    const char *sampleData = frameData + channel * bytesPerSample;

    switch (m_audioFormat.sampleFormat()) {
    case QAudioFormat::UInt8: {
        const quint8 value = static_cast<quint8>(*sampleData);
        return (static_cast<double>(value) - 128.0) / 128.0;
    }
    case QAudioFormat::Int16: {
        qint16 value = 0;
        std::memcpy(&value, sampleData, sizeof(value));
        return static_cast<double>(value) / 32768.0;
    }
    case QAudioFormat::Int32: {
        qint32 value = 0;
        std::memcpy(&value, sampleData, sizeof(value));
        return static_cast<double>(value) / 2147483648.0;
    }
    case QAudioFormat::Float: {
        float value = 0.0F;
        std::memcpy(&value, sampleData, sizeof(value));
        return std::clamp(static_cast<double>(value), -1.0, 1.0);
    }
    default:
        return 0.0;
    }
}

void MorseTrainer::updateToneState(bool detected, qint64 timestampMs)
{
    if (detected != m_candidateKeyDown) {
        m_candidateKeyDown = detected;
        m_candidateSinceMs = timestampMs;
        return;
    }

    if (m_candidateKeyDown == m_keyDown) {
        return;
    }

    if (timestampMs - m_candidateSinceMs < DebounceMilliseconds) {
        return;
    }

    transitionKeyState(m_candidateKeyDown, timestampMs);
}

void MorseTrainer::transitionKeyState(bool down, qint64 timestampMs)
{
    if (down == m_keyDown) {
        return;
    }

    if (down) {
        const qint64 gap = m_keyUpSinceMs >= 0
            ? timestampMs - m_keyUpSinceMs
            : -1;

        processIdleGap(timestampMs);

        if (gap > 0) {
            double expectedGap = dotMilliseconds();
            if (m_wordSpaceFinalizedForGap) {
                expectedGap = wordGapMilliseconds();
            } else if (m_characterFinalizedForGap) {
                expectedGap = characterGapMilliseconds();
            }
            recordTimingError(static_cast<double>(gap), expectedGap);
        }

        m_keyDownSinceMs = timestampMs;
    } else {
        const qint64 duration =
            std::max<qint64>(1, timestampMs - m_keyDownSinceMs);
        appendElement(duration);
        m_keyUpSinceMs = timestampMs;
        m_characterFinalizedForGap = false;
        m_wordSpaceFinalizedForGap = false;
    }

    m_keyDown = down;
    emit keyDownChanged();
}

void MorseTrainer::processIdleGap(qint64 timestampMs)
{
    if (m_keyDown || m_keyUpSinceMs < 0) {
        return;
    }

    const qint64 gap = timestampMs - m_keyUpSinceMs;

    if (!m_characterFinalizedForGap
        && !m_currentPattern.isEmpty()
        && gap >= characterBoundaryMilliseconds()) {
        finalizeCurrentCharacter(false);
        m_characterFinalizedForGap = true;
    }

    if (m_characterFinalizedForGap
        && !m_wordSpaceFinalizedForGap
        && gap >= wordBoundaryMilliseconds()) {
        if (!m_decodedText.isEmpty()
            && !m_decodedText.endsWith(QLatin1Char(' '))) {
            m_decodedText.append(QLatin1Char(' '));
            evaluateAttempt();
            emit attemptChanged();
        }
        m_wordSpaceFinalizedForGap = true;
    }
}

void MorseTrainer::appendElement(qint64 durationMs)
{
    const double dot = dotMilliseconds();
    const bool dash = durationMs >= dot * 2.0;
    const double expected = dash ? dot * 3.0 : dot;

    m_currentPattern.append(dash ? QLatin1Char('-') : QLatin1Char('.'));
    if (m_currentPattern.size() > 8) {
        m_currentPattern = QStringLiteral("????????");
    }

    recordTimingError(static_cast<double>(durationMs), expected);

    evaluateAttempt();
    emit attemptChanged();
}

void MorseTrainer::recordTimingError(double actualMs, double expectedMs)
{
    if (actualMs <= 0.0 || expectedMs <= 0.0) {
        return;
    }

    const double relativeError =
        std::abs(actualMs - expectedMs) / expectedMs;
    m_timingErrorSum += std::min(1.5, relativeError);
    ++m_timingErrorCount;
}

void MorseTrainer::finalizeCurrentCharacter(bool appendSpace)
{
    if (m_currentPattern.isEmpty()) {
        return;
    }

    const QString decoded = decodePattern(m_currentPattern);
    m_currentPattern.clear();
    appendDecodedCharacter(decoded);

    if (appendSpace
        && !m_decodedText.endsWith(QLatin1Char(' '))) {
        m_decodedText.append(QLatin1Char(' '));
    }

    evaluateAttempt();
    emit attemptChanged();
}

void MorseTrainer::appendDecodedCharacter(const QString &character)
{
    m_decodedText.append(character.isEmpty()
                             ? QStringLiteral("□")
                             : character);
}

double MorseTrainer::dotMilliseconds() const
{
    return 1200.0 / std::max(1, m_characterWpm);
}

double MorseTrainer::farnsworthSpacingFactor() const
{
    if (m_effectiveWpm >= m_characterWpm) {
        return 1.0;
    }

    const double factor =
        (50.0 * static_cast<double>(m_characterWpm)
             / static_cast<double>(m_effectiveWpm)
         - 31.0)
        / 19.0;
    return std::max(1.0, factor);
}

double MorseTrainer::characterGapMilliseconds() const
{
    return 3.0 * dotMilliseconds() * farnsworthSpacingFactor();
}

double MorseTrainer::wordGapMilliseconds() const
{
    return 7.0 * dotMilliseconds() * farnsworthSpacingFactor();
}

double MorseTrainer::characterBoundaryMilliseconds() const
{
    // La frontera de decodificación no se alarga con Farnsworth. Así una
    // letra enviada con el espaciado Morse normal se reconoce y la falta de
    // separación Farnsworth se refleja en la puntuación, en vez de unir dos
    // letras accidentalmente.
    return 2.2 * dotMilliseconds();
}

double MorseTrainer::wordBoundaryMilliseconds() const
{
    // Punto medio entre la separación esperada de carácter y palabra.
    return 0.5 * (characterGapMilliseconds() + wordGapMilliseconds());
}

QString MorseTrainer::decodePattern(const QString &pattern) const
{
    return morseDecodeTable().value(pattern, QStringLiteral("□"));
}

QString MorseTrainer::normalizedForScoring(const QString &text) const
{
    QString normalized;
    normalized.reserve(text.size());

    for (const QChar character : text.toUpper()) {
        if (!character.isSpace()) {
            normalized.append(character);
        }
    }

    return normalized;
}

MorseTrainer::ComparisonResult MorseTrainer::compareForScoring(
    const QString &targetText,
    const QString &copiedText
) const
{
    const QString target = normalizedForScoring(targetText);
    const QString copied = normalizedForScoring(copiedText);

    enum class AlignmentStep : quint8 {
        None,
        Match,
        Substitution,
        Omission,
        Extra
    };

    struct Cell {
        int cost = 0;
        int correct = 0;
        int substitutions = 0;
        int omissions = 0;
        int extras = 0;
    };

    auto isBetter = [](const Cell &candidate, const Cell &current) {
        if (candidate.cost != current.cost) {
            return candidate.cost < current.cost;
        }
        if (candidate.correct != current.correct) {
            return candidate.correct > current.correct;
        }
        if (candidate.substitutions != current.substitutions) {
            return candidate.substitutions > current.substitutions;
        }
        if (candidate.omissions != current.omissions) {
            return candidate.omissions < current.omissions;
        }
        return candidate.extras < current.extras;
    };

    QVector<Cell> previous(copied.size() + 1);
    QVector<Cell> current(copied.size() + 1);
    QVector<QVector<AlignmentStep>> alignment(
        target.size() + 1,
        QVector<AlignmentStep>(copied.size() + 1, AlignmentStep::None)
    );

    for (int column = 1; column <= copied.size(); ++column) {
        previous[column] = previous[column - 1];
        ++previous[column].cost;
        ++previous[column].extras;
        alignment[0][column] = AlignmentStep::Extra;
    }

    for (int row = 1; row <= target.size(); ++row) {
        current[0] = previous[0];
        ++current[0].cost;
        ++current[0].omissions;
        alignment[row][0] = AlignmentStep::Omission;

        for (int column = 1; column <= copied.size(); ++column) {
            // El ejercicio contiene exactamente target.size() símbolos.
            // Cualquier carácter escrito después de esa posición temporal
            // pertenece ya a una zona en la que no se transmitió ningún
            // símbolo y, por tanto, debe ser siempre un añadido/error.
            //
            // Sin esta restricción, la distancia de edición podía desplazar
            // una coincidencia tardía hacia atrás y mostrar, por ejemplo,
            // el carácter 26 como correcto en un ejercicio de 25 símbolos.
            if (column > target.size()) {
                Cell extra = current[column - 1];
                ++extra.cost;
                ++extra.extras;
                current[column] = extra;
                alignment[row][column] = AlignmentStep::Extra;
                continue;
            }

            Cell diagonal = previous[column - 1];
            AlignmentStep bestStep = AlignmentStep::Match;
            if (target.at(row - 1) == copied.at(column - 1)) {
                ++diagonal.correct;
            } else {
                ++diagonal.cost;
                ++diagonal.substitutions;
                bestStep = AlignmentStep::Substitution;
            }

            Cell omission = previous[column];
            ++omission.cost;
            ++omission.omissions;

            Cell extra = current[column - 1];
            ++extra.cost;
            ++extra.extras;

            Cell best = diagonal;
            if (isBetter(omission, best)) {
                best = omission;
                bestStep = AlignmentStep::Omission;
            }
            if (isBetter(extra, best)) {
                best = extra;
                bestStep = AlignmentStep::Extra;
            }

            current[column] = best;
            alignment[row][column] = bestStep;
        }

        previous.swap(current);
    }

    const Cell finalCell = previous.at(copied.size());

    ComparisonResult result;
    result.targetCharacters = target.size();
    result.copiedCharacters = copied.size();
    result.correct = finalCell.correct;
    result.substitutions = finalCell.substitutions;
    result.omissions = finalCell.omissions;
    result.extras = finalCell.extras;
    result.errors = finalCell.cost;

    if (result.targetCharacters > 0) {
        result.accuracy = std::clamp(
            100.0
                * (1.0 - static_cast<double>(result.errors)
                             / static_cast<double>(result.targetCharacters)),
            0.0,
            100.0
        );
    }

    struct AlignedCharacter {
        QChar targetCharacter;
        QChar copiedCharacter;
        bool targetPresent = false;
        bool copiedPresent = false;
        bool correct = false;
    };

    QVector<AlignedCharacter> aligned;
    aligned.reserve(target.size() + copied.size());

    int row = target.size();
    int column = copied.size();
    while (row > 0 || column > 0) {
        AlignmentStep step = alignment[row][column];
        if (row == 0) {
            step = AlignmentStep::Extra;
        } else if (column == 0) {
            step = AlignmentStep::Omission;
        }

        AlignedCharacter character;
        switch (step) {
        case AlignmentStep::Match:
            character.targetCharacter = target.at(row - 1);
            character.copiedCharacter = copied.at(column - 1);
            character.targetPresent = true;
            character.copiedPresent = true;
            character.correct = true;
            --row;
            --column;
            break;
        case AlignmentStep::Substitution:
            character.targetCharacter = target.at(row - 1);
            character.copiedCharacter = copied.at(column - 1);
            character.targetPresent = true;
            character.copiedPresent = true;
            --row;
            --column;
            break;
        case AlignmentStep::Omission:
            character.targetCharacter = target.at(row - 1);
            character.targetPresent = true;
            --row;
            break;
        case AlignmentStep::Extra:
            character.copiedCharacter = copied.at(column - 1);
            character.copiedPresent = true;
            --column;
            break;
        case AlignmentStep::None:
            // Protección ante una matriz incompleta: avanzar por el borde.
            if (row > 0) {
                character.targetCharacter = target.at(row - 1);
                character.targetPresent = true;
                --row;
            } else {
                character.copiedCharacter = copied.at(column - 1);
                character.copiedPresent = true;
                --column;
            }
            break;
        }
        aligned.append(character);
    }
    std::reverse(aligned.begin(), aligned.end());

    const QString correctTargetColor = QStringLiteral("#f7df86");
    const QString correctCopyColor = QStringLiteral("#75e69b");
    const QString errorColor = QStringLiteral("#ff5f5f");
    const QString placeholder = QStringLiteral("·");

    auto coloredCharacter = [](const QString &character,
                               const QString &color) {
        return QStringLiteral(
            "<span style=\"color:%1;\">%2</span>"
        ).arg(color, character.toHtmlEscaped());
    };

    QString targetHtml;
    QString copyHtml;
    targetHtml.reserve(aligned.size() * 52);
    copyHtml.reserve(aligned.size() * 52);

    for (int index = 0; index < aligned.size(); ++index) {
        const AlignedCharacter &character = aligned.at(index);
        const bool error = !character.correct;
        const QString targetCharacter = character.targetPresent
            ? QString(1, character.targetCharacter)
            : placeholder;
        const QString copiedCharacter = character.copiedPresent
            ? QString(1, character.copiedCharacter)
            : placeholder;

        targetHtml += coloredCharacter(
            targetCharacter,
            error ? errorColor : correctTargetColor
        );
        copyHtml += coloredCharacter(
            copiedCharacter,
            error ? errorColor : correctCopyColor
        );

        // Separa visualmente la comparación en grupos, pero mantiene ambas
        // líneas exactamente alineadas incluso con omisiones o añadidos.
        if (m_groupSize > 0
            && (index + 1) % m_groupSize == 0
            && index + 1 < aligned.size()) {
            targetHtml += QStringLiteral("&nbsp;");
            copyHtml += QStringLiteral("&nbsp;");
        }
    }

    result.targetComparisonHtml = targetHtml;
    result.copyComparisonHtml = copyHtml;
    return result;
}

void MorseTrainer::evaluateAttempt()
{
    const ComparisonResult comparison = compareForScoring(
        m_targetText,
        m_decodedText
    );

    m_accuracy = comparison.accuracy;
    m_correctCharacters = comparison.correct;
    m_errorCount = comparison.errors;

    if (m_timingErrorCount > 0) {
        const double averageError =
            m_timingErrorSum / m_timingErrorCount;
        m_timingScore = std::clamp(
            100.0 * (1.0 - std::min(1.0, averageError)),
            0.0,
            100.0
        );
        m_totalScore = m_accuracy * 0.80 + m_timingScore * 0.20;
    } else {
        // Sin muestras válidas de duración no debe aplicarse un 20 % de
        // puntuación cero: la nota coincide con la precisión de caracteres.
        m_timingScore = 0.0;
        m_totalScore = m_accuracy;
    }

    emit scoreChanged();
}

MorseTrainer::ComparisonResult MorseTrainer::evaluateReceptionCopy()
{
    const ComparisonResult comparison = compareForScoring(
        m_receptionTargetText,
        m_receptionCopyText
    );

    m_receptionAccuracy = comparison.accuracy;
    m_receptionCorrectCharacters = comparison.correct;
    m_receptionErrorCount = comparison.errors;
    m_receptionScore = m_receptionAccuracy;
    m_receptionTargetComparisonHtml = comparison.targetComparisonHtml;
    m_receptionCopyComparisonHtml = comparison.copyComparisonHtml;
    emit receptionScoreChanged();

    return comparison;
}

QByteArray MorseTrainer::generateMorseAudio(
    const QString &text,
    const QAudioFormat &format,
    double leadingSilenceMilliseconds,
    double trailingSilenceMilliseconds
) const
{
    QByteArray audio;
    if (!format.isValid()
        || format.sampleRate() <= 0
        || format.channelCount() <= 0) {
        return audio;
    }

    const int sampleRate = format.sampleRate();
    const int channels = format.channelCount();
    const auto sampleFormat = format.sampleFormat();
    if (sampleFormat == QAudioFormat::Unknown) {
        return audio;
    }

    double phase = 0.0;
    const double phaseStep =
        2.0 * std::numbers::pi * m_toneFrequencyHz / sampleRate;

    auto appendFrame = [&](double normalizedSample) {
        normalizedSample = std::clamp(normalizedSample, -1.0, 1.0);
        for (int channel = 0; channel < channels; ++channel) {
            switch (sampleFormat) {
            case QAudioFormat::UInt8: {
                const quint8 value = static_cast<quint8>(std::clamp(
                    128.0 + normalizedSample * 127.0,
                    0.0,
                    255.0
                ));
                audio.append(reinterpret_cast<const char *>(&value),
                             sizeof(value));
                break;
            }
            case QAudioFormat::Int16: {
                const qint16 value = static_cast<qint16>(
                    normalizedSample
                    * static_cast<double>(std::numeric_limits<qint16>::max())
                );
                audio.append(reinterpret_cast<const char *>(&value),
                             sizeof(value));
                break;
            }
            case QAudioFormat::Int32: {
                const qint32 value = static_cast<qint32>(
                    normalizedSample
                    * static_cast<double>(std::numeric_limits<qint32>::max())
                );
                audio.append(reinterpret_cast<const char *>(&value),
                             sizeof(value));
                break;
            }
            case QAudioFormat::Float: {
                const float value = static_cast<float>(normalizedSample);
                audio.append(reinterpret_cast<const char *>(&value),
                             sizeof(value));
                break;
            }
            default:
                break;
            }
        }
    };

    auto appendSilence = [&](double milliseconds) {
        const int count = std::max(
            0,
            static_cast<int>(std::llround(
                milliseconds * sampleRate / 1000.0
            ))
        );
        for (int index = 0; index < count; ++index) {
            appendFrame(0.0);
        }
    };

    auto appendTone = [&](double milliseconds) {
        const int count = std::max(
            1,
            static_cast<int>(std::llround(
                milliseconds * sampleRate / 1000.0
            ))
        );
        const int rampSamples = std::min(
            count / 2,
            std::max(1, sampleRate / 200)
        );

        for (int index = 0; index < count; ++index) {
            double envelope = 1.0;
            if (index < rampSamples) {
                envelope = 0.5 - 0.5 * std::cos(
                    std::numbers::pi * index / rampSamples
                );
            } else if (index >= count - rampSamples) {
                const int remaining = count - 1 - index;
                envelope = 0.5 - 0.5 * std::cos(
                    std::numbers::pi * remaining / rampSamples
                );
            }

            appendFrame(0.34 * envelope * std::sin(phase));
            phase += phaseStep;
            if (phase >= 2.0 * std::numbers::pi) {
                phase -= 2.0 * std::numbers::pi;
            }
        }
    };

    const double dot = dotMilliseconds();
    const QStringList words = text.toUpper().split(
        QRegularExpression(QStringLiteral("\\s+")),
        Qt::SkipEmptyParts
    );

    appendSilence(std::max(0.0, leadingSilenceMilliseconds));
    for (int wordIndex = 0; wordIndex < words.size(); ++wordIndex) {
        const QString word = words.at(wordIndex);
        for (int characterIndex = 0;
             characterIndex < word.size();
             ++characterIndex) {
            const QString character(word.at(characterIndex));
            const QString pattern = morseEncodeTable().value(character);
            if (pattern.isEmpty()) {
                continue;
            }

            for (int elementIndex = 0;
                 elementIndex < pattern.size();
                 ++elementIndex) {
                appendTone(pattern.at(elementIndex) == QLatin1Char('-')
                           ? 3.0 * dot
                           : dot);
                if (elementIndex + 1 < pattern.size()) {
                    appendSilence(dot);
                }
            }

            if (characterIndex + 1 < word.size()) {
                appendSilence(characterGapMilliseconds());
            }
        }

        if (wordIndex + 1 < words.size()) {
            appendSilence(wordGapMilliseconds());
        }
    }
    appendSilence(std::max(0.0, trailingSilenceMilliseconds));
    return audio;
}

bool MorseTrainer::beginReceptionCountdown()
{
    cancelReceptionCountdown();

    // La salida de audio se abre al comenzar la cuenta atrás, no al terminarla.
    // De este modo PipeWire/PulseAudio/ALSA tienen tiempo para reactivar el
    // dispositivo y estabilizar su nivel antes del primer punto o raya.
    const double requestedLeadInMilliseconds =
        std::max(0, m_receptionLeadInSeconds) * 1000.0;
    const double audioWarmUpMilliseconds = std::max(
        1200.0,
        requestedLeadInMilliseconds
    );

    if (!beginReceptionPlayback(audioWarmUpMilliseconds)) {
        return false;
    }

    if (m_receptionLeadInSeconds <= 0) {
        m_receptionStatusText = QStringLiteral(
            "Activando la salida de audio. La señal comienza enseguida."
        );
        emit receptionChanged();
        return true;
    }

    m_receptionCountdownActive = true;
    m_receptionCountdownRemaining = m_receptionLeadInSeconds;
    m_receptionStatusText = QStringLiteral(
        "Comienza en %1 s. Activando audio; prepare el lápiz o el teclado."
    ).arg(m_receptionCountdownRemaining);
    m_receptionCountdownTimer.start();
    emit receptionChanged();
    return true;
}

void MorseTrainer::advanceReceptionCountdown()
{
    if (!m_receptionCountdownActive) {
        m_receptionCountdownTimer.stop();
        return;
    }

    if (m_receptionCountdownRemaining > 1) {
        --m_receptionCountdownRemaining;
        m_receptionStatusText = QStringLiteral(
            "Comienza en %1 s. Suelte el ratón y prepare el lápiz o el teclado."
        ).arg(m_receptionCountdownRemaining);
        emit receptionChanged();
        return;
    }

    cancelReceptionCountdown();
    if (m_audioSink != nullptr && m_receptionPlaying) {
        m_receptionStatusText = QStringLiteral(
            "Reproduciendo: copie de oído sin mirar el texto."
        );
    } else {
        m_receptionStatusText = QStringLiteral(
            "No se pudo mantener preparada la salida de audio."
        );
    }
    emit receptionChanged();
}

void MorseTrainer::cancelReceptionCountdown()
{
    m_receptionCountdownTimer.stop();
    m_receptionCountdownActive = false;
    m_receptionCountdownRemaining = 0;
}

bool MorseTrainer::beginReceptionPlayback(
    double leadingSilenceMilliseconds
)
{
    const QAudioDevice outputDevice = QMediaDevices::defaultAudioOutput();
    if (outputDevice.isNull()) {
        m_receptionStatusText = QStringLiteral(
            "No hay una salida de audio disponible en el sistema."
        );
        emit receptionChanged();
        return false;
    }

    QAudioFormat format;
    format.setSampleRate(48000);
    format.setChannelCount(1);
    format.setSampleFormat(QAudioFormat::Int16);
    if (!outputDevice.isFormatSupported(format)) {
        format = outputDevice.preferredFormat();
    }

    m_playbackData = generateMorseAudio(
        m_receptionTargetText,
        format,
        leadingSilenceMilliseconds,
        220.0
    );
    if (m_playbackData.isEmpty()) {
        m_receptionStatusText = QStringLiteral(
            "No se pudo generar el audio del ejercicio."
        );
        emit receptionChanged();
        return false;
    }

    m_playbackBuffer = new QBuffer(this);
    m_playbackBuffer->setData(m_playbackData);
    if (!m_playbackBuffer->open(QIODevice::ReadOnly)) {
        m_receptionStatusText = QStringLiteral(
            "No se pudo abrir el audio generado."
        );
        releaseReceptionPlayback();
        emit receptionChanged();
        return false;
    }

    m_audioSink = new QAudioSink(outputDevice, format, this);
    m_audioSink->setVolume(0.72);
    connect(
        m_audioSink,
        &QAudioSink::stateChanged,
        this,
        [this](QAudio::State state) {
            handleReceptionPlaybackState(static_cast<int>(state));
        }
    );

    m_receptionPlaying = true;
    if (!m_receptionCountdownActive) {
        m_receptionStatusText = QStringLiteral(
            "Preparando la salida de audio…"
        );
    }
    emit receptionChanged();
    m_audioSink->start(m_playbackBuffer);
    return true;
}

bool MorseTrainer::beginReferencePlayback(const QString &symbol)
{
    const QAudioDevice outputDevice = QMediaDevices::defaultAudioOutput();
    if (outputDevice.isNull()) {
        return false;
    }

    QAudioFormat format;
    format.setSampleRate(48000);
    format.setChannelCount(1);
    format.setSampleFormat(QAudioFormat::Int16);
    if (!outputDevice.isFormatSupported(format)) {
        format = outputDevice.preferredFormat();
    }

    // Los símbolos de prueba también llevan un preámbulo suficiente para
    // evitar que la reactivación de la salida recorte su primer elemento.
    m_playbackData = generateMorseAudio(symbol, format, 900.0, 180.0);
    if (m_playbackData.isEmpty()) {
        return false;
    }

    m_playbackBuffer = new QBuffer(this);
    m_playbackBuffer->setData(m_playbackData);
    if (!m_playbackBuffer->open(QIODevice::ReadOnly)) {
        releaseReceptionPlayback();
        return false;
    }

    m_audioSink = new QAudioSink(outputDevice, format, this);
    m_audioSink->setVolume(0.72);
    connect(
        m_audioSink,
        &QAudioSink::stateChanged,
        this,
        [this](QAudio::State state) {
            handleReceptionPlaybackState(static_cast<int>(state));
        }
    );

    m_referencePlaying = true;
    m_referenceSymbol = symbol;
    emit referencePlaybackChanged();
    m_audioSink->start(m_playbackBuffer);
    return true;
}

void MorseTrainer::handleReceptionPlaybackState(int state)
{
    if (m_audioSink == nullptr) {
        return;
    }

    const auto audioState = static_cast<QAudio::State>(state);
    if (audioState == QAudio::IdleState) {
        const bool referenceWasPlaying = m_referencePlaying;
        cancelReceptionCountdown();
        releaseReceptionPlayback();

        if (referenceWasPlaying) {
            emit referencePlaybackChanged();
            return;
        }

        m_receptionStatusText = QStringLiteral(
            "Fin del ejercicio. Revise su copia y pulse FINALIZAR Y PUNTUAR."
        );
        emit receptionChanged();
    } else if (audioState == QAudio::StoppedState
               && m_audioSink != nullptr
               && m_audioSink->error() != QAudio::NoError) {
        const bool referenceWasPlaying = m_referencePlaying;
        cancelReceptionCountdown();
        releaseReceptionPlayback();

        if (referenceWasPlaying) {
            emit referencePlaybackChanged();
            return;
        }

        m_receptionStatusText = QStringLiteral(
            "Error al reproducir el ejercicio de recepción."
        );
        emit receptionChanged();
    }
}

void MorseTrainer::releaseReceptionPlayback()
{
    QAudioSink *sink = m_audioSink;
    QBuffer *buffer = m_playbackBuffer;
    m_audioSink = nullptr;
    m_playbackBuffer = nullptr;
    m_receptionPlaying = false;
    m_referencePlaying = false;
    m_referenceSymbol.clear();

    if (sink != nullptr) {
        disconnect(sink, nullptr, this, nullptr);
        sink->stop();
        sink->deleteLater();
    }
    if (buffer != nullptr) {
        buffer->close();
        buffer->deleteLater();
    }
    m_playbackData.clear();
}

QString MorseTrainer::generateExerciseText() const
{
    const int introducedCount =
        std::min(int(kochSequence().size()), m_lesson + 1);
    const QStringList available = kochSequence().mid(0, introducedCount);
    const int newestStart = std::max(0, introducedCount - 2);

    QStringList groups;
    groups.reserve(m_exerciseGroups);

    for (int groupIndex = 0;
         groupIndex < m_exerciseGroups;
         ++groupIndex) {
        QString group;
        for (int characterIndex = 0;
             characterIndex < m_groupSize;
             ++characterIndex) {
            int selectedIndex = 0;
            const int roll = QRandomGenerator::global()->bounded(100);
            if (introducedCount > 2 && roll < 38) {
                selectedIndex = newestStart
                    + QRandomGenerator::global()->bounded(
                        introducedCount - newestStart
                    );
            } else {
                selectedIndex =
                    QRandomGenerator::global()->bounded(introducedCount);
            }
            group.append(available.at(selectedIndex));
        }
        groups.append(group);
    }

    return groups.join(QLatin1Char(' '));
}

QString MorseTrainer::dataDirectoryPath() const
{
    QString path = QStandardPaths::writableLocation(
        QStandardPaths::AppDataLocation
    );
    if (path.isEmpty()) {
        path = QDir::home().filePath(
            QStringLiteral(".local/share/Icom7300Mk2Control")
        );
    }
    return path;
}

void MorseTrainer::loadSettings()
{
    QSettings settings;
    m_toneFrequencyHz = std::clamp(
        settings.value(QStringLiteral("morse/toneFrequencyHz"), 600).toInt(),
        300,
        900
    );
    m_thresholdDb = std::clamp(
        settings.value(QStringLiteral("morse/thresholdDb"), -42.0).toDouble(),
        -80.0,
        -8.0
    );
    m_automaticThreshold = settings.value(
        QStringLiteral("morse/automaticThreshold"),
        true
    ).toBool();
    m_lesson = std::clamp(
        settings.value(QStringLiteral("morse/lesson"), 1).toInt(),
        1,
        maximumLesson()
    );
    m_characterWpm = std::clamp(
        settings.value(QStringLiteral("morse/characterWpm"), 20).toInt(),
        6,
        60
    );
    m_effectiveWpm = std::clamp(
        settings.value(QStringLiteral("morse/effectiveWpm"), 15).toInt(),
        5,
        m_characterWpm
    );
    m_groupSize = std::clamp(
        settings.value(QStringLiteral("morse/groupSize"), 5).toInt(),
        1,
        10
    );
    m_exerciseGroups = std::clamp(
        settings.value(QStringLiteral("morse/exerciseGroups"), 5).toInt(),
        1,
        20
    );
    m_receptionLeadInSeconds = std::clamp(
        settings.value(
            QStringLiteral("morse/receptionLeadInSeconds"),
            3
        ).toInt(),
        0,
        10
    );
}

void MorseTrainer::saveSettings() const
{
    QSettings settings;
    settings.setValue(QStringLiteral("morse/toneFrequencyHz"),
                      m_toneFrequencyHz);
    settings.setValue(QStringLiteral("morse/thresholdDb"),
                      m_thresholdDb);
    settings.setValue(QStringLiteral("morse/automaticThreshold"),
                      m_automaticThreshold);
    settings.setValue(QStringLiteral("morse/lesson"), m_lesson);
    settings.setValue(QStringLiteral("morse/characterWpm"),
                      m_characterWpm);
    settings.setValue(QStringLiteral("morse/effectiveWpm"),
                      m_effectiveWpm);
    settings.setValue(QStringLiteral("morse/groupSize"), m_groupSize);
    settings.setValue(QStringLiteral("morse/exerciseGroups"),
                      m_exerciseGroups);
    settings.setValue(QStringLiteral("morse/receptionLeadInSeconds"),
                      m_receptionLeadInSeconds);
}

void MorseTrainer::loadStatistics()
{
    QFile file(m_statisticsFilePath);
    if (!file.open(QIODevice::ReadOnly)) {
        rebuildStatistics();
        return;
    }

    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isArray()) {
        rebuildStatistics();
        return;
    }

    for (const QJsonValue &value : document.array()) {
        if (!value.isObject()) {
            continue;
        }

        const QJsonObject object = value.toObject();
        SessionRecord record;
        record.timestamp = object.value(QStringLiteral("timestamp")).toString();
        record.lesson = std::clamp(
            object.value(QStringLiteral("lesson")).toInt(1),
            1,
            maximumLesson()
        );
        record.characterWpm = object.value(
            QStringLiteral("characterWpm")
        ).toInt(20);
        record.effectiveWpm = object.value(
            QStringLiteral("effectiveWpm")
        ).toInt(15);
        record.target = object.value(QStringLiteral("target")).toString();
        record.decoded = object.value(QStringLiteral("decoded")).toString();
        record.mode = object.value(
            QStringLiteral("mode")
        ).toString(QStringLiteral("manipulation"));
        record.accuracy = object.value(QStringLiteral("accuracy")).toDouble();
        record.timing = object.value(QStringLiteral("timing")).toDouble();
        record.total = object.value(QStringLiteral("total")).toDouble();
        record.correct = object.value(QStringLiteral("correct")).toInt();
        record.errors = object.value(QStringLiteral("errors")).toInt();
        m_history.append(record);
    }

    while (m_history.size() > 5000) {
        m_history.removeFirst();
    }

    rebuildStatistics();
}

void MorseTrainer::saveStatistics() const
{
    QJsonArray array;
    for (const SessionRecord &record : m_history) {
        QJsonObject object;
        object.insert(QStringLiteral("timestamp"), record.timestamp);
        object.insert(QStringLiteral("lesson"), record.lesson);
        object.insert(QStringLiteral("characterWpm"), record.characterWpm);
        object.insert(QStringLiteral("effectiveWpm"), record.effectiveWpm);
        object.insert(QStringLiteral("target"), record.target);
        object.insert(QStringLiteral("decoded"), record.decoded);
        object.insert(QStringLiteral("mode"), record.mode);
        object.insert(QStringLiteral("accuracy"), record.accuracy);
        object.insert(QStringLiteral("timing"), record.timing);
        object.insert(QStringLiteral("total"), record.total);
        object.insert(QStringLiteral("correct"), record.correct);
        object.insert(QStringLiteral("errors"), record.errors);
        array.append(object);
    }

    QSaveFile file(m_statisticsFilePath);
    if (!file.open(QIODevice::WriteOnly)) {
        return;
    }

    file.write(QJsonDocument(array).toJson(QJsonDocument::Indented));
    file.commit();
}

void MorseTrainer::rebuildStatistics()
{
    m_totalSessions = m_history.size();
    m_averageScore = 0.0;
    m_bestScore = 0.0;
    m_currentLessonSessions = 0;
    m_currentLessonBest = 0.0;
    m_currentLessonAverage = 0.0;
    m_currentLessonPassed = false;
    m_recentSessions.clear();
    m_lessonStatistics.clear();

    double totalSum = 0.0;
    double currentLessonSum = 0.0;

    for (const SessionRecord &record : std::as_const(m_history)) {
        totalSum += record.total;
        m_bestScore = std::max(m_bestScore, record.total);

        if (record.lesson == m_lesson) {
            ++m_currentLessonSessions;
            currentLessonSum += record.total;
            m_currentLessonBest = std::max(
                m_currentLessonBest,
                record.total
            );
        }
    }

    if (m_totalSessions > 0) {
        m_averageScore = totalSum / m_totalSessions;
    }
    if (m_currentLessonSessions > 0) {
        m_currentLessonAverage =
            currentLessonSum / m_currentLessonSessions;
    }
    m_currentLessonPassed = m_currentLessonBest >= PassedScore;

    const int recentCount = std::min(12, int(m_history.size()));
    for (int offset = 0; offset < recentCount; ++offset) {
        m_recentSessions.append(
            sessionToVariant(m_history.at(m_history.size() - 1 - offset))
        );
    }

    for (int lessonNumber = 1;
         lessonNumber <= maximumLesson();
         ++lessonNumber) {
        int sessions = 0;
        double sum = 0.0;
        double best = 0.0;

        for (const SessionRecord &record : std::as_const(m_history)) {
            if (record.lesson != lessonNumber) {
                continue;
            }
            ++sessions;
            sum += record.total;
            best = std::max(best, record.total);
        }

        QVariantMap row;
        row.insert(QStringLiteral("lesson"), lessonNumber);
        row.insert(
            QStringLiteral("characters"),
            kochSequence()
                .mid(0, std::min(int(kochSequence().size()), lessonNumber + 1))
                .join(QStringLiteral(" "))
        );
        row.insert(QStringLiteral("sessions"), sessions);
        row.insert(QStringLiteral("average"),
                   sessions > 0 ? sum / sessions : 0.0);
        row.insert(QStringLiteral("best"), best);
        row.insert(QStringLiteral("passed"), best >= PassedScore);
        m_lessonStatistics.append(row);
    }

    emit statisticsChanged();
}

QVariantMap MorseTrainer::sessionToVariant(const SessionRecord &record) const
{
    QVariantMap row;
    row.insert(QStringLiteral("timestamp"), record.timestamp);
    row.insert(QStringLiteral("lesson"), record.lesson);
    row.insert(QStringLiteral("characterWpm"), record.characterWpm);
    row.insert(QStringLiteral("effectiveWpm"), record.effectiveWpm);
    row.insert(QStringLiteral("target"), record.target);
    row.insert(QStringLiteral("decoded"), record.decoded);
    row.insert(QStringLiteral("mode"), record.mode);
    row.insert(
        QStringLiteral("modeText"),
        record.mode == QStringLiteral("reception")
            ? QStringLiteral("Recepción")
            : QStringLiteral("Manipulación")
    );
    row.insert(QStringLiteral("accuracy"), record.accuracy);
    row.insert(QStringLiteral("timing"), record.timing);
    row.insert(QStringLiteral("total"), record.total);
    row.insert(QStringLiteral("correct"), record.correct);
    row.insert(QStringLiteral("errors"), record.errors);
    return row;
}
