#pragma once

#include <QObject>
#include <QAudioDevice>
#include <QAudioFormat>
#include <QByteArray>
#include <QList>
#include <QElapsedTimer>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>

class QAudioSource;
class QAudioSink;
class QBuffer;
class QIODevice;

class MorseTrainer final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QStringList audioInputNames READ audioInputNames
               NOTIFY audioInputsChanged)
    Q_PROPERTY(int audioInputIndex READ audioInputIndex
               WRITE setAudioInputIndex NOTIFY audioInputIndexChanged)
    Q_PROPERTY(bool capturing READ capturing NOTIFY capturingChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)

    Q_PROPERTY(double inputLevelDb READ inputLevelDb
               NOTIFY levelsChanged)
    Q_PROPERTY(double toneLevelDb READ toneLevelDb
               NOTIFY levelsChanged)
    Q_PROPERTY(double noiseFloorDb READ noiseFloorDb
               NOTIFY levelsChanged)
    Q_PROPERTY(bool keyDown READ keyDown NOTIFY keyDownChanged)
    Q_PROPERTY(QString currentPattern READ currentPattern
               NOTIFY attemptChanged)
    Q_PROPERTY(QString decodedText READ decodedText
               NOTIFY attemptChanged)

    Q_PROPERTY(int toneFrequencyHz READ toneFrequencyHz
               WRITE setToneFrequencyHz NOTIFY settingsChanged)
    Q_PROPERTY(double thresholdDb READ thresholdDb
               WRITE setThresholdDb NOTIFY settingsChanged)
    Q_PROPERTY(bool automaticThreshold READ automaticThreshold
               WRITE setAutomaticThreshold NOTIFY settingsChanged)

    Q_PROPERTY(int lesson READ lesson WRITE setLesson
               NOTIFY trainingSettingsChanged)
    Q_PROPERTY(int maximumLesson READ maximumLesson CONSTANT)
    Q_PROPERTY(QString lessonCharacters READ lessonCharacters
               NOTIFY trainingSettingsChanged)
    Q_PROPERTY(QString newestLessonCharacters READ newestLessonCharacters
               NOTIFY trainingSettingsChanged)
    Q_PROPERTY(int characterWpm READ characterWpm WRITE setCharacterWpm
               NOTIFY trainingSettingsChanged)
    Q_PROPERTY(int effectiveWpm READ effectiveWpm WRITE setEffectiveWpm
               NOTIFY trainingSettingsChanged)
    Q_PROPERTY(int groupSize READ groupSize WRITE setGroupSize
               NOTIFY trainingSettingsChanged)
    Q_PROPERTY(int exerciseGroups READ exerciseGroups WRITE setExerciseGroups
               NOTIFY trainingSettingsChanged)
    Q_PROPERTY(QString targetText READ targetText NOTIFY exerciseChanged)
    Q_PROPERTY(int targetCharacterCount READ targetCharacterCount
               NOTIFY exerciseChanged)
    Q_PROPERTY(bool exerciseActive READ exerciseActive
               NOTIFY exerciseChanged)

    Q_PROPERTY(bool receptionPlaying READ receptionPlaying
               NOTIFY receptionChanged)
    Q_PROPERTY(bool receptionCountdownActive READ receptionCountdownActive
               NOTIFY receptionChanged)
    Q_PROPERTY(int receptionCountdownRemaining READ receptionCountdownRemaining
               NOTIFY receptionChanged)
    Q_PROPERTY(int receptionLeadInSeconds READ receptionLeadInSeconds
               WRITE setReceptionLeadInSeconds
               NOTIFY trainingSettingsChanged)
    Q_PROPERTY(bool receptionExerciseActive READ receptionExerciseActive
               NOTIFY receptionChanged)
    Q_PROPERTY(bool receptionTargetRevealed READ receptionTargetRevealed
               NOTIFY receptionChanged)
    Q_PROPERTY(QString receptionTargetText READ receptionTargetText
               NOTIFY receptionChanged)
    Q_PROPERTY(int receptionTargetCharacterCount
               READ receptionTargetCharacterCount
               NOTIFY receptionChanged)
    Q_PROPERTY(QString receptionCopyText READ receptionCopyText
               WRITE setReceptionCopyText NOTIFY receptionChanged)
    Q_PROPERTY(QString receptionStatusText READ receptionStatusText
               NOTIFY receptionChanged)
    Q_PROPERTY(QString receptionTargetComparisonHtml
               READ receptionTargetComparisonHtml
               NOTIFY receptionScoreChanged)
    Q_PROPERTY(QString receptionCopyComparisonHtml
               READ receptionCopyComparisonHtml
               NOTIFY receptionScoreChanged)
    Q_PROPERTY(double receptionAccuracy READ receptionAccuracy
               NOTIFY receptionScoreChanged)
    Q_PROPERTY(double receptionScore READ receptionScore
               NOTIFY receptionScoreChanged)
    Q_PROPERTY(int receptionCorrectCharacters READ receptionCorrectCharacters
               NOTIFY receptionScoreChanged)
    Q_PROPERTY(int receptionErrorCount READ receptionErrorCount
               NOTIFY receptionScoreChanged)

    Q_PROPERTY(bool referencePlaying READ referencePlaying
               NOTIFY referencePlaybackChanged)
    Q_PROPERTY(QString referenceSymbol READ referenceSymbol
               NOTIFY referencePlaybackChanged)

    Q_PROPERTY(double accuracy READ accuracy NOTIFY scoreChanged)
    Q_PROPERTY(double timingScore READ timingScore NOTIFY scoreChanged)
    Q_PROPERTY(double totalScore READ totalScore NOTIFY scoreChanged)
    Q_PROPERTY(int correctCharacters READ correctCharacters
               NOTIFY scoreChanged)
    Q_PROPERTY(int errorCount READ errorCount NOTIFY scoreChanged)

    Q_PROPERTY(int totalSessions READ totalSessions NOTIFY statisticsChanged)
    Q_PROPERTY(double averageScore READ averageScore
               NOTIFY statisticsChanged)
    Q_PROPERTY(double bestScore READ bestScore NOTIFY statisticsChanged)
    Q_PROPERTY(int currentLessonSessions READ currentLessonSessions
               NOTIFY statisticsChanged)
    Q_PROPERTY(double currentLessonBest READ currentLessonBest
               NOTIFY statisticsChanged)
    Q_PROPERTY(double currentLessonAverage READ currentLessonAverage
               NOTIFY statisticsChanged)
    Q_PROPERTY(bool currentLessonPassed READ currentLessonPassed
               NOTIFY statisticsChanged)
    Q_PROPERTY(QVariantList recentSessions READ recentSessions
               NOTIFY statisticsChanged)
    Q_PROPERTY(QVariantList lessonStatistics READ lessonStatistics
               NOTIFY statisticsChanged)
    Q_PROPERTY(QString statisticsFilePath READ statisticsFilePath CONSTANT)

