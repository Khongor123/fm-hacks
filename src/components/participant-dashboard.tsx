import Link from "next/link";
import { HeroLogo } from "@/components/hero-logo";
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
      <section className="participant-panel participant-team" id="my-team">
        <span className="card-label">YOUR TEAM</span>
        <h2>{team ? team.name : "Build your crew."}</h2>
        {teamLoadError ? <p role="alert">Team details are unavailable right now.</p>
        : !canJoinTeams ? <p>{profile.admin ? "Organizer accounts do not join participant teams." : "Teams are available to confirmed participants."}</p>
        : team ? <><p>{team.members.length} of 4 places filled</p><p>Share your code and build with your crew.</p></>
        : <p>Create a team or join one with a code from a teammate.</p>}
        {canJoinTeams && <Link href="/team" className="text-link">{team ? "View and manage team" : "Create or join a team"} ↗</Link>}
        {!profile.admin && <Link href="/participants" className="text-link participant-directory-link">View participants ↗</Link>}
      </section>
      <div className="participant-panel participant-logo-panel"><HeroLogo serverNow={now} /></div>
    </div>
  </div></section>;
}
