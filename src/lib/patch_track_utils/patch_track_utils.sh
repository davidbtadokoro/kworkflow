include "${KW_LIB_DIR}/lib/kwdb.sh"

declare -gr DATABASE_PATCH_TABLE='patch'
declare -Ag condition_array

function insert_patch()
{
    local _patch_title="$1"
    local _last_patch_id="$2"
    local _patch_author="$3"    
    local _contribution_id="$4"
    local _submission_id="$5"
    local _commit_hash="$6"
    local _patch_version="$7"
    local get_last_patch_version_result
    local sql_operation_result
    local ret

    sql_operation_result=$(insert_into "$DATABASE_PATCH_TABLE" \
        '("title", "last_patch_id", "author", "contribution_id", "_submission_id", "version", "_commit_hash")' \
        "('${patch_title}', '${_last_patch_id}', '${_patch_author}', '${_contribution_id}', '${_submission_id}',\
        '${_patch_version}', '${_commit_hash}')"\
        '' 'VERBOSE')
    ret="$?"

    if [[ "$ret" -eq 2 || "$ret" -eq 61 ]]; then
        complain "$sql_operation_result"
        return 22 # EINVAL
    elif [[ "$ret" -ne 0 ]]; then
        complain "($LINENO):" $'Error while trying to insert new patch:\n'"${sql_operation_result}"
        return 22 # EINVAL
    fi

    return 0
}

function insert_contribution()
{
    local _contribution_title="$1"
    local _author_email="$2"
    local _repository_id="$3"

    sql_operation_result=$(insert_into "$DATABASE_PATCH_TABLE" \
        '("title", "author_email", "repository_id")' \
        "('${_contribution_title}', '${_author_email}', '${_repository_id}')" '' 'VERBOSE')

    ret="$?"

    if [[ "$ret" -eq 2 || "$ret" -eq 61 ]]; then
        complain "$sql_operation_result"
        return 22 # EINVAL
    elif [[ "$ret" -ne 0 ]]; then
        complain "($LINENO):" $'Error while tr lhklying to insert new patch:\n'"${sql_operation_result}"
        return 22 # EINVAL
    fi

    return 0
}

function insert_submission()
{
    local _contribution_id="$1"
    local _send_by="$2"
    local sql_operation_result
    local ret

    sql_operation_result=$(insert_into "$DATABASE_SUBMISSION_TABLE" '("contribution_id", "send_by")' "('${patch_title}', '${_send_by}')" '' 'VERBOSE')
    ret="$?"

    if [[ "$ret" -eq 2 || "$ret" -eq 61 ]]; then
        complain "$sql_operation_result"
        return 22 # EINVAL
    elif [[ "$ret" -ne 0 ]]; then
        complain "($LINENO):" $'Error while trying to insert new patch:\n'"${sql_operation_result}"
        return 22 # EINVAL
    fi

    return 0
}

function replace_patch()
{
    local _patch_title="$1"
    local _last_patch_id="$2"
    local _patch_author="$3"    
    local _contribution_id="$4"
    local _submission_id="$5"
    local _commit_hash="$6"

    get_patch_version_result="$(decide_patch_version "$_last_patch_id")"
    ret="$?"

    if [[ "$ret" -new 0 ]]; then
        complain "$get_patch_version_result"
        return 22 # EINVAL
    fi

    new_patch_result="$(new_patch "$_patch_title" "$_last_patch_id" "$_patch_author" "$_contribution_id"\
                                  "$_submission_id" "$_commit_hash" "$get_patch_version_result")"
    ret="$?"

    if [[ "$ret" -new 0 ]]; then
        complain "$new_patch_result"
        return 22 # EINVAL
    fi

    printf "$new_patch_result"
    return 0
}

