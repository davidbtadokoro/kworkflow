#!/usr/bin/env bash

include './src/patch_track.sh'
include './src/lib/patch_track_utils/patch_utils.sh'
include './src/lib/patch_track_utils/contribution_utils.sh'
include './src/lib/patch_track_utils/submission_utils.sh'
include './src/lib/kw_db.sh'
include './tests/unit/utils.sh'

function oneTimeSetUp()
{
  declare -g DB_FILES

  export KW_ETC_DIR="${SHUNIT_TMPDIR}/etc/"
  export KW_CACHE_DIR="${SHUNIT_TMPDIR}/cache/"
  export KW_DATA_DIR="${SHUNIT_TMPDIR}"

  DB_FILES="$(realpath './tests/unit/samples/db_files')"
  KW_DB_DIR="$(realpath './database')"
}

function setUp()
{
  declare -gA options_values
  declare -gA set_confs

  setupDatabase
}

function tearDown()
{
  unset options_values
  unset set_confs

  tearDownDatabase
}

function setupDatabase()
{
  declare -g TEST_PATCH_TITLE='TEST_PATCH'
  declare -g TEST_PATCH_ID

  execute_sql_script "${KW_DB_DIR}/kwdb.sql" > /dev/null 2>&1
  #sqlite3 "${KW_DATA_DIR}/kw.db" -batch "INSERT INTO \"${DATABASE_PATCH_TABLE}\" (title) VALUES (\"${TEST_PATCH_TITLE}\");"
  #TEST_PATCH_ID="$(sqlite3 "${KW_DATA_DIR}/kw.db" -batch "SELECT id FROM \"${DATABASE_PATCH_TABLE}\" WHERE title='${TEST_PATCH_TITLE}';")"

  # --- Criação de uma contribution inicial ---
  TEST_CONTRIBUTION_TITLE='TEST_CONTRIBUTION'
  sqlite3 "${KW_DATA_DIR}/kw.db" -batch "INSERT INTO contribution (title, author_email, repository_id) VALUES ('${TEST_CONTRIBUTION_TITLE}', 'test@example.com', 1);"
  TEST_CONTRIBUTION_ID="$(sqlite3 "${KW_DATA_DIR}/kw.db" -batch "SELECT id FROM contribution WHERE title='${TEST_CONTRIBUTION_TITLE}';")"

  # --- Criação de uma submission inicial ---
  TEST_SUBMISSION_AUTHOR='test@example.com'
  sqlite3 "${KW_DATA_DIR}/kw.db" -batch "INSERT INTO submission (contribution_id, send_by) VALUES ('${TEST_CONTRIBUTION_ID}', '${TEST_SUBMISSION_AUTHOR}');"
  TEST_SUBMISSION_ID="$(sqlite3 "${KW_DATA_DIR}/kw.db" -batch "SELECT id FROM submission WHERE contribution_id='${TEST_CONTRIBUTION_ID}' ORDER BY id DESC LIMIT 1;")"

  # --- Criação de um patch inicial ---
  TEST_PATCH_TITLE='TEST_PATCH'
  sqlite3 "${KW_DATA_DIR}/kw.db" -batch "INSERT INTO patch (title, author, contribution_id, commit_hash, version) VALUES ('${TEST_PATCH_TITLE}', '${TEST_SUBMISSION_AUTHOR}', '${TEST_CONTRIBUTION_ID}', 'abc123', 1);"
  TEST_PATCH_ID="$(sqlite3 "${KW_DATA_DIR}/kw.db" -batch "SELECT id FROM patch WHERE title='${TEST_PATCH_TITLE}';")"

  TEST_REPOSITORY_TITLE='TEST_REPOSITORY'
  sqlite3 "${KW_DATA_DIR}/kw.db" -batch "INSERT INTO repository (name, origin_url, branch_name) VALUES ('${TEST_REPOSITORY_TITLE}', '${TEST_SUBMISSION_AUTHOR}', 'branch');"
  TEST_PATCH_ID="$(sqlite3 "${KW_DATA_DIR}/kw.db" -batch "SELECT id FROM repository WHERE name='${TEST_REPOSITORY_TITLE}';")"
}

