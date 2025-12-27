include "${KW_LIB_DIR}/lib/kwlib.sh"
include "${KW_LIB_DIR}/lib/kw_string.sh"
include "${KW_LIB_DIR}/lib/patch_track_utils/contribution_utils.sh"
include "${KW_LIB_DIR}/lib/patch_track_utils/patch_utils.sh"
include "${KW_LIB_DIR}/lib/patch_track_utils/submission_utils.sh"
include "${KW_LIB_DIR}/lib/patch_track_utils/repository_utils.sh"
include "${KW_LIB_DIR}/lib/kw_config_loader.sh"

declare -g MUTT_CONFIG_NAME='patch_track_mutt.config'
declare -g MUTT_CONFIG_PATH="${KW_ETC_DIR}/${MUTT_CONFIG_NAME}"
declare -g KW_MUTT_DIR="${KW_SHARE_DIR}/mutt"
declare -g MUTT_RC_PATH="${KW_MUTT_DIR}/.muttrc-kw-patch-track"
declare -g ISYNC_RC_PATH="${KW_MUTT_DIR}/.mbsyncrc"
declare -g KW_MUTT_MAIL_DIR="${KW_MUTT_DIR}/mail"
declare -g KW_MUTT_MESSAGES_DIR="${KW_MUTT_DIR}/messages"
declare -g KW_MUTT_HEADERS_DIR="${KW_MUTT_DIR}/headers"
declare -g KW_MUTT_MAIL_CHECK='60'

declare -gA set_confs
declare -gA options_values
declare -gA condition_array
declare -gA updates_array

declare -ga essential_config_options=('imap_user' 'imap_pass'
  'folder' 'spoolfile' 'record')

# This is the main entry point for the patch-track feature. It processes 
# command-line arguments through the parser and dispatches the execution 
# to specific sub-modules, such as dashboards, status management, metadata 
# registration, and external tool integration. It handles validations for 
# mandatory identifiers (patch, contribution, or repository IDs) and 
# manages errors related to missing arguments or invalid configurations.
#
# @$@: Arguments passed from the command line.
#
# Return:
# Returns 0 if the operation is successful; 22 if no arguments are provided, 
# if parsing fails, or if mandatory parameters are missing.
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

  if [[ -n "${options_values['SHOW_PATCHES']}" ]]; then
    show_patches_dashboard "$flag"
    return 0
  fi

  if [[ -n "${options_values['SET_STATUS']}" ]]; then
    if [[ -z "${options_values['PATCH_ID']}" ]]; then
      complain 'Patch id not specified with `--id <num>`'
      return 22 # EINVAL
    fi

    set_patch_status "${options_values['PATCH_ID']}" "${options_values['STATUS']}" "$flag"
    if [[ "$?" -eq 0 ]]; then
      success "Patch status updated successfully."
    fi
    return 0
  fi

  if [[ -n "${options_values['SET_REPOSITORY']}" ]]; then
    if [[ -z "${options_values['CONTRIBUTION_ID']}" ]]; then
      complain 'Contribution id not specified'
      return 22 # EINVAL
    fi

    if [[ -z "${options_values['ORIGIN_URL']}" ]]; then
      complain 'Branch name not specified'
      return 22 # EINVAL
    fi

    register_contribution_repository "${options_values['CONTRIBUTION_ID']}" "${options_values['SET_REPOSITORY']}" "${options_values['ORIGIN_URL']}" "$flag"
    if [[ "$?" -eq 0 ]]; then
      success "Patch repository updated successfully."
    fi
    return 0
  fi

  if [[ -n "${options_values['SET_MAINTAINER']}" ]]; then
    if [[ -z "${options_values['REPOSITORY_ID']}" ]]; then
      complain 'Repository id not specified'
      return 22 # EINVAL
    fi

    if [[ -z "${options_values['MAINTAINER_EMAIL']}" ]]; then
      complain 'Maintainer email not specified'
      return 22 # EINVAL
    fi

    register_repository_maintainer "${options_values['REPOSITORY_ID']}" "${options_values['SET_MAINTAINER']}" "${options_values['MAINTAINER_EMAIL']}" "$flag"
    if [[ "$?" -eq 0 ]]; then
      success "Repository Maintainer updated successfully."
    fi
    return 0
  fi

  if [[ -n "${options_values['SHOW_CONTRIBUTIONS']}" ]]; then
    show_contributions_dashboard "$flag" '' "${options_values['CONTRIBUTION_ID']}"
    return 0
  fi

  verify_mutt_minimal_config

  if [[ -n "${options_values['UPDATE_STATUS']}" ]]; then
    if [[ -z "${options_values['CONTRIBUTION_ID']}" ]]; then
      complain 'Contribution id not specified'
      return 22 # EINVAL
    fi

    update_contribution_status ${options_values['CONTRIBUTION_ID']}
    if [[ "$?" -eq 0 ]]; then
      success "Contribution Status updated successfully."
    fi
    return 0
  fi

  if [[ -n "${options_values['OPEN_CONTRIBUTION_ON_MUTT']}" ]]; then
    if [[ -z "${options_values['CONTRIBUTION_ID']}" ]]; then
      complain 'Contribution id not specified'
      return 22 # EINVAL
    fi

    open_contribution_on_mutt ${options_values['CONTRIBUTION_ID']}
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
  local submission_id="$3"
  local caption="${4:-'Patches infos'}"
  local from="${options_values['FROM']}"
  local before="${options_values['BEFORE']}"
  local after="${options_values['AFTER']}"
  local patches_info
  declare -a patches_array

  if [[ -z $columns ]]; then
    columns="$(tput cols)"
  fi

  condition_array=()

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

  if [[ -n "$submission_id" ]]; then
    condition_array+=(["${DATABASE_PATCH_SUBMISSION_TABLE}.submission_id"]="$submission_id")
    patches_info=$(select_from "$DATABASE_PATCH_TABLE JOIN $DATABASE_PATCH_SUBMISSION_TABLE ON ${DATABASE_PATCH_TABLE}.id = ${DATABASE_PATCH_SUBMISSION_TABLE}.patch_id" 'patch.id, patch.created_at, patch.status, patch.title' '' 'condition_array')
  else
    patches_info=$(select_from "$DATABASE_PATCH_TABLE" 'id, created_at, status, title' '' 'condition_array')
  fi

  patches_info=$(select_from "$DATABASE_PATCH_TABLE JOIN $DATABASE_PATCH_SUBMISSION_TABLE ON ${DATABASE_PATCH_TABLE}.id = ${DATABASE_PATCH_SUBMISSION_TABLE}.patch_id" 'patch.id, patch.created_at, patch.status, patch.title' '' 'condition_array')
  readarray -t patches_array <<< "$patches_info"

  print_patches_dashboard 'patches_array' "$columns" "$caption"
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
  local email_from
  local -A patches_message_id_array

  email_from=$(cat "$send_patch_output_dir" |
    grep -m 1 '^MAIL FROM:' | tail -n 1 | cut -d'<' -f2 | cut -d'>' -f1)

  get_or_create_contribution_result="$(get_or_create_contribution "$contribution_name" "$email_from" '')"
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

  create_submission_result="$(create_submission "$get_or_create_contribution_result" "$email_from")"
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

