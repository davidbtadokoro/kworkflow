include "${KW_LIB_DIR}/lib/kw_db.sh"

declare -gr DATABASE_SUBMISSION_TABLE='submission'
declare -gr DATABASE_PATCH_SUBMISSION_TABLE='patch_submission'
declare -Ag patch_track_condition_array

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