function tearDownDatabase()
{
  is_safe_path_to_remove "${KW_DATA_DIR}/kw.db"
  if [[ "$?" == 0 ]]; then
    rm "${KW_DATA_DIR}/kw.db"
  fi
}

function test_check_patch_existence()
{
  local output
  local ret
  local expected
  local patch_title='TEST_PATCH'
  local patch_author='test_author'
  local contribution_id=1
  local commit_hash='abc123'

    
  sqlite3 "${KW_DATA_DIR}/kw.db" -batch \
    "INSERT INTO \"${DATABASE_PATCH_TABLE}\" (title, author, contribution_id, commit_hash, version) \
    VALUES ('TEST_PATCH', 'test_author', 1, 'abc123', 1);"

  output=$(check_patch_existence_by_unique_attributes "$patch_title" "$patch_author" "$contribution_id" "$commit_hash")
  expected=1
  ret="$?"

  assert_equals_helper 'The patch should exist' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected success' "$LINENO" 0 "$ret"

  output=$(check_patch_existence_by_unique_attributes "patch_title" "patch_author" "contribution_id" "commit_hash")
  expected=0
  ret="$?"

  assert_equals_helper 'The patch should not not exist' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected success' "$LINENO" 0 "$ret"
}

function test_decide_patch_version()
{
  local output
  local ret

  # id de patch válido de teste
  local last_patch_id=1

  output=$(decide_patch_version "$last_patch_id")
  ret="$?"
  expected=2
  # verifica se retornou sucesso
  assert_equals_helper 'The group should have been created' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected success' "$LINENO" 0 "$ret"
}

function test_get_database_table_info() {
    local patch_id
    local result

    # Insere um patch para teste
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO patch (title, author, contribution_id, commit_hash, version) VALUES ('TEST_PATCH', 'test_author', 1, 'cde123', 1);"
    patch_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM patch WHERE commit_hash='cde123';")"

    declare -A cond_array=(['id']="$patch_id")
    result="$(get_database_table_info 'patch' 'id' 'cond_array')"
    ret="$?"

    assert_equals_helper 'Expected get_database_table_info to succeed' "$LINENO" 0 "$ret"
    assert_equals_helper 'Expected get_database_table_info to succeed' "$LINENO" "$patch_id" "$result"
}

function test_check_existence() {
    local patch_id
    local result

    # Insere um patch para teste
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO patch (title, author, contribution_id, commit_hash, version) VALUES ('EXISTING_PATCH', 'author_test', 2, 'def456', 1);"
    patch_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM patch WHERE title='EXISTING_PATCH';")"

    declare -A cond_array=(['id']="$patch_id")
    result="$(check_existence 'patch' 'cond_array')"
    ret="$?"

    assert_equals_helper 'Expected check_existence to succeed' "$LINENO" 0 "$ret"
    assert_equals_helper 'Expected existence to return 1' "$LINENO" 1 "$result"

    declare -A cond_array=(['id']="150")
    result="$(check_existence 'patch' 'cond_array')"
    ret="$?"

    assert_equals_helper 'Expected check_existence to succeed' "$LINENO" 0 "$ret"
    assert_equals_helper 'Expected existence to return 0' "$LINENO" 0 "$result"
}

function test_get_patch_info() {
    local patch_id
    local result

    # Insere patch válido
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO patch (title, author, contribution_id, commit_hash, version) VALUES ('PATCH_INFO', 'authorX', 3, 'hash123', 1);"
    patch_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM patch WHERE commit_hash='hash123';")"

    declare -A cond_array=(['id']="$patch_id")
    result="$(get_patch_info 'id,title,commit_hash' cond_array)"
    ret="$?"

    assert_equals_helper 'Expected get_patch_info to succeed' "$LINENO" 0 "$ret"
    assertContains "$result" "hash123"
    assertContains "$result" "PATCH_INFO"
}

