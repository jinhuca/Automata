#include "FsmMachine.h"

void FsmMachine::build(const fsmdef::FsmDefinition& def)
{
    m_dfa = fsm::dfa<std::string, std::string>{};
    m_dfa.start(def.initial.toStdString());
    for (const QString& a : def.accept)
        m_dfa.accept(a.toStdString());
    for (const fsmdef::Transition& t : def.tr)
        m_dfa.on(t.from, t.sym, t.to);

    // Surface the per-state entry/exit actions: fire the library's real
    // on_entry/on_exit hooks and route the action text into the activity log, so
    // a run shows the exit(from) -> transition -> entry(to) order the DFA defines.
    for (auto it = def.entry.cbegin(); it != def.entry.cend(); ++it) {
        const std::string s = it.key().toStdString();
        const QString txt = it.value();
        m_dfa.on_entry(s, [this, key = it.key(), txt] {
            if (m_log)
                m_log(QStringLiteral("    » entry(%1): %2").arg(key, txt));
        });
    }
    for (auto it = def.exit.cbegin(); it != def.exit.cend(); ++it) {
        const std::string s = it.key().toStdString();
        const QString txt = it.value();
        m_dfa.on_exit(s, [this, key = it.key(), txt] {
            if (m_log)
                m_log(QStringLiteral("    » exit(%1): %2").arg(key, txt));
        });
    }

    // GUI semantics: an undefined input is ignored (the machine stays put and
    // keeps running) rather than halting, so stepping stray symbols is harmless.
    m_dfa.undefined(fsm::on_undefined::ignore);
    m_dfa.subscribe([this](const fsm::transition<std::string, std::string>& t) {
        if (m_log)
            m_log(QStringLiteral("    %1 --%2--> %3")
                      .arg(QString::fromStdString(t.from),
                           QString::fromStdString(t.symbol),
                           QString::fromStdString(t.to)));
    });
    m_dfa.reset();
    m_built = true;
    m_path = QStringList{def.initial};
    m_lastFrom.clear();
    m_lastSymbol.clear();
    m_lastTo.clear();
    refresh();
}

bool FsmMachine::step(const QString& symbol)
{
    if (!m_built)
        return false;
    const QString from = m_current;
    const bool fired = m_dfa.step(symbol.toStdString());
    if (fired) {
        const QString to = QString::fromStdString(m_dfa.current());
        m_lastFrom = from;
        m_lastSymbol = symbol;
        m_lastTo = to;
        m_path << to;  // extend the trace
    } else if (m_log) {
        m_log(QStringLiteral("    [ignored] %1 has no transition from %2").arg(symbol, from));
    }
    refresh();
    return fired;
}

void FsmMachine::reset()
{
    if (m_built) {
        m_dfa.reset();
        m_path = QStringList{QString::fromStdString(m_dfa.current())};
        m_lastFrom.clear();
        m_lastSymbol.clear();
        m_lastTo.clear();
        if (m_log)
            m_log(QStringLiteral("[reset] -> %1").arg(QString::fromStdString(m_dfa.current())));
    }
    refresh();
}

void FsmMachine::clear()
{
    m_built = false;
    m_current.clear();
    m_live = false;
    m_accepted = false;
    m_available.clear();
    m_path.clear();
    m_lastFrom.clear();
    m_lastSymbol.clear();
    m_lastTo.clear();
}

void FsmMachine::refresh()
{
    if (m_built) {
        m_current = QString::fromStdString(m_dfa.current());
        m_live = m_dfa.live();
        m_accepted = m_dfa.accepted();
        m_available.clear();
        for (const std::string& s : m_dfa.available())
            m_available << QString::fromStdString(s);
    } else {
        m_current.clear();
        m_live = false;
        m_accepted = false;
        m_available.clear();
    }
}
