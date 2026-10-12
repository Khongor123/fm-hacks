import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { logout } from "@/app/actions/auth";
import { createClient } from "@/lib/supabase/server";
import { FormNotice } from "@/components/form-notice";

export const metadata: Metadata = { title: "My account" };

const statusCopy: Record<string, { heading: string; detail: string }> = {
  pending_assignment: { heading: "Registration is processing", detail: "Your place or waitlist position will appear here shortly." },
  confirmed: { heading: "You’re on the list", detail: "Your place at F&MHacks is confirmed. We’ll share final arrival details before the event." },
  waitlisted: { heading: "You’re on the waitlist", detail: "We have your registration. An organizer will contact you if a place opens." },
  organizer: { heading: "Organizer account", detail: "You have access to the organizer roster and event administration." },
};

export default async function Account({ searchParams }: { searchParams: Promise<{ password_updated?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: profile, error } = await supabase.from("profiles").select("full_name,email,grade,tshirt_size,registration_status,admin").eq("id", user.id).single();
  if (error || !profile) return <main className="dashboard-page shell"><div className="dashboard-intro"><p className="section-kicker">MY ACCOUNT</p><h1>Account setup is finishing.</h1><p>Refresh in a moment. If this persists, contact the organizers.</p></div></main>;
  const status = statusCopy[profile.registration_status] ?? statusCopy.pending_assignment;
  return <main className="dashboard-page"><div className="shell"><div className="dashboard-intro"><p className="section-kicker">MY F&MHACKS</p><h1>Hey, {profile.full_name.split(" ")[0]}.</h1><p>Everything you need before the hackathon begins.</p></div><FormNotice success={params.password_updated ? "Your password was updated." : undefined} /><div className="dashboard-grid"><section className="dashboard-card status-card"><span className="card-label">REGISTRATION STATUS</span><div className={`status-badge status-${profile.registration_status}`}>{profile.registration_status.replaceAll("_", " ")}</div><h2>{status.heading}</h2><p>{status.detail}</p></section><section className="dashboard-card"><span className="card-label">YOUR DETAILS</span><dl className="detail-list"><div><dt>Name</dt><dd>{profile.full_name}</dd></div><div><dt>Email</dt><dd>{profile.email}</dd></div><div><dt>Class year</dt><dd>{profile.grade}</dd></div><div><dt>T-shirt size</dt><dd>{profile.tshirt_size}</dd></div></dl></section><section className="dashboard-card next-card"><span className="card-label">WHAT’S NEXT</span><h2>{profile.admin ? "Organize the event." : profile.registration_status === "confirmed" ? "Build your crew." : "Stay in the loop."}</h2><p>{profile.admin ? "Review registrations and help participants get ready." : profile.registration_status === "confirmed" ? "Create a team or join one by code from your dashboard. Team changes close November 3 at 11:59 p.m. Eastern." : "Check your dashboard for your registration status and event details."}</p><Link href={profile.admin ? "/admin" : "/#dashboard"} className="text-link">{profile.admin ? "Open organizer roster" : "Go to my dashboard"} ↗</Link></section></div><div className="account-actions">{profile.admin && <Link href="/admin" className="text-link">Organizer roster ↗</Link>}<form action={logout}><button type="submit" className="text-link">Log out →</button></form></div></div></main>;
}
