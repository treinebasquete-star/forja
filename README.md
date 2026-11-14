# Forja — treino de musculação (azul + preto metálico)

Produto separado do app de basquete: projeto próprio no Supabase (`treino-academia`), repositório próprio e marca própria.

## Como funciona
- **Link principal** (`/`): login do professor/instrutor.
- **Link pessoal do aluno** (`/?a=CÓDIGO`): sem login; fichas A–E, carga e repetições por série, "última vez", agenda e uso sem internet.
- Cada cliente (personal ou academia) é uma **organização**; cada professor só vê a dela. O dono do sistema tem a aba **Clientes**.

## Colocar no ar
1. Crie um repositório novo (por exemplo `forja`) e envie TODOS os arquivos desta pasta: `index.html`, `manifest.webmanifest`, `sw.js`, `icon-192.png`, `icon-512.png`, `apple-touch-icon.png`, `README.md` e a pasta `supabase`.
2. **Settings → Pages → Deploy from a branch → main / (root)**.
3. No Supabase (projeto `treino-academia`): **Authentication → Users → Add user** (marque *Auto Confirm User*) com o seu e-mail e uma senha, e desative **Sign In / Providers → Allow new users to sign up**.
4. Avise o e-mail usado para liberar o acesso de dono e cadastrar o primeiro cliente.

`index.html` já aponta para o banco da academia. A chave `anon` é pública por desenho; quem protege os dados são as regras (RLS) de `supabase/schema.sql`.
