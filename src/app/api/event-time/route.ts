import { createClient } from "@/lib/supabase/server";
import { getEventNow } from "@/lib/event-clock";

export const dynamic = "force-dynamic";
export async function GET() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return Response.json({ error: "Sign in required" }, { status: 401, headers: { "Cache-Control": "no-store" } });
  try {
    const now = await getEventNow(supabase);
    return Response.json({ now }, { headers: { "Cache-Control": "no-store" } });
  } catch {
    return Response.json({ error: "Event clock unavailable" }, { status: 503, headers: { "Cache-Control": "no-store" } });
  }
}
