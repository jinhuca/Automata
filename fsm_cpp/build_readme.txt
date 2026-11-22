Both updated to 1.0.1:

CMakeLists.txt:3 — project(fsm_visualizer VERSION 1.0.1 …)
installer.iss:10 — #define AppVersion "1.0.1" (drives the setup filename)
That's the full bump per the project's packaging README — those are the only two spots (the qt_add_qml_module … VERSION 1.0 on line 39 is the QML import version, not the app version, so it stays).

To produce the 1.0.1 build/installer, re-run the packaging script from fsm_visualizer/:


powershell -ExecutionPolicy Bypass -File packaging/package.ps1

which outputs build-release\fsm_visualizer-1.0.1-setup.exe.

Want me to commit these two version edits (and, if you like, kick off package.ps1 to verify the build)?