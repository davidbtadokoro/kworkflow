include "${KW_LIB_DIR}/lib/kwlib.sh"
include "${KW_LIB_DIR}/lib/kw_string.sh"
include "${KW_LIB_DIR}/lib/patch_track_utils/contribution_utils.sh"
include "${KW_LIB_DIR}/lib/patch_track_utils/patch_utils.sh"
include "${KW_LIB_DIR}/lib/patch_track_utils/submission_utils.sh"

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
  local patch_cache="$1"
  local send_patch_output_dir="$2"
  local contribution_name="$3"
  local ret
  local -A patches_message_id_array

  from="joaosouzaaa12@gmail.com"
  get_or_create_contribution_result="$(get_or_create_contribution "contribution_name" "$from" '')"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$ret"
    return "$ret"
  fi

  register_patches "$patch_cache" "$send_patch_output_dir" "$get_or_create_contribution_result" 'patches_message_id_array'
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "($LINENO): Error while trying to register patches"
    return "$ret"
  fi

  create_submission_result="$(create_submission "$get_or_create_contribution_result" "$from")"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$ret"
    return "$ret"
  fi
  
  register_patch_submissions_result="$(register_patch_submissions "$create_submission_result" 'patches_message_id_array')"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$ret"
    return "$ret"
  fi

  success "Patch registered successfully."
  return 0
}

function register_contribution()
{
  local contribution_name="$1"
  local from
  local get_or_create_contribution_result

  #from="$(grep -m 1 '^From:' <<< "$header_block" | tail -n 1 | sed 's/^From:[[:space:]]*//')"
  from="joaosouzaaa12@gmail.com"
  get_or_create_contribution_result="$(get_or_create_contribution "contribution_name" "$from")"
  ret="$?"

  echo "começou contribution" > /dev/tty

  if [[ "$ret" -ne 0 ]]; then
    complain "$get_or_create_contribution_result"
    return "$ret"
  fi

  echo "registrou contribution" > /dev/tty
  printf '%s\n' "$get_or_create_contribution_result"
  return 0
}

function register_patches()
{
  local patch_cache="$1"
  local send_patch_output_dir="$2"
  local contribution_id="$3"
  local -n patches_output_array="$4"
  local patch_num=1
  local -A patch_metadata
  local get_or_create_patch_result

  patch_numbers="$(find "${patch_cache}" -maxdepth 1 -type f -name "*.patch" | wc -l)"

  patches_output_array=()

  if [[ "$patch_numbers" -ne 1 ]]; then #if there is a cover letter it wouldn't be in the patch_cache dir
    extract_patch_from_file "$patch_num" "$send_patch_output_dir" 'patch_metadata'
    get_or_create_patch_result="$(get_or_create_patch "${patch_metadata["subject"]}" '' "${patch_metadata["from"]}"\
                                  "$contribution_id" '' 1)"
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
      complain "$get_or_create_patch_result"
      return "$ret"
    fi

    patches_output_array["$get_or_create_patch_result"]=''

    ((patch_num++))
    echo "${patch_metadata["subject"]}"
  fi

  for patch_path in "${patch_cache}/"*; do
    if is_a_patch "$patch_path"; then
      extract_patch_from_file "$patch_num" "$send_patch_output_dir" 'patch_metadata'
      patch_metadata["commit_hash"]="$(get_patch_commit_hash "$patch_path")"

      get_or_create_patch_result="$(get_or_create_patch "${patch_metadata["subject"]}" '' "${patch_metadata["from"]}"\
                                    "$contribution_id" "${patch_metadata["commit_hash"]}" 1)"
      ret="$?"

      if [[ "$ret" -ne 0 ]]; then
        complain "$get_or_create_patch_result"
        return "$ret"
      fi
      
      patches_output_array["$get_or_create_patch_result"]="${patch_metadata["message_id"]}"
      echo "${patch_metadata["subject"]}"
      echo "${patch_metadata["commit_hash"]}"
      ((patch_num++))
    fi
  done

  return 0;
}

function register_patch_submissions()
{
  local submission_id="$1"
  local -n patches_message_id="$2"

  echo "começou patch submission register " > /dev/tty

  for patch_id in "${!patches_message_id[@]}"; do
    message_id="${patches_message_id[$patch_id]}"
    create_patch_submission_result="$(create_patch_submission "$patch_id" "$submission_id" "$message_id")"
    ret="$?"
    echo "${patch_id} EE ${message_id}" > /dev/tty
    if [[ "$ret" -ne 0 ]]; then
      complain "$create_patch_submission_result"
      return "$ret"
    fi
  done

  return 0
}

#function register_submission()
#{
#  local contribution_id="$1"
#  
#}

function extract_patch_from_file()
{
  local _patch_extracted_num="$1"
  local _send_email_log_file="$2"
  local -n _output_metadata_array="$3"
  local header_block

  echo "PATCH NUM ${_patch_extracted_num} LOG FILE: ${_send_email_log_file}"
  header_block=$(cat "$_send_email_log_file" \
  | grep -Pzo \
    'MAIL FROM:[^\n]*\nRCPT TO:[^\n]*\nFrom:[^\n]*\nTo:[^\n]*\nSubject:[^\n]*\nDate:[^\n]*\nMessage-ID:[^\n]*(?!X-Mailer:)' | tr '\0' '\n')

  if [[ -z "$header_block" ]]; then
      echo "Erro: patch número $_patch_extracted_num não encontrado" >&2
      return 1
  fi

  _output_metadata_array=()
  _output_metadata_array["from"]="$(grep -m "$_patch_extracted_num" '^From:' <<< "$header_block" | tail -n 1 | sed 's/^From:[[:space:]]*//')"
  _output_metadata_array["to"]="$(grep -m "$_patch_extracted_num" '^To:' <<< "$header_block" | tail -n 1 | sed 's/^To:[[:space:]]*//')"
  _output_metadata_array["subject"]="$(grep -m "$_patch_extracted_num" '^Subject:' <<< "$header_block" | tail -n 1 | sed 's/^Subject:[[:space:]]*//')"
  _output_metadata_array["date"]="$(grep -m "$_patch_extracted_num" '^Date:' <<< "$header_block"  | tail -n 1 | sed 's/^Date:[[:space:]]*//')"
  _output_metadata_array["message_id"]="$(grep -m "$_patch_extracted_num" '^Message-ID:' <<< "$header_block" | tail -n 1 | sed 's/^Message-ID:[[:space:]]*//')"

  return 0
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