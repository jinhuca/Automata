#pragma once

#include <QString>
#include <QUrl>
#include <QVariantMap>

// File I/O for the document and generated-text exchange. Pure helpers (QFile /
// QJsonDocument only, no logging and no QObject): each reports success/failure
// so FsmViewModel can emit the activity-log messages. The QML layer assembles /
// applies the document map; these just move bytes.
namespace fsmstore {

// Display path for logging: the local filesystem path, or the URL as-is.
QString localPath(const QUrl& fileUrl);

// Write a QVariantMap as indented JSON. False if the file can't be opened.
bool saveJson(const QUrl& fileUrl, const QVariantMap& data);
// Read JSON into a QVariantMap. On failure returns {} and sets *error to a
// message ("cannot open <path>" or "invalid file: <reason>"); empty on success.
QVariantMap loadJson(const QUrl& fileUrl, QString* error);

// Write arbitrary UTF-8 text. False if the file can't be opened.
bool saveText(const QUrl& fileUrl, const QString& text);
// Read a UTF-8 text file. Sets *ok; returns an empty string on failure.
QString loadText(const QUrl& fileUrl, bool* ok);

}  // namespace fsmstore
