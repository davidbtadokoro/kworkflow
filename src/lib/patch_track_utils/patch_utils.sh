include "${KW_LIB_DIR}/lib/kw_db.sh"

declare -gr DATABASE_PATCH_TABLE='patch'
declare -Ag condition_array

# This function performs the physical insertion of a new patch record into 
# the database. It enforces strict validation of all mandatory fields, 
# including the title, author email, parent contribution ID, and commit 
# hash. Once validated, it constructs the SQL insertion statement and 
# manages the transaction through a database wrapper. It includes robust 
# error handling to catch and report schema violations, empty datasets, 
# or general execution failures during the persistence process.
#
# @_patch_title: The title or subject of the patch.
# @_patch_author: The email address of the patch author.
# @_contribution_id: Identifier of the contribution to which the patch belongs.
# @_commit_hash: The unique Git commit hash associated with the patch.
#
# Return:
# Returns 0 after a successful database insertion; 22 if mandatory 
# parameters are missing or if the database operation fails.
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

# This function implements an idempotent logic to ensure a patch record 
# exists in the database. It first validates mandatory fields and checks 
# for the existence of the patch using its unique attributes—including 
# the title, author, and commit hash. If no matching record is found, 
# it triggers the insertion of a new entry. Finally, it retrieves and 
# returns the primary identifier of the record, regardless of whether 
# it was newly created or previously stored. It manages errors for 
# missing fields, failed existence checks, and database persistence issues.
#
# @_patch_title: The title or subject of the patch.
# @_patch_author: The email address of the patch author.
# @_contribution_id: Identifier of the contribution to link the patch to.
# @_commit_hash: The unique Git commit hash for reliable identification.
#
# Return:
# Returns 0 after printing the patch ID to the standard output; 
# otherwise, returns the non-zero error code from the failed 
# validation or database operation.
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

# This function retrieves specific metadata from a patch record using its 
# primary database identifier. It validates that the provided ID is 
# not empty before performing a lookup through the patch information 
# module. The function handles error reporting for invalid identifiers 
# or database execution failures and explicitly manages cases where 
# the ID does not correspond to any existing entry in the persistent 
# storage.
#
# @_patch_infos: The specific columns or data attributes to be retrieved.
# @_patch_id: The unique primary key identifier of the patch.
#
# Return:
# Returns 0 if the patch record is found and the data is successfully 
# printed; 22 if the patch ID is empty or the query fails; 61 if no 
# record matches the provided identifier.
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

# This function retrieves specific patch data using a unique Git commit 
# hash as the primary search criterion. It serves as a specialized 
# lookup utility that validates the presence of the hash before 
# querying the database through the patch information module. It 
# handles errors for empty input strings and manages cases where 
# no corresponding record exists for the provided hash, ensuring 
# data integrity during the retrieval process.
#
# @_patch_infos: The specific columns or metadata fields to be retrieved.
# @_commit_hash: The unique commit hash identifying the target patch.
#
# Return:
# Returns 0 if the patch information is successfully found and printed; 
# 22 if the commit hash is empty or the query fails; 61 if no record 
# matches the provided hash.
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

# This function acts as a specialized wrapper to retrieve information from 
# the patches table in the database. It utilizes a provided condition 
# array to filter records and returns the requested data fields. It 
# centralizes error handling for patch-specific queries, ensuring that 
# any database operation failures are reported to the user.
#
# @_patch_infos: A string specifying the columns or attributes to retrieve.
# @_patch_condition_array: Reference to an associative array containing 
#                          the key-value pairs for the SQL WHERE clause.
#
# Return:
# Returns 0 after printing the requested patch data to the standard output; 
# otherwise, returns the non-zero error code from the database operation.
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

# This function verifies whether a specific patch already exists in the 
# database by checking a set of unique identifying attributes. It 
# validates the patch title, author email, and contribution ID against 
# the local storage. A critical safety check ensures that a commit hash 
# is present before proceeding, as identification without a hash is 
# considered unreliable. It handles error reporting for missing 
# parameters and processes the boolean result of the existence check.
#
# @_patch_title: The subject or title of the patch to verify.
# @_patch_author: The email address of the patch author.
# @_contribution_id: Identifier of the parent contribution.
# @_commit_hash: The unique commit hash required for reliable identification.
#
# Return:
# Returns 0 if the check is performed successfully (printing 1 for 
# existence and 0 for non-existence); 22 if mandatory parameters are 
# missing; 61 if the query returns a null result.
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

# This function retrieves specific patch information from the database by 
# validating a set of unique attributes, including the title, author email, 
# contribution identifier, and commit hash. It implements a safety check 
# to ensure that commit hashes are present before attempting a match, 
# preventing false positives in the identification process. It handles 
# errors related to missing mandatory attributes and manages scenarios 
# where no matching records are found in the persistent storage.
#
# @_patch_infos: The specific columns or data fields to be retrieved.
# @_patch_title: The title of the patch used as a search criterion.
# @_patch_author: The email address of the patch author.
# @_contribution_id: Identifier of the contribution the patch belongs to.
# @_commit_hash: The unique Git commit hash associated with the patch.
#
# Return:
# Returns 0 if the query is successful and a record is found; 22 if 
# mandatory arguments are missing or the query fails; 61 if no 
# matching data is found.
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

# This function normalizes a date string from the RFC 2822 format—commonly 
# found in patch headers—into a standardized YYYY-MM-DD HH:MM:SS format. 
# This conversion ensures compatibility with DATETIME and TIMESTAMP 
# schema requirements in most database systems. It handles the 
# transformation of raw date metadata into a structured, sortable, 
# and persistent string representation.
#
# @date_string: The raw date string (e.g., "Wed, 8 Oct 2025 00:37:32 -0300").
#
# Return:
# Returns 0 after printing the formatted date string to the standard output.
formatar_data_patch()
{
  local date_string="$1"
  local formatted_date

  if [ -z "$date_string" ]; then
    echo "Erro: Nenhuma string de data fornecida." >&2
    return 1
  fi

  formatted_date=$(date -d "$date_string" +"%Y-%m-%d %H:%M:%S")

  if [ "$?" -ne 0 ]; then
    echo "Erro: Falha ao processar a string de data: '$date_string'" >&2
    return 1
  fi

  printf '%s' "$formatted_date"
  return 0
}
