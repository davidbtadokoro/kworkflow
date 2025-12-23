include "${KW_LIB_DIR}/lib/kw_db.sh"

declare -gr DATABASE_PATCH_TABLE='patch'
declare -Ag condition_array

function insert_patch()
{
  local _patch_title="$1"
  local _patch_author="$2"
  local _contribution_id="$3"
  local _commit_hash="$4"
  local sql_operation_result
  local ret

  if [[ -z "$_patch_title" || -z "$_patch_author" || -z "$_contribution_id" || -z "$_commit_hash" ]]; then
    complain "($LINENO): missing mandatory field for a new patch"
    return 22 # EINVAL
  fi

  columns='"title", "author_email", "contribution_id", "commit_hash"'
  values="'${_patch_title}', '${_patch_author}', '${_contribution_id}', '${_commit_hash}'"

  sql_operation_result=$(insert_into "$DATABASE_PATCH_TABLE" \
    "($columns)" \
    "($values)")
  ret="$?"

  if [[ "$ret" -eq 2 || "$ret" -eq 61 ]]; then
    complain "$sql_operation_result"
    return 22 # EINVAL
  elif [[ "$ret" -ne 0 ]]; then
    complain "($LINENO):" $'Error while trying to insert new patch:\n'"$sql_operation_result"
    return 22 # EINVAL
  fi

  return 0
}

function get_or_create_patch()
{
  local _patch_title="$1"
  local _patch_author="$2"
  local _contribution_id="$3"
  local _commit_hash="$4"
  local ret
  local patch_existent_result
  local insert_contribution_result
  local get_contribution_id_result

  if [[ -z "$_patch_title" || -z "$_patch_author" || -z "$_contribution_id" ]]; then
    complain "($LINENO): missing mandatory field for new_patch title ${_patch_title}, author: ${_patch_author}, contribution_id ${_contribution_id}"
    return 22 # EINVAL
  fi

  patch_existent_result="$(check_patch_existence_by_unique_attributes "$_patch_title" "$_patch_author" "$_contribution_id" "$_commit_hash")"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$patch_existent_result"
    return "$ret" # EINVAL
  fi

  if [[ -z "$patch_existent_result" ]]; then
    complain "($LINENO): unexpected empty result from check_patch_existence_by_unique_attributes"
    return 22 # EINVAL
  fi

  if [[ "$patch_existent_result" -eq 0 ]]; then
    insert_contribution_result=$(insert_patch "$_patch_title" "$_patch_author" "$_contribution_id" \
      "$_commit_hash")
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
      complain "$insert_contribution_result"
      return "$ret" # EINVAL
    fi
  fi

  get_contribution_id_result=$(get_patch_infos_by_unique_attributes 'id' "$_patch_title" \
    "$_patch_author" "$_contribution_id" "$_commit_hash")
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$get_contribution_id_result"
    return "$ret" # EINVAL
  fi

  printf '%s\n' "$get_contribution_id_result"
  return 0
}

function get_patch_info_by_id()
{
  local _patch_infos="$1"
  local _patch_id="$2"
  local sql_operation_result
  local ret

  if [[ -z "$_patch_id" ]]; then
    complain "($LINENO): empty patch id"
    return 22 # EINVAL
  fi

  condition_array=(['id']="${_patch_id}")
  sql_operation_result="$(get_patch_info "$_patch_infos" 'condition_array')"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$sql_operation_result"
    return "$ret" # EINVAL
  fi

  if [[ -z "$sql_operation_result" ]]; then
    complain "($LINENO): no result found for patch id $_patch_id"
    return 61 # ENODATA
  fi

  printf '%s\n' "$sql_operation_result"
  return 0
}

function get_patch_info_by_commit_hash()
{
  local _patch_infos="$1"
  local _commit_hash="$2"
  local sql_operation_result
  local ret

  if [[ -z "$_commit_hash" ]]; then
    complain "($LINENO): empty commit hash"
    return 22 # EINVAL
  fi

  condition_array=(['commit_hash']="${_commit_hash}")
  sql_operation_result="$(get_patch_info "$_patch_infos" 'condition_array')"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$sql_operation_result"
    return "$ret" # EINVAL
  fi

  if [[ -z "$sql_operation_result" ]]; then
    complain "($LINENO): no result found for commit hash $_commit_hash"
    return 61 # ENODATA
  fi

  printf '%s\n' "$sql_operation_result"
  return 0
}

