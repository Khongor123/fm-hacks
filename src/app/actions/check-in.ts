"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function setCheckIn(formData: FormData) {
  const id = String(formData.get("id") ?? "");
  const arrived = formData.get("arrived") === "true";
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { error } = await supabase.rpc("set_check_in", { p_user_id: id, p_arrived: arrived });
  if (error) redirect(`/admin?error=${encodeURIComponent(error.message)}`);
  revalidatePath("/admin");
  revalidatePath("/admin/submissions");
  redirect("/admin?notice=check-in-updated");
}