# This interactive function prompts the user to select an existing 
# contribution or define a new one. It retrieves a list of available 
# contributions from the database, formats them into a numbered list 
# for selection, and handles the user input. It validates if the input 
# corresponds to a valid list index or treats it as a new contribution title.
#
# Return:
# Returns 0 after printing the chosen or newly created contribution title 
# to the standard output.
function ask_contribution_name()
{
  local existent_contributions=()
  local formatted_string=''
  local total_contributions=0
  local contribution
  local contribution_index

  condition_array=()
  mapfile -t existent_contributions < <(get_contribution_info 'title' 'condition_array' 'id')
  total_contributions=${#existent_contributions[@]}

  if [ "$total_contributions" -gt 0 ]; then
    for i in "${!existent_contributions[@]}"; do
      formatted_string+="$((i + 1)) - ${existent_contributions[i]}"

      if [ "$i" -lt "$((total_contributions - 1))" ]; then
        formatted_string+=$'\n'
      fi
    done
  fi

  contribution=$(ask_with_default $'Select one of the contributions bellow or write a new title:\n' "$formatted_string")

  if [[ "$contribution" =~ ^[0-9]+$ ]]; then
    contribution_index="$contribution"

    if [[ "$contribution_index" -ge 1 ]] && [[ "$contribution_index" -le "$total_contributions" ]]; then

      local array_index=$((contribution_index - 1))

      printf '%s\n' "${existent_contributions[array_index]}"
      return 0
    fi
  fi

  printf '%s\n' "$contribution"
  return 0
}

# This registers a new contribution or retrieves an existing one based on 
# a specified name and metadata extracted from email logs. It scrapes 
# the sender address from the provided log file and attempts to persist 
# or fetch the contribution in the database. It handles errors related 
# to database operations and ensures the operation result is reported.
#
# @contribution_name: The title or identifier for the contribution.
# @_send_email_log_file: Path to the log file containing email metadata.
#
# Return:
# Returns 0 if the contribution is successfully registered or retrieved; 
# otherwise, returns the non-zero error code from the database operation.
function register_contribution()
{
  local contribution_name="$1"
  local _send_email_log_file="$2"
  local from
  local get_or_create_contribution_result

  email_from=$(cat "$_send_email_log_file" |
    grep -m 1 '^MAIL FROM:' | tail -n 1 | cut -d'<' -f2 | cut -d'>' -f1)

  get_or_create_contribution_result="$(get_or_create_contribution "$contribution_name" "$email_from" '')"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$get_or_create_contribution_result"
    return "$ret"
  fi

  printf '%s\n' "$get_or_create_contribution_result"
  return 0
}

# This function registers multiple patches associated with a specific 
# contribution. It iterates through cached patch files, extracts 
# metadata such as subjects, authors, and commit hashes, and ensures 
# each patch is persisted in the database. It specifically handles 
# scenarios involving cover letters and stores the resulting patch 
# identifiers and message IDs in an associative array. It manages 
# errors related to metadata extraction or database persistence failures.
#
# @patch_cache: Directory containing the cached .patch files.
# @send_patch_output_dir: Directory with logs generated by kw send-patch.
# @contribution_id: Identifier of the contribution these patches belong to.
# @patches_output_array: Reference to an associative array to store patch IDs.
#
# Return:
# Returns 0 if all patches are successfully registered; otherwise, returns 
# the non-zero error code from the failed database or extraction operation.
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

  if [[ "$patch_numbers" -ne 1 ]]; then # if there is a cover letter it wouldn't be in the patch_cache dir
    extract_patch_from_file "$patch_num" "$send_patch_output_dir" 'patch_metadata'
    get_or_create_patch_result="$(get_or_create_patch "${patch_metadata["subject"]}" "${patch_metadata["from"]}" \
      "$contribution_id" '')"
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
      complain "$get_or_create_patch_result"
      return "$ret"
    fi

    patches_output_array["$get_or_create_patch_result"]=''

    ((patch_num++))
  fi

  for patch_path in "${patch_cache}/"*; do
    if is_a_patch "$patch_path"; then
      extract_patch_from_file "$patch_num" "$send_patch_output_dir" 'patch_metadata'
      patch_metadata["commit_hash"]="$(get_patch_commit_hash "$patch_path")"

      get_or_create_patch_result="$(get_or_create_patch "${patch_metadata["subject"]}" "${patch_metadata["from"]}" \
        "$contribution_id" "${patch_metadata["commit_hash"]}")"
      ret="$?"

      if [[ "$ret" -ne 0 ]]; then
        complain "$get_or_create_patch_result"
        return "$ret"
      fi

      patches_output_array["$get_or_create_patch_result"]="${patch_metadata["message_id"]}"
      ((patch_num++))
    fi
  done

  return 0
}

