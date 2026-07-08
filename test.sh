#!/usr/bin/env bash
set -euo pipefail

PATTERN="${1:-[PATCH]}"   # filtro, padrão "[PATCH]"
DEST="$HOME/Maildir/patches"
mkdir -p "$DEST"

MUTTRC="$HOME/.muttrc"

# função para extrair valor de .muttrc
get_muttrc_value() {
  local key="$1"
  grep -E "^set[[:space:]]+$key" "$MUTTRC" 2>/dev/null \
    | sed -E 's/set[[:space:]]+'"$key"'[[:space:]]*=[[:space:]]*"(.*)"/\1/'
}

IMAP_USER=$(get_muttrc_value imap_user)
IMAP_PASS=$(get_muttrc_value imap_pass)
IMAP_FOLDER=$(get_muttrc_value folder)
SPOOLFILE=$(get_muttrc_value spoolfile)

IMAP_SERVER=$(echo "$IMAP_FOLDER" | sed -E 's|imaps?://([^/]+)/.*|\1|; s|imaps?://([^/]+)|\1|')
MAILBOX="${SPOOLFILE#\+}"
MAILBOX="${MAILBOX:-INBOX}"

echo "Conectando a $IMAP_SERVER/$MAILBOX para buscar mensagens com Subject =~ $PATTERN"

# 1) SEARCH
UIDS=$(curl -s -u "$IMAP_USER:$IMAP_PASS" \
       --url "imaps://$IMAP_SERVER/$MAILBOX" \
       -X "UID SEARCH SUBJECT \"$PATTERN\"" \
       | tr -d '\r' | awk '{for(i=2;i<=NF;i++) print $i}')

if [ -z "$UIDS" ]; then
  echo "Nenhuma mensagem encontrada."
  exit 0
fi

echo "UIDs encontrados: $UIDS"

# 2) FETCH BODY[TEXT] (somente body) e salvar
for uid in $UIDS; do
  out="$DEST/mail_body_$uid.txt"
  echo "Baixando body UID $uid -> $out"
  curl -s -u "$IMAP_USER:$IMAP_PASS" \
       --url "imaps://$IMAP_SERVER/$MAILBOX" \
       -X "UID FETCH $uid BODY[TEXT]" \
       | sed -n '/FETCH/,/)/{ /FETCH/d; /\)/d; p }' > "$out"
done

echo "Concluído. Bodies salvos em $DEST"
