# Como ligar a agenda do site

A agenda usa o Supabase (plano grátis) para guardar as contas das clientes, os agendamentos, os serviços e os horários. Você faz isso uma vez só, em uns 15 minutos.

## 1. Criar o projeto

1. Entre em supabase.com e crie uma conta.
2. Clique em **New project**. Nome: `emi-santos`. Crie uma senha para o banco e guarde. Região: **South America (São Paulo)**.
3. Espere o projeto ficar pronto (1 a 2 minutos).

## 2. Criar o banco de dados

1. No menu da esquerda, abra **SQL Editor** e clique em **New query**.
2. Cole todo o conteúdo do arquivo `supabase.sql` e clique em **Run**.
3. Deve aparecer "Success". Os serviços, valores e horários já ficam cadastrados.

## 3. Ajustar o login das clientes

1. Abra **Authentication > Sign In / Providers**. Em **Email**, desligue **Confirm email** e salve.
   Sem um servidor de e-mail próprio, o Supabase só manda e-mails para a equipe do projeto. Com a confirmação ligada, as clientes não conseguiriam entrar.
2. Em **Authentication > URL Configuration**, coloque o endereço do site em **Site URL** (por exemplo `https://seu-usuario.github.io/emi-santos/`).

## 4. Ligar o site

1. Clique em **Connect** no topo do projeto (ou vá em **Project Settings > API Keys**).
2. Copie a **Project URL** e a **Publishable key** (em projetos antigos ela se chama **anon public**).
3. No GitHub, abra o arquivo `config.js`, clique no lápis para editar e cole os dois valores entre as aspas:
   ```
   supabaseUrl: 'https://xxxxxxxx.supabase.co',
   supabaseKey: 'sb_publishable_xxxxxxxx',
   ```
4. Clique em **Commit changes**. Em 1 a 2 minutos o site sai do modo demonstração.

Essa chave pode ficar no site: ela só permite o que as regras do banco liberam. Nunca coloque a chave **secret** ou **service_role** no site.

## 5. Dar acesso de administradora para a Emi

1. A Emi cria a conta dela pelo próprio site (seção Agendar > Criar conta).
2. No **SQL Editor**, rode a linha abaixo trocando pelo e-mail dela:
   ```
   update public.perfis set admin = true where id = (select id from auth.users where email = 'email-da-emi@gmail.com');
   ```
3. Pronto. No link **Área da Emi**, no rodapé do site (`painel.html`), ela entra com o mesmo e-mail e senha. Vale salvar essa página na tela inicial do celular.

## No dia a dia (painel)

- **Agenda:** os pedidos novos aparecem no topo. **Confirmar** muda o status e mostra o botão **Enviar confirmação**, que abre o WhatsApp com a mensagem pronta para a cliente. **Recusar** libera o horário no site.
- **Bloquear horários:** folgas, feriados e compromissos. Sem horário, bloqueia o dia inteiro. Com "Até o dia", bloqueia vários dias.
- **Lançar atendimento:** horários marcados pelo Instagram, WhatsApp ou pessoalmente. O horário some da agenda do site.
- **Serviços e horários:** nome, duração e valor de cada serviço; dias e horários de atendimento; intervalo entre horários, antecedência mínima e quantos pedidos em aberto cada cliente pode ter.

## Bom saber

- Dois agendamentos no mesmo horário são impossíveis: o próprio banco recusa, mesmo se duas clientes clicarem ao mesmo tempo.
- Nome e WhatsApp das clientes só aparecem no painel. A parte pública do site só sabe quais horários estão ocupados.
- A cliente pode cancelar o próprio agendamento pelo site, em **Meus agendamentos**.
- O plano grátis do Supabase pode pausar projetos que ficam muitos dias sem nenhum acesso. As visitas ao site mantêm o projeto ativo. Se pausar, é só clicar em **Restore** no painel do Supabase.
- "Esqueci minha senha" precisa de um servidor de e-mail próprio (Authentication > Emails > SMTP Settings).

## Login com Google (opcional)

O botão "Entrar com Google" só funciona depois destes passos. Se não quiser usar, deixe `loginGoogle: false` no `config.js` e o botão some.

1. No Supabase, abra **Authentication > Sign In / Providers > Google** e copie a **Callback URL** (algo como `https://xxxxxxxx.supabase.co/auth/v1/callback`).
2. Entre em console.cloud.google.com e crie um projeto.
3. Em **Google Auth Platform**, preencha **Branding** (nome do app e e-mail de suporte) e em **Audience** escolha **External** e clique em **Publish app**.
4. Em **Clients > Create client**, escolha **Web application**:
   - **Authorized JavaScript origins:** o endereço do site, ex. `https://seu-usuario.github.io`
   - **Authorized redirect URIs:** a Callback URL do passo 1
5. Copie o **Client ID** e o **Client secret**, volte ao Supabase (passo 1), ligue o Google, cole os dois e salve.
6. Em **Authentication > URL Configuration > Redirect URLs**, adicione `https://seu-usuario.github.io/**`.
7. No `config.js`, deixe `loginGoogle: true`.

Quem entra pelo Google precisa informar o WhatsApp na primeira vez. O site pede isso sozinho.

## Avisos por e-mail (opcional)

A cada pedido feito pelo site, a Emi recebe um e-mail com serviço, dia, horário, nome, WhatsApp e valor. Também chega um aviso quando a cliente cancela pelo site. O que a Emi lança no painel não gera e-mail.

1. Crie uma conta grátis em resend.com **com o e-mail que vai receber os avisos**. Sem domínio próprio, o Resend só envia para o e-mail da própria conta.
2. No Resend, abra **API Keys > Create API Key**, escolha **Sending access** e copie a chave (começa com `re_`).
3. Abra `agenda/avisos-email.sql` e troque os dois `COLE_AQUI` pela chave e pelo e-mail. Se quiser um link "Abrir painel" no e-mail, coloque também o endereço do `painel.html`.
4. No Supabase, abra **SQL Editor > New query**, cole tudo e clique em **Run**.
5. Para testar, rode numa nova query: `select privado.testar_aviso();`. O e-mail chega em até 1 minuto. Na primeira vez, confira o spam e marque como "Não é spam".
6. No celular da Emi, deixe ligadas as notificações do app de e-mail.

**Trocar quem recebe** (do seu teste para a Emi): a Emi cria a conta dela no Resend e gera uma chave. Rode o arquivo de novo com a chave e o e-mail dela.

**Desligar os avisos:** `update privado.notificacao set ativo = false;` Para religar, troque `false` por `true`.

**Se o e-mail não chegar:** rode `select status_code, content from net._http_response order by created desc limit 3;`. Código 200 quer dizer que o Resend aceitou o envio. Com outro código, o campo `content` mostra o motivo. O mais comum é chave errada ou e-mail diferente do da conta do Resend.
