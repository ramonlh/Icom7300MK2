#pragma once

#include <QImage>
#include <QMutex>
#include <QObject>
#include <QProcess>
#include <QQuickPaintedItem>
#include <QPointer>
#include <QStringList>

#include <memory>

struct VideoFrameStore
{
    QMutex mutex;
    QImage image;
};

class VideoCaptureController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList devices READ devices CONSTANT)
    Q_PROPERTY(QString selectedDevice READ selectedDevice WRITE setSelectedDevice
               NOTIFY selectedDeviceChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(bool scopeOnly READ scopeOnly WRITE setScopeOnly
               NOTIFY scopeOnlyChanged)
    Q_PROPERTY(int frameRevision READ frameRevision NOTIFY frameRevisionChanged)
    Q_PROPERTY(QSize frameSize READ frameSize NOTIFY frameSizeChanged)

public:
    explicit VideoCaptureController(QObject *parent = nullptr);
    ~VideoCaptureController() override;

    QStringList devices() const;
    QString selectedDevice() const;
    void setSelectedDevice(const QString &device);
    QString status() const;
    bool scopeOnly() const;
    void setScopeOnly(bool scopeOnly);
    int frameRevision() const;
    QSize frameSize() const;
    std::shared_ptr<VideoFrameStore> frameStore() const;

    Q_INVOKABLE void startCapture();
    Q_INVOKABLE void stopCapture();

signals:
    void selectedDeviceChanged();
    void statusChanged();
    void scopeOnlyChanged();
    void frameRevisionChanged();
    void frameSizeChanged();

private:
    void setStatus(const QString &status);
    void readFrames();

    QProcess m_process;
    QStringList m_devices;
    QString m_selectedDevice;
    QString m_ffmpegPath;
    QString m_status;
    bool m_scopeOnly = true;
    QByteArray m_jpegBuffer;
    QByteArray m_processError;
    QSize m_frameSize;
    int m_frameRevision = 0;
    bool m_stopping = false;
    std::shared_ptr<VideoFrameStore> m_frameStore;
};

class VideoFrameItem : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(VideoCaptureController *controller READ controller WRITE setController
               NOTIFY controllerChanged)
    Q_PROPERTY(bool scopeOnly READ scopeOnly WRITE setScopeOnly)

public:
    explicit VideoFrameItem(QQuickItem *parent = nullptr);
    VideoCaptureController *controller() const;
    void setController(VideoCaptureController *controller);
    bool scopeOnly() const;
    void setScopeOnly(bool scopeOnly);
    void paint(QPainter *painter) override;

signals:
    void controllerChanged();

private:
    QPointer<VideoCaptureController> m_controller;
    QMetaObject::Connection m_frameConnection;
    std::shared_ptr<VideoFrameStore> m_frameStore;
    bool m_scopeOnly = true;
};
