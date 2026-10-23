#include "filemodel.h"

#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QLocale>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QUrl>
#include <algorithm>
#include <utility>

QList<FileModel *> FileModel::s_instances;
QStringList FileModel::s_clip;
bool FileModel::s_cut = false;
QStringList FileModel::s_pinned;
bool FileModel::s_pinnedLoaded = false;

void FileModel::notifyClipboard()
{
    for (FileModel *m : std::as_const(s_instances))
        emit m->clipboardChanged();
}

void FileModel::notifyPinned()
{
    for (FileModel *m : std::as_const(s_instances))
        emit m->pinnedChanged();
}

// ---------- helpers ----------
static QString fmtSize(qint64 bytes)
{
    return QLocale().formattedDataSize(bytes, 1, QLocale::DataSizeSIFormat);
}

static int childCount(const QFileInfo &fi)
{
    return int(QDir(fi.absoluteFilePath())
                   .entryList(QDir::AllEntries | QDir::NoDotAndDotDot).size());
}

static bool isRealDir(const QFileInfo &fi) { return fi.isDir() && !fi.isSymLink(); }

static bool pathTaken(const QString &p)
{
    const QFileInfo fi(p);
    return fi.exists() || fi.isSymLink();
}

// "name.txt" -> "name (1).txt" when "name.txt" already exists
static QString uniquePath(const QString &dir, const QString &name, bool isDir)
{
    QString p = dir + '/' + name;
    if (!pathTaken(p))
        return p;
    const QFileInfo nf(name);
    const QString base = isDir ? name : nf.completeBaseName();
    const QString suf = (isDir || nf.suffix().isEmpty()) ? QString() : '.' + nf.suffix();
    for (int i = 1;; ++i) {
        p = dir + '/' + base + " (" + QString::number(i) + ")" + suf;
        if (!pathTaken(p))
            return p;
    }
}

static bool copyRecursively(const QString &src, const QString &dst)
{
    const QFileInfo fi(src);
    if (isRealDir(fi)) {
        if (!QDir().mkpath(dst))
            return false;
        const auto entries = QDir(src).entryInfoList(
            QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
        for (const QFileInfo &e : entries)
            if (!copyRecursively(e.absoluteFilePath(), dst + '/' + e.fileName()))
                return false;
        return true;
    }
    return QFile::copy(src, dst);
}

static bool removePath(const QString &p)
{
    const QFileInfo fi(p);
    return isRealDir(fi) ? QDir(p).removeRecursively() : QFile::remove(p);
}

// rename, falling back to copy + delete (e.g. across drives)
static bool movePath(const QString &from, const QString &to)
{
    if (QDir().rename(from, to))
        return true;
    return copyRecursively(from, to) && removePath(from);
}

// remove the .trashinfo that belongs to a trashed item we are restoring
static void cleanTrashInfo(const QString &trashedPath)
{
    const int i = trashedPath.lastIndexOf(QStringLiteral("/files/"));
    if (i < 0)
        return;
    QFile::remove(trashedPath.left(i) + "/info/" + QFileInfo(trashedPath).fileName()
                  + ".trashinfo");
}

// ---------- model ----------
FileModel::FileModel(QObject *parent) : QAbstractListModel(parent)
{
    m_path = QDir::homePath();

    s_instances.append(this);
    if (!s_pinnedLoaded) {
        s_pinnedLoaded = true;
        QSettings s("Files", "Files");
        const QStringList saved = s.value("pinned").toStringList();
        for (const QString &p : saved)
            if (QFileInfo(p).isDir())
                s_pinned.append(p);
    }

    reload();

    m_reloadTimer.setSingleShot(true);
    m_reloadTimer.setInterval(200);
    connect(&m_reloadTimer, &QTimer::timeout, this, &FileModel::reload);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this,
            [this] { m_reloadTimer.start(); });
    m_watcher.addPath(m_path);
}

FileModel::~FileModel()
{
    s_instances.removeAll(this);
}

int FileModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size());
}

