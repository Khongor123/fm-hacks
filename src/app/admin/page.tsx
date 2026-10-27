import type { Metadata } from "next";
import Link from "next/link";
import { setCheckIn } from "@/app/actions/check-in";
import { FormNotice } from "@/components/form-notice";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { CAPACITY } from "@/lib/config";

export const metadata: Metadata = { title: "Organizer roster" };

export default async function Admin({ searchParams }: { searchParams: Promise<{ error?: string; notice?: string; invite_accepted?: string; promoted?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: me } = await supabase.from("profiles").select("admin").eq("id", user.id).single();
  if (!me?.admin) redirect("/account");
  const { data: roster, error } = await supabase.from("profiles").select("id,full_name,email,grade,tshirt_size,registration_status,assigned_at,admin,checked_in_at,checked_in_by").order("assigned_at", { ascending: true, nullsFirst: false });
  const students = (roster ?? []).filter(person => !person.admin);
  const confirmed = students.filter(person => person.registration_status === "confirmed").length;
  const waitlisted = students.filter(person => person.registration_status === "waitlisted").length;
  return <main className="dashboard-page"><div className="shell"><div className="dashboard-intro"><p className="section-kicker">ORGANIZER SPACE</p><h1>Registration roster.</h1><p>Verify student identity before marking a confirmed participant as arrived.</p></div><FormNotice error={params.error} success={params.invite_accepted ? `Invitation accepted.${params.promoted ? ` ${params.promoted} was promoted from the waitlist; contact them directly.` : ""}` : params.notice ? "Check-in updated." : undefined} /><p><Link href="/admin/submissions" className="button button-dark">Review submissions ↗</Link> <Link href="/admin/invitations" className="button button-dark">Organizer invitations ↗</Link></p><div className="stat-row"><div><strong>{confirmed}<span> / {CAPACITY}</span></strong><p>Confirmed students</p></div><div><strong>{waitlisted}</strong><p>Waitlisted students</p></div><div><strong>{students.length}</strong><p>Total student accounts</p></div></div>{error ? <p role="alert" className="form-notice error">The roster could not be loaded.</p> : <div className="roster-wrap"><table className="roster-table"><thead><tr><th>Name</th><th>Email</th><th>Class</th><th>Shirt</th><th>Status</th><th>Arrival</th></tr></thead><tbody>{roster?.map(person => <tr key={person.id}><td>{person.full_name}</td><td>{person.email}</td><td>{person.grade}</td><td>{person.tshirt_size}</td><td><span className={`table-status status-${person.registration_status}`}>{person.registration_status.replaceAll("_", " ")}</span></td><td>{person.registration_status === "confirmed" && !person.admin ? <form action={setCheckIn}><input type="hidden" name="id" value={person.id} /><input type="hidden" name="arrived" value={person.checked_in_at ? "false" : "true"} /><button type="submit" className="text-link">{person.checked_in_at ? "Arrived ✓ · Undo" : "Mark arrived"}</button>{person.checked_in_at && <small className="checkin-meta">{new Date(person.checked_in_at).toLocaleString("en-US", { timeZone: "America/New_York" })} ET · by {roster?.find(organizer => organizer.id === person.checked_in_by)?.full_name ?? "organizer"}</small>}</form> : "—"}</td></tr>)}</tbody></table>{!roster?.length && <p className="empty-roster">No registrations yet.</p>}</div>}</div></main>;
}
