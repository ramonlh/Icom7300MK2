#include "videocapturecontroller.h"

#include <QDir>
#include <QFileInfo>
#include <QImageReader>
#include <QPainter>
#include <QSettings>
#include <QStandardPaths>

VideoCaptureController::VideoCaptureController(QObject *parent)
    : QObject(parent),
      m_ffmpegPath(QStandardPaths::findExecutable(QStringLiteral("ffmpeg"))),
      m_frameStore(std::make_shared<VideoFrameStore>())
{
    const QFileInfoList entries = QDir(QStringLiteral("/dev")).entryInfoList(
        {QStringLiteral("video*")}, QDir::System | QDir::Readable,
        QDir::Name | QDir::IgnoreCase);
    for (const QFileInfo &entry : entries) {
        if (entry.isReadable())
            m_devices.append(entry.absoluteFilePath());
    }

    QSettings settings;
    const QString savedDevice = settings.value(
        QStringLiteral("video/device")).toString();
    m_scopeOnly = settings.value(QStringLiteral("video/scopeOnly"), true)
                      .toBool();
    if (m_devices.contains(savedDevice))
        m_selectedDevice = savedDevice;
    else if (m_devices.contains(QStringLiteral("/dev/video2")))
        m_selectedDevice = QStringLiteral("/dev/video2");
    else if (!m_devices.isEmpty())
        m_selectedDevice = m_devices.constFirst();

    connect(&m_process, &QProcess::started, this, [this]() {
        setStatus(QStringLiteral("Abierto %1, esperando fotogramas…")
                      .arg(m_selectedDevice));
    });
    connect(&m_process, &QProcess::readyReadStandardOutput,
            this, &VideoCaptureController::readFrames);
    connect(&m_process, &QProcess::readyReadStandardError, this, [this]() {
        m_processError += m_process.readAllStandardError();
        if (m_processError.size() > 2048)
            m_processError = m_processError.right(2048);
    });
    connect(&m_process,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, [this](int exitCode, QProcess::ExitStatus exitStatus) {
        readFrames();
        if (m_stopping) {
            m_stopping = false;
            return;
        }
        const QString detail = QString::fromLocal8Bit(m_processError).trimmed();
        setStatus(detail.isEmpty()
                      ? QStringLiteral("Captura detenida (código %1)").arg(exitCode)
                      : detail);
        Q_UNUSED(exitStatus);
    });
    connect(&m_process, &QProcess::errorOccurred, this,
            [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            setStatus(m_ffmpegPath.isEmpty()
                          ? QStringLiteral("No se encontró ffmpeg")
                          : m_process.errorString());
    });

    if (m_ffmpegPath.isEmpty())
        setStatus(QStringLiteral("No se encontró ffmpeg"));
    else if (m_devices.isEmpty())
        setStatus(QStringLiteral("No se detectan dispositivos /dev/video*"));
    else
        setStatus(QStringLiteral("Capturador disponible: %1").arg(m_selectedDevice));
}

VideoCaptureController::~VideoCaptureController()
{
    stopCapture();
    if (m_process.state() != QProcess::NotRunning) {
        m_process.kill();
        m_process.waitForFinished(500);
    }
}

QStringList VideoCaptureController::devices() const
{
    return m_devices;
}

QString VideoCaptureController::selectedDevice() const
{
    return m_selectedDevice;
}

void VideoCaptureController::setSelectedDevice(const QString &device)
{
    if (!m_devices.contains(device) || device == m_selectedDevice)
        return;
    const bool wasRunning = m_process.state() != QProcess::NotRunning;
    m_selectedDevice = device;
    QSettings().setValue(QStringLiteral("video/device"), m_selectedDevice);
    emit selectedDeviceChanged();
    if (wasRunning)
        startCapture();
    else
        setStatus(QStringLiteral("Capturador disponible: %1")
                      .arg(m_selectedDevice));
}

QString VideoCaptureController::status() const
{
    return m_status;
}

bool VideoCaptureController::scopeOnly() const
{
    return m_scopeOnly;
}

