import { createClient } from "@/lib/supabase/server";
import { HeaderNavigation } from "@/components/header-navigation";

export async function SiteHeader() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  return (
    <header className="site-header">
      <HeaderNavigation signedIn={Boolean(user)} />
    </header>
  );
}
