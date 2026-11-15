-- Forja: banco completo (já aplicado no projeto "treino-academia").
-- Para recriar do zero, rode no SQL Editor do Supabase.
-- Cada cliente (personal ou academia) é uma "organização"; cada professor só enxerga a dela.

create table public.organizacoes (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (char_length(nome) between 1 and 80),
  status text not null default 'ativo' check (status in ('teste','ativo','suspenso','cancelado')),
  criado_em timestamptz not null default now()
);
create table public.superadmins (user_id uuid primary key references auth.users(id) on delete cascade);
create table public.professores (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  org_id uuid not null references public.organizacoes(id) on delete cascade
);
alter table public.organizacoes enable row level security;
alter table public.superadmins  enable row level security;
alter table public.professores  enable row level security;

create or replace function public.minha_org() returns uuid
language sql stable security definer set search_path = public as $$
  select p.org_id from public.professores p
  join public.organizacoes o on o.id = p.org_id
  where p.user_id = auth.uid() and o.status in ('teste','ativo')
  limit 1
$$;
create or replace function public.is_super() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.superadmins where user_id = auth.uid())
$$;
revoke all on function public.minha_org(), public.is_super() from public, anon;
grant execute on function public.minha_org(), public.is_super() to authenticated;

create table public.config (
  org_id uuid primary key default public.minha_org() references public.organizacoes(id) on delete cascade,
  plano jsonb,      -- modelo padrão masculino
  plano_f jsonb,    -- modelo padrão feminino
  atualizado_em timestamptz default now()
);
create table public.alunos (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null default public.minha_org() references public.organizacoes(id) on delete cascade,
  token text not null unique default replace(gen_random_uuid()::text, '-', ''),
  nome text not null,
  contato text,
  sexo text not null default 'm' check (sexo in ('m','f')),  -- perfil: m = masculino, f = feminino
  ativo boolean not null default true,
  plano jsonb,
  progresso jsonb not null default '{}'::jsonb,
  criado_em timestamptz default now(),
  atualizado_em timestamptz default now()
);
create index alunos_org_idx on public.alunos (org_id);
create table public.eventos (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null default public.minha_org() references public.organizacoes(id) on delete cascade,
  tipo text not null check (tipo in ('treino','aula','avaliacao','aviso','outro')),
  titulo text not null check (char_length(titulo) between 1 and 80),
  data date not null,
  hora time,
  local text check (local is null or char_length(local) <= 80),
  adversario text check (adversario is null or char_length(adversario) <= 80),  -- no Forja guarda o instrutor
  resultado text check (resultado is null or char_length(resultado) <= 40),
  observacoes text check (observacoes is null or char_length(observacoes) <= 500),
  criado_em timestamptz not null default now()
);
create index eventos_org_idx on public.eventos (org_id);
create index eventos_data_idx on public.eventos (data);
alter table public.config  enable row level security;
alter table public.alunos  enable row level security;
alter table public.eventos enable row level security;

create policy prof_self   on public.professores for select to authenticated using (user_id = auth.uid());
create policy prof_equipe on public.professores for select to authenticated using (org_id = public.minha_org());
create policy org_membro  on public.organizacoes for select to authenticated
  using (exists (select 1 from public.professores p where p.user_id = auth.uid() and p.org_id = organizacoes.id));
create policy org_alunos  on public.alunos  for all to authenticated using (org_id = public.minha_org()) with check (org_id = public.minha_org());
create policy org_eventos on public.eventos for all to authenticated using (org_id = public.minha_org()) with check (org_id = public.minha_org());
create policy org_config  on public.config  for all to authenticated using (org_id = public.minha_org()) with check (org_id = public.minha_org());

create or replace function public.aluno_get(p_token text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('nome', a.nome, 'sexo', a.sexo,
    'plano', coalesce(a.plano, (select case when a.sexo = 'f' then c.plano_f else c.plano end
                                from public.config c where c.org_id = a.org_id)),
    'progresso', a.progresso)
  from public.alunos a join public.organizacoes o on o.id = a.org_id
  where a.token = p_token and a.ativo and o.status in ('teste','ativo')
$$;
create or replace function public.aluno_agenda(p_token text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg((to_jsonb(e) - 'criado_em' - 'org_id') order by e.data, e.hora), '[]'::jsonb)
  from public.eventos e
  join public.alunos a on a.org_id = e.org_id and a.token = p_token and a.ativo
  join public.organizacoes o on o.id = a.org_id and o.status in ('teste','ativo')
  where e.data >= current_date - 60
$$;
create or replace function public.aluno_save(p_token text, p_progresso jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if length(p_progresso::text) > 300000 then raise exception 'payload grande demais'; end if;
  update public.alunos set progresso = p_progresso, atualizado_em = now()
  where token = p_token and ativo
    and exists (select 1 from public.organizacoes o where o.id = alunos.org_id and o.status in ('teste','ativo'));
end $$;
revoke all on function public.aluno_get(text), public.aluno_agenda(text), public.aluno_save(text, jsonb) from public;
grant execute on function public.aluno_get(text), public.aluno_agenda(text), public.aluno_save(text, jsonb) to anon, authenticated;

-- painel do dono (aba "Clientes")
create or replace function public.admin_clientes() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_super() then raise exception 'sem permissao' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(x order by x->>'criado_em' desc) from (
    select jsonb_build_object('id', o.id, 'nome', o.nome, 'status', o.status, 'criado_em', o.criado_em,
      'professores', coalesce((select jsonb_agg(jsonb_build_object('user_id', p.user_id, 'email', p.email) order by p.email) from public.professores p where p.org_id = o.id), '[]'::jsonb),
      'alunos', (select count(*) from public.alunos a where a.org_id = o.id),
      'ativos7d', (select count(*) from public.alunos a where a.org_id = o.id and a.progresso <> '{}'::jsonb and a.atualizado_em > now() - interval '7 days'),
      'ultima', (select max(a.atualizado_em) from public.alunos a where a.org_id = o.id and a.progresso <> '{}'::jsonb),
      'eventos', (select count(*) from public.eventos e where e.org_id = o.id)) as x
    from public.organizacoes o) s), '[]'::jsonb);
end $$;
create or replace function public.admin_definir_status(p_org uuid, p_status text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_super() then raise exception 'sem permissao' using errcode = '42501'; end if;
  if p_status not in ('teste','ativo','suspenso','cancelado') then raise exception 'status invalido'; end if;
  if p_status in ('suspenso','cancelado') and exists (select 1 from public.professores where user_id = auth.uid() and org_id = p_org) then
    raise exception 'voce nao pode suspender a propria organizacao';
  end if;
  update public.organizacoes set status = p_status where id = p_org;
  if not found then raise exception 'organizacao nao encontrada'; end if;
end $$;
revoke all on function public.admin_clientes(), public.admin_definir_status(uuid, text) from public, anon;
grant execute on function public.admin_clientes(), public.admin_definir_status(uuid, text) to authenticated;
