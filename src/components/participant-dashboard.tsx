import Link from "next/link";
import { createTeam, joinTeam, leaveTeam } from "@/app/actions/team";
import { teamChangesOpen } from "@/lib/config";
import { Countdown } from "@/components/countdown";
import { CopyTeamCode } from "@/components/copy-team-code";
import { FormNotice } from "@/components/form-notice";

export type Team = {
  id: string;
  name: string;
  code: string;
  created_by: string | null;
  members: { id: string; full_name: string; joined_at: string }[];
};

type Profile = { full_name: string; registration_status: string; admin: boolean };

const statusDetails: Record<string, string> = {
  confirmed: "Your place at F&MHacks is confirmed.",
  waitlisted: "You’re on the waitlist. An organizer will contact you if a place opens.",
  pending_assignment: "Your registration is being processed.",
  organizer: "Your organizer account is ready.",
};

export function ParticipantDashboard({ profile, team, teamLoadError, now, notice, error }: {
  profile: Profile;
  team: Team | null;
  teamLoadError: boolean;
  now: number;
  notice?: string;
  error?: string;
}) {
  const open = teamChangesOpen(now);
  const canJoinTeams = profile.registration_status === "confirmed" && !profile.admin;
  const firstName = profile.full_name.trim().split(/\s+/)[0];
  const success = notice === "created" ? "Your team is ready. Share its code with your teammates."
    : notice === "joined" ? "You joined the team."
    : notice === "left" ? "You left the team." : undefined;

  return <section className="participant-home" id="dashboard"><div className="shell">
    <div className="participant-heading">
      <div>
        <p className="section-kicker">MY F&MHACKS</p>
        <h1>Welcome back, <em>{firstName}.</em></h1>
        <p>Your place, your team, and everything coming up on November 7–8.</p>
      </div>
      <Link href="/account" className="button button-ghost">My account <span aria-hidden="true">↗</span></Link>
    </div>

    <FormNotice error={error} success={success} />
    <div className="participant-grid">
      <section className="participant-panel participant-status">
        <span className="card-label">REGISTRATION</span>
        <span className={`status-badge status-${profile.registration_status}`}>{profile.registration_status.replaceAll("_", " ")}</span>
        <h2>{statusDetails[profile.registration_status] ?? "Your registration is being processed."}</h2>
        <p>Saturday, November 7 · 9:00 a.m. · Stager Auditorium</p>
        {profile.admin && <Link href="/admin" className="text-link">Open organizer roster ↗</Link>}
      </section>
      <Countdown serverNow={now} />
    </div>

    <section className="participant-panel team-panel" id="my-team">
      <div className="team-panel-heading"><div><span className="card-label">YOUR TEAM</span><h2>{team ? team.name : "Build your crew."}</h2></div><span className="team-cutoff">Team changes close Nov 3 at 11:59 p.m. ET</span></div>
      {teamLoadError ? <p role="alert">Team tools are being set up. Please try again later.</p>
      : !canJoinTeams ? <p>{profile.admin ? "Organizer accounts do not join participant teams." : "Team creation and joining are available to confirmed participants."}</p>
      : team ? <>
        <div className="team-code-row"><div><span>TEAM CODE</span><strong>{team.code}</strong></div><CopyTeamCode code={team.code} /></div>
        <p>Share this code with teammates. A team can have up to four members.</p>
        <ol className="team-member-list">{team.members.map(member => <li key={member.id}><span>{member.full_name}</span>{member.id === team.created_by && <small>Creator</small>}</li>)}</ol>
        <p className="team-count">{team.members.length} of 4 places filled</p>
        {open && <form action={leaveTeam}><button type="submit" className="text-link">Leave team</button></form>}
      </> : open ? <div className="team-actions">
        <form action={createTeam} className="team-action-card"><h3>Create a team</h3><p>Give your team a name, then share its code.</p><div className="field"><label htmlFor="team_name">Team name</label><input id="team_name" name="team_name" minLength={2} maxLength={40} placeholder="Your team name" required /></div><button type="submit" className="button button-dark">Create team <span aria-hidden="true">→</span></button></form>
        <form action={joinTeam} className="team-action-card"><h3>Join a team</h3><p>Ask a teammate for their 12-character code.</p><div className="field"><label htmlFor="team_code">Team code</label><input id="team_code" name="team_code" minLength={12} maxLength={12} placeholder="12-character code" autoCapitalize="characters" required /></div><button type="submit" className="button button-ghost">Join team <span aria-hidden="true">→</span></button></form>
      </div> : <p>Team changes closed November 3 at 11:59 p.m. Eastern.</p>}
    </section>
  </div></section>;
}
