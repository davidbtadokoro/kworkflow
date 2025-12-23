# This file handles the interactions with the kw database

include "${KW_LIB_DIR}/lib/kwio.sh"
include "${KW_LIB_DIR}/lib/kwlib.sh"

declare -g DB_NAME='kw.db'

# This function reads and executes a SQL script in the database
#
# @sql_path:  Path to SQL script
# @db:        Name of the database file
# @db_folder: Path to the folder that contains @db
#
# Return:
# 0 if succesful; non-zero otherwise
function execute_sql_script()
{
  local sql_path="$1"
  local db="${2:-"$DB_NAME"}"
  local db_folder="${3:-"$KW_DATA_DIR"}"
  local db_path

  db_path="$(join_path "$db_folder" "$db")"

  if [[ ! -f "$sql_path" ]]; then
    complain "Could not find the file: $sql_path"
    return 2
  fi

  [[ -f "$db_path" ]] || warning "Creating database: $db_path"

  sqlite3 -init "$KW_DB_DIR/pre_cmd.sql" "$db_path" < "$sql_path"
}

# This function reads and executes a SQL script in the database
#
# @sql_cmd:   SQL command to be executed on @db
# @db:        Name of the database file
# @db_folder: Path to the folder that contains @db
#
# Return:
# 2 if db doesn't exist;
# 0 if succesful; non-zero otherwise
function execute_command_db()
{
  local sql_cmd="$1"
  local db="${2:-"$DB_NAME"}"
  local db_folder="${3:-"$KW_DATA_DIR"}"
  local db_path

  db_path="$(join_path "$db_folder" "$db")"

  if [[ ! -f "$db_path" ]]; then
    complain 'Database does not exist'
    return 2
  fi

  sqlite3 -init "$KW_DB_DIR/pre_cmd.sql" "$db_path" -bail -batch "$sql_cmd"
}

# This function inserts values into table of given database
#
# @table:     Table to insert data into
# @entries:   Columns on the table where to add the data
# @values:    Rows of data to be added
# @db:        Name of the database file
# @db_folder: Path to the folder that contains @db
#
# Return:
# 2 if db doesn't exist;
# 0 if succesful; non-zero otherwise
function insert_into()
{
  local table="$1"
  local entries="$2"
  local values="$3"
  local db="${4:-"$DB_NAME"}"
  local flag=${5:-'SILENT'}
  local db_folder="${6:-$KW_DATA_DIR}"
  local db_path
  local cmd

  db_path="$(join_path "$db_folder" "$db")"

  if [[ ! -f "$db_path" ]]; then
    complain 'Database does not exist'
    return 2
  fi

  if [[ -z "$table" || -z "$values" ]]; then
    complain 'Empty table or values.'
    return 61 # ENODATA
  fi

  [[ -n "$entries" && ! "$entries" =~ ^\(.*\)$ ]] && entries="($entries)"

  cmd="sqlite3 -init "${KW_DB_DIR}/pre_cmd.sql" \"${db_path}\" -batch \"INSERT INTO ${table} ${entries} VALUES ${values};\""
  cmd_manager "$flag" "$cmd"
}

# This function updates or insert rows into table of given database,
# depending if the rows already exist or not.
#
# @table:     Table to replace/insert data into
# @columns:   Columns on the table where to update/add the data
# @rows:      Rows of data to be added
# @db:        Name of the database file
# @db_folder: Path to the folder that contains @db
#
# Return:
# 2 if db doesn't exist;
# 22 if empty table or empty rows are passed;
# 0 if succesful.
function replace_into()
{
  local table="$1"
  local columns="$2"
  local rows="$3"
  local db="${4:-"$DB_NAME"}"
  local flag=${5:-'SILENT'}
  local db_folder="${6:-"$KW_DATA_DIR"}"
  local db_path
  local cmd

  db_path="$(join_path "$db_folder" "$db")"

  if [[ ! -f "$db_path" ]]; then
    complain 'Database does not exist'
    return 2 # ENOENT
  fi

  if [[ -z "$table" || -z "$rows" ]]; then
    complain 'Empty table or rows.'
    return 61 # ENODATA
  fi

  [[ -n "$columns" && ! "$columns" =~ ^\(.*\)$ ]] && columns="($columns)"

  cmd="sqlite3 -init "${KW_DB_DIR}/pre_cmd.sql" \"${db_path}\" -batch \"REPLACE INTO ${table} ${columns} VALUES ${rows};\""
  cmd_manager "$flag" "$cmd"
}

