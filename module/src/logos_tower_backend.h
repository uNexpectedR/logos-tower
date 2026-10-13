#pragma once

#include "rep_logos_tower_source.h"
#include "logos_ui_plugin_context.h"

#include <QByteArray>
#include <QJsonArray>
#include <QSettings>
#include <QString>

class LogosTowerBackend : public LogosTowerSimpleSource,
                          public LogosUiPluginContext
{
public:
    LogosTowerBackend();

    QString ensurePersona(QString alias) override;
    QString clearPersona() override;
    QString signAndSubmit(int height) override;
    QString leaderboardJson() override;

protected:
    void onContextReady() override;

private:
    QSettings m_settings;
    QJsonArray m_board;

    void loadBoard();
    void saveBoard();
    void refreshPersonaProp();
    QByteArray seedBytes() const;
    static QString toHex(const QByteArray &bytes);
    static QByteArray fromHex(const QString &hex);
    static QString fingerprint(const QByteArray &publicKey);
    static int leadingZeroBits(const QByteArray &hash);
};
