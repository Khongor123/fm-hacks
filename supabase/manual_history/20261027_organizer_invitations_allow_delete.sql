-- Apply after 20261027_organizer_invitations.sql on projects that already ran it.
-- Keep invitation history without preventing Auth user/profile deletion.
alter table public.organizer_invitations
  alter column invited_by drop not null,
  drop constraint if exists organizer_invitations_invited_by_fkey,
  add constraint organizer_invitations_invited_by_fkey
    foreign key (invited_by) references public.profiles(id) on delete set null,
  drop constraint if exists organizer_invitations_used_by_fkey,
  add constraint organizer_invitations_used_by_fkey
    foreign key (used_by) references public.profiles(id) on delete set null;
