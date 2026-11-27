-- Avisos por e-mail para a Emi (Supabase + Resend)
-- Passo a passo em "Como configurar a agenda.md", seção "Avisos por e-mail".
-- 1. Troque os valores COLE_AQUI logo abaixo.
-- 2. Cole tudo no SQL Editor do Supabase e clique em Run.
-- 3. Numa nova query, rode: select privado.testar_aviso();
-- Pode rodar de novo para trocar a chave ou o e-mail.

create extension if not exists pg_net with schema extensions;

create schema if not exists privado;

create table if not exists privado.notificacao (
  id int primary key default 1 check (id = 1),
  resend_key text not null default '',
  email text not null default '',
  link_painel text not null default '',
  ativo boolean not null default true
);
alter table privado.notificacao enable row level security;

insert into privado.notificacao as n (id, resend_key, email, link_painel) values (
  1,
  'COLE_AQUI_A_CHAVE_DO_RESEND',  -- começa com re_
  'COLE_AQUI_O_EMAIL',            -- o mesmo e-mail da conta do Resend
  ''                              -- opcional: endereço do painel, ex. https://seu-usuario.github.io/emi-santos/painel.html
)
on conflict (id) do update set
  resend_key = case when excluded.resend_key like 'COLE_AQUI%' then n.resend_key else excluded.resend_key end,
  email = case when excluded.email like 'COLE_AQUI%' then n.email else excluded.email end,
  link_painel = case when excluded.link_painel = '' then n.link_painel else excluded.link_painel end;

