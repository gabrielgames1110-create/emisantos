-- Agenda Emi Santos (Supabase)
-- Cole tudo no SQL Editor do Supabase e clique em Run. Pode rodar de novo sem perder dados.

create table if not exists public.perfis (
  id uuid primary key references auth.users on delete cascade,
  nome text not null default '',
  whatsapp text not null default '',
  admin boolean not null default false,
  criado_em timestamptz not null default now()
);

create table if not exists public.servicos (
  id bigint generated always as identity primary key,
  nome text not null,
  duracao int not null check (duracao between 5 and 600),
  valor numeric(10,2),
  ordem int not null default 0,
  ativo boolean not null default true
);

create table if not exists public.horarios (
  dia int primary key check (dia between 0 and 6), -- 0 = domingo
  abre time,
  fecha time,
  pausa_inicio time,
  pausa_fim time
);

create table if not exists public.config (
  id int primary key default 1 check (id = 1),
  intervalo int not null default 30,
  dias_frente int not null default 30,
  antecedencia_horas int not null default 12,
  limite_por_cliente int not null default 2
);

create table if not exists public.bloqueios (
  id bigint generated always as identity primary key,
  inicio timestamptz not null,
  fim timestamptz not null,
  motivo text not null default '',
  check (fim > inicio)
);

create table if not exists public.agendamentos (
  id bigint generated always as identity primary key,
  cliente uuid references auth.users on delete set null,
  nome text not null,
  whatsapp text not null default '',
  servico text not null,
  valor numeric(10,2),
  inicio timestamptz not null,
  fim timestamptz not null,
  status text not null default 'pendente' check (status in ('pendente', 'confirmado', 'cancelado')),
  origem text not null default 'site',
  criado_em timestamptz not null default now(),
  check (fim > inicio),
  -- O próprio banco impede dois atendimentos no mesmo horário, mesmo com cliques simultâneos
  constraint sem_conflito exclude using gist (tstzrange(inicio, fim) with &&) where (status <> 'cancelado')
);
create index if not exists agendamentos_cliente_idx on public.agendamentos (cliente);

-- Dados iniciais
insert into public.config (id) values (1) on conflict (id) do nothing;

insert into public.horarios (dia, abre, fecha, pausa_inicio, pausa_fim) values
  (0, null, null, null, null),
  (1, '09:00', '18:00', '12:00', '13:00'),
  (2, '09:00', '18:00', '12:00', '13:00'),
  (3, '09:00', '18:00', '12:00', '13:00'),
  (4, '09:00', '18:00', '12:00', '13:00'),
  (5, '09:00', '18:00', '12:00', '13:00'),
  (6, '09:00', '13:00', null, null)
on conflict (dia) do nothing;

insert into public.servicos (nome, duracao, valor, ordem)
select v.nome, v.duracao, v.valor, v.ordem from (values
  ('Aplicação volume brasileiro', 100, 150.00, 1),
  ('Aplicação volume 5D', 100, 150.00, 2),
  ('Aplicação fox eyes', 100, 150.00, 3),
  ('Lash lifting', 80, 75.00, 4),
  ('Manutenção volume brasileiro', 80, 80.00, 5),
  ('Manutenção volume egípcio', 80, 80.00, 6),
  ('Manutenção fox eyes', 80, 80.00, 7),
  ('Ensaio fotográfico', 120, 200.00, 8)
) as v(nome, duracao, valor, ordem)
where not exists (select 1 from public.servicos);

-- Funções
create or replace function public.eh_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select admin from public.perfis where id = auth.uid()), false);
$$;

