#include <QGuiApplication>
#include <QQmlApplicationEngine>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    // used by QtCore's Settings (saved theme) and by QSettings (pinned folders)
    app.setOrganizationName("Files");
    app.setApplicationName("Files");

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, [] { QCoreApplication::exit(-1); }, Qt::QueuedConnection);
    engine.loadFromModule("Files", "Main");
    return app.exec();
}
