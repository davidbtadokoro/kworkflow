include "${KW_LIB_DIR}/lib/kwlib.sh"
include "${KW_LIB_DIR}/lib/kw_string.sh"

declare -gr DATABASE_PATCH_TABLE='patch'

declare -gA options_values
declare -gA condition_array
declare -gA updates_array

function patch_track_main()
{
  local flag

  flag=${flag:-'SILENT'}

  if [[ -z "$*" ]]; then
    complain 'Please, provide an argument'
    patch_track_help "$@"
    exit 22 # EINVAL
  fi

  parse_patch_track "$@"
  if [[ "$?" -gt 0 ]]; then
    complain "${options_values['ERROR']}"
    patch_track_help "$@"
    exit 22 # EINVAL
  fi

  if [[ -n "${options_values['DASHBOARD']}" ]]; then
    show_patches_dashboard "${options_values['FROM']}" "${options_values['BEFORE']}" "${options_values['AFTER']}" "$flag"
    return 0
  fi

  if [[ -n "${options_values['SET_STATUS']}" ]]; then
    if [[ -z "${options_values['PATCH_ID']}" ]]; then
      complain 'Patch id not specified with `--id <num>`'
      return 22 # EINVAL
    fi

    set_patch_status "${options_values['PATCH_ID']}" "${options_values['STATUS']}" "$flag"
    if [[ "$?" -eq 0 ]]; then
      echo "Patch status updated successfully."
    fi
    return 0
  fi

  return 0
}

# This function inserts each patch subject into the database and handles
# errors related to empty subjects or database insertion failures.
#
# @patches_subjects: Array of patch subjects to be registered.
#
# Return:
# Returns 0 if successful; 22 if there is an invalid argument or
# an error during insertion.
function register_patch_track()
{
  local -n _patches_subjects="$1"
  local sql_operation_result
  local ret

  for patch_subject in "${_patches_subjects[@]}"; do
    if [[ -z "$patch_subject" ]]; then
      complain 'Patch subject is empty'
      return 61 # ENODATA
    fi

    sql_operation_result=$(insert_into "$DATABASE_PATCH_TABLE" '("title")' "('${patch_subject}')" '' 'VERBOSE')
    ret="$?"

    if [[ "$ret" -eq 2 || "$ret" -eq 61 ]]; then
      complain "$sql_operation_result"
      return 22 # EINVAL
    elif [[ "$ret" -ne 0 ]]; then
      complain "($LINENO):" $'Error while trying to insert patch into the database with the command:\n'"${sql_operation_result}"
      return 22 # EINVAL
    fi
  done

  success "Patch registered successfully."
}

# This function displays the patches dashboard based on provided filters.
# It fetches patches from the database according to the conditions
# and prints them in a formatted table.
#
# @flag: Display mode flag (e.g., SILENT).
#
# Return:
# No specific return value.
function show_patches_dashboard()
{
  local flag="$1"
  local columns="$2"
  local from="${options_values['FROM']}"
  local before="${options_values['BEFORE']}"
  local after="${options_values['AFTER']}"
  local patches_info
  declare -a patches_array

  if [[ -n "$from" ]]; then
    condition_array=(['date,=']="${from}")
  else
    if [[ -n "$before" ]]; then
      condition_array=(['date,<=']="${before}")
    fi
    if [[ -n "$after" ]]; then
      condition_array=(['date,>=']="${after}")
    fi
  fi

  patches_info=$(select_from "$DATABASE_PATCH_TABLE" '' '' 'condition_array')
  readarray -t patches_array <<< "$patches_info"

  print_patches_dashboard 'patches_array' "$columns"
}

# Displays the patches dashboard based on provided filters. It
# fetches patches from the database according to the conditions
# and prints them in a formatted table.
#
# @_patches_array: an array formatted as: [index]=[id|date|time|status]
# for each of the patches that will be displayed.
# Return:
# No specific return value.
function print_patches_dashboard()
{
  local -n _patches_array="$1"
  local columns="$2"
  local id
  local date
  local time
  local status
  local title
  local id_width=6
  local date_width=12
  local time_width=10
  local status_width=10
  local title_width=$(("$columns" - id_width - date_width - time_width - status_width - 6))

  if [[ -z $columns ]]; then
    columns="$(tput cols)"
  fi

  printf "%-${id_width}s|%-${date_width}s|%-${time_width}s|%-${status_width}s|%s\n" "ID" "Date" "Time" "Status" "Title"
  printf "%-${columns}s\n" | tr ' ' '-'

  # Print rows
  for patch in "${!_patches_array[@]}"; do
    IFS='|' read -r id date time status title <<< "${_patches_array[$patch]}"
    printf "%-${id_width}s|%-${date_width}s|%-${time_width}s|%-${status_width}s|%s\n" "$id" "$date" "$time" "$status" "$title"
  done

  tput cnorm > /dev/tty
  printf "%-${columns}s\n" | tr ' ' '-'
}

