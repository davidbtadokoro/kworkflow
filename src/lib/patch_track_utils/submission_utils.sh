include "${KW_LIB_DIR}/lib/kw_db.sh"

declare -gr DATABASE_SUBMISSION_TABLE='submission'
declare -gr DATABASE_PATCH_SUBMISSION_TABLE='patch_submission'
declare -Ag patch_track_condition_array

# This function performs the physical insertion of a new submission record 
# into the database. It establishes a historical entry for a specific 
# contribution, logging both the parent contribution identifier and the 
# timestamp or versioning context represented by the sender metadata. 
# It interfaces with the persistence layer to record the event and 
# includes error handling to manage schema constraint violations or 
# database execution failures, ensuring that the submission lifecycle 
# is accurately tracked.
#
# @_contribution_id: The unique identifier of the parent contribution.
# @_send_by: Metadata indicating the origin or timestamp of the submission.
#
# Return:
# Returns 0 after a successful database insertion; otherwise, returns 
# the specific error code (2 || 61) if the operation fails due to 
# data or execution errors.
function insert_submission()
{
  local _contribution_id="$1"
  local _send_by="$2"
  local sql_operation_result
  local ret

  sql_operation_result="$(insert_into "$DATABASE_SUBMISSION_TABLE" '("contribution_id", "send_by")' "('${_contribution_id}', '${_send_by}')")"
  ret="$?"

  if [[ "$ret" -eq 2 || "$ret" -eq 61 ]]; then
    complain "$sql_operation_result"
    return "$ret" # EINVAL
  elif [[ "$ret" -ne 0 ]]; then
    complain "($LINENO):" $'Error while trying to insert new submission:\n'"$sql_operation_result"
    return "$ret" # EINVAL
  fi

  return 0
}

# This function orchestrates the creation of a submission event and 
# retrieves its resulting identifier. It functions as a high-level 
# transactional wrapper that first persists a new record in the 
# submissions table—linking it to a parent contribution—and then 
# immediately queries the database to obtain the most recent 
# submission ID for that contribution. This ensures the caller receives 
# the auto-generated primary key necessary for subsequent operations, 
# such as linking patches to this specific submission instance.
#
# @_contribution_id: The unique identifier of the parent contribution.
# @_submission_author: The email or name of the entity submitting the work.
#
# Return:
# Returns 0 and prints the new submission ID on success; returns a 
# non-zero error code if the insertion or ID retrieval fails.
function create_submission()
{
  local _contribution_id="$1"
  local _submission_author="$2"
  local ret
  local patch_existent_result
  local insert_submission_result
  local get_submission_id_result

  insert_submission_result="$(insert_submission "$_contribution_id" "$_submission_author")"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$insert_submission_result"
    return "$ret" # EINVAL
  fi

  get_submission_id_result="$(get_last_submission_infos_by_contribution_id 'id' "$_contribution_id")"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$get_submission_id_result"
    return "$ret" # EINVAL
  fi

  printf '%s\n' "$get_submission_id_result"
  return 0
}

# This function retrieves metadata from the most recent submission 
# associated with a specific contribution. It filters the submission 
# table by the contribution identifier and applies a descending sort 
# on the primary key (ID) to isolate the latest entry. By limiting 
# the result set to a single record, it provides a reliable way to 
# access the current state or latest identifier of a contribution's 
# lifecycle. It handles query execution and returns the requested 
# fields or reports an error if the retrieval fails.
#
# @_submission_infos: A string specifying the columns or data fields 
#                     to be retrieved from the submission table.
# @_contribution_id: The unique identifier of the parent contribution.
#
# Return:
# Returns 0 and prints the requested submission metadata on success; 
# returns a non-zero error code if the database query fails.
function get_last_submission_infos_by_contribution_id()
{
  local _submission_infos="$1"
  local _contribution_id="$2"
  local sql_operation_result
  local ret

  patch_track_condition_array=(['contribution_id']="${_contribution_id}")

  sql_operation_result="$(get_submission_info "$_submission_infos" 'patch_track_condition_array' 'ID DESC' '1')"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$sql_operation_result"
    return "$ret" # EINVAL
  fi

  printf '%s\n' "$sql_operation_result"
  return 0
}

# This function serves as a specialized abstraction layer for retrieving 
# data from the submission table. It maps high-level requests to the 
# underlying database engine, utilizing a condition array for record 
# filtering, and optional parameters for result sorting and pagination 
# (LIMIT). It centralizes error management for submission-specific 
# queries, ensuring that database execution failures are intercepted 
# and reported consistently while returning the requested metadata fields.
#
# @_submission_infos: A string specifying the columns or data fields to 
#                     be retrieved from the submission table.
# @_submission_condition_array: Reference to an associative array 
#                               defining the query's WHERE clause.
# @_order_by: (Optional) SQL clause to define the sort order of the results.
# @_limit: (Optional) Integer value to restrict the number of records returned.
#
# Return:
# Returns 0 and prints the retrieved submission data to the standard 
# output on success; returns a non-zero error code if the database 
# operation fails.
function get_submission_info()
{
  local _submission_infos="$1"
  local -n _submission_condition_array="$2"
  local _order_by="${3:-}"
  local _limit="${4:-}"

  sql_operation_result="$(get_database_table_info "$DATABASE_SUBMISSION_TABLE" "$_submission_infos" '_submission_condition_array' "$_order_by" "$_limit")"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$sql_operation_result"
    return "$ret" # EINVAL
  fi

  printf '%s\n' "$sql_operation_result"
  return 0
}

