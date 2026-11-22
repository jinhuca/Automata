#include "FsmViewModel.h"

#include <QRegularExpression>
#include <QSettings>
#include <QTimer>

#include <algorithm>

#include "FsmCodecs.h"
#include "FsmFileStore.h"

FsmViewModel::FsmViewModel(QObject *parent)
    : QObject(parent)
{
    // Route the machine's transition trace / "ignored" notices into the log.
    m_machine.setLogger([this](const QString &line) { appendLog(line); });

    m_timer = new QTimer(this);
    m_timer->setInterval(m_stepInterval);  // tunable; one step is watchable
    connect(m_timer, &QTimer::timeout, this, [this] {
        if (m_queue.isEmpty()) {
            stopRun();
            return;
        }
        const QString sym = m_queue.takeFirst();
        step(sym);
        if (m_queue.isEmpty())
            stopRun();
    });

    restoreSavedDefinition();
}

FsmViewModel::~FsmViewModel() = default;

bool FsmViewModel::running() const
{
    return m_timer && m_timer->isActive();
}

void FsmViewModel::setStepInterval(int ms)
{
    ms = std::clamp(ms, 100, 3000);
    if (ms == m_stepInterval)
        return;
    m_stepInterval = ms;
    if (m_timer)
        m_timer->setInterval(ms);
    emit stepIntervalChanged();
}

void FsmViewModel::appendLog(const QString &line)
{
    m_log += line + QLatin1Char('\n');
    emit logChanged();
}

void FsmViewModel::restoreSavedDefinition()
{
    // Fall back to the "even number of 1s" example on first launch.
    QSettings s;
    m_savedSymbols = s.value(QStringLiteral("def/symbols"), QStringLiteral("0, 1")).toString();
    m_savedStates = s.value(QStringLiteral("def/states"), QStringLiteral("even, odd")).toString();
    m_savedTransitions = s.value(QStringLiteral("def/transitions"),
                                 QStringLiteral(
                                     "even, 0, even\neven, 1, odd\nodd, 0, odd\nodd, 1, even"))
                             .toString();
    m_savedInitial = s.value(QStringLiteral("def/initial"), QStringLiteral("even")).toString();
    m_savedAccept = s.value(QStringLiteral("def/accept"), QStringLiteral("even")).toString();
    m_savedActions = s.value(QStringLiteral("def/actions"), QString()).toString();
}

void FsmViewModel::persistDefinition(const QString &symbolsCsv, const QString &statesCsv,
                                     const QString &transitionsText, const QString &initial,
                                     const QString &acceptCsv, const QString &actionsText)
{
    QSettings s;
    s.setValue(QStringLiteral("def/symbols"), symbolsCsv);
    s.setValue(QStringLiteral("def/states"), statesCsv);
    s.setValue(QStringLiteral("def/transitions"), transitionsText);
    s.setValue(QStringLiteral("def/initial"), initial);
    s.setValue(QStringLiteral("def/accept"), acceptCsv);
    s.setValue(QStringLiteral("def/actions"), actionsText);
}

void FsmViewModel::build(const QString &symbolsCsv, const QString &statesCsv,
                         const QString &transitionsText, const QString &initial,
                         const QString &acceptCsv, const QString &actionsText)
{
    stopRun();
    // Persist the raw definition so the form reloads on next launch.
    persistDefinition(symbolsCsv, statesCsv, transitionsText, initial, acceptCsv, actionsText);

    // Parse + validate (pure); publish the possibly-augmented definition either way.
    fsmdef::ParseResult r = fsmdef::parseDefinition(symbolsCsv, statesCsv, transitionsText, initial,
                                                    acceptCsv, actionsText);
    m_def = std::move(r.def);
    m_warnings = std::move(r.warnings);
    m_error = std::move(r.error);

    emit definitionChanged();

    if (!m_error.isEmpty()) {
        appendLog(QStringLiteral("[build] error: %1").arg(m_error));
        m_machine.clear();
        emit runChanged();
        return;
    }
    for (const QString &w : std::as_const(m_warnings))
        appendLog(QStringLiteral("[build] warning: %1").arg(w));

    m_machine.build(m_def);
    appendLog(QStringLiteral("[build] %1 states, %2 symbols, %3 transitions; start = %4")
                  .arg(m_def.states.size())
                  .arg(m_def.symbols.size())
                  .arg(m_def.tr.size())
                  .arg(m_def.initial));
    emit runChanged();
}

