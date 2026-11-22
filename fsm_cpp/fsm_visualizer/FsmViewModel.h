#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>
#include <QtQmlIntegration>

#include "FsmDefinition.h"
#include "FsmMachine.h"

class QTimer;

// QML-facing view-model (MVVM): exposes the FSM definition, live run state and
// commands that QML data-binds to. It owns no domain logic itself — it
// orchestrates the single-responsibility helpers: fsmdef (parse/validate the
// definition), FsmMachine (build + run the fsm::dfa), FsmCodecs (C++/DOT
// serialize + parse) and fsmstore (file I/O) — and adds the UI-level concerns:
// run animation pacing (QTimer), the activity log and QSettings persistence.
class FsmViewModel : public QObject {
  Q_OBJECT
  QML_ELEMENT

  // --- definition (parsed from the form) ---
  Q_PROPERTY(QStringList states READ states NOTIFY definitionChanged)
  Q_PROPERTY(QStringList symbols READ symbols NOTIFY definitionChanged)
  Q_PROPERTY(QStringList acceptStates READ acceptStates NOTIFY definitionChanged)
  Q_PROPERTY(QString initialState READ initialState NOTIFY definitionChanged)
  // Each entry is a map { from, symbol, to }.
  Q_PROPERTY(QVariantList transitions READ transitions NOTIFY definitionChanged)
  // Per-state entry/exit action text, keyed by state name (annotated states only).
  Q_PROPERTY(QVariantMap entryActions READ entryActions NOTIFY definitionChanged)
  Q_PROPERTY(QVariantMap exitActions READ exitActions NOTIFY definitionChanged)
  // Fatal error that blocked the last build (empty when the build succeeded).
  Q_PROPERTY(QString error READ error NOTIFY definitionChanged)
  // Non-fatal issues from the last build (duplicates, inferred/undeclared names,
  // malformed lines, nondeterminism). The machine still builds.
  Q_PROPERTY(QStringList warnings READ warnings NOTIFY definitionChanged)

  // --- live run state ---
  Q_PROPERTY(bool built READ built NOTIFY runChanged)
  Q_PROPERTY(QString current READ current NOTIFY runChanged)
  Q_PROPERTY(bool live READ live NOTIFY runChanged)
  Q_PROPERTY(bool accepted READ accepted NOTIFY runChanged)
  Q_PROPERTY(QStringList available READ available NOTIFY runChanged)
  Q_PROPERTY(bool running READ running NOTIFY runChanged)
  // Milliseconds between steps during an animated run (tunable from the UI).
  Q_PROPERTY(int stepInterval READ stepInterval WRITE setStepInterval NOTIFY stepIntervalChanged)
  // Sequence of states visited since the last reset (the trace of the run).
  Q_PROPERTY(QStringList path READ path NOTIFY runChanged)
  // The transition that fired most recently (for edge highlighting); empty if none.
  Q_PROPERTY(QString lastFrom READ lastFrom NOTIFY runChanged)
  Q_PROPERTY(QString lastSymbol READ lastSymbol NOTIFY runChanged)
  Q_PROPERTY(QString lastTo READ lastTo NOTIFY runChanged)
  Q_PROPERTY(QString log READ log NOTIFY logChanged)

  // Last-built definition, restored from QSettings so the form reloads on launch.
  Q_PROPERTY(QString savedSymbols READ savedSymbols CONSTANT)
  Q_PROPERTY(QString savedStates READ savedStates CONSTANT)
  Q_PROPERTY(QString savedTransitions READ savedTransitions CONSTANT)
  Q_PROPERTY(QString savedInitial READ savedInitial CONSTANT)
  Q_PROPERTY(QString savedAccept READ savedAccept CONSTANT)
  Q_PROPERTY(QString savedActions READ savedActions CONSTANT)

 public:
  explicit FsmViewModel(QObject* parent = nullptr);
  ~FsmViewModel();

