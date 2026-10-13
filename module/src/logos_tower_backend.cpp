#include "logos_tower_backend.h"

extern "C" {
#include "monocypher.h"
#include "monocypher-ed25519.h"
}

#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRandomGenerator>

#include <algorithm>
#include <vector>

namespace {
constexpr int kPowBits = 12;
constexpr int kMaxHeight = 1000000;
constexpr int kTop = 50;
constexpr qint64 kMaxFutureMs = 10LL * 60 * 1000;
const char kCrockford[] = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

QString jsonString(const QString &s)
{
    return QString::fromUtf8(QJsonDocument(QJsonValue(s)).toJson(QJsonDocument::Compact));
}
} // namespace

LogosTowerBackend::LogosTowerBackend()
    : m_settings(QStringLiteral("logos"), QStringLiteral("logos_tower"))
{
}

void LogosTowerBackend::onContextReady()
{
    loadBoard();
    refreshPersonaProp();
    setBoard(QString::fromUtf8(QJsonDocument(m_board).toJson(QJsonDocument::Compact)));
    setStatus(QStringLiteral("Ready"));
    setMessage(QStringLiteral("Create a persona, play, submit a signed height."));
}

QString LogosTowerBackend::toHex(const QByteArray &bytes)
{
    return QString::fromLatin1(bytes.toHex());
}

QByteArray LogosTowerBackend::fromHex(const QString &hex)
{
    return QByteArray::fromHex(hex.toLatin1());
}

int LogosTowerBackend::leadingZeroBits(const QByteArray &hash)
{
    int bits = 0;
    for (unsigned char byte : hash) {
        if (byte == 0) {
            bits += 8;
            continue;
        }
        for (int i = 7; i >= 0; --i) {
            if (byte & (1u << i))
                return bits;
            ++bits;
        }
        break;
    }
    return bits;
}

QString LogosTowerBackend::fingerprint(const QByteArray &publicKey)
{
    uint8_t hash[16];
    crypto_blake2b_general(hash, 16, nullptr, 0,
                           reinterpret_cast<const uint8_t *>(publicKey.constData()),
                           static_cast<size_t>(publicKey.size()));
    quint64 bits = 0;
    for (int i = 0; i < 5; ++i)
        bits = (bits << 8) | hash[i];
    QString out = QStringLiteral("lt:");
    for (int i = 7; i >= 0; --i) {
        out += QLatin1Char(kCrockford[(bits >> (i * 5)) & 0x1f]);
        if (i == 4)
            out += QLatin1Char('-');
    }
    return out;
}

QByteArray LogosTowerBackend::seedBytes() const
{
    return fromHex(m_settings.value(QStringLiteral("seed")).toString());
}

void LogosTowerBackend::refreshPersonaProp()
{
    const QByteArray seed = seedBytes();
    if (seed.size() != 32) {
        setPersona(QStringLiteral("—"));
        return;
    }
    uint8_t pk[32];
    crypto_ed25519_public_key(pk, reinterpret_cast<const uint8_t *>(seed.constData()));
    const QString alias = m_settings.value(QStringLiteral("alias")).toString().trimmed().left(24);
    const QString fp = fingerprint(QByteArray(reinterpret_cast<const char *>(pk), 32));
    setPersona(alias.isEmpty() ? fp : (alias + QStringLiteral(" · ") + fp));
}

void LogosTowerBackend::loadBoard()
{
    m_board = QJsonDocument::fromJson(
                  m_settings.value(QStringLiteral("board")).toByteArray())
                  .array();
}

void LogosTowerBackend::saveBoard()
{
    m_settings.setValue(QStringLiteral("board"),
                        QJsonDocument(m_board).toJson(QJsonDocument::Compact));
    setBoard(QString::fromUtf8(QJsonDocument(m_board).toJson(QJsonDocument::Compact)));
}