void VideoCaptureController::setScopeOnly(bool scopeOnly)
{
    if (m_scopeOnly == scopeOnly)
        return;
    m_scopeOnly = scopeOnly;
    QSettings().setValue(QStringLiteral("video/scopeOnly"), m_scopeOnly);
    emit scopeOnlyChanged();
}

int VideoCaptureController::frameRevision() const
{
    return m_frameRevision;
}

QSize VideoCaptureController::frameSize() const
{
    return m_frameSize;
}

std::shared_ptr<VideoFrameStore> VideoCaptureController::frameStore() const
{
    return m_frameStore;
}

void VideoCaptureController::startCapture()
{
    if (m_ffmpegPath.isEmpty()) {
        setStatus(QStringLiteral("No se encontró ffmpeg"));
        return;
    }
    if (m_selectedDevice.isEmpty()) {
        setStatus(QStringLiteral("No hay capturador seleccionado"));
        return;
    }
    if (m_process.state() != QProcess::NotRunning) {
        m_stopping = true;
        m_process.kill();
        m_process.waitForFinished(500);
        m_stopping = false;
    }

    m_jpegBuffer.clear();
    m_processError.clear();
    {
        QMutexLocker lock(&m_frameStore->mutex);
        m_frameStore->image = QImage();
    }
    if (m_frameSize.isValid()) {
        m_frameSize = QSize();
        emit frameSizeChanged();
    }
    if (m_frameRevision != 0) {
        m_frameRevision = 0;
        emit frameRevisionChanged();
    }
    const bool usbCaptureMjpeg = m_selectedDevice == QStringLiteral("/dev/video2");
    QStringList arguments{
        QStringLiteral("-hide_banner"), QStringLiteral("-loglevel"),
        QStringLiteral("error"), QStringLiteral("-nostdin"),
        QStringLiteral("-fflags"), QStringLiteral("nobuffer"),
        QStringLiteral("-flags"), QStringLiteral("low_delay"),
        QStringLiteral("-thread_queue_size"), QStringLiteral("1"),
        QStringLiteral("-f"), QStringLiteral("v4l2")};
    if (usbCaptureMjpeg) {
        arguments.append({QStringLiteral("-input_format"), QStringLiteral("mjpeg"),
                          QStringLiteral("-video_size"), QStringLiteral("1280x720"),
                          QStringLiteral("-framerate"), QStringLiteral("30")});
    }
    arguments.append({QStringLiteral("-i"), m_selectedDevice,
                      QStringLiteral("-an"), QStringLiteral("-fps_mode"),
                      QStringLiteral("passthrough")});
    if (usbCaptureMjpeg) {
        arguments.append({QStringLiteral("-c:v"), QStringLiteral("copy")});
    } else {
        arguments.append({QStringLiteral("-c:v"), QStringLiteral("mjpeg"),
                          QStringLiteral("-q:v"), QStringLiteral("5")});
    }
    arguments.append({QStringLiteral("-f"), QStringLiteral("image2pipe"),
                      QStringLiteral("-flush_packets"), QStringLiteral("1"),
                      QStringLiteral("pipe:1")});
    m_process.setProgram(m_ffmpegPath);
    m_process.setArguments(arguments);
    setStatus(QStringLiteral("Abriendo %1 con ffmpeg…").arg(m_selectedDevice));
    m_process.start();
}

void VideoCaptureController::stopCapture()
{
    {
        QMutexLocker lock(&m_frameStore->mutex);
        m_frameStore->image = QImage();
    }
    if (m_frameSize.isValid()) {
        m_frameSize = QSize();
        emit frameSizeChanged();
    }
    if (m_frameRevision != 0) {
        m_frameRevision = 0;
        emit frameRevisionChanged();
    }
    if (m_process.state() == QProcess::NotRunning) {
        setStatus(QStringLiteral("Vídeo detenido"));
        return;
    }
    m_stopping = true;
    m_process.kill();
    m_process.waitForFinished(500);
    setStatus(QStringLiteral("Vídeo detenido"));
}

