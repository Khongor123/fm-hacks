import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { createTeam, joinTeam, leaveTeam } from "@/app/actions/team";
import { CopyTeamCode } from "@/components/copy-team-code";
import { FormNotice } from "@/components/form-notice";
import type { Team } from "@/components/participant-dashboard";
import { teamChangesOpen } from "@/lib/config";
import { getEventNow } from "@/lib/event-clock";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Your team" };

export default async function TeamPage({ searchParams }: { searchParams: Promise<{ team_error?: string; team_notice?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: profile } = await supabase.from("profiles").select("registration_status,admin").eq("id", user.id).single();
  if (profile?.registration_status !== "confirmed" || profile.admin) redirect("/#dashboard");
  const [{ data: team, error }, now] = await Promise.all([supabase.rpc("get_my_team"), getEventNow(supabase)]);
  const open = teamChangesOpen(now);
  const currentTeam = team as Team | null;
  const success = params.team_notice === "created" ? "Your team is ready. Share its code with your teammates."
    : params.team_notice === "joined" ? "You joined the team."
    : params.team_notice === "left" ? "You left the team." : undefined;

  return <main className="dashboard-page"><div className="shell">
    <div className="dashboard-intro"><p className="section-kicker">MY F&MHACKS</p><h1>Your team.</h1><p>Build your crew for November 7–8.</p><Link href="/#dashboard" className="text-link">← Back to dashboard</Link></div>
    <FormNotice error={params.team_error || (error ? "Team details are unavailable right now." : undefined)} success={success} />
    <section className="participant-panel team-panel" id="my-team">
      <div className="team-panel-heading"><div><span className="card-label">YOUR TEAM</span><h2>{currentTeam ? currentTeam.name : "Build your crew."}</h2></div><span className="team-cutoff">Team changes close Nov 3 at 11:59 p.m. ET</span></div>
      {error ? <p role="alert">Team tools are being set up. Please try again later.</p>
      : currentTeam ? <>
        <div className="team-code-row"><div><span>TEAM CODE</span><strong>{currentTeam.code}</strong></div><CopyTeamCode code={currentTeam.code} /></div>
        <p>Share this code with teammates. A team can have up to four members.</p>
        <ol className="team-member-list">{currentTeam.members.map(member => <li key={member.id}><span>{member.full_name}</span>{member.id === currentTeam.created_by && <small>Creator</small>}</li>)}</ol>
        <p className="team-count">{currentTeam.members.length} of 4 places filled</p>
        {open && <form action={leaveTeam}><button type="submit" className="text-link">Leave team</button></form>}
      </> : open ? <div className="team-actions">
        <form action={createTeam} className="team-action-card"><h3>Create a team</h3><p>Give your team a name, then share its code.</p><div className="field"><label htmlFor="team_name">Team name</label><input id="team_name" name="team_name" minLength={2} maxLength={40} placeholder="Your team name" required /></div><button type="submit" className="button button-dark">Create team <span aria-hidden="true">→</span></button></form>
        <form action={joinTeam} className="team-action-card"><h3>Join a team</h3><p>Ask a teammate for their 6-character code.</p><div className="field"><label htmlFor="team_code">Team code</label><input id="team_code" name="team_code" minLength={6} maxLength={6} placeholder="6-character code" autoCapitalize="characters" required /></div><button type="submit" className="button button-ghost">Join team <span aria-hidden="true">→</span></button></form>
      </div> : <p>Team changes closed November 3 at 11:59 p.m. Eastern.</p>}
    </section>
  </div></main>;
}
