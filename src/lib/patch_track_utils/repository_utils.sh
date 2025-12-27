include "${KW_LIB_DIR}/lib/kw_db.sh"
include "${KW_LIB_DIR}/lib/patch_track_utils/contact_utils.sh"

declare -gr DATABASE_REPOSITORY_TABLE='repository'
declare -gr DATABASE_REPO_MAINTAINER_TABLE='repository_maintainer'
declare -Ag condition_array

# This function handles the physical insertion of a new repository record 
# into the database. It enforces mandatory validation for the repository 
# name and its origin URL before constructing the SQL command. It 
# interfaces with the low-level database wrapper to persist the data 
# and includes specific error handling to manage schema violations, 
# empty results, or general execution failures, ensuring that the 
# repository's identity and location are correctly recorded.
#
# @_repository_name: The descriptive name of the repository.
# @_origin_url: The source URL (e.g., Git remote URL) of the repository.
#
# Return:
# Returns 0 after a successful database insertion; 22 if mandatory 
# parameters are missing or if the database operation fails.
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

# This function verifies the existence of a repository in the database 
# by using its origin URL as a unique identifier. It ensures that the 
# URL parameter is not empty before querying the persistent storage 
# through the existence utility. It handles error reporting for 
# database communication failures and provides a boolean output 
# indicating whether the repository record is already registered, 
# preventing the creation of duplicate entries.
#
# @_origin_url: The unique source URL (e.g., Git origin) used to identify 
#               the repository.
#
# Return:
# Returns 0 and prints '1' if the repository exists, or '0' if it does 
# not; 22 if the URL parameter is missing; 61 if the query returns an 
# unexpected null result.
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

# This function serves as a specialized abstraction layer for retrieving 
# data from the repository table. It maps high-level requests to the 
# underlying database engine, utilizing a condition array for filtering 
# specific records based on defined criteria. It centralizes error 
# management for repository-specific queries, ensuring that database 
# failures are intercepted and reported consistently to the caller 
# while returning the requested metadata fields.
#
# @_repository_infos: A string specifying the columns or data fields to 
#                     be retrieved from the repository table.
# @_repo_info_condition_array: Reference to an associative array 
#                              defining the query's WHERE clause.
#
# Return:
# Returns 0 and prints the retrieved repository data to the standard 
# output on success; 22 if the database operation fails.
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

# This function retrieves specific repository metadata using the origin 
# URL as the unique search criterion. It validates that the URL 
# parameter is not empty before executing a lookup through the 
# repository information module. The function serves as a targeted 
# retrieval utility, handling error reporting for missing identifiers 
# and ensuring that database execution failures or missing records 
# are managed appropriately during the data fetching process.
#
# @_repository_infos: A string specifying the columns or data fields to 
#                     be retrieved from the database.
# @_origin_url: The unique source URL used to identify the target repository.
#
# Return:
# Returns 0 if the repository record is found and data is printed; 
# 22 if the origin URL is empty; otherwise, returns the specific 
# error code from the database operation.
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

# This function implements an idempotent workflow to ensure a repository 
# record exists in the persistent storage. It validates that both the 
# repository name and origin URL are provided, then performs an 
# existence check based on the unique URL. If no matching record is 
# found, it triggers the creation of a new repository entry. Finally, 
# it retrieves and returns the primary identifier (ID) of the record. 
# This logic prevents duplicate repository entries while ensuring the 
# caller receives a valid reference for relational linking.
#
# @_repository_name: The descriptive name of the repository.
# @_origin_url: The unique source URL used for identification and persistence.
#
# Return:
# Returns 0 and prints the repository ID on success; returns a non-zero 
# error code (e.g., 22) if validation fails or a database operation 
# encounters an error.
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

# This function establishes a relational link between a repository and 
# an email contact in the database, designating the contact as a 
# maintainer. It enforces mandatory validation for both the repository 
# and contact identifiers before executing the insertion. By 
# interfacing with a join-table structure, it persists the many-to-many 
# relationship and provides detailed error handling for schema 
# constraint violations or database execution failures.
#
# @_repository_id: The unique identifier of the target repository.
# @_contact_id: The unique identifier of the email contact to be linked.
#
# Return:
# Returns 0 after a successful database insertion; 22 if mandatory 
# parameters are missing or if the database operation fails.
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

# This function verifies whether a specific maintenance relationship exists 
# between a repository and a contact within the join table. It validates 
# that both the repository and contact identifiers are provided before 
# querying the persistent storage. By evaluating the composite link 
# through the existence utility, it provides a boolean result that 
# confirms if the association is already registered, effectively 
# preventing the creation of duplicate maintainer assignments.
#
# @_repository_id: The unique identifier of the repository to check.
# @_contact_id: The unique identifier of the email contact to check.
#
# Return:
# Returns 0 and prints '1' if the association exists, or '0' if it does 
# not; 22 if mandatory parameters are missing; 61 if the database 
# returns an unexpected null result.
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

# This function ensures that a specific contact is registered and linked as 
# a maintainer to a repository, implementing an idempotent multi-step 
# workflow. It first secures a valid contact identifier by calling the 
# contact management module. It then verifies if a relationship already 
# exists between the repository and that contact in the association table. 
# If no link is found, it persists the new maintainer-repository 
# relationship. It manages data dependencies across different tables 
# and provides comprehensive error handling for missing arguments or 
# database failures at any stage of the process.
#
# @_repository_id: The identifier of the repository to link.
# @_maintainer_name: The display name of the maintainer.
# @_maintainer_email: The unique email address of the maintainer.
#
# Return:
# Returns 0 and prints the contact ID on success; returns a non-zero 
# error code if validation fails, contact creation fails, or the 
# relationship cannot be persisted.
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

# This function serves as a specialized abstraction layer for retrieving 
# data from the repository maintainer join table. It maps high-level 
# requests to the underlying database engine, utilizing a condition 
# array to filter records based on specific repository or contact 
# identifiers. It centralizes error management for maintenance-relation 
# queries, ensuring that database execution failures are intercepted and 
# reported consistently while returning the requested metadata fields.
#
# @_maintainers_infos: A string specifying the columns or data fields to 
#                      be retrieved from the join table.
# @_maintainers_condition_array: Reference to an associative array 
#                                defining the query's WHERE clause.
#
# Return:
# Returns 0 and prints the retrieved association data to the standard 
# output on success; 22 if the database operation fails.
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

# This function acts as a specialized query interface for the repository 
# maintainer association table. It abstracts the underlying database 
# retrieval logic, using a passed condition array to filter specific 
# maintenance relationships. It serves as a dedicated wrapper that 
# ensures consistent error handling and standardizes the output format 
# for metadata requests involving the link between repositories and 
# their assigned contacts.
#
# @_repository_maintainers_infos: A string defining the specific columns 
#                                 or fields to extract from the table.
# @_repository_maintainers_condition_array: Reference to an associative 
#                                           array used to filter the 
#                                           query results (WHERE clause).
#
# Return:
# Returns 0 and prints the resulting dataset to standard output on 
# success; 22 if the database retrieval fails.
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