public:
    explicit MorseTrainer(QObject *parent = nullptr);
    ~MorseTrainer() override;

    [[nodiscard]] QStringList audioInputNames() const;
    [[nodiscard]] int audioInputIndex() const;
    [[nodiscard]] bool capturing() const;
    [[nodiscard]] QString statusText() const;

    [[nodiscard]] double inputLevelDb() const;
    [[nodiscard]] double toneLevelDb() const;
    [[nodiscard]] double noiseFloorDb() const;
    [[nodiscard]] bool keyDown() const;
    [[nodiscard]] QString currentPattern() const;
    [[nodiscard]] QString decodedText() const;

    [[nodiscard]] int toneFrequencyHz() const;
    [[nodiscard]] double thresholdDb() const;
    [[nodiscard]] bool automaticThreshold() const;

    [[nodiscard]] int lesson() const;
    [[nodiscard]] int maximumLesson() const;
    [[nodiscard]] QString lessonCharacters() const;
    [[nodiscard]] QString newestLessonCharacters() const;
    [[nodiscard]] int characterWpm() const;
    [[nodiscard]] int effectiveWpm() const;
    [[nodiscard]] int groupSize() const;
    [[nodiscard]] int exerciseGroups() const;
    [[nodiscard]] QString targetText() const;
    [[nodiscard]] int targetCharacterCount() const;
    [[nodiscard]] bool exerciseActive() const;

    [[nodiscard]] bool receptionPlaying() const;
    [[nodiscard]] bool receptionCountdownActive() const;
    [[nodiscard]] int receptionCountdownRemaining() const;
    [[nodiscard]] int receptionLeadInSeconds() const;
    [[nodiscard]] bool receptionExerciseActive() const;
    [[nodiscard]] bool receptionTargetRevealed() const;
    [[nodiscard]] QString receptionTargetText() const;
    [[nodiscard]] int receptionTargetCharacterCount() const;
    [[nodiscard]] QString receptionCopyText() const;
    [[nodiscard]] QString receptionStatusText() const;
    [[nodiscard]] QString receptionTargetComparisonHtml() const;
    [[nodiscard]] QString receptionCopyComparisonHtml() const;
    [[nodiscard]] double receptionAccuracy() const;
    [[nodiscard]] double receptionScore() const;
    [[nodiscard]] int receptionCorrectCharacters() const;
    [[nodiscard]] int receptionErrorCount() const;

    [[nodiscard]] bool referencePlaying() const;
    [[nodiscard]] QString referenceSymbol() const;

    [[nodiscard]] double accuracy() const;
    [[nodiscard]] double timingScore() const;
    [[nodiscard]] double totalScore() const;
    [[nodiscard]] int correctCharacters() const;
    [[nodiscard]] int errorCount() const;

    [[nodiscard]] int totalSessions() const;
    [[nodiscard]] double averageScore() const;
    [[nodiscard]] double bestScore() const;
    [[nodiscard]] int currentLessonSessions() const;
    [[nodiscard]] double currentLessonBest() const;
    [[nodiscard]] double currentLessonAverage() const;
    [[nodiscard]] bool currentLessonPassed() const;
    [[nodiscard]] QVariantList recentSessions() const;
    [[nodiscard]] QVariantList lessonStatistics() const;
    [[nodiscard]] QString statisticsFilePath() const;

    Q_INVOKABLE void refreshAudioInputs();
    Q_INVOKABLE bool startCapture();
    Q_INVOKABLE void stopCapture();

    Q_INVOKABLE void createExercise();
    Q_INVOKABLE void clearAttempt();
    Q_INVOKABLE void finishExercise();
    Q_INVOKABLE void appendWordSpace();
    Q_INVOKABLE void removeLastDecodedCharacter();

    Q_INVOKABLE bool startReceptionExercise();
    Q_INVOKABLE bool replayReceptionExercise();
    Q_INVOKABLE void stopReceptionPlayback();
    Q_INVOKABLE void clearReceptionCopy();
    Q_INVOKABLE void finishReceptionExercise();

    Q_INVOKABLE bool playReferenceSymbol(const QString &symbol);
    Q_INVOKABLE void stopReferencePlayback();

    Q_INVOKABLE void resetStatistics();
    Q_INVOKABLE void resetCurrentLessonStatistics();