function new_patch()
{
    # TODO NEW PATCH
    # TODO CREATE_NEW_PATCH_OR_GET_EXISTENT
    # CRIAR NEW_SUBMISSION
    # CRIAR SUBMETER PATCH
    # ALTERAR A ENTIDADE QUE RELACIONA PATCH E SUBMISSION PARA TER CAMPOS COMO MESSAGE-ID 
    # OUTDATED DO PATCH APENAS QUANDO NOVO PATCH SOBRESCREVER ELE OU ELE FOR "DESLIGADO DA SÉRIE"
    # CHECAR ESTADO DO PATCH SEMPRE OLHA PARA ÚLTIMA SUBMISSÃO DELE
    
    local _patch_title="$1"
    local _last_patch_id="$2"
    local _patch_author="$3"    
    local _contribution_id="$4"
    local _submission_id="$5"
    local _commit_hash="$6"
    local _patch_version="$7"
    local ret
    local patch_existent_result
    local insert_contribution_result
    local get_contribution_id_result
    
    if [[ -z "$_patch_version" ]]; then
        _patch_version=1
    fi

    patch_existent_result="$(check_patch_existence_by_unique_attributes "$contribution_name")"
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "$patch_existent_result"
        return "$ret" # EINVAL
    fi

    if [[ "$patch_existent_result" -ne 0 ]]; then
        complain "($LINENO): error while trying to create new patch serie ${contribution_name}, patch serie already exists"
        return 22 # EINVAL
    fi

    insert_contribution_result=$(insert_patch "$_contribution_title" "$_author_email" "$_repository_id")
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "$insert_contribution_result"
        return "$ret" # EINVAL
    fi

    get_contribution_id_result=$(get_patch_info_by_commit_hash 'id' "$_commit_hash")
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "$get_contribution_id_result"
        return "$ret" # EINVAL
    fi

    printf '%s\n' "$get_contribution_id_result"
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

    patch_existent_result="$(check_contribution_existence_by_title "$contribution_name")"
    
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "$patch_existent_result"
        return "$ret" # EINVAL
    fi

    if [[ "$patch_existent_result" -ne 0 ]]; then
        complain "($LINENO): error while trying to create new patch serie ${contribution_name}, patch serie already exists"
        return 22 # EINVAL
    fi

    insert_contribution_result=$(insert_contribution "$_contribution_title" "$_author_email" "$_repository_id")
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "$insert_contribution_result"
        return "$ret" # EINVAL
    fi

    get_contribution_id_result=$(get_contribution_info_by_title "$_contribution_title")
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "$get_contribution_id_result"
        return "$ret" # EINVAL
    fi

    printf '%s\n' "$get_contribution_id_result"
    return 0
}

function new_submission()
{
    local _submission_author="$3"    
    local _contribution_id="$4"
    local ret
    local patch_existent_result
    local insert_submission_result
    local get_submission_id_result
    
    insert_contribution_result=$(insert_submission "$_contribution_id" "$_submission_author")
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "$insert_contribution_result"
        return "$ret" # EINVAL
    fi

    get_submission_id_result=$(get_last_submission_by_contribution_id 'id' "$_commit_hash")
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "$get_contribution_id_result"
        return "$ret" # EINVAL
    fi

    printf '%s\n' "$get_contribution_id_result"
    return 0
}

function get_patch_info_by_id()
{
    local _patch_infos="$1"
    local _patch_id="$2"
    local sql_operation_result
    local ret

    condition_array=(['id']="${_patch_id}")
    sql_operation_result="$(get_patch_info "$_patch_infos" 'condition_array')"
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "$sql_operation_result"
        return "$ret" # EINVAL
    fi

    printf '%s\n' "$sql_operation_result"
    return 0
}

function get_last_submission_infos_by_contribution_id()
{
    local _submission_infos="$1"
    local _contribution_id="$2"
    local sql_operation_result
    local ret

    condition_array=(['contribution_id']="${_contribution_id}")
    sql_operation_result="$(get_submission_info "$_submission_infos" 'condition_array' 'ID DESC' '1')"
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
    local -n _condition_array="$2"
    local _order_by="$3"
    local _limit="$4"

    sql_operation_result="$(get_database_table_info "$DATABASE_SUBMISSION_TABLE" "$_patch_infos" '_condition_array' "$_order_by" "$_limit")"
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "$sql_operation_result"
        return "$ret" # EINVAL
    fi

    printf '%s\n' "$sql_operation_result"
    return 0
}