QVariant FileModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_items.size())
        return {};
    const QFileInfo &fi = m_items.at(index.row());
    switch (role) {
    case NameRole:     return fi.fileName();
    case PathRole:     return fi.absoluteFilePath();
    case IsDirRole:    return fi.isDir();
    case SizeRole:     return fi.isDir() ? QString() : fmtSize(fi.size());
    case ExtRole:      return fi.isDir() ? QString() : fi.suffix().toUpper();
    case ItemsRole:    return fi.isDir() ? childCount(fi) : 0;
    case ModifiedRole: return QLocale().toString(fi.lastModified(), QLocale::ShortFormat);
    }
    return {};
}

QHash<int, QByteArray> FileModel::roleNames() const
{
    return {{NameRole, "name"},   {PathRole, "path"},   {IsDirRole, "isDir"},
            {SizeRole, "size"},   {ExtRole, "ext"},     {ItemsRole, "items"},
            {ModifiedRole, "modified"}};
}

QVariantList FileModel::crumbs() const
{
    QVariantList out;
    QDir d(m_path);
    while (true) {
        const QString name = d.isRoot() ? d.path() : d.dirName();
        out.prepend(QVariantMap{{"name", name}, {"path", d.absolutePath()}});
        if (d.isRoot() || !d.cdUp())
            break;
    }
    return out;
}

void FileModel::setFilter(const QString &f)
{
    if (f == m_filter)
        return;
    m_filter = f;
    reload();
    emit filterChanged();
}

void FileModel::setShowHidden(bool on)
{
    if (on == m_showHidden)
        return;
    m_showHidden = on;
    reload();
    emit showHiddenChanged();
}

void FileModel::setSort(int key)
{
    if (key == m_sortKey) {
        m_desc = !m_desc;
    } else {
        m_sortKey = key;
        m_desc = false;
    }
    reload();
    emit sortChanged();
}

void FileModel::reload()
{
    beginResetModel();
    m_items.clear();
    QDir::Filters flags = QDir::AllEntries | QDir::NoDotAndDotDot;
    if (m_showHidden)
        flags |= QDir::Hidden;
    const auto list = QDir(m_path).entryInfoList(flags, QDir::NoSort);
    for (const QFileInfo &fi : list)
        if (m_filter.isEmpty() || fi.fileName().contains(m_filter, Qt::CaseInsensitive))
            m_items.append(fi);

    std::sort(m_items.begin(), m_items.end(), [this](const QFileInfo &a, const QFileInfo &b) {
        if (a.isDir() != b.isDir())
            return a.isDir();                       // folders always first
        int c = 0;
        switch (m_sortKey) {
        case 1:
            if (!a.isDir())
                c = a.size() < b.size() ? -1 : (a.size() > b.size() ? 1 : 0);
            break;
        case 2:
            c = a.lastModified() < b.lastModified() ? -1
                                                    : (a.lastModified() > b.lastModified() ? 1 : 0);
            break;
        case 3:
            c = a.suffix().compare(b.suffix(), Qt::CaseInsensitive);
            break;
        default:
            break;
        }
        if (c == 0)
            c = a.fileName().compare(b.fileName(), Qt::CaseInsensitive);
        return m_desc ? c > 0 : c < 0;
    });
    endResetModel();
    emit countChanged();
}

void FileModel::setPath(const QString &p)
{
    if (!m_watcher.directories().isEmpty())
        m_watcher.removePaths(m_watcher.directories());
    m_path = p;
    m_watcher.addPath(m_path);
    reload();
    emit pathChanged();
    emit navChanged();
}

// ---------- navigation ----------
void FileModel::openPath(const QString &p)
{
    const QFileInfo fi(p);
    if (!fi.isDir() || !fi.isReadable()) {
        emit failed(tr("Can't open this folder"));
        return;
    }
    const QString np = QDir::cleanPath(fi.absoluteFilePath());
    if (np == m_path)
        return;
    m_back.append(m_path);
    m_fwd.clear();
    setPath(np);
}

void FileModel::jumpTo(const QString &p)
{
    const QFileInfo fi(p);
    if (!fi.isDir() || !fi.isReadable())
        return;
    m_back.clear();
    m_fwd.clear();
    setPath(QDir::cleanPath(fi.absoluteFilePath()));
}

void FileModel::back()
{
    if (m_back.isEmpty())
        return;
    m_fwd.append(m_path);
    setPath(m_back.takeLast());
}

void FileModel::forward()
{
    if (m_fwd.isEmpty())
        return;
    m_back.append(m_path);
    setPath(m_fwd.takeLast());
}

