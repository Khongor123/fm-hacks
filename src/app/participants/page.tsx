import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Participants" };

type Participant = { full_name: string; email: string; team_status: string };

export default async function Participants() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: profile } = await supabase.from("profiles").select("admin").eq("id", user.id).single();
  if (!profile) redirect("/account");
  if (profile.admin) redirect("/admin");

  const { data, error } = await supabase.rpc("list_participants");
  const participants = (data ?? []) as Participant[];

  return <main className="dashboard-page"><div className="shell">
    <div className="dashboard-intro"><p className="section-kicker">MY F&MHACKS</p><h1>Participants.</h1><p>Find students and see who has joined a team.</p><Link href="/#dashboard" className="text-link">← Back to dashboard</Link></div>
    {error ? <p role="alert" className="form-notice error">Participants could not be loaded. Please try again later.</p>
      : <div className="roster-wrap"><table className="roster-table participant-directory"><thead><tr><th>Name</th><th>Email</th><th>Team</th></tr></thead><tbody>{participants.map(person => <tr key={person.email}><td>{person.full_name}</td><td>{person.email}</td><td>{person.team_status}</td></tr>)}</tbody></table>{participants.length === 0 && <p className="empty-roster">No participants yet.</p>}</div>}
  </div></main>;
}
