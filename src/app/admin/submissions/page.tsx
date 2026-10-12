import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SlideDownload } from "@/components/slide-download";
import { TRACKS, type Submission } from "@/lib/event";

export const metadata: Metadata = { title: "Organizer submissions" };
type Entry = Submission & { team_name: string | null; members: { name: string; checked_in_at: string | null }[] | null };
export default async function OrganizerSubmissions() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: me } = await supabase.from("profiles").select("admin").eq("id", user.id).single();
  if (!me?.admin) redirect("/account");
  const { data, error } = await supabase.rpc("get_organizer_submissions");
  const entries = (data ?? []) as Entry[];
  const groups = [...TRACKS, "No track selected"];
  return <main className="dashboard-page"><div className="shell"><div className="dashboard-intro"><p className="section-kicker">ORGANIZER SPACE</p><h1>Project submissions.</h1><p>Review each team or solo entry. Check that GitHub repositories open publicly before judging.</p><Link href="/admin" className="text-link">← Back to roster</Link></div>
    {error ? <p role="alert" className="form-notice error">Submissions could not be loaded.</p> : groups.map(group => {
      const rows = entries.filter(entry => (entry.track ?? "No track selected") === group);
      return <section className="organizer-group" key={group}><h2>{group} <small>{rows.length}</small></h2>{rows.length ? <div className="organizer-cards">{rows.map(entry => <article className="participant-panel" key={entry.id}>
        <div className="submission-heading"><div><span className="card-label">{entry.team_name || "Solo project"}</span><h3>{entry.title || "Untitled draft"}</h3></div><span className={`submission-state ${entry.status}`}>{entry.status}</span></div>
        <p>{entry.description || "No description yet."}</p><dl className="submission-summary"><div><dt>Members / check-in</dt><dd>{entry.members?.map(member => <span className="member-check" key={member.name}>{member.name}: {member.checked_in_at ? "arrived" : "not arrived"}</span>)}</dd></div><div><dt>GitHub</dt><dd>{entry.github_url ? <a className="text-link" href={entry.github_url} target="_blank" rel="noreferrer">{entry.github_url} ↗</a> : "—"}{entry.github_url && <small>Public link affirmed: {entry.public_repo_confirmed ? "yes" : "no"}</small>}</dd></div><div><dt>AI use</dt><dd>{entry.ai_level || "—"} · {entry.ai_disclosure || "No disclosure yet"}</dd></div><div><dt>Slides</dt><dd>{entry.slide_path ? <SlideDownload path={entry.slide_path} /> : "None uploaded"}</dd></div><div><dt>Updated</dt><dd>{new Date(entry.updated_at).toLocaleString("en-US", { timeZone: "America/New_York" })} ET</dd></div></dl>
      </article>)}</div> : <p>No submissions in this track.</p>}</section>;
    })}</div></main>;
}