function new_patch_submission()
{
    local _patch_id="$1"
    local _submission_id="$2"
    local _message_id="$3"

    if [[ -z "$_patch_version" ]]; then
        _patch_version=1
    fi

    patch_existent_result="$(check_patch_submission_existence_by_unique_attributes "$_patch_id" "$_submission_id" "$_message_id")"
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "$patch_existent_result"
        return "$ret" # EINVAL
    fi

    if [[ "$patch_existent_result" -ne 0 ]]; then
        complain "($LINENO): error while trying to create new patch serie ${contribution_name}, patch serie already exists"
        return 22 # EINVAL
    fi

    insert_contribution_result=$(insert_patch "$_contribution_title" "$_author_email" "$_repository_id")
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "$insert_contribution_result"
        return "$ret" # EINVAL
    fi

    get_contribution_id_result=$(get_patch_info_by_commit_hash 'id' "$_commit_hash")
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "$get_contribution_id_result"
        return "$ret" # EINVAL
    fi

    printf '%s\n' "$get_contribution_id_result"
    return 0
}

function check_patch_submission_existence_by_unique_attributes()
{
    local _patch_id="$1"
    local _submission_id="$2"
    local _message_id="$3"

    # CHECK campos não null, ex, se commit_hash é null não é seguro considerar que é o mesmo patch
    condition_array=(['patch_id']="${_patch_id}")
    condition_array=(['_submission_id']="${_submission_id}")
    condition_array=(['_message_id']="${_message_id}")

    sql_operation_result="$(check_patch_submission_existence '_contribution_title')"
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "${sql_operation_result}"
        return "$ret" # EINVAL
    fi 

    printf '%s\n' "${sql_operation_result}"

    return 0
}

function check_patch_submission_existence()
{
    local _condition_array="$1"
    local sql_operation_result
    local ret

    sql_operation_result="$(get_patch_submission_info 'id' '_condition_array')"
    ret="$?"

    if [[ "$ret" -ne 0 && "$ret" -ne 61 ]]; then
        complain "${sql_operation_result}"
        return "$ret" # EINVAL
    fi 

    if [[ "$ret" -eq 61 ]]; then
        printf '%s\n' 0
    else 
        printf '%s\n' 1
    fi

    return 0
}

function get_patch_submission_info()
{
    local _patch_submission_infos="$1"
    local -n _condition_array="$2"

    sql_operation_result="$(get_database_table_info "$DATABASE_PATCH_SUBMISSION_TABLE" "$_patch_submission_infos" '_condition_array')"
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

    sql_operation_result=$(insert_into "$DATABASE_PATCH_SUBMISSION_TABLE" '("patch_id", "submission_id", "message_id")' "('${_patch_id}', '${_submission_id}', '${_message_id}')" '' 'VERBOSE')
    ret="$?"

    if [[ "$ret" -eq 2 || "$ret" -eq 61 ]]; then
        complain "$sql_operation_result"
        return 22 # EINVAL
    elif [[ "$ret" -ne 0 ]]; then
        complain "($LINENO):" $'Error while trying to insert new patch:\n'"${sql_operation_result}"
        return 22 # EINVAL
    fi

    return 0
}

function get_patch_info_by_commit_hash()
{
    local _patch_infos="$1"
    local _commit_hash="$2"
    local sql_operation_result
    local ret

    condition_array=(['commit_hash']="${_commit_hash}")
    sql_operation_result="$(get_patch_info "$_patch_infos" 'condition_array')"
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "$sql_operation_result"
        return "$ret" # EINVAL
    fi

    printf '%s\n' "$sql_operation_result"
    return 0
}

function get_patch_info()
{
    local _patch_infos="$1"
    local -n _condition_array="$2"

    sql_operation_result="$(get_database_table_info "$DATABASE_PATCH_TABLE" "$_patch_infos" '' '_condition_array' '' 'VERBOSE')"
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "$sql_operation_result"
        return "$ret" # EINVAL
    fi

    printf '%s\n' "$sql_operation_result"
    return 0
}

