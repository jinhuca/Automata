#include "FsmDefinition.h"

#include <QChar>
#include <QHash>
#include <QRegularExpression>
#include <QVariantMap>

#include <utility>

namespace fsmdef {

QStringList splitCsv(const QString& s)
{
    QStringList out;
    static const QRegularExpression sep(QStringLiteral("[,\\n]"));  // comma or newline
    for (const QString& part : s.split(sep, Qt::SkipEmptyParts)) {
        const QString t = part.trimmed();
        if (!t.isEmpty())
            out << t;
    }
    return out;
}

ParseResult parseDefinition(const QString& symbolsCsv, const QString& statesCsv,
                            const QString& transitionsText, const QString& initial,
                            const QString& acceptCsv, const QString& actionsText)
{
    ParseResult r;
    FsmDefinition& def = r.def;
    QStringList& warnings = r.warnings;

    def.initial = initial.trimmed();

    // Declared states / symbols, de-duplicated (non-fatal warning on dups).
    auto dedup = [&warnings](const QStringList& in, const QString& kind) {
        QStringList out;
        for (const QString& v : in) {
            if (out.contains(v))
                warnings << QStringLiteral("duplicate %1 \"%2\" ignored").arg(kind, v);
            else
                out << v;
        }
        return out;
    };
    def.states = dedup(splitCsv(statesCsv), QStringLiteral("state"));
    def.symbols = dedup(splitCsv(symbolsCsv), QStringLiteral("symbol"));
    def.accept = splitCsv(acceptCsv);

    // Parse transition triples: "from, sym, to" separated by ';' or newlines.
    // Malformed lines are skipped with a warning; undeclared states/symbols are
    // inferred (with a warning); a redefined (from, symbol) is nondeterministic
    // for a DFA, so the last target wins (with a warning).
    QHash<QString, int> edgeIndex;  // key "from\x1Fsymbol" -> index in def.tr/def.transitions
    const QString norm = QString(transitionsText).replace('\n', ';');
    for (const QString& rawTriple : norm.split(';', Qt::SkipEmptyParts)) {
        if (rawTriple.trimmed().isEmpty())
            continue;
        const QStringList p = rawTriple.split(',');
        if (p.size() != 3) {
            warnings << QStringLiteral(
                            "malformed transition \"%1\" (need: from, symbol, to) — skipped")
                            .arg(rawTriple.trimmed());
            continue;
        }
        const QString from = p[0].trimmed(), sym = p[1].trimmed(), to = p[2].trimmed();
        if (from.isEmpty() || sym.isEmpty() || to.isEmpty()) {
            warnings << QStringLiteral("transition \"%1\" has an empty field — skipped")
                            .arg(rawTriple.trimmed());
            continue;
        }
        if (!def.states.contains(from)) {
            warnings << QStringLiteral("state \"%1\" (from a transition) was not declared — added")
                            .arg(from);
            def.states << from;
        }
        if (!def.states.contains(to)) {
            warnings << QStringLiteral("state \"%1\" (from a transition) was not declared — added")
                            .arg(to);
            def.states << to;
        }
        if (!def.symbols.contains(sym)) {
            warnings << QStringLiteral("symbol \"%1\" (from a transition) was not declared — added")
                            .arg(sym);
            def.symbols << sym;
        }

        QVariantMap m;
        m["from"] = from;
        m["symbol"] = sym;
        m["to"] = to;
        const QString key = from + QChar(0x1F) + sym;
        if (edgeIndex.contains(key)) {
            const int i = edgeIndex.value(key);
            if (def.tr[i].to != to.toStdString())
                warnings << QStringLiteral(
                                "nondeterministic: (%1, %2) redefined — last target \"%3\" wins")
                                .arg(from, sym, to);
            def.tr[i] = {from.toStdString(), sym.toStdString(), to.toStdString()};
            def.transitions[i] = m;
        } else {
            edgeIndex.insert(key, static_cast<int>(def.tr.size()));
            def.tr.push_back({from.toStdString(), sym.toStdString(), to.toStdString()});
            def.transitions.push_back(m);
        }
    }

    // Accept states must be known; drop unknown ones with a warning.
    {
        QStringList kept;
        for (const QString& a : std::as_const(def.accept)) {
            if (def.states.contains(a))
                kept << a;
            else
                warnings << QStringLiteral("accept state \"%1\" is not a state — ignored").arg(a);
        }
        def.accept = kept;
    }

    // Per-state entry/exit actions: one "state : entry : exit" line each (split on
    // the first two colons; either action may be blank). Parsed after the state
    // set is final so unknown-state actions can be rejected.
    for (const QString& rawLine : actionsText.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        if (rawLine.trimmed().isEmpty())
            continue;
        const int c1 = rawLine.indexOf(QLatin1Char(':'));
        if (c1 < 0) {
            warnings << QStringLiteral(
                            "malformed action \"%1\" (need: state : entry : exit) — skipped")
                            .arg(rawLine.trimmed());
            continue;
        }
        const QString state = rawLine.left(c1).trimmed();
        const QString rest = rawLine.mid(c1 + 1);
        const int c2 = rest.indexOf(QLatin1Char(':'));
        const QString entryTxt = (c2 < 0 ? rest : rest.left(c2)).trimmed();
        const QString exitTxt = (c2 < 0 ? QString() : rest.mid(c2 + 1)).trimmed();
        if (state.isEmpty())
            continue;
        if (!def.states.contains(state)) {
            warnings << QStringLiteral("action for state \"%1\" which is not a state — ignored")
                            .arg(state);
            continue;
        }
        if (!entryTxt.isEmpty()) {
            def.entry[state] = entryTxt;
            def.entryActions[state] = entryTxt;
        }
        if (!exitTxt.isEmpty()) {
            def.exit[state] = exitTxt;
            def.exitActions[state] = exitTxt;
        }
    }

    // Fatal errors (these block the build).
    if (def.states.isEmpty())
        r.error = QStringLiteral("No states defined.");
    else if (def.initial.isEmpty())
        r.error = QStringLiteral("No initial state.");
    else if (!def.states.contains(def.initial))
        r.error = QStringLiteral("Initial state \"%1\" is not a state.").arg(def.initial);

    return r;
}

}  // namespace fsmdef
