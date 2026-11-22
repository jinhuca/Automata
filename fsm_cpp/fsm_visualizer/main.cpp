#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQuickStyle>

#ifndef APP_VERSION
#  define APP_VERSION "0.0.0"   // normally injected from the CMake project version
#endif

int main(int argc, char* argv[]) {
  QGuiApplication app(argc, argv);
  // Identify the app so QSettings persists the last definition between runs.
  QCoreApplication::setOrganizationName(QStringLiteral("fsm_cpp"));
  QCoreApplication::setApplicationName(QStringLiteral("fsm_visualizer"));
  QCoreApplication::setApplicationVersion(QStringLiteral(APP_VERSION));  // -> Qt.application.version
  // Window / taskbar icon (the frameless window has no native title bar, so this
  // drives the taskbar and Alt-Tab entry at runtime).
  app.setWindowIcon(QIcon(QStringLiteral(":/qt/qml/FsmVis/appicon.png")));
  QQuickStyle::setStyle(QStringLiteral("Fusion"));

  QQmlApplicationEngine engine;
  QObject::connect(
      &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
      [] { QCoreApplication::exit(-1); }, Qt::QueuedConnection);
  engine.loadFromModule("FsmVis", "Main");
  if (engine.rootObjects().isEmpty()) return -1;
  return app.exec();
}
