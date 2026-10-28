import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { deleteAccount } from "@/app/actions/auth";
import { FormNotice } from "@/components/form-notice";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Delete account" };

export default async function DeleteAccount({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { error } = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  return <main className="dashboard-page"><div className="shell"><div className="dashboard-intro"><p className="section-kicker">MY ACCOUNT</p><h1>Delete your account?</h1><p>This permanently removes your account, registration, and team membership. A confirmed student’s place will go to the next person on the waitlist.</p></div><FormNotice error={error} /><form action={deleteAccount} className="delete-account-form"><label className="checkbox-line"><input type="checkbox" name="confirm_delete" value="yes" required /><span>I understand this cannot be undone.</span></label><div className="account-actions"><button type="submit" className="text-link">Delete account</button><Link href="/account" className="text-link">Cancel</Link></div></form></div></main>;
}