# This sets the status of a specified patch. It updates the status
# of a patch identified by its ID and handles errors related to
# empty IDs or statuses, as well as database update failures.
#
# @patch_id: ID of the patch to be updated.
# @patch_new_status: New status to be set for the patch.
#
# Return:
# Returns 0 if successful; 22 if there is an invalid argument or
# an error during the update.
function set_patch_status()
{
  local patch_id="$1"
  local patch_new_status="$2"
  local formatted_status
  local sql_operation_result
  local ret

  if [[ -z "$patch_id" ]]; then
    complain 'Patch ID is empty'
    return 61 # ENODATA
  fi

  if [[ -z "$patch_new_status" ]]; then
    complain 'New status is empty'
    return 61 # ENODATA
  fi

  formatted_status=$(check_valid_status "$patch_new_status")

  if [[ "$?" -ne 0 ]]; then
    formatted_status=$(get_patch_status)
  fi

  condition_array=(['id']="${patch_id}")
  updates_array=(['status']="${formatted_status}")

  sql_operation_result=$(update_into "$DATABASE_PATCH_TABLE" 'updates_array' '' 'condition_array' 'VERBOSE')
  ret="$?"

  if [[ "$ret" -eq 2 || "$ret" -eq 61 ]]; then
    complain "$sql_operation_result"
    return 22 # EINVAL
  elif [[ "$ret" -ne 0 ]]; then
    complain "($LINENO):" $'Error while trying to update patch status in the database with the command:\n'"${sql_operation_result}"
    return 22 # EINVAL
  fi

  return 0
}

# This function prompts the user for the current patch status and validates
# it. It returns the validated status or prompts again if the status
# is invalid.
#
# Return:
# Returns the formatted status.
function get_patch_status()
{
  local status
  local formatted_status
  local message=$'Enter your current patch status'
  local default_status=$'[Sent - S], [Reviewed - RW], [Approved - A], [Rejected - R], [Merged - M]'

  status=$(ask_with_default "$message" "$default_status")
  formatted_status=$(check_valid_status "$status")

  if [[ "$?" -ne 0 ]]; then
    formatted_status=$(get_patch_status)
  fi

  printf '%s' "$formatted_status"
}

# This function checks if the provided status is valid and returns
# the corresponding formatted status.
#
# @status: The status to be validated.
#
# Return:
# Returns 0 if valid; non-zero otherwise.
function check_valid_status()
{
  local status="$1"

  if [[ -z "$status" ]]; then
    return 61 # ENODATA
  elif [[ "$status" =~ ^([sS][eE][nN][tT]|[sS])+$ ]]; then
    printf '%s' 'SENT'
  elif [[ "$status" =~ ^([aA][pP][pP][rR][oO][vV][eE][dD]|[aA])+$ ]]; then
    printf '%s' 'APPROVED'
  elif [[ "$status" =~ ^([rR][eE][jJ][eE][cC][tT][eE][dD]|[rR])+$ ]]; then
    printf '%s' 'REJECTED'
  elif [[ "$status" =~ ^([mM][eE][rR][gG][eE][dD]|[mM])+$ ]]; then
    printf '%s' 'MERGED'
  elif [[ "$status" =~ ^([rR][eE][vV][iI][eE][wW][eE][dD]|[rR][wW])+$ ]]; then
    printf '%s' 'REVIEWED'
  else
    return 22 # EINVAL
  fi

  return 0
}

# Parses the command-line arguments for the patch track operation.
# It populates the options_values associative array with parsed options.
#
# Return:
# Returns 22 if there are invalid arguments.
function parse_patch_track()
{
  local long_options='help,dashboard,from:,before:,after:,id:,set-status:'
  local short_options='d,f:,b:,a:,s:'
  local options
  local option

  options="$(kw_parse "$short_options" "$long_options" "$@")"

  if [[ "$?" != 0 ]]; then
    options_values['ERROR']="$(kw_parse_get_errors 'kw patch_track' "$short_options" \
      "$long_options" "$@")"
    return 22 # EINVAL
  fi

  eval "set -- ${options}"

  # Default values
  options_values['DASHBOARD']=''
  options_values['PATCH_ID']=''
  options_values['SET_STATUS']=
  options_values['STATUS']=''
  options_values['FROM']=''
  options_values['BEFORE']=''
  options_values['AFTER']=''

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --dashboard | -d)
        options_values['DASHBOARD']=1
        shift
        ;;
      --id)
        options_values['PATCH_ID']="$2"
        shift 2
        ;;
      --set-status | -s)
        option="$(str_strip "${2}")"
        options_values['SET_STATUS']=1
        options_values['STATUS']="$option"
        shift 2
        ;;
      --from | -f)
        options_values['FROM']="$2"
        shift 2
        ;;
      --before | -b)
        options_values['BEFORE']="$2"
        shift 2
        ;;
      --after | -a)
        options_values['AFTER']="$2"
        shift 2
        ;;
      --help | -h)
        patch_track_help "$1"
        exit
        ;;
      *)
        shift
        ;;
    esac
  done
}

# Displays help information for the patch track command.
# It prints usage instructions and available options.
# Return:
# Returns nothing
function patch_track_help()
{
  if [[ "$1" == --help ]]; then
    include "$KW_LIB_DIR/help.sh"
    kworkflow_man 'patch-track'
    return
  fi

  printf '%s\n' 'kw patch-track:' \
    '  patch-track (-d|--dashboard) [[--from <YYYY-MM-DD>] | [--after <YYYY-MM-DD>] [--before <YYYY-MM-DD>]] - Show patches dashboard in chronological order ' \
    '  patch-track (--id <num>) [-s[=<status>]| --set-status[=<status>]] - Set the patch status '
}
