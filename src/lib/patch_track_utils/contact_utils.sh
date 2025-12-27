include "${KW_LIB_DIR}/lib/kw_db.sh"

declare -Ag condition_array
declare -gr DATABASE_EMAIL_CONTACT_TABLE='email_contact'

# This function persists a new email contact into the database. It enforces 
# the presence of both a contact name and an email address as mandatory 
# fields before proceeding with the insertion. It constructs the SQL 
# command dynamically and interfaces with the database management layer, 
# providing robust error handling to intercept and report schema 
# violations, data inconsistencies, or connectivity issues.
#
# @_contact_name: The display name of the contact.
# @_contact_email: The unique email address of the contact.
#
# Return:
# Returns 0 after a successful database insertion; 22 if mandatory 
# parameters are missing or if the database operation fails.
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

# This function verifies the existence of an email contact within the 
# database using the email address as a unique identifier. It enforces 
# a validation check to ensure the email string is not empty before 
# querying the persistent storage. By interfacing with the lower-level 
# existence utility, it provides a boolean result that indicates 
# whether the contact is already registered, while handling potential 
# database communication errors or null responses.
#
# @_contact_email: The unique email address to search for in the contact table.
#
# Return:
# Returns 0 and prints '1' if the contact exists, or '0' if it does not; 
# 22 if the email parameter is missing or the query fails; 61 if the 
# database returns an unexpected null result.
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

# This function serves as a specialized abstraction layer for retrieving 
# data from the email contact table. It maps high-level requests to the 
# underlying database engine, utilizing a condition array for filtering 
# specific records. It centralizes error management for contact queries, 
# ensuring that database failures are intercepted and reported 
# consistently to the caller while returning the requested metadata fields.
#
# @_contact_infos: A string specifying the columns or data fields to 
#                  be retrieved from the contact table.
# @_contact_info_condition_array: Reference to an associative array 
#                                 defining the query's WHERE clause.
#
# Return:
# Returns 0 and prints the retrieved contact data to the standard output 
# on success; 22 if the database operation fails.
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

# This function retrieves specific metadata from an email contact record 
# using the email address as a unique search key. It validates that the 
# email parameter is not empty before performing a lookup through the 
# contact information module. The function handles error reporting for 
# invalid identifiers and ensures that database execution failures are 
# intercepted, returning the requested fields in a standardized format.
#
# @_contact_infos: A string specifying the columns or data fields to 
#                  be retrieved from the database.
# @_contact_email: The unique email address used to identify the contact.
#
# Return:
# Returns 0 if the query is executed successfully and data is printed; 
# 22 if the email parameter is missing; otherwise, returns the 
# specific error code from the database operation.
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

# This function implements an idempotent workflow to manage email contact 
# records. it first validates that both the name and email are provided, 
# then checks for the record's existence based on the unique email 
# address. If the contact does not exist, it triggers a new insertion 
# into the database. Finally, it retrieves and returns the primary 
# identifier (ID) of the contact. This ensures that the caller always 
# receives a valid reference ID while preventing duplicate entries.
#
# @_contact_name: The display name of the contact to be ensured.
# @_contact_email: The unique email address used for identification.
#
# Return:
# Returns 0 and prints the contact ID on success; returns a non-zero 
# error code (e.g., 22) if validation fails or a database operation 
# encounters an error.
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
