import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Organizer roster" };

export default async function Admin() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: me } = await supabase.from("profiles").select("admin").eq("id", user.id).single();
  if (!me?.admin) redirect("/account");
  const { data: roster, error } = await supabase.from("profiles").select("id,full_name,email,grade,tshirt_size,registration_status,assigned_at,admin").order("assigned_at", { ascending: true, nullsFirst: false });
  const students = (roster ?? []).filter(person => !person.admin);
  const confirmed = students.filter(person => person.registration_status === "confirmed").length;
  const waitlisted = students.filter(person => person.registration_status === "waitlisted").length;
  return <main className="dashboard-page"><div className="shell"><div className="dashboard-intro"><p className="section-kicker">ORGANIZER SPACE</p><h1>Registration roster.</h1><p>Private student information for F&MHacks organizers.</p></div><div className="stat-row"><div><strong>{confirmed}<span> / 75</span></strong><p>Confirmed students</p></div><div><strong>{waitlisted}</strong><p>Waitlisted students</p></div><div><strong>{students.length}</strong><p>Total student accounts</p></div></div>{error ? <p role="alert" className="form-notice error">The roster could not be loaded.</p> : <div className="roster-wrap"><table className="roster-table"><thead><tr><th>Name</th><th>Email</th><th>Class</th><th>Shirt</th><th>Status</th></tr></thead><tbody>{roster?.map(person => <tr key={person.id}><td>{person.full_name}</td><td>{person.email}</td><td>{person.grade}</td><td>{person.tshirt_size}</td><td><span className={`table-status status-${person.registration_status}`}>{person.registration_status.replaceAll("_", " ")}</span></td></tr>)}</tbody></table>{!roster?.length && <p className="empty-roster">No registrations yet.</p>}</div>}</div></main>;
}
