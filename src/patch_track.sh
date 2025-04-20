include "${KW_LIB_DIR}/lib/kwlib.sh"
include "${KW_LIB_DIR}/lib/kw_string.sh"

declare -gr DATABASE_PATCH_TABLE='patch'

declare -gA options_values

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

# Parses the command-line arguments for the patch track operation.
# It populates the options_values associative array with parsed options.
#
# Return:
# Returns 22 if there are invalid arguments.
function parse_patch_track()
{
  local long_options='help'
  local short_options='h'
  local options

  options="$(kw_parse "$short_options" "$long_options" "$@")"

  if [[ "$?" != 0 ]]; then
    options_values['ERROR']="$(kw_parse_get_errors 'kw patch_track' "$short_options" \
      "$long_options" "$@")"
    return 22 # EINVAL
  fi

  eval "set -- ${options}"

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --help | -h)
        patch_track_help '--help'
        exit
        ;;
      --)
        shift
        ;;
      *)
        options_values['ERROR']="$1"
        return 22 # EINVAL
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

  printf '%s\n' 'kw patch-track:'
}
