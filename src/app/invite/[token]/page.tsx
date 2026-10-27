import type { Metadata } from "next";
import { createClient } from "@/lib/supabase/server";
import { InviteForms } from "./invite-forms";

export const metadata: Metadata = { title: "Organizer invitation", robots: { index: false, follow: false }, referrer: "no-referrer" };
export default async function Invite({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  return <main className="auth-page"><div className="shell auth-layout"><div className="auth-side"><p className="section-kicker">F&MHACKS 2026</p><h1>Help make<br/><em>it happen.</em></h1><p>This single-use organizer invitation is valid for seven days. Use the exact F&M email the organizer invited.</p></div><InviteForms token={token} signedInEmail={user?.email} /></div></main>;
}