void FsmViewModel::step(const QString &symbol)
{
    if (!m_machine.built())
        return;
    const bool fired = m_machine.step(symbol);
    emit runChanged();
    if (fired)
        emit stepped();
}

void FsmViewModel::runWord(const QString &word)
{
    if (!m_machine.built())
        return;
    reset();
    // Tokenise by whitespace and commas, so multi-character symbols are supported
    // ("coin push" or "1,0,1").
    static const QRegularExpression sep(QStringLiteral("[\\s,]+"));
    m_queue.clear();
    for (const QString &tok : word.split(sep, Qt::SkipEmptyParts))
        m_queue << tok;
    if (m_queue.isEmpty())
        return;
    appendLog(QStringLiteral("[run] %1").arg(m_queue.join(' ')));
    m_timer->start();
    emit runChanged();
}

void FsmViewModel::reset()
{
    stopRun();
    m_machine.reset();  // logs "[reset] -> X" when built
    emit runChanged();
}

void FsmViewModel::stopRun()
{
    if (m_timer && m_timer->isActive()) {
        m_timer->stop();
        m_queue.clear();
        emit runChanged();
    }
}

bool FsmViewModel::saveToFile(const QUrl &fileUrl, const QVariantMap &data)
{
    const bool ok = fsmstore::saveJson(fileUrl, data);
    appendLog(ok ? QStringLiteral("[save] wrote %1").arg(fsmstore::localPath(fileUrl))
                 : QStringLiteral("[save] cannot open %1").arg(fsmstore::localPath(fileUrl)));
    return ok;
}

QVariantMap FsmViewModel::loadFromFile(const QUrl &fileUrl)
{
    QString error;
    const QVariantMap map = fsmstore::loadJson(fileUrl, &error);
    if (!error.isEmpty()) {
        appendLog(QStringLiteral("[load] %1").arg(error));
        return {};
    }
    appendLog(QStringLiteral("[load] read %1").arg(fsmstore::localPath(fileUrl)));
    return map;
}

QString FsmViewModel::exportCpp() const
{
    return fsmcodecs::exportCpp(m_def);
}

QString FsmViewModel::exportDot() const
{
    return fsmcodecs::exportDot(m_def);
}

bool FsmViewModel::saveTextToFile(const QUrl &fileUrl, const QString &text)
{
    const bool ok = fsmstore::saveText(fileUrl, text);
    appendLog(ok ? QStringLiteral("[export] wrote %1").arg(fsmstore::localPath(fileUrl))
                 : QStringLiteral("[export] cannot open %1").arg(fsmstore::localPath(fileUrl)));
    return ok;
}

QString FsmViewModel::readTextFromFile(const QUrl &fileUrl)
{
    bool ok = false;
    const QString text = fsmstore::loadText(fileUrl, &ok);
    if (!ok)
        appendLog(QStringLiteral("[import] cannot open %1").arg(fsmstore::localPath(fileUrl)));
    return text;
}

QVariantMap FsmViewModel::importCpp(const QString &code) const
{
    return fsmcodecs::importCpp(code);
}

QVariantMap FsmViewModel::importDot(const QString &code) const
{
    return fsmcodecs::importDot(code);
}

void FsmViewModel::clearAll()
{
    stopRun();
    m_def = fsmdef::FsmDefinition{};
    m_error.clear();
    m_warnings.clear();
    m_machine.clear();
    m_log.clear();
    emit definitionChanged();
    emit logChanged();
    emit runChanged();
}
