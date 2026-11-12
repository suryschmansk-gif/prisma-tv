# Prisma TV: passo a passo completo (usando um PC com Windows)

Você vai fazer três coisas:

1. Colocar o código no **GitHub**, que compila o app de graça numa máquina Mac na nuvem.
2. **Testar no navegador do PC** com o Appetize, que roda um iPhone virtual.
3. **Instalar no iPhone/iPad** com o Sideloadly.

---

## Parte 1: GitHub (uns 10 minutos, só na primeira vez)

1. Descompacte o `PrismaTV.zip` numa pasta do PC, por exemplo `Documentos\PrismaTV`.
2. Mostre os arquivos ocultos. No Explorador de Arquivos, clique em **Exibir → Mostrar → Itens ocultos**. Isso é necessário porque a pasta `.github` começa com ponto e o Windows a esconde.
3. Crie uma conta em **https://github.com**. É grátis.
4. No canto superior direito, clique em **+ → New repository**.
   - Repository name: `prisma-tv`
   - Marque **Private**.
   - Clique em **Create repository**.
5. Na página que abrir, clique no link **uploading an existing file**.
6. Abra a pasta `PrismaTV` no Explorador, selecione **tudo lá dentro** (Ctrl+A, incluindo a `.github`) e arraste para a página do GitHub.
7. Espere terminar de carregar e clique em **Commit changes**.
8. Confira se a pasta `.github` apareceu na lista de arquivos do repositório.
   - Se não apareceu: clique em **Add file → Create new file**, digite o nome `.github/workflows/build.yml`, cole o conteúdo do arquivo `build.yml` desta pasta e clique em **Commit changes**.

## Parte 2: Esperar o app compilar

1. No repositório, abra a aba **Actions**.
2. A tarefa **"Gerar app (IPA)"** começa sozinha. Se não começar, clique nela e depois em **Run workflow**.
3. Leva de 10 a 20 minutos. Quando aparecer ✅, clique na execução.
4. No fim da página, em **Artifacts**, aparecem dois arquivos:
   - **PrismaTV-ipa**: para instalar no iPhone/iPad (Parte 4).
   - **PrismaTV-simulador**: para testar no navegador do PC (Parte 3).
5. Baixe os dois e descompacte cada um uma vez. Você vai ter o `PrismaTV.ipa` e o `PrismaTV-simulador.zip`.

> Se aparecer ❌: abra a execução, clique no passo vermelho, copie as linhas que têm `error:` e me mande. Eu corrijo.

## Parte 3: Testar no PC, sem iPhone (opcional)

1. Acesse **https://appetize.io** e crie uma conta grátis.
2. Clique em **Upload** e envie o arquivo `PrismaTV-simulador.zip`. Não descompacte este.
3. Escolha um iPhone ou iPad e clique em **Play**. O app abre no navegador como se fosse um celular.
4. Faça login com a sua linha e teste tudo.

> O plano grátis do Appetize tem um limite de minutos por mês. Os sons de clique, a vibração e o brilho só funcionam no aparelho de verdade.

## Parte 4: Instalar no iPhone/iPad

1. No PC, instale o **iTunes** e o **iCloud** pelo site da Apple (não use a versão da Microsoft Store).
2. Instale o **Sideloadly**: https://sideloadly.io
3. Ligue o iPhone/iPad no cabo e toque em **Confiar** no aparelho.
4. Abra o Sideloadly, arraste o `PrismaTV.ipa`, digite seu **Apple ID** e clique em **Start**.
5. No aparelho, ative o **Modo de Desenvolvedor** em *Ajustes → Privacidade e Segurança → Modo de Desenvolvedor*. O aparelho reinicia.
6. Vá em *Ajustes → Geral → VPN e Gerenciamento de Dispositivo*, toque no seu e-mail e escolha **Confiar**.
7. Abra o **Prisma TV** e faça o login.
   - Servidor: `http://bludx.top`
   - Ou toque em **Colar link M3U**.

> **Validade:** com um Apple ID gratuito o app funciona por **7 dias**. Para renovar, basta repetir o passo 4; seus dados continuam salvos. Se usar o **AltStore** no lugar do Sideloadly, ele renova sozinho com o PC ligado na mesma rede Wi-Fi.

## Como atualizar o app depois

Quando eu te mandar uma versão nova:

1. Entre no repositório e use **Add file → Upload files** para enviar os arquivos que mudaram (pode arrastar a pasta inteira de novo).
2. Clique em **Commit changes**. O GitHub compila sozinho.
3. Baixe o novo `.ipa` e reinstale pelo Sideloadly por cima do antigo.

---

## O que tem no app

- **Abertura animada**, som e vibração leves ao tocar e conteúdo surgindo com um fade sutil ao rolar. O som pode ser desligado em Configurações.
- **Abas separadas** (Séries, Filmes e TV), com o app abrindo em Séries. A barra de abas fica flutuando em vidro.
- **Continuar assistindo** mostrando temporada, episódio, título e tempo, por exemplo "T1 · E3", "Episódio 3 — Sem Saída" e "21:36 de 45:00 · faltam 23 min".
- **Player premium**:
  - Gira sozinho para a horizontal.
  - Botões de vidro e barras de volume e brilho nas laterais.
  - Gaveta de episódios e botão de próximo episódio.
  - Velocidade, áudio, legendas e proporção da tela.
  - Botão "Pular abertura", que pula para 1:30. A posição é aproximada.
  - Contagem automática para o próximo episódio.
- **Player VLC**, que toca MKV, AVI, TS e HLS.
- **Guia de canais (EPG)** com o programa de agora e o próximo.
- As listas ficam guardadas no aparelho e são atualizadas sozinhas a cada 12 horas.

## Problemas comuns

| Sintoma | O que fazer |
|---|---|
| "Usuário ou senha incorretos" | Confira o servidor com a porta, por exemplo `http://dominio.com:8080` |
| Canal não abre ou fica travando | Toque no ícone de conta → Formato da TV ao vivo → troque para HLS |
| A compilação deu ❌ | Me mande as linhas com `error:` |