function get_patch_info()
{
  local _patch_infos="$1"
  local -n _patch_condition_array="$2"

  sql_operation_result="$(get_database_table_info "$DATABASE_PATCH_TABLE" "$_patch_infos" '_patch_condition_array')"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$sql_operation_result"
    return "$ret" # EINVAL
  fi

  printf '%s\n' "$sql_operation_result"
  return 0
}

function check_patch_existence_by_unique_attributes()
{
  local _patch_title="$1"
  local _patch_author="$2"
  local _contribution_id="$3"
  local _commit_hash="$4"

  if [[ -z "$_commit_hash" ]]; then
    printf '%s\n' 0
    return 0 # Not safe to check if the patch is the same if there is no commit hash
  fi

  if [[ -z "$_patch_title" || -z "$_patch_author" || -z "$_contribution_id" ]]; then
    complain "($LINENO): no attributes provided for check_patch_existence_by_unique_attributes"
    return 22 # EINVAL
  fi

  condition_array=(['title']="${_patch_title}"
    ['author_email']="${_patch_author}"
    ['contribution_id']="${_contribution_id}"
    ['commit_hash']="${_commit_hash}")

  sql_operation_result="$(check_existence "$DATABASE_PATCH_TABLE" 'condition_array')"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$sql_operation_result"
    return "$ret" # EINVAL
  fi

  if [[ -z "$sql_operation_result" ]]; then
    complain "($LINENO): check existence returned null"
    return 61 # ENODATA
  fi

  printf '%s\n' "$sql_operation_result"
  return 0
}

function get_patch_infos_by_unique_attributes()
{
  local _patch_infos="$1"
  local _patch_title="$2"
  local _patch_author="$3"
  local _contribution_id="$4"
  local _commit_hash="$5"

  if [[ -z "$_commit_hash" ]]; then
    printf '%s\n' 0
    return 0 # Not safe to check if the patch is the same if there is no commit hash
  fi

  if [[ -z "$_patch_title" || -z "$_patch_author" || -z "$_contribution_id" ]]; then
    complain "($LINENO): no attributes provided for check_patch_existence_by_unique_attributes"
    return 22 # EINVAL
  fi

  condition_array=(['title']="${_patch_title}"
    ['author_email']="${_patch_author}"
    ['contribution_id']="${_contribution_id}"
    ['commit_hash']="${_commit_hash}")

  sql_operation_result="$(get_patch_info "$_patch_infos" 'condition_array')"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$sql_operation_result"
    return "$ret" # EINVAL
  fi

  if [[ -z "$sql_operation_result" ]]; then
    complain "($LINENO): no result found for patch title _${_patch_title}, patch author ${_patch_author},\
        contribution id ${_contribution_id} commit hash ${_commit_hash}"
    return 61 # ENODATA
  fi

  printf '%s\n' "$sql_operation_result"
  return 0
}

# Função: formatar_data_patch
# Descrição: Recebe uma string de data no formato RFC 2822 (como em cabeçalhos de patch)
#            e a formata para o padrão YYYY-MM-DD HH:MM:SS, seguro para a maioria
#            dos campos DATETIME/TIMESTAMP de bancos de dados.
#
# @date_string: A string de data bruta (Ex: "Wed, 8 Oct 2025 00:37:32 -0300")
#
# Retorna: A data formatada no stdout.
formatar_data_patch()
{
  local date_string="$1"
  local formatted_date

  if [ -z "$date_string" ]; then
    echo "Erro: Nenhuma string de data fornecida." >&2
    return 1
  fi

  # Usa 'date -d' para interpretar a string de data complexa.
  # O formato de saída é %Y-%m-%d %H:%M:%S.
  # Nota: A data é convertida para o fuso horário LOCAL do sistema que está rodando o script.
  # Se você quiser manter o fuso horário original, o formato seria diferente.
  formatted_date=$(date -d "$date_string" +"%Y-%m-%d %H:%M:%S")

  # Verifica se o comando date foi bem-sucedido
  if [ "$?" -ne 0 ]; then
    echo "Erro: Falha ao processar a string de data: '$date_string'" >&2
    return 1
  fi

  # Imprime a data formatada no stdout
  printf '%s' "$formatted_date"
  return 0
}