function test_get_patch_info_by_commit_hash() {
    local result

    # Insere patch válido
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO patch (title, author, contribution_id, commit_hash, version) VALUES ('PATCH_BY_HASH', 'authorY', 4, 'hash999', 2);"

    result="$(get_patch_info_by_commit_hash 'id,title,author,commit_hash' 'hash999')"
    ret="$?"

    assert_equals_helper 'Expected get_patch_info_by_commit_hash to succeed' "$LINENO" 0 "$ret"
    assertContains "$result" "hash999"
    assertContains "$result" "PATCH_BY_HASH"
}

function test_new_patch() {
    local result
    local ret
    local patch_id

    # Criar novo patch
    result="$(new_patch 'PATCH_OK' '' 'authorx@email' 1 'hash777' 1)"
    ret="$?"

    assert_equals_helper 'Expected new_patch to succeed' "$LINENO" 0 "$ret"

    # Conferir que id retornado corresponde a um patch no banco
    patch_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM patch WHERE commit_hash='hash777';")"
    assertEquals "Patch id returned must match db record" "$patch_id" "$result"
}

function test_get_patch_info_by_id() {
    local result
    local ret
    local patch_id

    # Inserir patch diretamente
    sqlite3 "${KW_DATA_DIR}/kw.db" \
        "INSERT INTO patch (id, title, author, contribution_id, commit_hash, version) \
         VALUES (120, 'PATCH_INFO_ID', 'authorY', 1, 'hash888', 2);"
    patch_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM patch WHERE commit_hash='hash888';")"

    # Buscar patch pelo id
    result="$(get_patch_info_by_id 'id,title,commit_hash' "$patch_id")"
    ret="$?"

    assert_equals_helper 'Expected get_patch_info_by_id to succeed' "$LINENO" 0 "$ret"
    assertContains "$result" "hash888"
    assertContains "$result" "PATCH_INFO_ID"
}

function test_insert_submission() {
    output="$(insert_submission '1' "test_insert_submission@example.com")"
    ret="$?"
    assert_equals_helper 'insert_submission should succeed' "$LINENO" 0 "$ret"

    count="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT COUNT(*) FROM submission WHERE contribution_id=1 AND send_by='test_insert_submission@example.com';")"
    assert_equals_helper 'submission row must exist' "$LINENO" 1 "$count"
}

function test_get_last_submission_infos_by_contribution_id() {
    # prepara contribution e duas submissions
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO contribution (title, author_email, repository_id) VALUES ('C_TEST3', 'c@t', 3);"
    contrib_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM contribution WHERE title='C_TEST3' LIMIT 1;")"
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO submission (contribution_id, send_by) VALUES (${contrib_id}, 's1');"
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO submission (contribution_id, send_by) VALUES (${contrib_id}, 's2');"
    last_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM submission WHERE contribution_id=${contrib_id} ORDER BY id DESC LIMIT 1;")"

    output="$(get_last_submission_infos_by_contribution_id 'id' "$contrib_id")"
    ret="$?"
    assert_equals_helper 'get_last_submission_infos_by_contribution_id should succeed' "$LINENO" 0 "$ret"
    assertContains "$output" "$last_id"
}

function test_get_submission_info() {
    # prepara contribution + submission
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO contribution (title, author_email, repository_id) VALUES ('C_TEST4', 'd@t', 4);"
    contrib_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM contribution WHERE title='C_TEST4' LIMIT 1;")"
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO submission (contribution_id, send_by) VALUES (${contrib_id}, 'senderX');"
    sub_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM submission WHERE contribution_id=${contrib_id} ORDER BY id DESC LIMIT 1;")"

    # definir array com o nome esperado internamente
    declare -gA _submission_test_condition_array
    _submission_test_condition_array=( ['contribution_id']="${contrib_id}" )

    output="$(get_submission_info 'id,send_by' '_submission_test_condition_array' 'id DESC' '1')"
    ret="$?"
    assert_equals_helper 'get_submission_info should succeed' "$LINENO" 0 "$ret"
    assertContains "$output" "${sub_id}"
    assertContains "$output" "senderX"
}

