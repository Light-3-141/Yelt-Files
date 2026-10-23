#pragma once

#include <QAbstractListModel>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class FileModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString path READ path NOTIFY pathChanged)
    Q_PROPERTY(QVariantList crumbs READ crumbs NOTIFY pathChanged)
    Q_PROPERTY(bool canGoBack READ canGoBack NOTIFY navChanged)
    Q_PROPERTY(bool canGoForward READ canGoForward NOTIFY navChanged)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
    Q_PROPERTY(bool showHidden READ showHidden WRITE setShowHidden NOTIFY showHiddenChanged)
    Q_PROPERTY(bool canPaste READ canPaste NOTIFY clipboardChanged)
    Q_PROPERTY(QStringList cutPaths READ cutPaths NOTIFY clipboardChanged)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY historyChanged)
    Q_PROPERTY(bool canRedo READ canRedo NOTIFY historyChanged)
    Q_PROPERTY(int sortKey READ sortKey NOTIFY sortChanged)
    Q_PROPERTY(bool descending READ descending NOTIFY sortChanged)
    Q_PROPERTY(QStringList pinned READ pinned NOTIFY pinnedChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        PathRole,
        IsDirRole,
        SizeRole,
        ExtRole,
        ItemsRole,
        ModifiedRole
    };

    explicit FileModel(QObject *parent = nullptr);
    ~FileModel() override;

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString path() const { return m_path; }
    QVariantList crumbs() const;
    bool canGoBack() const { return !m_back.isEmpty(); }
    bool canGoForward() const { return !m_fwd.isEmpty(); }
    QString filter() const { return m_filter; }
    void setFilter(const QString &f);
    bool showHidden() const { return m_showHidden; }
    void setShowHidden(bool on);
    bool canPaste() const { return !s_clip.isEmpty(); }
    QStringList cutPaths() const { return s_cut ? s_clip : QStringList(); }
    bool canUndo() const { return !m_undo.isEmpty(); }
    bool canRedo() const { return !m_redo.isEmpty(); }
    int sortKey() const { return m_sortKey; }
    bool descending() const { return m_desc; }
    QStringList pinned() const { return s_pinned; }

    // navigation
    Q_INVOKABLE void openPath(const QString &p);
    Q_INVOKABLE void jumpTo(const QString &p);        // no history entry (used for new tabs)
    Q_INVOKABLE void back();
    Q_INVOKABLE void forward();
    Q_INVOKABLE void up();
    Q_INVOKABLE void activate(int row);
    Q_INVOKABLE void setSort(int key);                 // same key again flips direction
    Q_INVOKABLE void openTerminal();
    Q_INVOKABLE QString loadSetting(const QString &key, const QString &def) const;
    Q_INVOKABLE void saveSetting(const QString &key, const QString &value);

    // file operations (absolute paths, multi-item)
    Q_INVOKABLE void copyItems(const QStringList &paths);
    Q_INVOKABLE void cutItems(const QStringList &paths);
    Q_INVOKABLE QString paste();                       // returns name of last pasted item
    Q_INVOKABLE QString transfer(const QStringList &paths, const QString &destDir, bool copy);
    Q_INVOKABLE bool trashItems(const QStringList &paths);
    Q_INVOKABLE bool removeItems(const QStringList &paths);   // permanent
    Q_INVOKABLE bool rename(const QString &path, const QString &newName);
    Q_INVOKABLE QString newFolder(const QString &name);
    Q_INVOKABLE QString newFile(const QString &name);
    Q_INVOKABLE QString undo();                        // returns label of what was undone
    Q_INVOKABLE QString redo();

    // pinned folders
    Q_INVOKABLE void pin(const QString &path);
    Q_INVOKABLE void unpin(const QString &path);

    // lookups
    Q_INVOKABLE int indexOf(const QString &name) const;
    Q_INVOKABLE int indexOfPath(const QString &path) const;
    Q_INVOKABLE QString pathAt(int row) const;
    Q_INVOKABLE QString place(const QString &name) const;
    Q_INVOKABLE QVariantMap details(int row) const;
    Q_INVOKABLE QVariantMap summarize(const QStringList &paths) const;
    Q_INVOKABLE QVariantMap diskInfo() const;

signals:
    void pathChanged();
    void navChanged();
    void filterChanged();
    void countChanged();
    void showHiddenChanged();
    void clipboardChanged();
    void historyChanged();
    void sortChanged();
    void pinnedChanged();
    void failed(const QString &message);

private:
    enum OpType { OpMove, OpCopy, OpCreate, OpTrash };
    struct Entry { QString from; QString to; bool isDir = false; };
    struct Op { OpType type = OpMove; QString label; QList<Entry> items; };

    void setPath(const QString &p);
    void reload();
    void push(const Op &op);
    bool applyUndo(Op &op);
    bool applyRedo(Op &op);
    void savePinned();

    QString m_path;
    QString m_filter;
    int m_sortKey = 0;          // 0 name, 1 size, 2 modified, 3 type
    bool m_desc = false;
    bool m_showHidden = false;
    QStringList m_back, m_fwd;
    QList<QFileInfo> m_items;
    QList<Op> m_undo, m_redo;
    QFileSystemWatcher m_watcher;
    QTimer m_reloadTimer;

    static void notifyClipboard();
    static void notifyPinned();

    // shared between all panes/tabs
    static QList<FileModel *> s_instances;
    static QStringList s_clip;
    static bool s_cut;
    static QStringList s_pinned;
    static bool s_pinnedLoaded;
};
