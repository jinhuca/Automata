#include "FsmFileStore.h"

#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>

namespace fsmstore {

QString localPath(const QUrl& fileUrl)
{
    return fileUrl.isLocalFile() ? fileUrl.toLocalFile() : fileUrl.toString();
}

bool saveJson(const QUrl& fileUrl, const QVariantMap& data)
{
    QFile f(localPath(fileUrl));
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    f.write(QJsonDocument::fromVariant(data).toJson(QJsonDocument::Indented));
    f.close();
    return true;
}

QVariantMap loadJson(const QUrl& fileUrl, QString* error)
{
    const QString path = localPath(fileUrl);
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        if (error)
            *error = QStringLiteral("cannot open %1").arg(path);
        return {};
    }
    const QByteArray bytes = f.readAll();
    f.close();
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(bytes, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        if (error)
            *error = QStringLiteral("invalid file: %1").arg(err.errorString());
        return {};
    }
    if (error)
        error->clear();
    return doc.object().toVariantMap();
}

bool saveText(const QUrl& fileUrl, const QString& text)
{
    QFile f(localPath(fileUrl));
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    f.write(text.toUtf8());
    f.close();
    return true;
}

QString loadText(const QUrl& fileUrl, bool* ok)
{
    QFile f(localPath(fileUrl));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (ok)
            *ok = false;
        return QString();
    }
    const QString text = QString::fromUtf8(f.readAll());
    f.close();
    if (ok)
        *ok = true;
    return text;
}

}  // namespace fsmstore