function test_new_submission() {
    # prepara contribution
    output="$(new_submission '1' "test_new_submission@email.com")"
    ret="$?"
    assert_equals_helper 'new_submission should return success' "$LINENO" 0 "$ret"

    db_last_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM submission WHERE contribution_id=${contrib_id} ORDER BY id DESC LIMIT 1;")"
    assert_equals_helper 'returned id must match last insertion' "$LINENO" "$db_last_id" "$output"
}

function test_insert_patch_submission() {
    # prepara contribution, submission, patch
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO contribution (title, author_email, repository_id) VALUES ('C_TEST5', 'e@t', 5);"
    contrib_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM contribution WHERE title='C_TEST5' LIMIT 1;")"
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO submission (contribution_id, send_by) VALUES (${contrib_id}, 'snd');"
    submission_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM submission WHERE contribution_id=${contrib_id} ORDER BY id DESC LIMIT 1;")"
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO patch (title, author, contribution_id, commit_hash, version) VALUES ('PATCH_A', 'authorA', ${contrib_id}, 'hA', 1);"
    patch_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM patch WHERE commit_hash='hA' LIMIT 1;")"

    output="$(insert_patch_submission "$patch_id" "$submission_id" "msg-1")"
    ret="$?"
    assert_equals_helper 'insert_patch_submission should succeed' "$LINENO" 0 "$ret"

    count="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT COUNT(*) FROM patch_submission WHERE patch_id=${patch_id} AND submission_id=${submission_id} AND message_id='msg-1';")"
    assert_equals_helper 'patch_submission row must exist' "$LINENO" 1 "$count"
}

function test_new_patch_submission() {
    # prepara contribution, submission, patch
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO contribution (title, author_email, repository_id) VALUES ('C_TEST6', 'f@t', 6);"
    contrib_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM contribution WHERE title='C_TEST6' LIMIT 1;")"
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO submission (contribution_id, send_by) VALUES (${contrib_id}, 'snd2');"
    submission_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM submission WHERE contribution_id=${contrib_id} ORDER BY id DESC LIMIT 1;")"
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO patch (title, author, contribution_id, commit_hash, version) VALUES ('PATCH_B', 'authorB', ${contrib_id}, 'hB', 1);"
    patch_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM patch WHERE commit_hash='hB' LIMIT 1;")"

    output="$(new_patch_submission "$patch_id" "$submission_id" "msg-2")"
    ret="$?"
    assert_equals_helper 'new_patch_submission should succeed' "$LINENO" 0 "$ret"

    count="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT COUNT(*) FROM patch_submission WHERE patch_id=${patch_id} AND submission_id=${submission_id} AND message_id='msg-2';")"
    assert_equals_helper 'patch_submission row must exist after new_patch_submission' "$LINENO" 1 "$count"
}

function test_check_patch_submission_existence_by_unique_attributes() {
    # prepara contribution, submission, patch + relation
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO contribution (title, author_email, repository_id) VALUES ('C_TEST7', 'g@t', 7);"
    contrib_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM contribution WHERE title='C_TEST7' LIMIT 1;")"
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO submission (contribution_id, send_by) VALUES (${contrib_id}, 'snd3');"
    submission_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM submission WHERE contribution_id=${contrib_id} ORDER BY id DESC LIMIT 1;")"
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO patch (title, author, contribution_id, commit_hash, version) VALUES ('PATCH_C', 'authorC', ${contrib_id}, 'hC', 1);"
    patch_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM patch WHERE commit_hash='hC' LIMIT 1;")"
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO patch_submission (patch_id, submission_id, message_id) VALUES (${patch_id}, ${submission_id}, 'msg-exist');"

    output="$(check_patch_submission_existence_by_unique_attributes "$patch_id" "$submission_id" 'msg-exist')"
    ret="$?"
    assert_equals_helper 'check_patch_submission_existence_by_unique_attributes should succeed' "$LINENO" 0 "$ret"
    assert_equals_helper 'existence must be reported as 1' "$LINENO" 1 "$output"
}

