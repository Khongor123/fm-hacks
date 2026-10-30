"use server";

import { createHash, randomBytes } from "node:crypto";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { siteUrl } from "@/lib/config";

export type InviteState = { error: string | null; link: string | null };
const emailPattern = /^[^@\s]+@fandm\.edu$/;
const tokenPattern = /^[0-9a-f]{64}$/;
const hash = (token: string) => createHash("sha256").update(token).digest("hex");
const field = (data: FormData, name: string) => String(data.get(name) ?? "").trim();

export async function createInvitation(_previous: InviteState, data: FormData): Promise<InviteState> {
  const email = field(data, "email").toLowerCase();
  if (!emailPattern.test(email)) return { error: "Use an F&M email address.", link: null };
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Sign in as an organizer first.", link: null };
  const token = randomBytes(32).toString("hex");
  const { error } = await supabase.rpc("create_organizer_invitation", { p_email: email, p_token_hash: hash(token) });
  if (error) return { error: "Could not create the invitation. Check organizer access and try again.", link: null };
  revalidatePath("/admin/invitations");
  return { error: null, link: `${siteUrl()}/invite/${token}` };
}

export async function revokeInvitation(data: FormData) {
  const id = field(data, "id");
  if (!/^[0-9a-f-]{36}$/.test(id)) redirect("/admin/invitations?error=Invalid%20invitation.");
  const supabase = await createClient();
  const { error } = await supabase.rpc("revoke_organizer_invitation", { p_id: id });
  if (error) redirect("/admin/invitations?error=Could%20not%20revoke%20the%20invitation.");
  revalidatePath("/admin/invitations");
  redirect("/admin/invitations?notice=revoked");
}

export type AcceptState = { error: string | null };
export async function acceptInvitation(_previous: AcceptState, data: FormData): Promise<AcceptState> {
  const token = field(data, "token");
  if (!tokenPattern.test(token)) return { error: "This invitation link is invalid." };
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Sign in to accept this invitation." };
  const { data: promotedEmail, error } = await supabase.rpc("accept_organizer_invitation", { p_hash: hash(token) });
  if (error) return { error: error.message === "A team submission exists. Ask an organizer for help before accepting this invitation."
    ? error.message : "This invitation is invalid, expired, already used, or intended for another F&M account." };
  revalidatePath("/admin");
  revalidatePath("/account");
  redirect(`/admin?invite_accepted=1${promotedEmail ? `&promoted=${encodeURIComponent(promotedEmail)}` : ""}`);
}

export async function signInAndAccept(_previous: AcceptState, data: FormData): Promise<AcceptState> {
  const token = field(data, "token");
  const email = field(data, "email").toLowerCase();
  const password = String(data.get("password") ?? "");
  if (!tokenPattern.test(token)) return { error: "This invitation link is invalid." };
  if (!emailPattern.test(email) || !password) return { error: "Enter your F&M email and password." };
  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) return { error: "Email or password is incorrect." };
  const { data: promotedEmail, error: acceptError } = await supabase.rpc("accept_organizer_invitation", { p_hash: hash(token) });
  if (acceptError) return { error: acceptError.message === "A team submission exists. Ask an organizer for help before accepting this invitation."
    ? acceptError.message : "This invitation is invalid, expired, already used, or intended for another F&M account." };
  revalidatePath("/admin");
  redirect(`/admin?invite_accepted=1${promotedEmail ? `&promoted=${encodeURIComponent(promotedEmail)}` : ""}`);
}

export async function registerInvited(_previous: AcceptState, data: FormData): Promise<AcceptState> {
  const token = field(data, "token");
  const fullName = field(data, "full_name");
  const email = field(data, "email").toLowerCase();
  const password = String(data.get("password") ?? "");
  if (!tokenPattern.test(token)) return { error: "This invitation link is invalid." };
  if (fullName.length < 2 || fullName.length > 120) return { error: "Enter your full name." };
  if (!emailPattern.test(email)) return { error: "Use your F&M email address." };
  if (password.length < 8) return { error: "Use a password with at least 8 characters." };
  const supabase = await createClient();
  const { data: signup, error } = await supabase.auth.signUp({
    email, password, options: { data: { full_name: fullName, organizer_invite_hash: hash(token) } },
  });
  if (error || !signup.user || signup.user.identities?.length === 0) return { error: "Could not create the organizer account. The invitation may be invalid, expired, used, or for another email. If you already have an account, sign in above." };
  if (!signup.session) redirect("/register?confirmation_required=1");
  redirect("/admin?invite_accepted=1");
}