void FileModel::up()
{
    QDir d(m_path);
    if (d.cdUp())
        openPath(d.absolutePath());
}

void FileModel::activate(int row)
{
    if (row < 0 || row >= m_items.size())
        return;
    const QFileInfo &fi = m_items.at(row);
    if (fi.isDir())
        openPath(fi.absoluteFilePath());
    else if (!QDesktopServices::openUrl(QUrl::fromLocalFile(fi.absoluteFilePath())))
        emit failed(tr("No application found to open this file"));
}

void FileModel::openTerminal()
{
    const QStringList names = {"ptyxis", "gnome-terminal", "konsole", "xfce4-terminal",
                               "kitty", "alacritty", "xterm"};
    for (const QString &n : names) {
        const QString exe = QStandardPaths::findExecutable(n);
        if (exe.isEmpty())
            continue;
        QStringList args;
        if (n == "ptyxis" || n == "gnome-terminal" || n == "xfce4-terminal")
            args << "--working-directory=" + m_path;
        else if (n == "konsole")
            args << "--workdir" << m_path;
        else if (n == "kitty")
            args << "--directory" << m_path;
        else if (n == "alacritty")
            args << "--working-directory" << m_path;
        QProcess::startDetached(exe, args, m_path);
        return;
    }
    emit failed(tr("No terminal emulator found"));
}

// ---------- persistent UI settings ----------
QString FileModel::loadSetting(const QString &key, const QString &def) const
{
    QSettings s("Files", "Files");
    return s.value("ui/" + key, def).toString();
}

void FileModel::saveSetting(const QString &key, const QString &value)
{
    QSettings s("Files", "Files");
    s.setValue("ui/" + key, value);
}

// ---------- history ----------
void FileModel::push(const Op &op)
{
    m_undo.append(op);
    while (m_undo.size() > 50)
        m_undo.removeFirst();
    m_redo.clear();
    emit historyChanged();
}

bool FileModel::applyUndo(Op &op)
{
    bool ok = true;
    for (int i = int(op.items.size()) - 1; i >= 0; --i) {
        const Entry &e = op.items.at(i);
        switch (op.type) {
        case OpMove:
            if (pathTaken(e.from)) { ok = false; break; }
            ok = movePath(e.to, e.from) && ok;
            break;
        case OpCopy:
        case OpCreate:
            ok = QFile::moveToTrash(e.to) && ok;
            break;
        case OpTrash:
            if (pathTaken(e.from)) { ok = false; break; }
            if (movePath(e.to, e.from))
                cleanTrashInfo(e.to);
            else
                ok = false;
            break;
        }
    }
    return ok;
}

bool FileModel::applyRedo(Op &op)
{
    bool ok = true;
    for (Entry &e : op.items) {
        switch (op.type) {
        case OpMove:
            if (pathTaken(e.to)) { ok = false; break; }
            ok = movePath(e.from, e.to) && ok;
            break;
        case OpCopy:
            if (pathTaken(e.to)) { ok = false; break; }
            ok = copyRecursively(e.from, e.to) && ok;
            break;
        case OpCreate: {
            bool made;
            if (e.isDir) {
                made = QDir().mkdir(e.to);
            } else {
                QFile f(e.to);
                made = f.open(QIODevice::WriteOnly);
            }
            ok = made && ok;
            break;
        }
        case OpTrash: {
            QString t;
            if (QFile::moveToTrash(e.from, &t))
                e.to = t;
            else
                ok = false;
            break;
        }
        }
    }
    return ok;
}

QString FileModel::undo()
{
    if (m_undo.isEmpty())
        return {};
    Op op = m_undo.takeLast();
    const bool ok = applyUndo(op);
    if (ok)
        m_redo.append(op);
    else
        emit failed(tr("Couldn't undo %1").arg(op.label));
    emit historyChanged();
    reload();
    return ok ? op.label : QString();
}

QString FileModel::redo()
{
    if (m_redo.isEmpty())
        return {};
    Op op = m_redo.takeLast();
    const bool ok = applyRedo(op);
    if (ok)
        m_undo.append(op);
    else
        emit failed(tr("Couldn't redo %1").arg(op.label));
    emit historyChanged();
    reload();
    return ok ? op.label : QString();
}