# This function establishes the formal association between a specific 
# patch and a submission instance, optionally including a message 
# identifier for tracking. It implements an existence check to prevent 
# duplicate entries within the patch-submission join table. If the 
# relationship does not already exist, it triggers the persistence 
# logic to link the entities. It provides detailed error reporting 
# should validation fail, duplicates be detected, or the database 
# insertion encounter an execution error.
#
# @_patch_id: The unique identifier of the patch to be linked.
# @_submission_id: The identifier of the submission instance.
# @_message_id: The mailing list or system message identifier associated 
#               with this specific patch delivery.
#
# Return:
# Returns 0 upon successful verification and insertion; returns 22 or 
# a relevant database error code if the record already exists, 
# parameters are invalid, or the insertion fails.
function create_patch_submission()
{
  local _patch_id="$1"
  local _submission_id="$2"
  local _message_id="$3"

  patch_existent_result="$(check_patch_submission_existence_by_unique_attributes "$_patch_id" "$_submission_id" "$_message_id")"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$patch_existent_result"
    return "$ret" # EINVAL
  fi

  if [[ "$patch_existent_result" -ne 0 ]]; then
    complain "($LINENO): error while trying to create new patch submission for patch-id {$_patch_id} into submission {$_submission_id}"
    return 22 # EINVAL
  fi

  insert_patch_submission_result="$(insert_patch_submission "$_patch_id" "$_submission_id" "$_message_id")"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$insert_patch_submission_result"
    return "$ret" # EINVAL
  fi

  return 0
}

# This function verifies the existence of a specific patch-to-submission 
# association using a composite set of unique attributes: the patch ID, 
# the submission ID, and the message ID. It enforces strict validation 
# to ensure all three identifiers are provided before querying the 
# association table. By interfacing with the lower-level existence 
# utility, it determines if this specific delivery of a patch has 
# already been recorded, providing a safeguard against duplicate 
# relational entries in the tracking system.
#
# @_patch_id: The unique identifier of the patch.
# @_submission_id: The identifier of the submission instance.
# @_message_id: The unique message identifier (e.g., Message-ID header).
#
# Return:
# Returns 0 and prints '1' if the specific association exists, or '0' 
# if it does not; 22 if mandatory parameters are missing; otherwise, 
# returns the specific error code from the database operation.
function check_patch_submission_existence_by_unique_attributes()
{
  local _patch_id="$1"
  local _submission_id="$2"
  local _message_id="$3"

  if [[ -z "$_patch_id" || -z "$_submission_id" || -z "$_message_id" ]]; then
    complain "($LINENO): missing mandatory field(s) for new_patch_submission"
    return 22 # EINVAL
  fi

  patch_track_condition_array=(['patch_id']="${_patch_id}"
    ['submission_id']="${_submission_id}"
    ['message_id']="${_message_id}")

  sql_operation_result="$(check_existence "$DATABASE_PATCH_SUBMISSION_TABLE" 'patch_track_condition_array')"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$sql_operation_result"
    return "$ret" # EINVAL
  fi

  printf '%s\n' "${sql_operation_result}"
  return 0
}

# This function serves as a specialized abstraction layer for retrieving 
# data from the patch-submission association table. It maps high-level 
# requests to the underlying database engine, utilizing a condition 
# array for precise filtering of links between patches and their 
# respective submission instances. It supports optional sorting and 
# record limiting, centralizing error management to ensure that 
# failures in the tracking layer are reported consistently while 
# returning the requested relational metadata.
#
# @_patch_submission_infos: A string specifying the columns or data 
#                           fields to be retrieved.
# @_patch_submission_condition_array: Reference to an associative array 
#                                     defining the query's WHERE clause.
# @_order_by: (Optional) SQL clause to define the sort order of results.
# @_limit: (Optional) Integer value to restrict the result set size.
#
# Return:
# Returns 0 and prints the retrieved association data to the standard 
# output on success; returns a non-zero error code if the database 
# operation fails.
function get_patch_submission_info()
{
  local _patch_submission_infos="$1"
  local -n _patch_submission_condition_array="$2"
  local _order_by="${3:-}"
  local _limit="${4:-}"

  sql_operation_result="$(get_database_table_info "$DATABASE_PATCH_SUBMISSION_TABLE" "$_patch_submission_infos" '_patch_submission_condition_array' "$_order_by" "$_limit")"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$sql_operation_result"
    return "$ret" # EINVAL
  fi

  printf '%s\n' "$sql_operation_result"
  return 0
}

# This function performs the physical insertion of a record into the 
# patch-submission join table, formally linking a patch to a specific 
# submission event. It persists the relationship along with the unique 
# message identifier used during the delivery process. The function 
# operates in a verbose mode to capture detailed transaction logs and 
# includes comprehensive error handling to manage unique constraint 
# violations or database execution failures, ensuring the integrity of 
# the patch tracking history.
#
# @_patch_id: The unique identifier of the patch to be associated.
# @_submission_id: The identifier of the submission instance.
# @_message_id: The unique message identifier (e.g., Message-ID) 
#               linking the patch to its communication source.
#
# Return:
# Returns 0 after a successful database insertion; 22 if the 
# operation fails due to schema violations, data errors, or general 
# database connectivity issues.
function insert_patch_submission()
{
  local _patch_id="$1"
  local _submission_id="$2"
  local _message_id="$3"
  local ret

  sql_operation_result="$(insert_into "$DATABASE_PATCH_SUBMISSION_TABLE" '("patch_id", "submission_id", "message_id")' \
    "('${_patch_id}', '${_submission_id}', '${_message_id}')" '' 'VERBOSE')"
  ret="$?"

  if [[ "$ret" -eq 2 || "$ret" -eq 61 ]]; then
    complain "$sql_operation_result"
    return 22 # EINVAL
  elif [[ "$ret" -ne 0 ]]; then
    complain "($LINENO):" $'Error while trying to insert new patch submission:\n'"${sql_operation_result}"
    return 22 # EINVAL
  fi

  return 0
}