# This function orchestrates the automatic status update for all patches 
# within a specific contribution. It synchronizes the local repository 
# with the remote origin, retrieves metadata for the most recent 
# submission, and iterates through each associated patch to trigger 
# the heuristic evaluation engine. Finally, it consolidates the 
# individual patch results to determine the overall contribution status 
# and displays the updated dashboard. It handles errors related to 
# missing submission data or failed metadata retrieval.
#
# @contribution_id: Identifier of the contribution to be updated.
#
# Return:
# Returns 0 if the update process completes successfully; 22 if the 
# last submission information or patch metadata cannot be retrieved.
function update_contribution_status()
{
  local contribution_id="$1"

  local submission_infos
  local submission_id

  local patch_submission_infos
  local patch_id

  local patch_infos
  local patch_commit_hash
  local patch_message_id
  local patch_author_email
  local patch_current_status
  local final_status
  local repository_origin_url
  local maintainer_email
  declare -A patches_status
  declare -A patch_submission_condition_array
  declare -A patch_condition_array
  declare -a maintainers_emails=()

  condition_array=(['id']="$contribution_id")
  contribution_repository_id="$(get_contribution_info 'repository_id' 'condition_array')"

  condition_array=(['id']="$contribution_repository_id")
  repository_origin_url="$(get_repository_info 'origin_url' 'condition_array')"

  cmd_manager git -C "$repository_origin_url" fetch origin > /dev/null 2>&1

  submission_id="$(get_last_submission_infos_by_contribution_id 'id' "$contribution_id")" || return 22
  condition_array=(['submission_id']="$submission_id")

  patch_submission_infos="$(
    get_patch_submission_info 'patch_id, submission_id, message_id' 'condition_array'
  )" || return 22

  for patch_id in $patch_submission_infos; do
    IFS='|' read -r patch_id submission_id message_id <<< "$patch_submission_infos"

    condition_array=(['patch_id']="$patch_id"
      ['submission_id']="$submission_id"
      ['message_id']="$message_id")
    message_id="$(get_patch_submission_info 'message_id' 'condition_array')" || continue

    condition_array=(['id']="$patch_id")
    patch_infos="$(get_patch_info 'commit_hash, status' 'condition_array')" || continue

    IFS='|' read -r commit_hash status <<< "$patch_infos"

    final_status="$(
      update_patch_status \
        "$patch_id" \
        "$message_id" \
        "$commit_hash" \
        '' \
        "$status"
    )"
    patches_status["$patch_id"]="$final_status"
  done

  decide_patch_status "$contribution_id" 'patches_status'
  show_contributions_dashboard '' '' "$contribution_id"
}

# This function evaluates and updates the status of an individual patch 
# using automated heuristics. It leverages the mutt email client to 
# search for and download relevant message threads, then analyzes 
# local message files for specific indicators such as approval tags 
# or last reply authorship. It handles state transitions between 
# SENT, REVIEWED, and APPROVED, while respecting existing terminal 
# states like MERGED. It manages synchronization with external 
# processes through temporary status files and handles scenarios 
# where no replies are found.
#
# @patch_id: Identifier of the patch to be updated in the database.
# @patch_message_id: The unique Message-ID used to track email threads.
# @patch_commit_hash: Hash associated with the patch for future merge checks.
# @patch_maintainer_email: Email address of the maintainer (for future logic).
# @patch_current_status: The current state of the patch to determine logic flow.
# @flag: Execution mode flag (defaults to 'SILENT').
#
# Return:
# Returns 0 after updating the patch status and printing the new status 
# string to the standard output.
function update_patch_status()
{
  local patch_id="$1"
  local patch_message_id="$2"
  local patch_commit_hash="$3"
  local patch_maintainer_email="$4"
  local patch_current_status="$5"
  local flag="${6:-'SILENT'}"
  local last_msg_file
  local last_author
  local reply_files

  if [[ "$patch_current_status" == 'MERGED' ]]; then
    printf '%s' 'MERGED'
    return 0
  fi

  [[ -f /tmp/mutt-status ]] && rm -f /tmp/mutt-status

  xterm -iconic -e \
    sh -c "mutt -F ${MUTT_RC_PATH} \
      -e 'push \"l ((~i ${patch_message_id})|(~x ${patch_message_id})) ~b .* <enter><pause><enter>q\"' \
      ; echo finished > /tmp/mutt-status" \
    > /dev/null 2>&1 &

  while [[ ! -s /tmp/mutt-status ]]; do
    sleep 0.2
  done

  mapfile -t reply_files < <(grep -R -l "In-Reply-To:.*${patch_message_id}" "$KW_MUTT_MESSAGES_DIR")

  if [[ "${#reply_files[@]}" -eq 0 ]]; then
    set_patch_status "$patch_id" 'SENT'
    printf '%s' 'SENT'
    return 0
  fi

  for file in "${reply_files[@]}"; do
    if grep -Eiw "Approved|Reviewed-by" "$file" > /dev/null 2>&1; then
      set_patch_status "$patch_id" 'APPROVED'
      printf '%s' 'APPROVED'
      return 0
    fi
  done

  last_msg_file=$(printf '%s\n' "${reply_files[@]}" |
    xargs -d '\n' stat --format='%Y %n' 2> /dev/null |
    sort -n |
    tail -n1 |
    cut -d' ' -f2-)

  if [[ -z "$last_msg_file" ]]; then
    set_patch_status "$patch_id" 'SENT'
    printf '%s' 'SENT'
    return 0
  fi

  last_author=$(grep -i '^From:' "$last_msg_file" |
    sed -E 's/From:.*<([^>]+)>.*/\1/')

  if [[ "$last_author" == "${patch_track_mutt_config[imap_user]}" ]]; then
    set_patch_status "$patch_id" 'SENT'
    printf '%s' 'SENT'
  else
    set_patch_status "$patch_id" 'REVIEWED'
    printf '%s' 'REVIEWED'
  fi

  return 0
}

# This function creates records for patch submissions by associating 
# individual patch identifiers with a specific submission and its 
# corresponding email Message-ID. It iterates through an associative 
# array of patches, ensuring each entry is persisted in the database 
# relationship table. It handles errors during the creation process 
# and ensures that any failure in database persistence is reported 
# to the user.
#
# @submission_id: Identifier of the submission to which the patches belong.
# @patches_message_id: Reference to an associative array mapping patch IDs 
#                      to their respective Message-IDs.
#
# Return:
# Returns 0 if all patch submissions are successfully registered; 
# otherwise, returns the non-zero error code from the failed operation.
function register_patch_submissions()
{
  local submission_id="$1"
  local -n patches_message_id="$2"

  for patch_id in "${!patches_message_id[@]}"; do
    message_id="${patches_message_id[$patch_id]}"
    create_patch_submission_result="$(create_patch_submission "$patch_id" "$submission_id" "$message_id")"
    ret="$?"
    if [[ "$ret" -ne 0 ]]; then
      complain "$create_patch_submission_result"
      return "$ret"
    fi
  done

  return 0
}