function test_get_patch_submission_info() {
    # prepara relation
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO contribution (title, author_email, repository_id) VALUES ('C_TEST8', 'h@t', 8);"
    contrib_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM contribution WHERE title='C_TEST8' LIMIT 1;")"
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO submission (contribution_id, send_by) VALUES (${contrib_id}, 'snd4');"
    submission_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM submission WHERE contribution_id=${contrib_id} ORDER BY id DESC LIMIT 1;")"
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO patch (title, author, contribution_id, commit_hash, version) VALUES ('PATCH_D', 'authorD', ${contrib_id}, 'hD', 1);"
    patch_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM patch WHERE commit_hash='hD' LIMIT 1;")"
    sqlite3 "${KW_DATA_DIR}/kw.db" "INSERT INTO patch_submission (patch_id, submission_id, message_id) VALUES (${patch_id}, ${submission_id}, 'msg-info');"

    declare -gA _patch_submission_test_condition_array
    _patch_submission_test_condition_array=( ['patch_id']="${patch_id}" )

    output="$(get_patch_submission_info 'submission_id,message_id' _patch_submission_test_condition_array)"
    ret="$?"
    assert_equals_helper 'get_patch_submission_info should succeed' "$LINENO" 0 "$ret"
    assertContains "$output" "msg-info"
    assertContains "$output" "${submission_id}"
}

function test_insert_contribution_success() {
    insert_contribution "Contrib Test 1" "user1@example.com" 1
    ret="$?"
    assertEquals "insert_contribution should succeed" 0 "$ret"

    db_count="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT COUNT(*) FROM contribution WHERE title='Contrib Test 1' AND author_email='user1@example.com' AND repository_id=1;")"
    assertEquals "Contribution should exist in DB" 1 "$db_count"
}

function test_new_contribution_success() {
    output="$(new_contribution "Contrib Test 2" "user2@example.com" 1)"
    ret="$?"

    db_id="$(sqlite3 "${KW_DATA_DIR}/kw.db" "SELECT id FROM contribution WHERE title='Contrib Test 2';")"
    assert_equals_helper "Returned ID should match DB" "$LINENO" "$db_id" "$output"
    assert_equals_helper "new_contribution_success" "$LINENO" "$ret" 0
}

function test_check_contribution_existence_by_title_success() {
    output="$(check_contribution_existence_by_title "TEST_CONTRIBUTION")"
    ret="$?"
    assert_equals_helper "check_contribution_existence_by_title should succeed" "$LINENO" 0 "$ret"
    assert_equals_helper "Existence check should return 1" "$LINENO" 1 "$output"
}

function test_get_contribution_info_by_title_success() {
    output="$(get_contribution_info_by_title 'id' 'TEST_CONTRIBUTION')"
    ret="$?"
    assert_equals_helper "get_contribution_info_by_title should succeed" "$LINENO" 0 "$ret"
    assert_equals_helper "Output ID should not be null" "$LINENO" 1 "$output"
}

function test_get_contribution_info_success() {
    condition_array=(['title']="TEST_CONTRIBUTION")
    output="$(get_contribution_info 'id' 'condition_array')"
    ret="$?"
    assert_equals_helper "get_contribution_info should succeed" "$LINENO" 0 "$ret"
    assert_equals_helper "Output ID should not be null" "$LINENO" 1 "$output"
}

invoke_shunit