// ---------- file operations ----------
void FileModel::copyItems(const QStringList &paths)
{
    s_clip = paths;
    s_cut = false;
    notifyClipboard();
}

void FileModel::cutItems(const QStringList &paths)
{
    s_clip = paths;
    s_cut = true;
    notifyClipboard();
}

QString FileModel::transfer(const QStringList &paths, const QString &destDir, bool copy)
{
    QString last;
    bool failedAny = false;
    Op op;
    op.type = copy ? OpCopy : OpMove;
    op.label = copy ? tr("copy") : tr("move");

    for (const QString &src : paths) {
        const QFileInfo fi(src);
        if (!fi.exists()) { failedAny = true; continue; }
        const bool dir = isRealDir(fi);

        if (dir && (destDir == src || destDir.startsWith(src + '/'))) {
            emit failed(tr("Can't copy a folder into itself"));
            continue;
        }
        if (!copy && fi.absolutePath() == destDir) {      // moved onto itself: nothing to do
            last = fi.fileName();
            continue;
        }

        const QString dst = uniquePath(destDir, fi.fileName(), dir);
        const bool ok = copy ? copyRecursively(src, dst) : movePath(src, dst);
        if (ok) {
            last = QFileInfo(dst).fileName();
            op.items.append({src, dst, dir});
        } else {
            failedAny = true;
        }
    }

    if (failedAny)
        emit failed(tr("Some items couldn't be transferred"));
    if (!op.items.isEmpty())
        push(op);
    reload();
    return last;
}

QString FileModel::paste()
{
    const bool cut = s_cut;
    const QString name = transfer(s_clip, m_path, !cut);
    if (cut) {
        s_clip.clear();
        s_cut = false;
        notifyClipboard();
    }
    return name;
}

bool FileModel::trashItems(const QStringList &paths)
{
    bool failedAny = false;
    Op op;
    op.type = OpTrash;
    op.label = tr("trash");
    for (const QString &p : paths) {
        const bool dir = isRealDir(QFileInfo(p));
        QString inTrash;
        if (QFile::moveToTrash(p, &inTrash))
            op.items.append({p, inTrash, dir});
        else
            failedAny = true;
    }
    if (failedAny)
        emit failed(tr("Couldn't move some items to Trash"));
    if (!op.items.isEmpty())
        push(op);
    reload();
    return !failedAny;
}

bool FileModel::removeItems(const QStringList &paths)
{
    bool ok = true;
    for (const QString &p : paths)
        ok = removePath(p) && ok;
    if (!ok)
        emit failed(tr("Couldn't delete some items"));
    reload();
    return ok;
}

bool FileModel::rename(const QString &path, const QString &newName)
{
    const QString n = newName.trimmed();
    const QFileInfo fi(path);
    if (n.isEmpty() || n == "." || n == ".." || n.contains('/')) {
        emit failed(tr("That name isn't valid"));
        return false;
    }
    if (n == fi.fileName())
        return true;
    const QString dst = fi.absolutePath() + '/' + n;
    if (pathTaken(dst)) {
        emit failed(tr("“%1” already exists").arg(n));
        return false;
    }
    const bool dir = isRealDir(fi);
    if (!QDir().rename(path, dst)) {
        emit failed(tr("Couldn't rename (permission denied?)"));
        return false;
    }
    Op op;
    op.type = OpMove;
    op.label = tr("rename");
    op.items.append({path, dst, dir});
    push(op);
    reload();
    return true;
}

QString FileModel::newFolder(const QString &name)
{
    const QString n = name.trimmed().isEmpty() ? tr("New Folder") : name.trimmed();
    if (n.contains('/')) {
        emit failed(tr("That name isn't valid"));
        return {};
    }
    const QString p = uniquePath(m_path, n, true);
    if (!QDir().mkdir(p)) {
        emit failed(tr("Couldn't create the folder"));
        return {};
    }
    Op op;
    op.type = OpCreate;
    op.label = tr("new folder");
    op.items.append({QString(), p, true});
    push(op);
    reload();
    return QFileInfo(p).fileName();
}