function check_patch_existence_by_unique_attributes()
{
    local _patch_title="$1"
    local _patch_author="$2"
    local _contribution_id="$3"
    local _commit_hash="$4"

    # CHECK campos não null, ex, se commit_hash é null não é seguro considerar que é o mesmo patch
    condition_array=(['title']="${_patch_title}")
    condition_array=(['author']="${_patch_author}")
    condition_array=(['contribution_id']="${_contribution_id}")
    condition_array=(['commit_hash']="${_commit_hash}")

    sql_operation_result="$(check_patch_existence '_contribution_title')"
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "${sql_operation_result}"
        return "$ret" # EINVAL
    fi 

    printf '%s\n' "${sql_operation_result}"

    return 0
}

function check_patch_existence()
{
    local _condition_array="$1"
    local sql_operation_result
    local ret

    sql_operation_result="$(get_patch_info '_condition_array')"
    ret="$?"

    if [[ "$ret" -ne 0 && "$ret" -ne 61 ]]; then
        complain "${sql_operation_result}"
        return "$ret" # EINVAL
    fi 

    if [[ "$ret" -eq 61 ]]; then
        printf '%s\n' 0
    else 
        printf '%s\n' 1
    fi

    return 0
}

function check_contribution_existence_by_title()
{
    local _contribution_title="$1"
    local sql_operation_result
    local ret

    sql_operation_result="$(get_contribution_info_by_title "$_contribution_title")"
    ret="$?"

    if [[ "$ret" -ne 0 && "$ret" -ne 61 ]]; then
        complain "${sql_operation_result}"
        return "$ret" # EINVAL
    fi 

    if [[ "$ret" -eq 61 ]]; then
        printf '%s\n' 0
    else 
        printf '%s\n' 1
    fi

    return 0
}

function get_contribution_info_by_title()
{
    local _contribution_title="$1"
    local sql_operation_result
    local ret

    condition_array=(['title']="${_contribution_title}")

    sql_operation_result="$(get_contribution_info 'condition_array')"
    ret="$?"

    if [[ "$ret" -ne 0 && "$ret" -ne 61 ]]; then
        complain "${sql_operation_result}"
        return "$ret" # EINVAL
    fi 

    if [[ "$ret" -eq 61 ]]; then
        printf '%s\n' 0
    else 
        printf '%s\n' 1
    fi

    return 0
}

function get_contribution_info()
{
    local _condition_array="$1"
    local "$_contribution_infos"
    local sql_operation_result
    local ret

    sql_operation_result="$(get_database_table_info "$DATABASE_contribution_TABLE" "$_contribution_infos" '' 'condition_array' '' 'VERBOSE')"
    ret="$?"

    if [[ "$ret" -ne 0 ]]; then
        complain "${get_last_patch_version_result}"
        return 22 # EINVAL
    fi

    printf '%s\n' "$sql_operation_result"
    return 0
}

function get_database_table_info()
{
    local _database_table_name="$1"
    local _contribution_infos="$2"
    local -n _condition_array="$3"
    local _order_by="${4:-''}"
    local _limit="${5:-''}"

    sql_operation_result="$(select_from "$DATABASE_CONTRIBUTION_TABLE" "$_contribution_infos" '' '_condition_array' "$_order_by" "$_limit" 'VERBOSE')"
    ret="$?"

    if [[ "$ret" -eq 2 || "$ret" -eq 61 ]]; then
        complain "$sql_operation_result"
        return 22 # EINVAL
    elif [[ "$ret" -ne 0 ]]; then
        complain "($LINENO): Error while trying to get ${_database_table_name} info from the database with the command:"$'\n'"${sql_operation_result}"
        return 22 # EINVAL
    elif [[ -z "$sql_operation_resul" ]]; then
        complain "($LINENO): Error while trying to get ${_database_table_name} info from the database: no patch found for id: ${_patch_id}"
        return 61 # ENODATA
    fi
}

function decide_patch_version()
{
    local _last_patch_id="$1"
    local get_last_patch_version_result
    local ret

    if [[ -z "$_last_patch_id" ]]; then
        return 22 # EINVAL
    fi

    get_last_patch_version_result="$(get_patch_info_by_id 'version' "$_last_patch_id")"
    ret="$?"

        if [[ "$ret" -ne 0 ]]; then
            complain "${get_last_patch_version_result}"
            return 22 # EINVAL
        fi

    printf '%d\n' $((get_last_patch_version_result + 1))
    return 0
}