create or replace function public.novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfis (id, nome, whatsapp) values (
    new.id,
    left(coalesce(new.raw_user_meta_data->>'nome', new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', ''), 80),
    left(regexp_replace(coalesce(new.raw_user_meta_data->>'whatsapp', ''), '\D', '', 'g'), 15)
  ) on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists ao_criar_usuario on auth.users;
create trigger ao_criar_usuario after insert on auth.users
  for each row execute function public.novo_usuario();

-- Horários ocupados para o site (sem nome nem telefone de ninguém)
create or replace function public.horarios_ocupados(de timestamptz, ate timestamptz)
returns table (inicio timestamptz, fim timestamptz)
language sql stable security definer set search_path = public as $$
  select a.inicio, a.fim from public.agendamentos a
   where a.status <> 'cancelado' and a.fim > de and a.inicio < ate
  union all
  select b.inicio, b.fim from public.bloqueios b
   where b.fim > de and b.inicio < ate;
$$;

create or replace function public.agendar(p_servico bigint, p_inicio timestamptz)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_p public.perfis;
  v_s public.servicos;
  v_c public.config;
  v_h public.horarios;
  v_fim timestamptz;
  v_dia date;
  v_hi time;
  v_hf time;
  v_id bigint;
begin
  if auth.uid() is null then raise exception 'login'; end if;
  select * into v_p from public.perfis where id = auth.uid();
  if v_p.id is null or length(v_p.nome) < 2 or length(v_p.whatsapp) < 10 then raise exception 'perfil'; end if;
  select * into v_s from public.servicos where id = p_servico and ativo;
  if v_s.id is null then raise exception 'servico'; end if;
  select * into v_c from public.config where id = 1;

  v_fim := p_inicio + make_interval(mins => v_s.duracao);
  v_dia := (p_inicio at time zone 'America/Sao_Paulo')::date;
  v_hi := (p_inicio at time zone 'America/Sao_Paulo')::time;
  v_hf := (v_fim at time zone 'America/Sao_Paulo')::time;

  if p_inicio < now() + make_interval(hours => v_c.antecedencia_horas)
     or v_dia > (now() at time zone 'America/Sao_Paulo')::date + v_c.dias_frente then
    raise exception 'prazo';
  end if;

  select * into v_h from public.horarios where dia = extract(dow from v_dia)::int;
  if v_h.abre is null or v_h.fecha is null or v_hi < v_h.abre or v_hf > v_h.fecha
     or (v_fim at time zone 'America/Sao_Paulo')::date <> v_dia
     or (v_h.pausa_inicio is not null and v_h.pausa_fim is not null and v_hi < v_h.pausa_fim and v_hf > v_h.pausa_inicio) then
    raise exception 'fora';
  end if;

  if exists (select 1 from public.bloqueios b where b.inicio < v_fim and b.fim > p_inicio) then
    raise exception 'ocupado';
  end if;

  if (select count(*) from public.agendamentos a
       where a.cliente = auth.uid() and a.status <> 'cancelado' and a.fim > now()) >= v_c.limite_por_cliente then
    raise exception 'limite';
  end if;

  insert into public.agendamentos (cliente, nome, whatsapp, servico, valor, inicio, fim)
  values (auth.uid(), v_p.nome, v_p.whatsapp, v_s.nome, v_s.valor, p_inicio, v_fim)
  returning id into v_id;
  return v_id;
exception when exclusion_violation then
  raise exception 'ocupado';
end $$;

create or replace function public.cancelar_agendamento(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.agendamentos set status = 'cancelado'
   where id = p_id and cliente = auth.uid() and inicio > now() and status <> 'cancelado';
  if not found then raise exception 'cancelar'; end if;
end $$;

-- Segurança: cada cliente vê só os próprios agendamentos; só a administradora vê e muda tudo
alter table public.perfis enable row level security;
alter table public.servicos enable row level security;
alter table public.horarios enable row level security;
alter table public.config enable row level security;
alter table public.bloqueios enable row level security;
alter table public.agendamentos enable row level security;

drop policy if exists perfis_ver on public.perfis;
create policy perfis_ver on public.perfis for select using (id = auth.uid() or public.eh_admin());
drop policy if exists perfis_editar on public.perfis;
create policy perfis_editar on public.perfis for update using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists servicos_ver on public.servicos;
create policy servicos_ver on public.servicos for select using (true);
drop policy if exists servicos_admin on public.servicos;
create policy servicos_admin on public.servicos for all using (public.eh_admin()) with check (public.eh_admin());

drop policy if exists horarios_ver on public.horarios;
create policy horarios_ver on public.horarios for select using (true);
drop policy if exists horarios_admin on public.horarios;
create policy horarios_admin on public.horarios for all using (public.eh_admin()) with check (public.eh_admin());

drop policy if exists config_ver on public.config;
create policy config_ver on public.config for select using (true);
drop policy if exists config_admin on public.config;
create policy config_admin on public.config for all using (public.eh_admin()) with check (public.eh_admin());

drop policy if exists bloqueios_admin on public.bloqueios;
create policy bloqueios_admin on public.bloqueios for all using (public.eh_admin()) with check (public.eh_admin());

drop policy if exists agendamentos_ver on public.agendamentos;
create policy agendamentos_ver on public.agendamentos for select using (cliente = auth.uid() or public.eh_admin());
drop policy if exists agendamentos_admin on public.agendamentos;
create policy agendamentos_admin on public.agendamentos for all using (public.eh_admin()) with check (public.eh_admin());

revoke all on public.perfis, public.servicos, public.horarios, public.config, public.bloqueios, public.agendamentos from anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select on public.servicos, public.horarios, public.config to anon;
grant select, insert, update, delete on public.servicos, public.horarios, public.config, public.bloqueios, public.agendamentos to authenticated;
grant select on public.perfis to authenticated;
grant update (nome, whatsapp) on public.perfis to authenticated;

revoke execute on function public.agendar(bigint, timestamptz), public.cancelar_agendamento(bigint) from public, anon;
grant execute on function public.agendar(bigint, timestamptz), public.cancelar_agendamento(bigint) to authenticated;
grant execute on function public.eh_admin(), public.horarios_ocupados(timestamptz, timestamptz) to anon, authenticated;

-- Depois que a Emi criar a conta dela pelo site, rode só a linha abaixo com o e-mail dela (sem os dois traços):
-- update public.perfis set admin = true where id = (select id from auth.users where email = 'email-da-emi@gmail.com');