public slots:
    void setAudioInputIndex(int index);
    void setToneFrequencyHz(int frequencyHz);
    void setThresholdDb(double thresholdDb);
    void setAutomaticThreshold(bool enabled);

    void setLesson(int lesson);
    void setCharacterWpm(int wpm);
    void setEffectiveWpm(int wpm);
    void setGroupSize(int size);
    void setExerciseGroups(int groups);
    void setReceptionLeadInSeconds(int seconds);
    void setReceptionCopyText(const QString &text);

signals:
    void audioInputsChanged();
    void audioInputIndexChanged();
    void capturingChanged();
    void statusTextChanged();
    void levelsChanged();
    void keyDownChanged();
    void attemptChanged();
    void settingsChanged();
    void trainingSettingsChanged();
    void exerciseChanged();
    void receptionChanged();
    void receptionScoreChanged();
    void referencePlaybackChanged();
    void scoreChanged();
    void statisticsChanged();

private slots:
    void processAudioData();
    void handleAudioStateChanged(int state);

private:
    struct ComparisonResult {
        int targetCharacters = 0;
        int copiedCharacters = 0;
        int correct = 0;
        int substitutions = 0;
        int omissions = 0;
        int extras = 0;
        int errors = 0;
        double accuracy = 0.0;
        QString targetComparisonHtml;
        QString copyComparisonHtml;
    };

    struct SessionRecord {
        QString timestamp;
        int lesson = 1;
        int characterWpm = 20;
        int effectiveWpm = 15;
        QString target;
        QString decoded;
        QString mode = QStringLiteral("manipulation");
        double accuracy = 0.0;
        double timing = 0.0;
        double total = 0.0;
        int correct = 0;
        int errors = 0;
    };

    void setStatusText(const QString &text);
    void resetDecoderState();
    void consumeAudioBytes(const QByteArray &bytes);
    void analyzeFrame(const QVector<double> &samples);
    double decodeSample(const char *frameData, int channel) const;
    void updateToneState(bool detected, qint64 timestampMs);
    void transitionKeyState(bool down, qint64 timestampMs);
    void processIdleGap(qint64 timestampMs);
    void appendElement(qint64 durationMs);
    void recordTimingError(double actualMs, double expectedMs);
    void finalizeCurrentCharacter(bool appendSpace);
    void appendDecodedCharacter(const QString &character);

    [[nodiscard]] double dotMilliseconds() const;
    [[nodiscard]] double farnsworthSpacingFactor() const;
    [[nodiscard]] double characterGapMilliseconds() const;
    [[nodiscard]] double wordGapMilliseconds() const;
    [[nodiscard]] double characterBoundaryMilliseconds() const;
    [[nodiscard]] double wordBoundaryMilliseconds() const;
    [[nodiscard]] QString decodePattern(const QString &pattern) const;
    [[nodiscard]] QString normalizedForScoring(const QString &text) const;
    [[nodiscard]] ComparisonResult compareForScoring(
        const QString &targetText,
        const QString &copiedText
    ) const;
    void evaluateAttempt();
    [[nodiscard]] ComparisonResult evaluateReceptionCopy();
    [[nodiscard]] QByteArray generateMorseAudio(
        const QString &text,
        const QAudioFormat &format,
        double leadingSilenceMilliseconds = 900.0,
        double trailingSilenceMilliseconds = 180.0
    ) const;
    bool beginReceptionCountdown();
    void advanceReceptionCountdown();
    void cancelReceptionCountdown();
    bool beginReceptionPlayback(
        double leadingSilenceMilliseconds = 900.0
    );
    bool beginReferencePlayback(const QString &symbol);
    void handleReceptionPlaybackState(int state);
    void releaseReceptionPlayback();

    [[nodiscard]] QString generateExerciseText() const;
    [[nodiscard]] QString dataDirectoryPath() const;
    void loadSettings();
    void saveSettings() const;
    void loadStatistics();
    void saveStatistics() const;
    void rebuildStatistics();
    [[nodiscard]] QVariantMap sessionToVariant(const SessionRecord &record) const;

    QStringList m_audioInputNames;
    QList<QAudioDevice> m_audioInputDevices;
    int m_audioInputIndex = -1;
    QAudioSource *m_audioSource = nullptr;
    QIODevice *m_audioDevice = nullptr;
    QAudioFormat m_audioFormat;
    QByteArray m_pendingBytes;
    QVector<double> m_analysisSamples;
    int m_analysisFrameSamples = 480;
    bool m_capturing = false;
    bool m_stoppingCapture = false;
    QString m_statusText = QStringLiteral("Preparado");

    double m_inputLevelDb = -90.0;
    double m_toneLevelDb = -90.0;
    double m_noiseFloorDb = -70.0;
    bool m_keyDown = false;
    bool m_candidateKeyDown = false;
    qint64 m_candidateSinceMs = 0;
    qint64 m_keyDownSinceMs = 0;
    qint64 m_keyUpSinceMs = -1;
    bool m_characterFinalizedForGap = false;
    bool m_wordSpaceFinalizedForGap = false;
    QElapsedTimer m_captureClock;
    qint64 m_lastLevelsSignalMs = 0;
    qint64 m_processedAudioSamples = 0;

    QString m_currentPattern;
    QString m_decodedText;
    int m_toneFrequencyHz = 600;
    double m_thresholdDb = -42.0;
    bool m_automaticThreshold = true;

    int m_lesson = 1;
    int m_characterWpm = 20;
    int m_effectiveWpm = 15;
    int m_groupSize = 5;
    int m_exerciseGroups = 5;
    QString m_targetText;
    bool m_exerciseActive = false;

    QAudioSink *m_audioSink = nullptr;
    QBuffer *m_playbackBuffer = nullptr;
    QTimer m_receptionCountdownTimer;
    QByteArray m_playbackData;
    bool m_receptionPlaying = false;
    bool m_receptionCountdownActive = false;
    int m_receptionCountdownRemaining = 0;
    int m_receptionLeadInSeconds = 3;
    bool m_referencePlaying = false;
    QString m_referenceSymbol;
    bool m_receptionExerciseActive = false;
    bool m_receptionTargetRevealed = false;
    QString m_receptionTargetText;
    QString m_receptionCopyText;
    QString m_receptionStatusText =
        QStringLiteral("Pulse NUEVO Y REPRODUCIR para comenzar.");
    QString m_receptionTargetComparisonHtml;
    QString m_receptionCopyComparisonHtml;
    double m_receptionAccuracy = 0.0;
    double m_receptionScore = 0.0;
    int m_receptionCorrectCharacters = 0;
    int m_receptionErrorCount = 0;

    double m_accuracy = 0.0;
    double m_timingScore = 0.0;
    double m_totalScore = 0.0;
    int m_correctCharacters = 0;
    int m_errorCount = 0;
    double m_timingErrorSum = 0.0;
    int m_timingErrorCount = 0;

    QList<SessionRecord> m_history;
    int m_totalSessions = 0;
    double m_averageScore = 0.0;
    double m_bestScore = 0.0;
    int m_currentLessonSessions = 0;
    double m_currentLessonBest = 0.0;
    double m_currentLessonAverage = 0.0;
    bool m_currentLessonPassed = false;
    QVariantList m_recentSessions;
    QVariantList m_lessonStatistics;
    QString m_statisticsFilePath;
};
