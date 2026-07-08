include "${KW_LIB_DIR}/lib/kw_db.sh"

declare -gr DATABASE_CONTRIBUTION_TABLE='contribution'
declare -gA condition_array
declare -gA updates_array

# This function handles the creation of a new contribution record within 
# the database. It validates mandatory fields such as the title and 
# author email before initiating the persistence process. The function 
# features dynamic SQL construction to optionally include a repository 
# identifier if provided. It manages database transactions through a 
# specialized wrapper and provides detailed error reporting for missing 
# arguments, schema constraints, or execution failures.
#
# @_contribution_title: The descriptive title of the contribution.
# @_author_email: The email address of the individual submitting the work.
# @_repository_id: (Optional) The identifier of the associated repository.
#
# Return:
# Returns 0 after a successful database insertion; 22 if mandatory 
# parameters are missing or if the database operation fails.
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

# This function implements an idempotent workflow to ensure a contribution 
# record exists in the database. It validates mandatory fields and 
# performs an existence check based on unique attributes—specifically 
# the contribution title and author email. If no matching record is 
# found, it triggers the insertion of a new entry, optionally linking 
# it to a repository. Finally, it retrieves and returns the primary 
# identifier of the contribution. It provides robust error handling 
# for missing arguments, failed lookups, or persistence errors.
#
# @_contribution_title: The descriptive title of the contribution.
# @_author_email: The email address of the contribution author.
# @_repository_id: (Optional) The identifier of the associated repository.
#
# Return:
# Returns 0 after printing the contribution ID to the standard output; 
# otherwise, returns the specific error code (22 or 61) encountered 
# during validation or database interaction.
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

# This function determines if a contribution record exists in the database 
# by evaluating its unique identifying attributes: the title and the 
# author's email. It enforces a strict validation check to ensure neither 
# attribute is empty before proceeding with the query. The function 
# interfaces with a low-level existence checker and manages various 
# failure modes, including database connectivity issues or unexpected 
# null results, returning a boolean-style output to indicate the 
# record's presence.
#
# @_contribution_title: The specific title of the contribution to check.
# @_author_email: The email address associated with the contribution.
#
# Return:
# Returns 0 and prints '1' if the contribution exists, or '0' if it 
# does not; 22 if mandatory parameters are missing; 61 if the 
# database query returns an invalid or null result.
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

# This function retrieves specific contribution metadata from the database 
# using a combination of unique identifying attributes: the contribution 
# title and the author's email. It validates the presence of these 
# mandatory fields before constructing a filtered query. The function 
# centralizes the retrieval logic for contribution records and handles 
# potential database errors, ensuring that the requested information 
# is returned in a format suitable for further processing.
#
# @_contribution_infos: A string specifying the columns or data fields 
#                       to be retrieved from the database.
# @_contribution_title: The specific title of the contribution to match.
# @_author_email: The author's email address associated with the record.
#
# Return:
# Returns 0 if the query is executed successfully and data is printed; 
# 22 if mandatory parameters are missing; otherwise, returns the 
# non-zero error code from the database operation.
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

# This function serves as a specialized abstraction layer for retrieving 
# data from the contributions table. It maps high-level requests to 
# the underlying database engine, utilizing a condition array for 
# filtering and an optional parameter for result sorting. It centralizes 
# error management for contribution queries, ensuring that database 
# failures are intercepted and reported consistently to the caller.
#
# @_contribution_infos: A string specifying the columns or data fields 
#                       to be retrieved.
# @_contrib_info_condition_array: Reference to an associative array 
#                                 defining the query's WHERE clause.
# @_order_by: (Optional) SQL clause to define the sort order of the results.
#
# Return:
# Returns 0 and prints the retrieved data to the standard output on success; 
# 22 if the database operation fails.
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

# This function updates the repository association for a specific 
# contribution record. It maps a contribution identifier to a 
# repository identifier within the persistent storage, ensuring 
# the relational link is established. It utilizes an update wrapper 
# to modify the database state and provides error handling to 
# manage failures in the persistence layer, ensuring that invalid 
# operations are reported to the caller.
#
# @contribution_id: The unique identifier of the contribution to be updated.
# @repository_id: The unique identifier of the repository to be linked.
#
# Return:
# Returns 0 upon a successful database update; 22 if the operation 
# fails due to a database error.
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