QString LogosTowerBackend::ensurePersona(QString alias)
{
    alias = alias.trimmed().left(24);
    QByteArray seed = seedBytes();
    if (seed.size() != 32) {
        seed.resize(32);
        for (int i = 0; i < 32; ++i)
            seed[i] = static_cast<char>(QRandomGenerator::global()->generate() & 0xff);
        m_settings.setValue(QStringLiteral("seed"), toHex(seed));
    }
    m_settings.setValue(QStringLiteral("alias"), alias);
    refreshPersonaProp();
    setMessage(QStringLiteral("Persona ready. Seed stays in this Basecamp profile."));
    setStatus(QStringLiteral("Logged in"));
    return persona();
}

QString LogosTowerBackend::clearPersona()
{
    QByteArray seed = seedBytes();
    if (!seed.isEmpty())
        crypto_wipe(seed.data(), static_cast<size_t>(seed.size()));
    m_settings.remove(QStringLiteral("seed"));
    m_settings.remove(QStringLiteral("alias"));
    refreshPersonaProp();
    setMessage(QStringLiteral("Logged out."));
    setStatus(QStringLiteral("Ready"));
    return QStringLiteral("ok");
}

QString LogosTowerBackend::signAndSubmit(int height)
{
    if (height < 0 || height > kMaxHeight) {
        setMessage(QStringLiteral("Invalid height."));
        return {};
    }
    QByteArray seed = seedBytes();
    if (seed.size() != 32) {
        setMessage(QStringLiteral("Create a persona first."));
        return {};
    }

    uint8_t pk[32];
    crypto_ed25519_public_key(pk, reinterpret_cast<const uint8_t *>(seed.constData()));
    const QString alias = m_settings.value(QStringLiteral("alias")).toString().trimmed().left(24);
    const qint64 ts = QDateTime::currentMSecsSinceEpoch();
    if (ts > QDateTime::currentMSecsSinceEpoch() + kMaxFutureMs) {
        setMessage(QStringLiteral("Timestamp invalid."));
        return {};
    }

    const QByteArray pkHexBytes = QByteArray(reinterpret_cast<const char *>(pk), 32);
    const QString pkHex = toHex(pkHexBytes);
    const QByteArray canonBytes =
        QStringLiteral("{\"alias\":%1,\"height\":%2,\"powBits\":%3,\"publicKey\":%4,\"timestampMs\":%5,\"version\":1}")
            .arg(jsonString(alias))
            .arg(height)
            .arg(kPowBits)
            .arg(jsonString(pkHex))
            .arg(ts)
            .toUtf8();

    uint8_t nonce[8];
    for (int i = 0; i < 8; ++i)
        nonce[i] = static_cast<uint8_t>(QRandomGenerator::global()->generate() & 0xff);

    uint8_t work[32];
    int tried = 0;
    for (;;) {
        crypto_blake2b_ctx ctx;
        crypto_blake2b_general_init(&ctx, 32, nullptr, 0);
        crypto_blake2b_update(&ctx, reinterpret_cast<const uint8_t *>(canonBytes.constData()),
                              static_cast<size_t>(canonBytes.size()));
        crypto_blake2b_update(&ctx, nonce, 8);
        crypto_blake2b_final(&ctx, work);
        if (leadingZeroBits(QByteArray(reinterpret_cast<const char *>(work), 32)) >= kPowBits)
            break;
        for (int i = 7; i >= 0; --i) {
            if (++nonce[i] != 0)
                break;
        }
        if (++tried > 4000000) {
            setMessage(QStringLiteral("Proof-of-work took too long."));
            crypto_wipe(seed.data(), static_cast<size_t>(seed.size()));
            return {};
        }
    }

    QByteArray signedMsg = canonBytes;
    signedMsg.append(reinterpret_cast<const char *>(nonce), 8);

    uint8_t sig[64];
    crypto_ed25519_sign(sig,
                        reinterpret_cast<const uint8_t *>(seed.constData()),
                        pk,
                        reinterpret_cast<const uint8_t *>(signedMsg.constData()),
                        static_cast<size_t>(signedMsg.size()));

    if (crypto_ed25519_check(sig, pk,
                             reinterpret_cast<const uint8_t *>(signedMsg.constData()),
                             static_cast<size_t>(signedMsg.size())) != 0) {
        setMessage(QStringLiteral("Signature self-check failed."));
        crypto_wipe(seed.data(), static_cast<size_t>(seed.size()));
        return {};
    }

    uint8_t idHash[16];
    crypto_blake2b_ctx idCtx;
    crypto_blake2b_general_init(&idCtx, 16, nullptr, 0);
    crypto_blake2b_update(&idCtx, reinterpret_cast<const uint8_t *>(signedMsg.constData()),
                          static_cast<size_t>(signedMsg.size()));
    crypto_blake2b_update(&idCtx, sig, 64);
    crypto_blake2b_final(&idCtx, idHash);
    const QString idHex = toHex(QByteArray(reinterpret_cast<const char *>(idHash), 16));

    QJsonObject env{
        {QStringLiteral("alias"), alias},
        {QStringLiteral("height"), height},
        {QStringLiteral("id"), idHex},
        {QStringLiteral("nonce"), toHex(QByteArray(reinterpret_cast<const char *>(nonce), 8))},
        {QStringLiteral("powBits"), kPowBits},
        {QStringLiteral("publicKey"), pkHex},
        {QStringLiteral("signature"), toHex(QByteArray(reinterpret_cast<const char *>(sig), 64))},
        {QStringLiteral("timestampMs"), ts},
        {QStringLiteral("version"), 1},
    };
    QJsonObject wireObj{
        {QStringLiteral("env"), QString::fromUtf8(QJsonDocument(env).toJson(QJsonDocument::Compact))},
        {QStringLiteral("t"), QStringLiteral("score")},
        {QStringLiteral("v"), 1},
    };

    const QString author = alias.isEmpty()
                               ? fingerprint(pkHexBytes)
                               : (alias + QStringLiteral(" · ") + fingerprint(pkHexBytes));

    std::vector<QJsonObject> rows;
    rows.reserve(static_cast<size_t>(m_board.size()) + 1);
    bool replaced = false;
    for (const QJsonValue &v : m_board) {
        QJsonObject o = v.toObject();
        if (o.value(QStringLiteral("publicKeyHex")).toString() == pkHex) {
            if (o.value(QStringLiteral("height")).toInt() < height) {
                o = QJsonObject{
                    {QStringLiteral("author"), author},
                    {QStringLiteral("height"), height},
                    {QStringLiteral("publicKeyHex"), pkHex},
                    {QStringLiteral("timestampMs"), ts},
                    {QStringLiteral("id"), idHex},
                };
            }
            replaced = true;
        }
        rows.push_back(o);
    }
    if (!replaced) {
        rows.push_back(QJsonObject{
            {QStringLiteral("author"), author},
            {QStringLiteral("height"), height},
            {QStringLiteral("publicKeyHex"), pkHex},
            {QStringLiteral("timestampMs"), ts},
            {QStringLiteral("id"), idHex},
        });
    }
    std::sort(rows.begin(), rows.end(), [](const QJsonObject &a, const QJsonObject &b) {
        return a.value(QStringLiteral("height")).toInt() > b.value(QStringLiteral("height")).toInt();
    });
    if (static_cast<int>(rows.size()) > kTop)
        rows.resize(static_cast<size_t>(kTop));

    m_board = QJsonArray();
    for (const QJsonObject &o : rows)
        m_board.append(o);
    saveBoard();

    setMessage(QStringLiteral("Saved %1 (Ed25519 + BLAKE2b PoW verified).").arg(height));
    setStatus(QStringLiteral("Scored"));
    crypto_wipe(seed.data(), static_cast<size_t>(seed.size()));
    return QString::fromUtf8(QJsonDocument(wireObj).toJson(QJsonDocument::Compact).toBase64());
}

QString LogosTowerBackend::leaderboardJson()
{
    return QString::fromUtf8(QJsonDocument(m_board).toJson(QJsonDocument::Compact));
}
