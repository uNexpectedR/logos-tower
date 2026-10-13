/**
 * Server-side Waku light node for logos.dev — same peer/TCP pattern as ForumerMobile.
 * Browsers cannot dial TCP store nodes; this process is the relay.
 */

import { tcp } from "@libp2p/tcp";
import {
  Protocols,
  createDecoder,
  createEncoder,
  createLightNode,
  waitForRemotePeer,
  type LightNode,
} from "@waku/sdk";
import {
  CLUSTER_ID,
  CONTENT_TOPIC,
  PUBSUB_TOPIC,
  SHARD_ID,
  ScoreError,
  parseWire,
  toBoardEntry,
  verifyScore,
  type BoardEntry,
} from "./score-codec";

const STORE_PEERS = [
  "/dns4/delivery-01.do-ams3.logos.dev.status.im/tcp/30303/p2p/16Uiu2HAmTUbnxLGT9JvV6mu9oPyDjqHK4Phs1VDJNUgESgNSkuby",
  "/dns4/delivery-02.do-ams3.logos.dev.status.im/tcp/30303/p2p/16Uiu2HAmMK7PYygBtKUQ8EHp7EfaD3bCEsJrkFooK8RQ2PVpJprH",
  "/dns4/delivery-01.gc-us-central1-a.logos.dev.status.im/tcp/30303/p2p/16Uiu2HAm4S1JYkuzDKLKQvwgAhZKs9otxXqt8SCGtB4hoJP1S397",
  "/dns4/delivery-02.gc-us-central1-a.logos.dev.status.im/tcp/30303/p2p/16Uiu2HAm8Y9kgBNtjxvCnf1X6gnZJW5EGE4UwwCL3CCm55TwqBiH",
  "/dns4/delivery-01.ac-cn-hongkong-c.logos.dev.status.im/tcp/30303/p2p/16Uiu2HAm8YokiNun9BkeA1ZRmhLbtNUvcwRr64F69tYj9fkGyuEP",
  "/dns4/delivery-02.ac-cn-hongkong-c.logos.dev.status.im/tcp/30303/p2p/16Uiu2HAkvwhGHKNry6LACrB8TmEFoCJKEX29XR5dDUzk3UT3UNSE",
];

const LOOKBACK_MS = 7 * 24 * 60 * 60 * 1000;
const DIAL_TIMEOUT_MS = 12_000;
const QUERY_TIMEOUT_MS = 12_000;

const routingInfo = {
  clusterId: CLUSTER_ID,
  shardId: SHARD_ID,
  pubsubTopic: PUBSUB_TOPIC,
};

let booting: Promise<LightNode> | null = null;

async function boot(): Promise<LightNode> {
  const node = await createLightNode({
    defaultBootstrap: false,
    bootstrapPeers: STORE_PEERS,
    networkConfig: { clusterId: CLUSTER_ID, numShardsInCluster: 8 },
    discovery: { dns: false, peerExchange: false, peerCache: false },
    libp2p: { transports: [tcp()] },
  });
  if (!node.isStarted()) await node.start();
  for (const addr of STORE_PEERS) {
    void node.dial(addr).catch((error: unknown) => {
      console.warn("logos.dev peer dial failed", addr, error);
    });
  }
  await waitForRemotePeer(node, [Protocols.Store], DIAL_TIMEOUT_MS);
  return node;
}

function node(): Promise<LightNode> {
  if (!booting) {
    booting = boot().catch((error: unknown) => {
      booting = null;
      throw error;
    });
  }
  return booting;
}

function peerReady(waku: LightNode, protocol: Protocols): Promise<boolean> {
  return waitForRemotePeer(waku, [protocol], 4_000).then(
    () => true,
    () => false,
  );
}

export type RelayStatus = {
  state: "ready" | "limited" | "down";
  detail: string;
  peers: number;
  store: boolean;
  lightPush: boolean;
};

export async function getRelayStatus(): Promise<RelayStatus> {
  try {
    const waku = await node();
    const peers = await waku.getConnectedPeers();
    const [store, lightPush] = await Promise.all([
      peerReady(waku, Protocols.Store),
      peerReady(waku, Protocols.LightPush),
    ]);
    if (store && lightPush) {
      return {
        state: "ready",
        detail: "Connected to logos.dev store and light-push.",
        peers: peers.length,
        store,
        lightPush,
      };
    }
    if (store || lightPush) {
      return {
        state: "limited",
        detail: "Partial logos.dev connectivity.",
        peers: peers.length,
        store,
        lightPush,
      };
    }
    return {
      state: "down",
      detail: "No logos.dev peer is ready.",
      peers: peers.length,
      store,
      lightPush,
    };
  } catch (error) {
    return {
      state: "down",
      detail: error instanceof Error ? error.message : "Could not reach logos.dev.",
      peers: 0,
      store: false,
      lightPush: false,
    };
  }
}

const decoder = createDecoder(CONTENT_TOPIC, routingInfo);
const encoder = createEncoder({
  contentTopic: CONTENT_TOPIC,
  routingInfo,
  ephemeral: false,
});

export async function fetchNetworkScores(nowMs = Date.now()): Promise<BoardEntry[]> {
  const waku = await node();
  if (!waku.store) throw new ScoreError("No store client.", 503);

  const entries: BoardEntry[] = [];
  const seen = new Set<string>();
  const query = (async () => {
    for await (const batch of waku.store!.queryGenerator([decoder], {
      timeStart: new Date(nowMs - LOOKBACK_MS),
      paginationForward: false,
      paginationLimit: 80,
    })) {
      const messages = await Promise.all(batch);
      for (const message of messages) {
        if (!message?.payload) continue;
        try {
          const env = parseWire(message.payload);
          verifyScore(env, nowMs);
          const entry = toBoardEntry(env);
          if (seen.has(entry.id)) continue;
          seen.add(entry.id);
          entries.push(entry);
        } catch {
          // drop invalid
        }
      }
      if (entries.length >= 200) break;
    }
  })();

  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(
      () => reject(new ScoreError("logos.dev store timed out.", 504)),
      QUERY_TIMEOUT_MS,
    );
  });
  try {
    await Promise.race([query, timeout]);
  } finally {
    clearTimeout(timer);
  }

  return entries;
}

export async function publishScoreWire(wireBytes: Uint8Array): Promise<void> {
  const env = parseWire(wireBytes);
  verifyScore(env);
  const waku = await node();
  if (!waku.lightPush) throw new ScoreError("No light-push client.", 503);
  try {
    await waitForRemotePeer(waku, [Protocols.LightPush], DIAL_TIMEOUT_MS);
  } catch {
    throw new ScoreError("No logos.dev peer is ready for light-push.", 503);
  }
  const result = await waku.lightPush.send(encoder, { payload: wireBytes });
  if (result.successes.length === 0) {
    const reason = result.failures[0]?.error ?? "no peer accepted the score";
    throw new ScoreError(`Signed score not accepted by logos.dev (${reason}).`, 502);
  }
}