# This function removes every matching row from a given table.
#
# @table:     Table to replace/insert data into
# @_condition_array: An array reference of condition pairs
#                    <column,value> to match rows
# @db:        Name of the database file
# @db_folder: Path to the folder that contains @db
#
# Return:
# 2 if db doesn't exist;
# 22 if empty table, columns or values are passed;
# 0 if succesful.
function remove_from()
{
  local table="$1"
  local _condition_array="$2"
  local db="${3:-"${DB_NAME}"}"
  local db_folder="${4:-"${KW_DATA_DIR}"}"
  local flag=${5:-'SILENT'}
  local where_clause=''
  local db_path

  db_path="$(join_path "${db_folder}" "$db")"

  if [[ ! -f "${db_path}" ]]; then
    complain 'Database does not exist'
    return 2
  fi

  if [[ -z "$table" || -z "$_condition_array" ]]; then
    complain 'Empty table or condition array.'
    return 61 # ENODATA
  fi

  where_clause="$(generate_where_clause "$_condition_array")"
  query="DELETE FROM ${table} ${where_clause} ;"

  cmd="sqlite3 -init "${KW_DB_DIR}/pre_cmd.sql" \"${db_path}\" -batch \"${query}\""
  cmd_manager "$flag" "$cmd"
}

# This function gets the values in the table of given database
# with the given conditions.
#
# @table:     Table to select info from
# @columns:   Columns of the table to get
# @pre_cmd:   Pre command to execute
# @_condition_array: An array reference of condition pairs. In case there is no
#   WHERE clause, an empty value must be passed
# @order_by:  List of attributes to use for ordering
# @flag:      Flag to control function output
# @db:        Name of the database file
# @db_folder: Path to the folder that contains @db
#
# Return:
# 2 if db doesn't exist; 22 if table is empty
# 0 if succesful; non-zero otherwise
function select_from()
{
  local table="$1"
  local columns="${2:-"*"}"
  local pre_cmd="$3"
  local _condition_array="$4"
  local order_by=${5:-}
  local limit=${6-}
  local flag=${7:-'SILENT'}
  local db="${8:-"$DB_NAME"}"
  local db_folder="${9:-"$KW_DATA_DIR"}"
  local where_clause=''
  local db_path
  local query

  db_path="$(join_path "$db_folder" "$db")"

  if [[ ! -f "$db_path" ]]; then
    complain 'Database does not exist'
    return 2
  fi

  if [[ -z "$table" ]]; then
    complain 'Empty table.'
    return 61 # ENODATA
  fi

  query="SELECT ${columns} FROM ${table} ;"

  if [[ -n "$_condition_array" && ${#_condition_array[@]} -gt 0 ]]; then
    where_clause="$(generate_where_clause "$_condition_array")"
    query="${query::-2} ${where_clause} ;"
  fi

  if [[ -n "${order_by}" ]]; then
    query="${query::-2} ORDER BY ${order_by} ;"
  fi

  if [[ -n "${limit}" ]]; then
    query="${query::-2} LIMIT ${limit} ;"
  fi

  cmd="sqlite3 -init "${KW_DB_DIR}/pre_cmd.sql" -cmd \"${pre_cmd}\" \"${db_path}\" -batch \"${query}\""
  cmd_manager "$flag" "$cmd"
}

# This function updates the set of values in the table of given database
# with the given conditions.
#
# @table: Table to select info from
# @_updates_array: An array reference of updates pairs that will be updated
#   in the db
# @pre_cmd: Pre command to execute
# @_condition_array: An array reference of condition pairs specifing the data
#   that will be updated
# @flag: Flag to control function output
# @db: Name of the database file
# @db_folder: Path to the folder that contains @db
#
# Return:
# 2 if db doesn't exist; 22 if table is empty
# 0 if succesful; non-zero otherwise
function update_into()
{
  local table="$1"
  local _updates_array="$2"
  local pre_cmd="$3"
  local _condition_array="$4"
  local flag=${5:-'SILENT'}
  local db="${6:-"$DB_NAME"}"
  local db_folder="${7:-"$KW_DATA_DIR"}"
  local where_clause=''
  local db_path
  local query

  db_path="$(join_path "$db_folder" "$db")"

  if [[ ! -f "$db_path" ]]; then
    complain 'Database does not exist'
    return 2
  fi

  if [[ -z "$table" ]]; then
    complain 'Empty table.'
    return 22 # EINVAL
  fi

  if [[ -z "$_condition_array" || -z "$_updates_array" ]]; then
    complain 'Empty condition or updates array.'
    return 61 # ENODATA
  fi

  where_clause="$(generate_where_clause "$_condition_array")"
  set_clause="$(generate_set_clause "$_updates_array")"

  query="UPDATE ${table} SET ${set_clause} ${where_clause} ;"

  cmd="sqlite3 -init "${KW_DB_DIR}/pre_cmd.sql" -cmd \"${pre_cmd}\" \"${db_path}\" -batch \"${query}\""
  cmd_manager "$flag" "$cmd"
}

# This function receives a condition_array and then generate
# the infos that will be used by the WHERE clause to specify
# the data we want.
#
# @condition_array_ref: The condition array reference containing the conditions
#
# Returns:
# A string containing the generated clause
function generate_where_clause()
{
  local -n condition_array_ref="$1"
  local clause
  local relational_op='='
  local attribute
  local where_clause="WHERE "
  local value

  for clause in "${!condition_array_ref[@]}"; do
    attribute="$(cut --delimiter=',' --fields=1 <<< "$clause")"
    value="${condition_array_ref["${clause}"]}"

    if [[ "$clause" =~ ',' ]]; then
      relational_op=$(cut --delimiter=',' --fields=2 <<< "$clause")
    fi

    where_clause+="${attribute}${relational_op}'${value}'"
    where_clause+=' AND '
  done

  printf '%s' "${where_clause::-5}" # Remove trailing ' AND '
}

# This function receives a updates_array and then generates the infos that
# will be used by the SET clause to update the data fields we want.
#
# @updates_array_ref: The updates array reference containing the conditions updates
#
# Returns:
# A string containing the generated clause
function generate_set_clause()
{
  local -n updates_array_ref="$1"
  local attribute
  local set_clause
  local value

  for attribute in "${!updates_array_ref[@]}"; do
    value="${updates_array_ref["${attribute}"]}"
    set_clause+="${attribute} = '${value}'"
    set_clause+=', '
  done

  printf '%s' "${set_clause::-2}" # Remove trailing ', '
}

# This function takes arguments and assembles them into the correct format to
# be used as values in SQL commands. For example, if we want to format two sets
# of three values - the first set being 'a1', 'a2', and 'a3' and the second being
# 'b1', 'b2', and 'b3' - the correct format to be used is
# ('a1','a2','a3'),('b1','b2','b3')
#
# @length: Number of arguments per group
# @@:      Values to be formatted
#
# Return:
# The arguments in formatted string to be used as values in an INSERT command
# 22 if no arguments are given
function format_values_db()
{
  local length="$1"
  shift
  local values=''
  local val
  local count=0

  if [[ "$#" == 0 ]]; then
    complain 'No arguments given'
    return 22
  fi

  for val in "$@"; do
    [[ "$count" -eq 0 ]] && values+='('
    # check if not a sqlite function nor NULL
    if [[ ! "$val" =~ ^[[:alnum:]_]+\(.*\)$ && "$val" != 'NULL' ]]; then
      val="'${val//\'/\'\'}'" # escapes single quotes and enclose
    fi
    values+="$val"
    ((count++))
    if [[ "$count" -eq "$length" ]]; then
      values+=')'
      count=0
    fi
    values+=','
  done

  printf '%s\n' "${values%?}" # removes last comma
}

function get_database_table_info()
{
  local _database_table_name="$1"
  local _entity_infos="$2"
  local -n _table_info_condition_array="$3"
  local _order_by="${4:-}"
  local _limit="${5:-}"

  sql_operation_result="$(select_from "$_database_table_name" "$_entity_infos" '' '_table_info_condition_array' "$_order_by" "$_limit")"
  ret="$?"

  if [[ "$ret" -eq 2 || "$ret" -eq 61 ]]; then
    complain "$sql_operation_result"
    return "$ret" # EINVAL
  elif [[ "$ret" -ne 0 ]]; then
    complain "($LINENO): Error while trying to get ${_database_table_name} info from the database with the command:"$'\n'"${sql_operation_result}"
    return "$ret" # EINVAL
  fi

  printf '%s\n' "$sql_operation_result"
  return 0
}

function check_existence()
{
  local _database_table_name="$1"
  local -n _check_existence_condition_array="$2"
  local sql_operation_result
  local ret

  sql_operation_result="$(get_database_table_info "$_database_table_name" 'COUNT(*)' '_check_existence_condition_array')"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$sql_operation_result"
    return "$ret" # EINVAL
  fi

  if [[ -z "$sql_operation_result" ]]; then
    complain "Error while trying to check entity existence in ${_database_table_name}"
    return "$ret" # EINVAL
  fi

  if [[ "$sql_operation_result" -eq 0 ]]; then
    printf '%s\n' 0
  else
    printf '%s\n' 1
  fi

  return 0
}