void VideoCaptureController::setStatus(const QString &status)
{
    if (m_status == status)
        return;
    m_status = status;
    emit statusChanged();
}

void VideoCaptureController::readFrames()
{
    if (m_stopping) {
        m_process.readAllStandardOutput();
        m_jpegBuffer.clear();
        return;
    }
    m_jpegBuffer += m_process.readAllStandardOutput();
    QByteArray newestJpeg;
    while (true) {
        const qsizetype start = m_jpegBuffer.indexOf(QByteArray::fromHex("ffd8"));
        if (start < 0) {
            if (m_jpegBuffer.size() > 4 * 1024 * 1024) {
                const bool keepPrefix = !m_jpegBuffer.isEmpty()
                                        && m_jpegBuffer.back() == char(0xff);
                const char prefix = keepPrefix ? char(0xff) : char(0);
                m_jpegBuffer.clear();
                if (keepPrefix)
                    m_jpegBuffer.append(prefix);
            }
            break;
        }
        if (start > 0)
            m_jpegBuffer.remove(0, start);
        const qsizetype end = m_jpegBuffer.indexOf(QByteArray::fromHex("ffd9"), 2);
        if (end < 0)
            break;

        newestJpeg = m_jpegBuffer.left(end + 2);
        m_jpegBuffer.remove(0, end + 2);
    }
    if (newestJpeg.isEmpty())
        return;

    const QImage image = QImage::fromData(newestJpeg, "JPEG");
    if (image.isNull())
        return;

    {
        QMutexLocker lock(&m_frameStore->mutex);
        m_frameStore->image = image;
    }
    if (m_frameSize != image.size()) {
        m_frameSize = image.size();
        emit frameSizeChanged();
    }
    ++m_frameRevision;
    emit frameRevisionChanged();
    if (m_status != QStringLiteral("Vídeo en directo · %1")
                            .arg(m_selectedDevice))
        setStatus(QStringLiteral("Vídeo en directo · %1")
                      .arg(m_selectedDevice));
}

VideoFrameItem::VideoFrameItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setOpaquePainting(true);
    setAntialiasing(false);
}

VideoCaptureController *VideoFrameItem::controller() const
{
    return m_controller.data();
}

void VideoFrameItem::setController(VideoCaptureController *controller)
{
    if (m_controller.data() == controller)
        return;
    QObject::disconnect(m_frameConnection);
    m_controller = controller;
    if (m_controller) {
        m_frameStore = m_controller->frameStore();
        m_frameConnection = connect(m_controller,
                                    &VideoCaptureController::frameRevisionChanged,
                                    this, [this]() { update(); });
    }
    emit controllerChanged();
    update();
}

bool VideoFrameItem::scopeOnly() const
{
    return m_scopeOnly;
}

void VideoFrameItem::setScopeOnly(bool scopeOnly)
{
    if (m_scopeOnly == scopeOnly)
        return;
    m_scopeOnly = scopeOnly;
    update();
}

void VideoFrameItem::paint(QPainter *painter)
{
    painter->fillRect(boundingRect(), Qt::black);
    const auto store = m_frameStore;
    if (!store)
        return;

    QImage frame;
    {
        QMutexLocker lock(&store->mutex);
        frame = store->image;
    }
    if (frame.isNull())
        return;

    const QRectF target = boundingRect();
    painter->setRenderHint(QPainter::SmoothPixmapTransform, true);
    if (m_scopeOnly) {
        const QRectF source(0.0, frame.height() * 0.264,
                            frame.width(), frame.height() * 0.651 - 10.0);
        painter->drawImage(target, frame, source);
        return;
    }

    const QSizeF fitted = QSizeF(frame.size()).scaled(target.size(),
                                                       Qt::KeepAspectRatio);
    const QRectF destination(target.x() + (target.width() - fitted.width()) / 2.0,
                             target.y() + (target.height() - fitted.height()) / 2.0,
                             fitted.width(), fitted.height());
    painter->drawImage(destination, frame);
}
