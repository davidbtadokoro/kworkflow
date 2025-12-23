include "${KW_LIB_DIR}/lib/kw_db.sh"
include "${KW_LIB_DIR}/lib/patch_track_utils/contact_utils.sh"

declare -gr DATABASE_REPOSITORY_TABLE='repository'
declare -gr DATABASE_REPO_MAINTAINER_TABLE='repository_maintainer'
declare -Ag condition_array

function insert_repository()
{
  local _repository_name="$1"
  local _origin_url="$2"
  local columns
  local values
  local sql_operation_result
  local ret

  if [[ -z "$_repository_name" || -z "$_origin_url" ]]; then
    complain "($LINENO): missing mandatory field(s) for insert_repository (name, url)"
    return 22 # EINVAL
  fi

  columns='"name", "origin_url"'
  values="'${_repository_name}', '${_origin_url}'"

  sql_operation_result=$(insert_into "$DATABASE_REPOSITORY_TABLE" \
    "($columns)" \
    "($values)")
  ret="$?"

  if [[ "$ret" -eq 2 || "$ret" -eq 61 ]]; then
    complain "$sql_operation_result"
    return 22 # EINVAL
  elif [[ "$ret" -ne 0 ]]; then
    complain "($LINENO):" $'Error while trying to insert new repository:\n'"$sql_operation_result"
    return 22 # EINVAL
  fi

  return 0
}

function check_repository_existence_by_unique_attributes()
{
  local _origin_url="$1"
  local sql_operation_result
  local ret

  if [[ -z "$_origin_url" ]]; then
    complain "($LINENO): empty unique attributes for check_repository_existence_by_unique_attributes"
    return 22 # EINVAL
  fi

  condition_array['origin_url']="${_origin_url}"

  sql_operation_result="$(check_existence "$DATABASE_REPOSITORY_TABLE" 'condition_array')"
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

function get_repository_info()
{
  local _repository_infos="$1"
  local -n _repo_info_condition_array="$2"
  local sql_operation_result
  local ret

  sql_operation_result="$(get_database_table_info "$DATABASE_REPOSITORY_TABLE" "$_repository_infos" '_repo_info_condition_array')"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$sql_operation_result"
    return 22 # EINVAL
  fi

  printf '%s\n' "$sql_operation_result"
  return 0
}

function get_repository_info_by_unique_attributes()
{
  local _repository_infos="$1"
  local _origin_url="$2"
  local sql_operation_result
  local ret

  if [[ -z "$_origin_url" ]]; then
    complain "($LINENO): empty unique attributes for get_repository_info_by_unique_attributes"
    return 22 # EINVAL
  fi

  condition_array['origin_url']="${_origin_url}"

  sql_operation_result="$(get_repository_info "$_repository_infos" 'condition_array')"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$sql_operation_result"
    return "$ret"
  fi

  printf '%s\n' "$sql_operation_result"
  return 0
}

function get_or_create_repository()
{
  local _repository_name="$1"
  local _origin_url="$2"
  local repo_existent_result
  local insert_repo_result
  local get_repo_id_result
  local ret

  if [[ -z "$_repository_name" || -z "$_origin_url" ]]; then
    complain "($LINENO): missing mandatory field(s) for get_or_create_repository"
    return 22 # EINVAL
  fi

  repo_existent_result="$(check_repository_existence_by_unique_attributes "$_origin_url")"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$repo_existent_result"
    return "$ret"
  fi

  if [[ "$repo_existent_result" -eq 0 ]]; then
    insert_repo_result=$(insert_repository "$_repository_name" "$_origin_url")
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
      complain "$insert_repo_result"
      return "$ret"
    fi
  fi

  get_repo_id_result=$(get_repository_info_by_unique_attributes 'id' "$_origin_url")
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$get_repo_id_result"
    return "$ret"
  fi

  printf '%s\n' "$get_repo_id_result"
  return 0
}

function insert_repository_maintainer()
{
  local _repository_id="$1"
  local _contact_id="$2"
  local columns
  local values
  local sql_operation_result
  local ret

  if [[ -z "$_repository_id" || -z "$_contact_id" ]]; then
    complain "($LINENO): missing mandatory field(s) for insert_repository_maintainer"
    return 22 # EINVAL
  fi

  columns='"repository_id", "contact_id"'
  values="'${_repository_id}', '${_contact_id}'"

  sql_operation_result=$(insert_into "$DATABASE_REPO_MAINTAINER_TABLE" \
    "($columns)" \
    "($values)")
  ret="$?"

  if [[ "$ret" -eq 2 || "$ret" -eq 61 ]]; then
    complain "$sql_operation_result"
    return 22 # EINVAL
  elif [[ "$ret" -ne 0 ]]; then
    complain "($LINENO):" $'Error while trying to insert new repository maintainer relation:\n'"$sql_operation_result"
    return 22 # EINVAL
  fi

  return 0
}

function check_repository_maintainer_existence()
{
  local _repository_id="$1"
  local _contact_id="$2"
  local sql_operation_result
  local ret

  if [[ -z "$_repository_id" || -z "$_contact_id" ]]; then
    complain "($LINENO): missing mandatory fields for check_repository_maintainer_existence"
    return 22 # EINVAL
  fi

  condition_array['repository_id']="${_repository_id}"
  condition_array['contact_id']="${_contact_id}"

  sql_operation_result="$(check_existence "$DATABASE_REPO_MAINTAINER_TABLE" 'condition_array')"
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

function get_or_create_repository_maintainer()
{
  local _repository_id="$1"
  local _maintainer_name="$2"
  local _maintainer_email="$3"
  local contact_id
  local maintainer_relation_exists_result
  local ret

  if [[ -z "$_repository_id" || -z "$_maintainer_name" || -z "$_maintainer_email" ]]; then
    complain "($LINENO): missing mandatory field(s) for get_or_create_repository_maintainer"
    return 22 # EINVAL
  fi

  contact_id=$(get_or_create_email_contact "$_maintainer_name" "$_maintainer_email")
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$contact_id"
    return "$ret"
  fi

  maintainer_relation_exists_result="$(check_repository_maintainer_existence "$_repository_id" "$contact_id")"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$maintainer_relation_exists_result"
    return "$ret"
  fi

  if [[ "$maintainer_relation_exists_result" -eq 0 ]]; then
    local insert_result

    insert_result=$(insert_repository_maintainer "$_repository_id" "$contact_id")
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
      complain "$insert_result"
      return "$ret"
    fi
  fi

  printf '%s\n' "$contact_id"
  return 0
}

function get_maintainers_info()
{
  local _maintainers_infos="$1"
  local -n _maintainers_condition_array="$2"
  local sql_operation_result
  local ret

  sql_operation_result="$(get_database_table_info "$DATABASE_REPO_MAINTAINER_TABLE" "$_maintainers_infos" '_maintainers_condition_array')"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$sql_operation_result"
    return 22 # EINVAL
  fi

  printf '%s\n' "$sql_operation_result"
  return 0
}

function get_repository_maintainers_info()
{
  local _repository_maintainers_infos="$1"
  local -n _repository_maintainers_condition_array="$2"
  local sql_operation_result
  local ret

  sql_operation_result="$(get_database_table_info "$DATABASE_REPO_MAINTAINER_TABLE" "$_repository_maintainers_infos" '_repository_maintainers_condition_array')"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$sql_operation_result"
    return 22 # EINVAL
  fi

  printf '%s\n' "$sql_operation_result"
  return 0
}
