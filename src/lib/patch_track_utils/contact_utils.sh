include "${KW_LIB_DIR}/lib/kw_db.sh"

declare -Ag condition_array
declare -gr DATABASE_EMAIL_CONTACT_TABLE='email_contact'

function insert_email_contact()
{
  local _contact_name="$1"
  local _contact_email="$2"
  local columns
  local values
  local sql_operation_result
  local ret

  if [[ -z "$_contact_name" || -z "$_contact_email" ]]; then
    complain "($LINENO): missing mandatory field(s) for insert_email_contact (name, email)"
    return 22 # EINVAL
  fi

  columns='"name", "email"'
  values="'${_contact_name}', '${_contact_email}'"

  sql_operation_result=$(insert_into "$DATABASE_EMAIL_CONTACT_TABLE" \
    "($columns)" \
    "($values)")
  ret="$?"

  if [[ "$ret" -eq 2 || "$ret" -eq 61 ]]; then
    complain "$sql_operation_result"
    return 22 # EINVAL
  elif [[ "$ret" -ne 0 ]]; then
    complain "($LINENO):" $'Error while trying to insert new email contact:\n'"$sql_operation_result"
    return 22 # EINVAL
  fi

  return 0
}

function check_email_contact_existence_by_unique_attributes()
{
  local _contact_email="$1"
  local sql_operation_result
  local ret

  if [[ -z "$_contact_email" ]]; then
    complain "($LINENO): empty unique attribute for check_email_contact_existence_by_unique_attributes (email)"
    return 22 # EINVAL
  fi

  condition_array['email']="${_contact_email}"

  sql_operation_result="$(check_existence "$DATABASE_EMAIL_CONTACT_TABLE" 'condition_array')"
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

function get_email_contact_info()
{
  local _contact_infos="$1"
  local -n _contact_info_condition_array="$2"
  local sql_operation_result
  local ret

  sql_operation_result="$(get_database_table_info "$DATABASE_EMAIL_CONTACT_TABLE" "$_contact_infos" '_contact_info_condition_array')"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$sql_operation_result"
    return 22 # EINVAL
  fi

  printf '%s\n' "$sql_operation_result"
  return 0
}

function get_email_contact_info_by_unique_attributes()
{
  local _contact_infos="$1"
  local _contact_email="$2"
  local sql_operation_result
  local ret

  if [[ -z "$_contact_email" ]]; then
    complain "($LINENO): empty unique attribute for get_email_contact_info_by_unique_attributes (email)"
    return 22 # EINVAL
  fi

  condition_array['email']="${_contact_email}"

  sql_operation_result="$(get_email_contact_info "$_contact_infos" 'condition_array')"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$sql_operation_result"
    return "$ret"
  fi

  printf '%s\n' "$sql_operation_result"
  return 0
}

function get_or_create_email_contact()
{
  local _contact_name="$1"
  local _contact_email="$2"
  local contact_existent_result
  local insert_contact_result
  local get_contact_id_result
  local ret

  if [[ -z "$_contact_name" || -z "$_contact_email" ]]; then
    complain "($LINENO): missing mandatory field(s) for get_or_create_email_contact"
    return 22 # EINVAL
  fi

  contact_existent_result="$(check_email_contact_existence_by_unique_attributes "$_contact_email")"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$contact_existent_result"
    return "$ret"
  fi

  if [[ "$contact_existent_result" -eq 0 ]]; then
    insert_contact_result=$(insert_email_contact "$_contact_name" "$_contact_email")
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
      complain "$insert_contact_result"
      return "$ret"
    fi
  fi

  get_contact_id_result=$(get_email_contact_info_by_unique_attributes 'id' "$_contact_email")
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$get_contact_id_result"
    return "$ret"
  fi

  printf '%s\n' "$get_contact_id_result"
  return 0
}
