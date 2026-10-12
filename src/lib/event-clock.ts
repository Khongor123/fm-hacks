import { createClient } from "@/lib/supabase/server";

export async function getEventNow(supabase: Awaited<ReturnType<typeof createClient>>): Promise<number> {
  const { data, error } = await supabase.rpc("event_now");
  if (error || typeof data !== "string") {
    throw new Error("Event clock is unavailable. Apply the event submissions migration before running this site.");
  }
  const now = Date.parse(data);
  if (!Number.isFinite(now)) throw new Error("Event clock returned an invalid time.");
  return now;
}