  QStringList states() const { return m_def.states; }
  QStringList symbols() const { return m_def.symbols; }
  QStringList acceptStates() const { return m_def.accept; }
  QString initialState() const { return m_def.initial; }
  QVariantList transitions() const { return m_def.transitions; }
  QVariantMap entryActions() const { return m_def.entryActions; }
  QVariantMap exitActions() const { return m_def.exitActions; }
  // Same data as the `transitions` property, but as a method: QML reads a
  // QVariantList *property* by re-invoking the getter on every access by every
  // binding that touches it (rebuilding the whole list each time), which storms
  // into a multi-second freeze on a large machine. The view snapshots this once
  // per definitionChanged into a plain property instead. See GraphView transList.
  Q_INVOKABLE QVariantList transitionList() const { return m_def.transitions; }
  QString error() const { return m_error; }
  QStringList warnings() const { return m_warnings; }
  bool built() const { return m_machine.built(); }
  QString current() const { return m_machine.current(); }
  bool live() const { return m_machine.live(); }
  bool accepted() const { return m_machine.accepted(); }
  QStringList available() const { return m_machine.available(); }
  bool running() const;
  int stepInterval() const { return m_stepInterval; }
  void setStepInterval(int ms);
  QStringList path() const { return m_machine.path(); }
  QString lastFrom() const { return m_machine.lastFrom(); }
  QString lastSymbol() const { return m_machine.lastSymbol(); }
  QString lastTo() const { return m_machine.lastTo(); }
  QString log() const { return m_log; }
  QString savedSymbols() const { return m_savedSymbols; }
  QString savedStates() const { return m_savedStates; }
  QString savedTransitions() const { return m_savedTransitions; }
  QString savedInitial() const { return m_savedInitial; }
  QString savedAccept() const { return m_savedAccept; }
  QString savedActions() const { return m_savedActions; }

  // Parse the form fields and (re)build the machine. transitionsText is a list of
  // "from, symbol, to" triples separated by ';' or newlines; actionsText is a
  // list of "state : entry : exit" lines (either action may be blank).
  Q_INVOKABLE void build(const QString& symbolsCsv, const QString& statesCsv,
                         const QString& transitionsText, const QString& initial,
                         const QString& acceptCsv, const QString& actionsText);
  Q_INVOKABLE void step(const QString& symbol);  // apply one symbol immediately
  Q_INVOKABLE void runWord(const QString& word);  // reset, then animate over tokens
  Q_INVOKABLE void reset();                       // back to s₀
  Q_INVOKABLE void stopRun();                     // halt an animation
  Q_INVOKABLE void clearAll();

  // Save/load the whole document (definition + view/run config) as JSON. The QML
  // layer assembles/applies the map; this just does the file + JSON I/O.
  Q_INVOKABLE bool saveToFile(const QUrl& fileUrl, const QVariantMap& data);
  Q_INVOKABLE QVariantMap loadFromFile(const QUrl& fileUrl);

  // Emit the current (built) machine as fsm::dfa<std::string,std::string> builder
  // code, ready to paste into the library / Generator3.
  Q_INVOKABLE QString exportCpp() const;
  // Emit the machine as a Graphviz DOT digraph (abstract; Graphviz lays it out).
  Q_INVOKABLE QString exportDot() const;
  // Write arbitrary text (e.g. generated code) to a file.
  Q_INVOKABLE bool saveTextToFile(const QUrl& fileUrl, const QString& text);
  // Read a text file (for importing C++); empty string on failure.
  Q_INVOKABLE QString readTextFromFile(const QUrl& fileUrl);
  // Append a line to the activity log (for QML-side status messages).
  Q_INVOKABLE void logMessage(const QString& line) { appendLog(line); }
  // Parse fsm::dfa builder code (start/accept/on calls, any variable name) into a
  // definition map { symbols, states, transitions, initial, accept }. Empty map
  // if nothing recognisable was found.
  Q_INVOKABLE QVariantMap importCpp(const QString& code) const;
  // Parse a Graphviz DOT digraph into the same definition map. Accepting states
  // are doublecircle nodes; the initial state is the target of an edge from a
  // point/none-shaped marker node.
  Q_INVOKABLE QVariantMap importDot(const QString& code) const;

 signals:
  void definitionChanged();
  void runChanged();
  void logChanged();
  void stepIntervalChanged();
  // Emitted each time a transition actually fires (step or animated run), so the
  // view can animate the firing edge and pulse the entered state.
  void stepped();

 private:
  void appendLog(const QString& line);
  // QSettings persistence of the raw form fields (prefill on next launch).
  void persistDefinition(const QString& symbolsCsv, const QString& statesCsv,
                         const QString& transitionsText, const QString& initial,
                         const QString& acceptCsv, const QString& actionsText);
  void restoreSavedDefinition();

  fsmdef::FsmDefinition m_def;  // parsed definition (states/symbols/transitions/…)
  QString m_error;
  QStringList m_warnings;

  FsmMachine m_machine;  // the fsm::dfa and live run state

  // Restored definition text (QSettings), used to prefill the form on launch.
  QString m_savedSymbols, m_savedStates, m_savedTransitions, m_savedInitial, m_savedAccept,
      m_savedActions;

  // run animation
  QStringList m_queue;
  QTimer* m_timer = nullptr;
  int m_stepInterval = 700;
  QString m_log;
};