# This function facilitates the exploration of a contribution by opening 
# its related email threads in the mutt terminal client. It retrieves 
# all submission identifiers linked to a contribution and extracts 
# their unique Message-IDs from the database. It then constructs a 
# complex search query and invokes mutt, providing an integrated 
# interface for reviewing mailing list interactions. It handles 
# errors related to missing contribution IDs or the absence of 
# submission metadata in the database.
#
# @contribution_id: Identifier of the contribution to be explored.
#
# Return:
# Returns 0 if mutt is successfully launched with the constructed query; 
# 22 if the contribution ID is missing; 61 if no submission data 
# or Message-IDs are found.
function open_contribution_on_mutt()
{
  local contribution_id="$1"
  local -a messages_ids=()
  local mutt_query=''

  if [[ -z "$contribution_id" ]]; then
    complain 'Contribution id not informed'
    return 22
  fi

  condition_array=(['contribution_id']="$contribution_id")
  submission_ids_result="$(get_submission_info 'id' 'condition_array')"

  if [[ "$?" -ne 0 ]]; then
    complain "$submission_ids_result"
    return 61 # ENODATA
  fi

  for submission_id in $submission_ids_result; do
    condition_array=(['submission_id']="$submission_id")
    message_id_result="$(get_patch_submission_info 'message_id' 'condition_array')"

    if [[ "$?" -ne 0 ]]; then
      continue
    fi

    mutt_query+="(~i $message_id_result | ~x $message_id_result) | "
  done

  mutt_query="${mutt_query% | }"

  if [[ -z "$mutt_query" ]]; then
    complain 'no submission message-id found for this contribution'
    return 61 # ENODATA
  fi

  mutt -F "$MUTT_RC_PATH" -e "push \"l ${mutt_query} <enter>\""

  return 0
}

# This function extracts metadata from a specific patch within a log file 
# generated by the email submission process. It uses text processing 
# tools to isolate header blocks and retrieve essential information 
# such as sender, recipient, subject, submission date, and the unique 
# Message-ID. The extracted data is stored in a referenced associative 
# array for further processing. It handles scenarios where the 
# expected header structure is missing or malformed.
#
# @_patch_extracted_num: The index of the patch to be extracted from the log.
# @_send_email_log_file: Path to the log file containing the email headers.
# @_output_metadata_array: Reference to an associative array to store metadata.
#
# Return:
# Returns 0 if metadata is successfully extracted; 22 if the header 
# block cannot be found or isolated.
function extract_patch_from_file()
{
  local _patch_extracted_num="$1"
  local _send_email_log_file="$2"
  local -n _output_metadata_array="$3"
  local header_block

  header_block=$(
    awk '
      /^MAIL FROM:/ {
        in_block=1
        block = $0 "\n"
        next
      }
      in_block {
        block = block $0 "\n"
        if ($0 ~ /^X-Mailer:/) {
          printf "%s", block
          in_block=0
          block=""
        }
      }
    ' "$_send_email_log_file"
  )

  if [[ -z "$header_block" ]]; then
    return 22
  fi

  _output_metadata_array=()
  _output_metadata_array["from"]="$(grep -m "$_patch_extracted_num" '^From:' <<< "$header_block" | tail -n 1 | sed 's/^From:[[:space:]]*//' | cut -d'<' -f2 | cut -d'>' -f1)"
  _output_metadata_array["to"]="$(grep -m "$_patch_extracted_num" '^To:' <<< "$header_block" | tail -n 1 | sed 's/^To:[[:space:]]*//')"
  _output_metadata_array["subject"]="$(grep -m "$_patch_extracted_num" '^Subject:' <<< "$header_block" | tail -n 1 | sed 's/^Subject:[[:space:]]*//')"
  _output_metadata_array["submission_date"]="$(grep -m "$_patch_extracted_num" '^Date:' <<< "$header_block" | tail -n 1 | sed 's/^Date:[[:space:]]*//')"
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
  local caption="$3"
  local id
  local date
  local time
  local status
  local title
  local id_width=6
  local date_width=22
  local status_width=10
  local title_width=$(("$columns" - id_width - date_width - status_width - 6))
  local caption_width=${#caption}
  local trim_width=$(((columns - caption_width) / 2))
  local remaining_width=$((columns - caption_width - trim_width))

  printf "%*s%s%*s\n" "$trim_width" "" "$caption" "$remaining_width" "" | tr ' ' '-'
  printf "%-${id_width}s|%-${date_width}s|%-${status_width}s|%-${title_width}s%s\n" "ID" "Date" "Status" "Title"
  printf "%-${columns}s\n" | tr ' ' '-'

  # Print rows
  for patch in "${!_patches_array[@]}"; do
    IFS='|' read -r id date status title <<< "${_patches_array[$patch]}"
    printf "%-${id_width}s|%-${date_width}s|%-${status_width}s|%-${title_width}s%s\n" "$id" "$date" "$status" "$title"
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
    formatted_status=$(get_valid_status)
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

# This sets the status of a specified contribution. It updates the state 
# of a contribution identified by its ID, ensuring that the new status 
# is validated against a predefined list of allowed values. It manages 
# errors related to empty identifiers, invalid status strings, or 
# database persistence failures.
#
# @contribution_id: ID of the contribution to be updated.
# @contribution_new_status: The new status string to be applied.
#
# Return:
# Returns 0 if the update is successful; 22 if an error occurs during 
# the database operation; 61 if mandatory arguments are missing.
function set_contribution_status()
{
  local contribution_id="$1"
  local contribution_new_status="$2"
  local formatted_status
  local sql_operation_result
  local ret

  if [[ -z "$contribution_id" ]]; then
    complain 'Contribution ID is empty'
    return 61 # ENODATA
  fi

  if [[ -z "$contribution_new_status" ]]; then
    complain 'New status is empty'
    return 61 # ENODATA
  fi

  formatted_status=$(check_valid_status "$contribution_new_status")

  if [[ "$?" -ne 0 ]]; then
    formatted_status=$(get_valid_status)
  fi

  condition_array=(['id']="${contribution_id}")
  updates_array=(['status']="${formatted_status}")

  sql_operation_result=$(update_into "$DATABASE_CONTRIBUTION_TABLE" 'updates_array' '' 'condition_array' 'VERBOSE')
  ret="$?"

  if [[ "$ret" -eq 2 || "$ret" -eq 61 ]]; then
    complain "$sql_operation_result"
    return 22 # EINVAL
  elif [[ "$ret" -ne 0 ]]; then
    complain "($LINENO):" $'Error while trying to update contribution status in the database with the command:\n'"${sql_operation_result}"
    return 22 # EINVAL
  fi

  return 0
}

# This function aggregates the statuses of all individual patches to 
# determine the overall state of a contribution. It implements a 
# hierarchical logic where certain states (like REVIEWED) take 
# precedence over others to reflect the most critical stage of the 
# lifecycle. After evaluating the patches through an associative array, 
# it persists the resulting contribution status in the database.
#
# @contribution_id: Identifier of the contribution to be updated.
# @_contribution_patches_status: Reference to an associative array mapping 
#                                patch IDs to their current status.
#
# Return:
# Returns 0 after successfully determining and updating the contribution status.
function decide_patch_status()
{
  local contribution_id="$1"
  local -n _contribution_patches_status="$2"
  local has_revisado=0
  local has_aprovado=0
  local has_mergeado=0

  for pid in "${!_contribution_patches_status[@]}"; do
    case "${_contribution_patches_status[$pid]}" in
      REVIEWED) has_revisado=1 ;;
      APPROVED) has_aprovado=1 ;;
      MERGED) has_mergeado=1 ;;
    esac
  done

  if [[ $has_revisado -eq 1 ]]; then
    contribution_status="REVIEWED"
  elif [[ $has_aprovado -eq 1 ]]; then
    contribution_status="APPROVED"
  elif [[ $has_mergeado -eq 1 ]]; then
    contribution_status="MERGED"
  else
    contribution_status="SENT"
  fi

  condition_array=(['id']="$contribution_id")
  set_contribution_status "$contribution_id" "$contribution_status"

  return 0
}

