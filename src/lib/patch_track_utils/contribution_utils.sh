include "${KW_LIB_DIR}/lib/kw_db.sh"

declare -gr DATABASE_CONTRIBUTION_TABLE='contribution'
declare -gA condition_array
declare -gA updates_array

function insert_contribution()
{
  local _contribution_title="$1"
  local _author_email="$2"
  local _repository_id="$3"

  # Checagem de valores nulos
  if [[ -z "$_contribution_title" || -z "$_author_email" ]]; then
    complain "($LINENO): missing mandatory field(s) for insert_contribution"
    return 22 # EINVAL
  fi

  columns='"title", "author_email"'
  values="'${_contribution_title}', '${_author_email}'"

  if [[ -n "${_repository_id}" ]]; then
    columns="$columns, \"repository_id\""
    values="$values, '${_repository_id}'"
  fi

  sql_operation_result=$(insert_into "$DATABASE_CONTRIBUTION_TABLE" \
    "($columns)" \
    "($values)")
  ret="$?"

  if [[ "$ret" -eq 2 || "$ret" -eq 61 ]]; then
    complain "$sql_operation_result"
    return 22 # EINVAL
  elif [[ "$ret" -ne 0 ]]; then
    complain "($LINENO):" $'Error while trying to insert new contribution:\n'"$sql_operation_result"
    return 22 # EINVAL
  fi

  return 0
}

function get_or_create_contribution()
{
  local _contribution_title="$1"
  local _author_email="$2"
  local _repository_id="$3"
  local sql_operation_result
  local insert_contribution_result
  local get_contribution_id_resultget_or_create_contribution

  # Checagem de valores nulos
  if [[ -z "$_contribution_title" || -z "$_author_email" ]]; then
    complain "($LINENO): missing mandatory field(s) for new_contribution"
    return 22 # EINVAL
  fi

  patch_existent_result="$(check_contribution_existence_by_unique_attributes "$_contribution_title" "$_author_email")"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$patch_existent_result"
    return "$ret"
  fi

  if [[ "$patch_existent_result" -eq 0 ]]; then

    insert_contribution_result=$(insert_contribution "$_contribution_title" "$_author_email" "$_repository_id")
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
      complain "$insert_contribution_result"
      return "$ret"
    fi
  fi

  get_contribution_id_result=$(get_contribution_info_by_unique_attributes 'id' "$_contribution_title" "$_author_email")
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$get_contribution_id_result"
    return "$ret"
  fi

  printf '%s\n' "$get_contribution_id_result"
  return 0
}

function check_contribution_existence_by_unique_attributes()
{
  local _contribution_title="$1"
  local _author_email="$2"
  local sql_operation_result
  local ret

  # Checagem de valor nulo
  if [[ -z "$_contribution_title" || -z "$_author_email" ]]; then
    complain "($LINENO): empty contribution infos for check_contribution_existence_by_unique_attributes"
    return 22 # EINVAL
  fi

  condition_array=(['title']="${_contribution_title}"
    ['author_email']="${_author_email}")

  sql_operation_result="$(check_existence "$DATABASE_CONTRIBUTION_TABLE" 'condition_array')"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$sql_operation_result"
    return "$ret"
  fi

  if [[ -z "$sql_operation_result" ]]; then
    complain "($LINENO): check existence returned null"
    return 61 # ENODATA
  fi

  printf '%s\n' "$sql_operation_result"
  return 0
}

function get_contribution_info_by_unique_attributes()
{
  local _contribution_infos="$1"
  local _contribution_title="$2"
  local _author_email="$3"
  local sql_operation_result
  local ret

  if [[ -z "$_contribution_title" || -z "$_author_email" ]]; then
    complain "($LINENO): empty contribution title for get_contribution_info_by_title"
    return 22 # EINVAL
  fi

  condition_array=(['title']="${_contribution_title}"
    ['author_email']="${_author_email}")

  sql_operation_result="$(get_contribution_info "$_contribution_infos" 'condition_array')"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$sql_operation_result"
    return "$ret"
  fi

  printf '%s\n' "$sql_operation_result"
  return 0
}

function get_contribution_info()
{
  local _contribution_infos="$1"
  local -n _contrib_info_condition_array="$2"
  local _order_by="${3:-}"
  local sql_operation_result
  local ret

  sql_operation_result="$(get_database_table_info "$DATABASE_CONTRIBUTION_TABLE" "$_contribution_infos" '_contrib_info_condition_array' "$_order_by")"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$sql_operation_result"
    return 22 # EINVAL
  fi

  printf '%s\n' "$sql_operation_result"
  return 0
}

function set_contribution_repository()
{
  local contribution_id="$1"
  local repository_id="$2"

  updates_array=(['repository_id']="$repository_id")
  condition_array=(['id']="$contribution_id")

  update_into_result=$(update_into "$DATABASE_CONTRIBUTION_TABLE" 'updates_array' '' 'condition_array')
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$update_into_result"
    return 22 # EINVAL
  fi

  return 0
}
