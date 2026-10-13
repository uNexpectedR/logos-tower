import { NextResponse } from "next/server";
import { getRelayStatus } from "@/lib/waku-relay";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  const status = await getRelayStatus();
  return NextResponse.json(status);
}