# This function prompts the user for the current patch status and validates
# it. It returns the validated status or prompts again if the status
# is invalid.
#
# Return:
# Returns the formatted status.
function get_valid_status()
{
  local status
  local formatted_status
  local message=$'Enter your current patch status'
  local default_status=$'[Sent - S], [Reviewed - RW], [Approved - A], [Rejected - R], [Merged - M]'

  status=$(ask_with_default "$message" "$default_status")
  formatted_status=$(check_valid_status "$status")

  if [[ "$?" -ne 0 ]]; then
    formatted_status=$(get_valid_status)
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
function register_contribution_repository()
{
  local contribution_id="$1"
  local repository="$2"
  local origin_url="$3"
  local sql_operation_result
  local ret

  if [[ -z "$contribution_id" ]]; then
    complain 'Contribution ID is empty'
    return 61 # ENODATA
  fi

  if [[ -z "$repository" ]]; then
    complain 'repository name is empty'
    return 61 # ENODATA
  fi

  if [[ -z "$origin_url" ]]; then
    complain 'origin_url is empty'
    return 61 # ENODATA
  fi

  check_valid_repository_name="$(check_valid_db_string "$repository")"

  if [[ "$?" -ne 0 ]]; then
    complain 'repository name is invalid'
    return 61 # ENODATA
  fi

  check_valid_origin_url_name="$(check_valid_db_string "$origin_url")"

  if [[ "$?" -ne 0 ]]; then
    complain 'origin_url is invalid'
    return 61 # ENODATA
  fi

  get_or_create_repository_result="$(get_or_create_repository "$repository" "$origin_url")"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$ret"
    return "$ret"
  fi

  set_contribution_repository_result="$(set_contribution_repository "$contribution_id" "$get_or_create_repository_result")"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$set_contribution_repository_result"
    return 22 # EINVAL
  fi

  return 0
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
function register_repository_maintainer()
{
  local repository_id="$1"
  local maintainer_name="$2"
  local maintainer_email="$3"
  local sql_operation_result
  local ret

  if [[ -z "$repository_id" ]]; then
    complain 'repository_id ID is empty'
    return 61 # ENODATA
  fi

  if [[ -z "$maintainer_name" ]]; then
    complain 'maintainer_name name is empty'
    return 61 # ENODATA
  fi

  if [[ -z "$maintainer_email" ]]; then
    complain 'maintainer_email is empty'
    return 61 # ENODATA
  fi

  check_valid_maintainer_name="$(check_valid_db_string "$maintainer_name")"

  if [[ "$?" -ne 0 ]]; then
    complain 'maintainer name is invalid'
    return 61 # ENODATA
  fi

  check_valid_maintainer_email="$(validate_email "$maintainer_email")"

  if [[ "$?" -ne 0 ]]; then
    complain 'maintainer email is invalid'
    return 61 # ENODATA
  fi

  get_or_create_repository_maintainer_result="$(get_or_create_repository_maintainer "$repository_id" "$maintainer_name" "$maintainer_email")"
  ret="$?"

  if [[ "$ret" -ne 0 ]]; then
    complain "$get_or_create_repository_maintainer_result"
    return 22 # EINVAL
  fi

  return 0
}

# This function ensures that the minimum required configuration for mutt 
# integration is met. It iterates through a list of essential options 
# and identifies any missing or empty values within the configuration 
# array. If discrepancies are found, it triggers an interactive handler 
# to resolve them, reloads the configuration, and recursively validates 
# the settings until completion. Finally, it invokes the generation 
# of the mutt runtime configuration file.
#
# Return:
# Returns 0 after validating the configuration and generating the 
# necessary mutt resources.
function verify_mutt_minimal_config()
{
  local -a missing_options=()
  local option

  for option in "${essential_config_options[@]}"; do
    if [[ -z "${patch_track_mutt_config[$option]}" || "${patch_track_mutt_config[$option]}" == '' ]]; then
      missing_options+=("$option")
    fi
  done

  if ((${#missing_options[@]} > 0)); then
    handle_missing_mutt_options 'missing_options'
    load_patch_track_mutt_config
    verify_mutt_minimal_config
  fi

  generate_mutt_rc
}

# This helper function provides a formatted visualization of an array's 
# content. It utilizes a nameref to access the specified array by its 
# name and iterates through all keys, printing each key-value pair 
# in a structured format to the standard output. It is primarily 
# intended for debugging and displaying associative or indexed 
# array metadata.
#
# @array_name: Name of the array to be printed.
#
# Return:
# Returns 0 after iterating through and printing all array elements.
print_array()
{
  local array_name="$1"
  local -n arr="$array_name"
  local key

  for key in "${!arr[@]}"; do
    printf "  [%s] = %s\n" "$key" "${arr[$key]}"
  done
}

# This interactive function resolves missing configuration parameters by 
# prompting the user for input. It iterates through a provided list of 
# absent options, ensuring that each entry receives a non-empty value 
# via a validation loop. Once a valid input is obtained, it triggers 
# the persistence of the setting into the configuration file. It manages 
# user feedback through warning messages when empty strings are provided.
#
# @_missing_options: Reference to an array containing the names of the 
#                    missing configuration keys.
#
# Return:
# Returns 0 after all specified missing options have been successfully 
# prompted and saved.
function handle_missing_mutt_options()
{
  local -n _missing_options="$1"
  local option
  local value

  for option in "${_missing_options[@]}"; do
    while true; do
      read -rp "Insert a new value for '${option}': " value
      [[ -n "$value" ]] && break
      warning "Value can not be empty"
    done

    save_mutt_config "$option" "$value"
  done
}

# This function persists a specific key-value pair into the mutt 
# configuration file. It handles string escaping for both keys and 
# values to ensure safe processing by sed and shell utilities. It 
# checks for the existence of the key within the file; if the key 
# exists, it performs an in-place update of its value; otherwise, 
# it appends the new configuration entry to the end of the file.
#
# @key: The configuration parameter name to be saved.
# @value: The setting value associated with the key.
#
# Return:
# Returns 0 after successfully updating or appending the configuration record.
function save_mutt_config()
{
  local key="$1"
  local value="$2"
  local escaped_key
  local escaped_value

  escaped_key="$(printf '%s\n' "$key" | sed 's/[.[\*^$(){}+?|\\/]/\\&/g')"
  escaped_value="${value//\"/\\\"}"

  if grep -qE "^${escaped_key}=" "$MUTT_CONFIG_PATH" 2> /dev/null; then
    sed -i \
      "s|^${escaped_key}=.*|${key}=\"${escaped_value}\"|" \
      "$MUTT_CONFIG_PATH"
  else
    printf '%s="%s"\n' "$key" "$escaped_value" >> "$MUTT_CONFIG_PATH"
  fi
}

# This function manages the assignment of options within a mutt 
# configuration file. It ensures that a specific key is either 
# updated with a new value or appended to the file if it does 
# not already exist. It utilizes regular expressions to handle 
# various formatting styles, such as the presence or absence 
# of the 'set' keyword and flexible whitespace. It silently 
# handles empty values by bypassing the update to maintain 
# file integrity.
#
# @file: Path to the mutt configuration file to be modified.
# @key: The specific mutt option name to set or replace.
# @value: The value to be assigned to the specified key.
#
# Return:
# Returns 0 after successfully updating or appending the option record, 
# or if the provided value is empty.
set_or_replace_mutt_option()
{
  local file="$1"
  local key="$2"
  local value="$3"

  [[ -z "$value" ]] && return 0

  if grep -qE "^[[:space:]]*(set[[:space:]]+)?${key}[[:space:]]*=" "$file"; then
    sed -i \
      -E "s|^[[:space:]]*(set[[:space:]]+)?${key}[[:space:]]*=.*|set ${key}=${value}|" \
      "$file"
  else
    echo "set ${key}=${value}" >> "$file"
  fi
}

# This function orchestrates the creation and population of the mutt 
# runtime configuration file (muttrc). It ensures the target file 
# exists and systematically applies user-defined settings for IMAP 
# authentication, mailbox paths, and local caching directories. It 
# leverages a helper utility to manage the assignment of each option, 
# ensuring that credentials and performance-related parameters like 
# header and message caches are correctly structured.
#
# Return:
# Returns 0 after successfully generating or updating the configuration 
# file; 1 if the file creation fails due to filesystem permissions.
generate_mutt_rc()
{
  touch "$MUTT_RC_PATH" || return 1

  set_or_replace_mutt_option "$MUTT_RC_PATH" imap_user "${patch_track_mutt_config[imap_user]}"
  set_or_replace_mutt_option "$MUTT_RC_PATH" imap_pass "${patch_track_mutt_config[imap_pass]}"
  set_or_replace_mutt_option "$MUTT_RC_PATH" folder "${patch_track_mutt_config[folder]}"
  set_or_replace_mutt_option "$MUTT_RC_PATH" spoolfile "${patch_track_mutt_config[spoolfile]}"
  set_or_replace_mutt_option "$MUTT_RC_PATH" record "${patch_track_mutt_config[record]}"
  set_or_replace_mutt_option "$MUTT_RC_PATH" mbox_type "${patch_track_mutt_config[mbox_type]}"

  set_or_replace_mutt_option "$MUTT_RC_PATH" header_cache "\"$KW_MUTT_HEADERS_DIR\""
  set_or_replace_mutt_option "$MUTT_RC_PATH" message_cachedir "\"$KW_MUTT_MESSAGES_DIR\""
  set_or_replace_mutt_option "$MUTT_RC_PATH" mail_check "\"$KW_MUTT_MAIL_CHECK\""
}

# Show contributions dashboard with optional filter by contribution_id.
#
# @flag: Display mode flag (e.g., SILENT)
# @columns: terminal width
# @contribution_id: optional filter (shows only that contribution if set)
function show_contributions_dashboard()
{
  local flag="$1"
  local columns="$2"
  local contribution_id="$3"
  local id
  local status
  local title
  local author_email
  local repository_id
  local created_at
  local repo_name
  local repo_origin_url
  local contributions_info_result
  local last_submission_id_result
  declare -a contributions_infos_array

  if [[ -z "$columns" ]]; then
    columns="$(tput cols)"
  fi

  if [[ -n "$contribution_id" ]]; then

    condition_array=(['id']="$contribution_id")
    contributions_info_result=$(get_contribution_info 'status, title, author_email, created_at, repository_id' 'condition_array')

    if [[ "$?" -ne 0 ]]; then
      complain "$contributions_info_result"
      return 22
    fi

    IFS='|' read -r c_status c_title c_author_email c_created_at repository_id <<< "$contributions_info_result"

    condition_array=(['id']="$repository_id")
    repo_infos_result="$(get_repository_info 'name, origin_url' 'condition_array')"

    if [[ "$?" -ne 0 ]]; then
      complain "$repo_infos_result"
      return 22
    fi

    IFS='|' read -r repo_name repo_url <<< "$repo_infos_result"

    last_submission_id_result="$(get_last_submission_infos_by_contribution_id 'id' "$contribution_id")"

    if [[ "$?" -ne 0 ]]; then
      complain "$last_submission_id_result"
      return 22
    fi

    contributions_infos_array[0]="$contribution_id|$c_status|$c_title|$c_author_email|$c_created_at|$repo_name|$repo_url|$repository_id|$last_submission_id_result"
    print_single_contribution_dashboard 'contributions_infos_array' "$columns"
    show_submissions_dashboard "$flag" "$columns" "$contribution_id"
    show_patches_dashboard "$flag" "$columns" "$last_submission_id_result" 'Last submission patches'

  else
    condition_array=()
    contributions_info_result=$(select_from "$DATABASE_CONTRIBUTION_TABLE" 'id, title, created_at, status' '' '')

    if [[ "$?" -ne 0 ]]; then
      complain "Erro ao buscar contributions"
      return 22
    fi

    readarray -t contributions_infos_array <<< "$contributions_info_result"
    print_contributions_dashboard 'contributions_infos_array' "$columns"
  fi

  return 0
}

# This function renders a detailed dashboard for a single contribution 
# to the standard output. It calculates dynamic widths based on the 
# terminal's column count to format a centered title header and 
# displays comprehensive metadata, including contribution ID, author 
# email, creation date, and status. Additionally, it retrieves and 
# lists associated repository details and maintainer contact 
# information from the database, ensuring a structured and 
# professional visual representation.
#
# @_contribs_array: Reference to an array containing the contribution 
#                   metadata delimited by pipe characters.
# @columns: The total width of the terminal display for formatting purposes.
#
# Return:
# Returns 0 after successfully formatting and printing the dashboard; 
# 22 if an error occurs while retrieving maintainer information.
function print_single_contribution_dashboard()
{
  local -n _contribs_array="$1"
  local columns="$2"
  local name_width=20
  local date_width=22
  local status_width=10
  local sendby_width=20
  local remaining_width
  local maintainers_ids
  local trim_width
  local c_title_width
  local item="${_contribs_array[0]}"

  IFS='|' read -r c_id c_status c_title c_author_email c_created_at repo_name repo_url repo_id submission_id <<< "$item"

  c_title_width=${#c_title}
  trim_width=$(((columns - c_title_width) / 2))
  remaining_width=$((columns - c_title_width - trim_width))

  printf "%*s%s%*s\n" "$trim_width" "" "$c_title" "$remaining_width" "" | tr ' ' '-'
  printf "ID: %s\n" "$c_id"
  printf "Send-By: %s\n" "$c_author_email"
  printf "Date: %s\n" "$c_created_at"
  printf "Status: %s\n" "$c_status"

  if [[ -n "$repo_id" && -n "$repo_name" && -n "$repo_url" ]]; then
    printf "Repository: %s\n" "(id: ${repo_id}) ${repo_name} - ${repo_url}"
  fi

  condition_array=(['repository_id']="$repo_id")
  maintainers_ids_result="$(get_maintainers_info 'contact_id' 'condition_array')"

  if [[ "$?" -ne 0 ]]; then
    complain "$maintainers_ids_result"
    return 22
  fi

  for maintainer_id in $maintainers_ids_result; do
    condition_array=(['id']="$maintainer_id")
    email_contact_infos_result="$(get_email_contact_info 'name, email' 'condition_array')"

    IFS='|' read -r m_name m_email <<< "$email_contact_infos_result"

    printf "Maintainer: %s - %s\n" "$m_name" "$m_email"
  done

  tput cnorm > /dev/tty
  printf "%-${columns}s\n" | tr ' ' '-'
}

# This function renders a tabular dashboard displaying a list of 
# contributions. It dynamically calculates the width of the name 
# column based on the terminal's dimensions and the fixed sizes of 
# the ID, date, and status fields. It formats a centered header 
# section and iterates through the provided array to print each 
# contribution's metadata in a structured, column-aligned layout. 
# It ensures visual consistency by utilizing terminal escape 
# sequences and horizontal separators.
#
# @_contribs_array: Reference to an array containing contribution 
#                   records delimited by pipe characters.
# @columns: The total width of the terminal display for formatting purposes.
#
# Return:
# Returns 0 after successfully rendering the formatted contributions table.
function print_contributions_dashboard()
{
  local -n _contribs_array="$1"
  local columns="$2"
  local id_width=6
  local date_width=22
  local status_width=10
  local name_width=$(("$columns" - id_width - date_width - status_width - 6))
  local maintainers_ids
  local id
  local name
  local date
  local status
  local caption='Contributions infos'
  local c_caption_width=${#caption}

  trim_width=$(((columns - c_caption_width) / 2))
  remaining_width=$((columns - c_caption_width - trim_width))

  printf "%*s%s%*s\n" "$trim_width" "" "$caption" "$remaining_width" "" | tr ' ' '-'

  printf "%-${id_width}s|%-${name_width}s|%-${date_width}s|%-${status_width}s\n" \
    "ID" "Contribution" "Date" "Status"
  printf "%-${columns}s\n" | tr ' ' '-'

  for item in "${_contribs_array[@]}"; do
    IFS='|' read -r id name date status <<< "$item"
    printf "%-${id_width}s|%-${name_width}s|%-${date_width}s|%-${status_width}s\n" \
      "$id" "$name" "$date" "$status"
  done

  tput cnorm > /dev/tty
  printf "%-${columns}s\n" | tr ' ' '-'
}

# Show submissions dashboard with optional filter by contribution_id.
#
# @flag: Display mode flag (e.g., SILENT)
# @columns: terminal width
# @contribution_id: optional filter (shows only that contribution if set)
function show_submissions_dashboard()
{
  local flag="$1"
  local columns="$2"
  local contribution_id="$3"
  local id
  local status
  local title
  local author_email
  local repository_id
  local created_at
  local repo_name
  local repo_origin_url
  local submission_infos_result
  declare -a submissions_infos_array

  if [[ -z "$columns" ]]; then
    columns="$(tput cols)"
  fi

  if [[ -n "$contribution_id" ]]; then

    condition_array=(['contribution_id']="$contribution_id")
    submission_infos_result=$(get_submission_info 'id, send_by, created_at' 'condition_array')

    if [[ "$?" -ne 0 ]]; then
      complain "$submission_infos_result"
      return 22
    fi

    readarray -t submissions_infos_array <<< "$submission_infos_result"
  else
    condition_array=()
    submission_infos_result=$(select_from "$DATABASE_SUBMISSION_TABLE" 'id, send_by, created_at' '' '')

    if [[ "$?" -ne 0 ]]; then
      complain "$submission_infos_result"
      return 22
    fi

    readarray -t submissions_infos_array <<< "$submission_infos_result"
  fi

  print_submissions_dashboard 'submissions_infos_array' "$columns"
  return 0
}

# This function renders a tabular dashboard displaying a list of 
# submission records. It dynamically calculates the width of the 
# author column based on the terminal's dimensions and fixed-width 
# fields for ID and date. The interface features a centered title 
# and a structured grid where each submission's metadata is 
# aligned for clear visualization. It ensures the terminal cursor 
# is properly managed and uses horizontal delimiters to separate 
# the header, data, and footer sections.
#
# @_contribs_array: Reference to an associative or indexed array 
#                   containing submission metadata (ID, sender, and date).
# @columns: The total width of the terminal display used for 
#           calculating dynamic column spacing.
#
# Return:
# Returns 0 after successfully rendering the formatted submissions table.
function print_submissions_dashboard()
{
  local -n _contribs_array="$1"
  local columns="$2"
  local id_width=6
  local date_width=22
  local send_by_with=$(("$columns" - id_width - date_width - 6))
  local id
  local name
  local date
  local status
  local caption='Submissions infos'
  local c_caption_width=${#caption}

  trim_width=$(((columns - c_caption_width) / 2))
  remaining_width=$((columns - c_caption_width - trim_width))

  printf "%*s%s%*s\n" "$trim_width" "" "$caption" "$remaining_width" "" | tr ' ' '-'

  printf "%-${id_width}s|%-${send_by_with}s|%-${date_width}s\n" \
    "ID" "Send By" "Date"
  printf "%-${columns}s\n" | tr ' ' '-'

  for item in "${_contribs_array[@]}"; do
    IFS='|' read -r id send_by date <<< "$item"
    printf "%-${id_width}s|%-${send_by_with}s|%-${date_width}s\n" \
      "$id" "$send_by" "$date"
  done

  tput cnorm > /dev/tty
  printf "%-${columns}s\n" | tr ' ' '-'
}

# Parses the command-line arguments for the patch track operation.
# It populates the options_values associative array with parsed options.
#
# Return:
# Returns 22 if there are invalid arguments.
function parse_patch_track()
{
  local long_options='help,show-patches,show-contributions,from:,before:,after:,id:,set-status:,set-repository:,contribution-id:,set-maintainer:,repository-id:,update,open-contribution'
  local short_options='d,f:,b:,a:,s:,r:,c:,m:,u,o'
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
  options_values['SHOW_PATCHES']=''
  options_values['SHOW_CONTRIBUTIONS']=''
  options_values['PATCH_ID']=''
  options_values['SET_STATUS']=
  options_values['STATUS']=''
  options_values['FROM']=''
  options_values['BEFORE']=''
  options_values['AFTER']=''
  options_values['CONTRIBUTION_ID']=''
  options_values['SET_REPOSITORY']=''
  options_values['ORIGIN_URL']=''
  options_values['REPOSITORY_ID']=''
  options_values['SET_MAINTAINER']=''
  options_values['MAINTAINER_EMAIL']=''
  options_values['INTERACTIVE']=''
  options_values['OPEN_CONTRIBUTION_ON_MUTT']=''

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --show-patches)
        options_values['SHOW_PATCHES']=1
        shift
        ;;
      --show-contributions | -d)
        options_values['SHOW_CONTRIBUTIONS']=1
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
      --set-repository)
        options_values['SET_REPOSITORY']=$(printf "%s\n" "$2" | cut -d':' -f1)
        options_values['ORIGIN_URL']=$(printf "%s\n" "$2" | cut -d':' -f2-)
        shift 2
        ;;
      --contribution-id | -c)
        options_values['CONTRIBUTION_ID']="$2"
        shift 2
        ;;
      --set-maintainer | -m)
        options_values['SET_MAINTAINER']=$(printf "%s\n" "$2" | cut -d':' -f1)
        options_values['MAINTAINER_EMAIL']=$(printf "%s\n" "$2" | cut -d':' -f2-)
        shift 2
        ;;
      --repository-id | -r)
        options_values['REPOSITORY_ID']="$2"
        shift 2
        ;;
      --update | -u)
        options_values['UPDATE_STATUS']=1
        shift
        ;;
      --open-contribution | -o)
        options_values['OPEN_CONTRIBUTION_ON_MUTT']=1
        shift
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
    '  patch-track (--show-patches) [[--from <YYYY-MM-DD>] | [--after <YYYY-MM-DD>] [--before <YYYY-MM-DD>]] - Show patches dashboard in chronological order ' \
    '  patch-track (-d | --show-contributions) - Show all contributions ' \
    '  patch-track (--id <num>) [-s <status> | --set-status <status>] - Set a patch status ' \
    '  patch-track (-u | --update) - Update patch statuses using heuristics ' \
    '  patch-track (-c | --contribution-id <id>) (--set-repository <name:url>) - Associate a repository to a contribution ' \
    '  patch-track (-r | --repository-id <id>) (-m | --set-maintainer <name:email>) - Associate a maintainer to a repository ' \
    '  patch-track (-c | --contribution-id <id>) (-o | --open-contribution) - Open contribution email thread in mutt '
}

load_patch_track_mutt_config
