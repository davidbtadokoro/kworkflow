include "${KW_LIB_DIR}/lib/kw_db.sh"

declare -gr DATABASE_CONTRIBUTION_TABLE='contribution'
declare -Ag condition_array

function insert_contribution()
{
    local _contribution_title="$1"
    local _author_email="$2"
    local _repository_id="$3"

    # Checagem de valores nulos
    if [[ -z "$_contribution_title" || -z "$_author_email" || -z "$_repository_id" ]]; then
        complain "($LINENO): missing mandatory field(s) for insert_contribution"
        return 22 # EINVAL
    fi

    sql_operation_result=$(insert_into "$DATABASE_CONTRIBUTION_TABLE" \
        '("title", "author_email", "repository_id")' \
        "('${_contribution_title}', '${_author_email}', '${_repository_id}')")

    ret="$?"

    if [[ "$ret" -eq 2 || "$ret" -eq 61 ]]; then
        complain "$sql_operation_result"
        return 22 # EINVAL
    elif [[ "$ret" -ne 0 ]]; then
        complain "($LINENO):" $'Error while trying to insert new contribution:\n'"$sql_operation_result"
        return 22 # EINVAL
    fi

    return 0
}

function new_contribution()
{
    local _contribution_title="$1"
    local _author_email="$2"
    local _repository_id="$3"
    local sql_operation_result
    local insert_contribution_result
    local get_contribution_id_result

    # Checagem de valores nulos
    if [[ -z "$_contribution_title" || -z "$_author_email" || -z "$_repository_id" ]]; then
        complain "($LINENO): missing mandatory field(s) for new_contribution"
        return 22 # EINVAL
    fi

    #patch_existent_result="$(check_contribution_existence_by_title "$_contribution_title")"
    #ret="$?"

    #if [[ "$ret" -ne 0 ]]; then
    #    complain "$patch_existent_result"
    #    return "$ret"
    #fi

    #if [[ "$patch_existent_result" -ne 0 ]]; then
    #    complain "($LINENO): error while trying to create new contribution ${_contribution_title}, contribution already exists"
    #    return 22 # EINVAL
    #fi

    insert_contribution_result=$(insert_contribution "$_contribution_title" "$_author_email" "$_repository_id")
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "$insert_contribution_result"
        return "$ret"
    fi

    get_contribution_id_result=$(get_contribution_info_by_title 'id' "$_contribution_title")
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "$get_contribution_id_result"
        return "$ret"
    fi

    printf '%s\n' "$get_contribution_id_result"
    return 0
}

function check_contribution_existence_by_title()
{
    local _contribution_title="$1"
    local sql_operation_result
    local ret

    # Checagem de valor nulo
    if [[ -z "$_contribution_title" ]]; then
        complain "($LINENO): empty contribution title for check_contribution_existence_by_title"
        return 22 # EINVAL
    fi

    sql_operation_result="$(check_existence "$DATABASE_CONTRIBUTION_TABLE" "$_contribution_title")"
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

function get_contribution_info_by_title()
{
    local _contribution_infos="$1"
    local _contribution_title="$2"
    local sql_operation_result
    local ret

    if [[ -z "$_contribution_title" ]]; then
        complain "($LINENO): empty contribution title for get_contribution_info_by_title"
        return 22 # EINVAL
    fi

    condition_array=(['title']="${_contribution_title}")

    sql_operation_result="$(get_contribution_info "$_contribution_infos" 'condition_array')"
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "$sql_operation_result"
        return "$ret"
    fi

    printf '%s\n' "$sql_operation_result"
    return 0
}

function get_contribution_info()
{
    local _contribution_infos="$1"
    local -n _contrib_info_condition_array="$2"
    local sql_operation_result
    local ret

    sql_operation_result="$(get_database_table_info "$DATABASE_CONTRIBUTION_TABLE" "$_contribution_infos" '_contrib_info_condition_array')"
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "$sql_operation_result"
        return 22 # EINVAL
    fi

    printf '%s\n' "$sql_operation_result"
    return 0
}