QString FileModel::newFile(const QString &name)
{
    const QString n = name.trimmed().isEmpty() ? QStringLiteral("untitled.txt") : name.trimmed();
    if (n.contains('/')) {
        emit failed(tr("That name isn't valid"));
        return {};
    }
    const QString p = uniquePath(m_path, n, false);
    QFile f(p);
    if (!f.open(QIODevice::WriteOnly)) {
        emit failed(tr("Couldn't create the file"));
        return {};
    }
    f.close();
    Op op;
    op.type = OpCreate;
    op.label = tr("new file");
    op.items.append({QString(), p, false});
    push(op);
    reload();
    return QFileInfo(p).fileName();
}

// ---------- pinned folders ----------
void FileModel::savePinned()
{
    QSettings s("Files", "Files");
    s.setValue("pinned", s_pinned);
    notifyPinned();
}

void FileModel::pin(const QString &path)
{
    const QFileInfo fi(path);
    if (!fi.isDir())
        return;
    const QString p = fi.absoluteFilePath();
    if (s_pinned.contains(p))
        return;
    s_pinned.append(p);
    savePinned();
}

void FileModel::unpin(const QString &path)
{
    if (s_pinned.removeAll(path) > 0)
        savePinned();
}

// ---------- lookups ----------
int FileModel::indexOf(const QString &name) const
{
    for (int i = 0; i < m_items.size(); ++i)
        if (m_items.at(i).fileName() == name)
            return i;
    return -1;
}

int FileModel::indexOfPath(const QString &path) const
{
    if (path.isEmpty())
        return -1;
    for (int i = 0; i < m_items.size(); ++i)
        if (m_items.at(i).absoluteFilePath() == path)
            return i;
    return -1;
}

QString FileModel::pathAt(int row) const
{
    return (row >= 0 && row < m_items.size()) ? m_items.at(row).absoluteFilePath() : QString();
}

QString FileModel::place(const QString &name) const
{
    using SP = QStandardPaths;
    if (name == "home")      return QDir::homePath();
    if (name == "desktop")   return SP::writableLocation(SP::DesktopLocation);
    if (name == "documents") return SP::writableLocation(SP::DocumentsLocation);
    if (name == "downloads") return SP::writableLocation(SP::DownloadLocation);
    if (name == "pictures")  return SP::writableLocation(SP::PicturesLocation);
    if (name == "root")      return QDir::rootPath();
    return {};
}

QVariantMap FileModel::details(int row) const
{
    QVariantMap m;
    if (row < 0 || row >= m_items.size())
        return m;
    const QFileInfo &fi = m_items.at(row);
    const QLocale loc;
    QDateTime created = fi.birthTime();
    if (!created.isValid())
        created = fi.metadataChangeTime();

    m["name"] = fi.fileName();
    m["path"] = fi.absoluteFilePath();
    m["ext"] = fi.isDir() ? QString() : fi.suffix().toUpper();
    m["isDir"] = fi.isDir();
    m["kind"] = fi.isDir() ? tr("Folder")
                           : (fi.suffix().isEmpty() ? tr("File") : fi.suffix().toUpper() + tr(" file"));
    m["size"] = fi.isDir() ? tr("%1 items").arg(childCount(fi)) : fmtSize(fi.size());
    m["created"] = loc.toString(created, QLocale::ShortFormat);
    m["modified"] = loc.toString(fi.lastModified(), QLocale::ShortFormat);
    m["where"] = fi.absolutePath();
    return m;
}

QVariantMap FileModel::summarize(const QStringList &paths) const
{
    qint64 size = 0;
    int dirs = 0, files = 0;
    for (const QString &p : paths) {
        const QFileInfo fi(p);
        if (fi.isDir()) {
            ++dirs;
        } else {
            ++files;
            size += fi.size();
        }
    }
    QVariantMap m;
    m["count"] = int(paths.size());
    m["folders"] = dirs;
    m["files"] = files;
    m["size"] = fmtSize(size);
    return m;
}

QVariantMap FileModel::diskInfo() const
{
    const QStorageInfo si(m_path);
    const qint64 total = si.bytesTotal();
    const qint64 used = total - si.bytesAvailable();
    QVariantMap m;
    m["used"] = fmtSize(used);
    m["total"] = fmtSize(total);
    m["free"] = fmtSize(si.bytesAvailable());
    m["fraction"] = total > 0 ? double(used) / double(total) : 0.0;
    return m;
}
