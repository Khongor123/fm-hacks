import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { revokeInvitation } from "@/app/actions/invitations";
import { FormNotice } from "@/components/form-notice";
import { createClient } from "@/lib/supabase/server";
import { InvitationForm } from "./invitation-form";

export const metadata: Metadata = { title: "Organizer invitations" };

type Invitation = { id: string; email: string; created_at: string; expires_at: string; used_at: string | null; revoked_at: string | null };
export default async function Invitations({ searchParams }: { searchParams: Promise<{ error?: string; notice?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: me } = await supabase.from("profiles").select("admin").eq("id", user.id).single();
  if (!me?.admin) redirect("/account");
  const { data, error } = await supabase.rpc("list_organizer_invitations");
  const invites = (data ?? []) as Invitation[];
  return <main className="dashboard-page"><div className="shell"><div className="dashboard-intro"><p className="section-kicker">ORGANIZER SPACE</p><h1>Organizer invitations.</h1><p>New organizer accounts do not use participant places.</p><Link href="/admin" className="text-link">← Back to roster</Link></div><FormNotice error={params.error || (error ? "Invitations could not be loaded." : undefined)} success={params.notice ? "Invitation revoked." : undefined} /><InvitationForm /><section className="dashboard-card"><h2>Invitation history</h2>{invites.length ? <div className="roster-wrap"><table className="roster-table"><thead><tr><th>Email</th><th>Created</th><th>Expires</th><th>Status</th><th></th></tr></thead><tbody>{invites.map(invite => {
    const available = !invite.used_at && !invite.revoked_at && new Date(invite.expires_at).getTime() > Date.now();
    return <tr key={invite.id}><td>{invite.email}</td><td>{new Date(invite.created_at).toLocaleDateString()}</td><td>{new Date(invite.expires_at).toLocaleDateString()}</td><td>{invite.used_at ? "Used" : invite.revoked_at ? "Revoked" : available ? "Available" : "Expired"}</td><td>{available && <form action={revokeInvitation}><input type="hidden" name="id" value={invite.id} /><button className="text-link" type="submit">Revoke</button></form>}</td></tr>;
  })}</tbody></table></div> : <p>No invitations yet.</p>}</section></div></main>;
}