create or replace function privado.esc(t text) returns text
language sql immutable as $$
  select replace(replace(replace(replace(coalesce(t, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;');
$$;

create or replace function privado.fone(w text) returns text
language sql immutable as $$
  select case
    when length(d) = 11 then '(' || substr(d, 1, 2) || ') ' || substr(d, 3, 5) || '-' || substr(d, 8)
    when length(d) = 10 then '(' || substr(d, 1, 2) || ') ' || substr(d, 3, 4) || '-' || substr(d, 7)
    else d
  end
  from (select case when length(x) > 11 and left(x, 2) = '55' then substr(x, 3) else x end as d
          from (select regexp_replace(coalesce(w, ''), '\D', '', 'g') as x) a) b;
$$;

create or replace function privado.enviar_aviso(
  p_tipo text, p_servico text, p_inicio timestamptz, p_fim timestamptz,
  p_nome text, p_whats text, p_valor numeric
) returns bigint
language plpgsql security definer set search_path = public, privado, extensions as $$
declare
  c privado.notificacao;
  ini timestamp := p_inicio at time zone 'America/Sao_Paulo';
  fim timestamp := p_fim at time zone 'America/Sao_Paulo';
  wd int := extract(dow from p_inicio at time zone 'America/Sao_Paulo')::int;
  hora text := to_char(p_inicio at time zone 'America/Sao_Paulo', 'HH24:MI');
  digitos text := regexp_replace(coalesce(p_whats, ''), '\D', '', 'g');
  dia_longo text;
  dia_curto text;
  wa text;
  valor_txt text := '';
  titulo text;
  assunto text;
  aviso text;
  tr text := '<tr><td style="padding:8px 12px 8px 0;width:90px;vertical-align:top;font-size:13px;color:#806044">%s</td><td style="padding:8px 0;font-size:15px;font-weight:bold;color:#050505">%s</td></tr>';
  linhas text;
  corpo text;
  txt text;
  req bigint;
begin
  select * into c from privado.notificacao where id = 1;
  if c.id is not null and not c.ativo then
    return null;
  end if;
  if c.id is null or c.resend_key = '' or c.resend_key like 'COLE_AQUI%' then
    raise exception 'Falta a chave do Resend. Preencha no arquivo avisos-email.sql e rode de novo.';
  end if;
  if c.email = '' or c.email like 'COLE_AQUI%' then
    raise exception 'Falta o e-mail que recebe os avisos. Preencha no arquivo avisos-email.sql e rode de novo.';
  end if;

  dia_longo := (array['domingo', 'segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado'])[wd + 1] || ', ' || to_char(ini, 'DD/MM');
  dia_curto := (array['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'])[wd + 1] || ', ' || to_char(ini, 'DD/MM');
  if length(digitos) >= 10 then
    wa := 'https://wa.me/' || case when length(digitos) <= 11 then '55' || digitos else digitos end;
  end if;
  if p_valor is not null then
    valor_txt := 'R$ ' || translate(to_char(p_valor, 'FM999,990.00'), ',.', '.,');
  end if;

  if p_tipo = 'cancelado' then
    titulo := 'Cancelado pela cliente';
    assunto := 'Cancelado pela cliente: ' || p_servico || ' · ' || dia_curto || ' às ' || hora;
    aviso := 'A cliente cancelou pelo site. O horário já está livre de novo na agenda.';
  else
    titulo := case when p_tipo = 'teste' then 'Teste de aviso' else 'Novo pedido pelo site' end;
    assunto := case when p_tipo = 'teste' then '[Teste] ' else '' end || 'Novo agendamento: ' || p_servico || ' · ' || dia_curto || ' às ' || hora;
    aviso := 'O horário já está reservado. Confirme ou recuse no painel e avise a cliente pelo WhatsApp.';
  end if;

  linhas := format(tr, 'Serviço', privado.esc(p_servico))
    || format(tr, 'Dia', privado.esc(dia_longo))
    || format(tr, 'Horário', hora || ' – ' || to_char(fim, 'HH24:MI'))
    || format(tr, 'Cliente', privado.esc(p_nome))
    || case when wa is not null then format(tr, 'WhatsApp', '<a href="' || wa || '" style="color:#806044">' || privado.fone(digitos) || '</a>') else '' end
    || case when valor_txt <> '' then format(tr, 'Valor', valor_txt) else '' end;

  corpo := '<div style="background:#EAE8E5;padding:24px 12px;font-family:Arial,Helvetica,sans-serif">'
    || '<div style="max-width:520px;margin:0 auto;background:#FFFFFF;border-top:3px solid #B89570;padding:28px 24px">'
    || '<p style="margin:0 0 6px;font-size:12px;letter-spacing:2px;text-transform:uppercase;color:#806044">Agenda Emi Santos</p>'
    || '<h1 style="margin:0 0 18px;font-size:21px;line-height:1.3;color:#050505">' || titulo || '</h1>'
    || '<table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse">' || linhas || '</table>'
    || '<p style="margin:20px 0 0;font-size:14px;line-height:1.6;color:#111111">' || aviso || '</p>'
    || case when wa is not null and p_tipo <> 'cancelado' then '<p style="margin:22px 0 0"><a href="' || wa || '" style="display:inline-block;padding:13px 22px;background:#050505;color:#FFFFFF;text-decoration:none;font-size:12px;font-weight:bold;letter-spacing:1px;text-transform:uppercase">Chamar no WhatsApp</a></p>' else '' end
    || case when c.link_painel <> '' then '<p style="margin:18px 0 0"><a href="' || privado.esc(c.link_painel) || '" style="color:#806044;font-size:13px;font-weight:bold;letter-spacing:1px;text-transform:uppercase">Abrir painel</a></p>' else '' end
    || '</div></div>';

  txt := titulo || E'\n\n'
    || 'Serviço: ' || p_servico || E'\n'
    || 'Dia: ' || dia_longo || E'\n'
    || 'Horário: ' || hora || ' – ' || to_char(fim, 'HH24:MI') || E'\n'
    || 'Cliente: ' || coalesce(p_nome, '') || E'\n'
    || case when wa is not null then 'WhatsApp: ' || privado.fone(digitos) || ' · ' || wa || E'\n' else '' end
    || case when valor_txt <> '' then 'Valor: ' || valor_txt || E'\n' else '' end
    || E'\n' || aviso
    || case when c.link_painel <> '' then E'\n\nPainel: ' || c.link_painel else '' end;

  select net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || c.resend_key),
    body := jsonb_build_object(
      'from', 'Agenda Emi Santos <onboarding@resend.dev>',
      'to', jsonb_build_array(c.email),
      'subject', assunto,
      'html', corpo,
      'text', txt
    )
  ) into req;
  return req;
end $$;

-- Dispara o aviso: pedido novo feito pelo site, ou cancelamento feito pela própria cliente.
-- Se o envio falhar, o agendamento continua valendo normalmente.
create or replace function privado.ao_mudar_agendamento() returns trigger
language plpgsql security definer set search_path = public, privado as $$
begin
  if tg_op = 'UPDATE' and (new.cliente is null or new.cliente is distinct from auth.uid()) then
    return new;
  end if;
  begin
    perform privado.enviar_aviso(
      case when tg_op = 'UPDATE' then 'cancelado' else 'novo' end,
      new.servico, new.inicio, new.fim, new.nome, new.whatsapp, new.valor
    );
  exception when others then
    raise warning 'Aviso por e-mail não enviado: %', sqlerrm;
  end;
  return new;
end $$;

drop trigger if exists avisar_novo on public.agendamentos;
create trigger avisar_novo
  after insert on public.agendamentos
  for each row when (new.origem = 'site')
  execute function privado.ao_mudar_agendamento();

drop trigger if exists avisar_cancelado on public.agendamentos;
create trigger avisar_cancelado
  after update of status on public.agendamentos
  for each row when (old.status is distinct from new.status and new.status = 'cancelado')
  execute function privado.ao_mudar_agendamento();

create or replace function privado.testar_aviso() returns text
language plpgsql security definer set search_path = public, privado as $$
declare
  t timestamptz := date_trunc('hour', now()) + interval '1 day';
begin
  if privado.enviar_aviso('teste', 'Lash lifting', t, t + interval '80 minutes', 'Cliente de teste', '51999999999', 75) is null then
    return 'Os avisos estão desligados. Para ligar: update privado.notificacao set ativo = true;';
  end if;
  return 'E-mail de teste enviado. Deve chegar em até 1 minuto (confira também o spam).';
end $$;

revoke all on schema privado from public;
revoke all on all tables in schema privado from public, anon, authenticated;
revoke all on all functions in schema privado from public, anon, authenticated;

select 'Pronto. Agora, numa nova query, rode: select privado.testar_aviso();' as proximo_passo;
