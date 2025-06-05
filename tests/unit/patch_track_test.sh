#!/usr/bin/env bash

include './src/patch_track.sh'
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
  sqlite3 "${KW_DATA_DIR}/kw.db" -batch "INSERT INTO \"${DATABASE_PATCH_TABLE}\" (title) VALUES (\"${TEST_PATCH_TITLE}\");"
  TEST_PATCH_ID="$(sqlite3 "${KW_DATA_DIR}/kw.db" -batch "SELECT id FROM \"${DATABASE_PATCH_TABLE}\" WHERE title='${TEST_PATCH_TITLE}';")"
}

function tearDownDatabase()
{
  is_safe_path_to_remove "${KW_DATA_DIR}/kw.db"
  if [[ "$?" == 0 ]]; then
    rm "${KW_DATA_DIR}/kw.db"
  fi
}

function test_register_patch_track()
{
  local expected
  local output
  local ret
  local _patches_titles

  # invalid values
  _patches_titles=('')
  output=$(register_patch_track _patches_titles)
  ret="$?"
  expected='Patch subject is empty'
  assert_equals_helper 'Empty group should not be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected an error' "$LINENO" "$ret" 61

  _patches_titles=("invalid_name'")
  output=$(register_patch_track _patches_titles 2> /dev/null)
  ret="$?"
  expected=$'Error while trying to insert patch into the database with the command:\n'
  expected+='sqlite3 -init /home/joao-souza/Mac0499---TCC/database/pre_cmd.sql "/tmp/shunit.tH1Kq2/tmp/kw.db"'
  expected+="-batch INSERT INTO patch (\"title\") VALUES ('invalid_name'');'"
  assertContains "$output" "$expected"
  assert_equals_helper 'Expected an error' "$LINENO" "$ret" 22

  # valid values
  _patches_titles=('valid_name')
  output=$(register_patch_track _patches_titles)
  ret="$?"
  assert_equals_helper 'Expected no error' "$LINENO" "$ret" 0
}

function test_show_patches_dashboard()
{
  local expected
  local output
  local ret
  local patch_info
  local IFS

  # valid values
  patch_info="$(sqlite3 "${KW_DATA_DIR}/kw.db" -batch "SELECT * FROM \"${DATABASE_PATCH_TABLE}\" WHERE title = (\"${TEST_PATCH_TITLE}\");")"
  IFS='|' read -r id date time status title <<< "$patch_info"

  output=$(show_patches_dashboard '' 150)
  ret="$?"

  expected+=$'ID    |Date        |Time      |Status    |Title\n'
  expected+=$'------------------------------------------------------------------------------------------------------------------------------------------------------\n'
  expected+="${id}     |${date}  |${time}  |${status}      |${title}"
  expected+=$'\n'
  expected+=$'------------------------------------------------------------------------------------------------------------------------------------------------------'
  assert_equals_helper 'Empty group should not be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error' "$LINENO" "$ret" 0
}

function test_set_patch_status()
{
  local expected
  local output
  local ret

  # valid values
  set_patch_status "$TEST_PATCH_ID" 'MERGED'
  ret="$?"
  expected='MERGED'
  output=$(sqlite3 "${KW_DATA_DIR}/kw.db" -batch "SELECT status FROM \"${DATABASE_PATCH_TABLE}\" WHERE ID=\"${TEST_PATCH_ID}\";")
  assert_equals_helper 'Empty group should not be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error' "$LINENO" "$ret" 0

  set_patch_status "$TEST_PATCH_ID" 'SENT'
  ret="$?"
  expected='SENT'
  output=$(sqlite3 "${KW_DATA_DIR}/kw.db" -batch "SELECT status FROM \"${DATABASE_PATCH_TABLE}\" WHERE ID=\"${TEST_PATCH_ID}\";")
  assert_equals_helper 'Empty group should not be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error' "$LINENO" "$ret" 0

  printf 'REVIEWED\n' | set_patch_status "$TEST_PATCH_ID" 'INVALID'
  ret="$?"
  expected='REVIEWED'
  output=$(sqlite3 "${KW_DATA_DIR}/kw.db" -batch "SELECT status FROM \"${DATABASE_PATCH_TABLE}\" WHERE ID=\"${TEST_PATCH_ID}\";")
  assert_equals_helper 'Empty group should not be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error' "$LINENO" "$ret" 0

  # invalid values
  output=$(set_patch_status '' 'SENT')
  ret="$?"
  expected='Patch ID is empty'
  assert_equals_helper 'Empty group should not be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error' "$LINENO" "$ret" 61

  output=$(set_patch_status "$TEST_PATCH_ID" '')
  ret="$?"
  expected='New status is empty'
  assert_equals_helper 'Empty group should not be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error' "$LINENO" "$ret" 61
}

function test_get_patch_status()
{
  local expected
  local output
  local ret

  output=$(printf 's\n' | get_patch_status)
  ret="$?"
  expected='SENT'
  assert_equals_helper 'Status should have been received' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "s"' "$LINENO" "$ret" 0
}
function test_check_valid_status()
{
  local expected
  local output
  local ret

  # SENT
  output=$(check_valid_status 's')
  ret="$?"
  expected='SENT'
  assert_equals_helper 'Status "s" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "s"' "$LINENO" "$ret" 0

  output=$(check_valid_status 'sent')
  ret="$?"
  expected='SENT'
  assert_equals_helper 'Status "sent" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "sent"' "$LINENO" "$ret" 0

  output=$(check_valid_status 'SeNt')
  ret="$?"
  expected='SENT'
  assert_equals_helper 'Status "SeNt" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "SeNt"' "$LINENO" "$ret" 0

  output=$(check_valid_status 'SENT')
  ret="$?"
  expected='SENT'
  assert_equals_helper 'Status "SENT" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "SENT"' "$LINENO" "$ret" 0

  # APPROVED
  output=$(check_valid_status 'a')
  ret="$?"
  expected='APPROVED'
  assert_equals_helper 'Status "a" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "a"' "$LINENO" "$ret" 0

  output=$(check_valid_status 'approved')
  ret="$?"
  expected='APPROVED'
  assert_equals_helper 'Status "approved" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "approved"' "$LINENO" "$ret" 0

  output=$(check_valid_status 'ApPrOvEd')
  ret="$?"
  expected='APPROVED'
  assert_equals_helper 'Status "ApPrOvEd" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "ApPrOvEd"' "$LINENO" "$ret" 0

  output=$(check_valid_status 'APPROVED')
  ret="$?"
  expected='APPROVED'
  assert_equals_helper 'Status "APPROVED" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "APPROVED"' "$LINENO" "$ret" 0

  # REJECTED
  output=$(check_valid_status 'r')
  ret="$?"
  expected='REJECTED'
  assert_equals_helper 'Status "r" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "r"' "$LINENO" "$ret" 0

  output=$(check_valid_status 'rejected')
  ret="$?"
  expected='REJECTED'
  assert_equals_helper 'Status "rejected" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "rejected"' "$LINENO" "$ret" 0

  output=$(check_valid_status 'ReJeCtEd')
  ret="$?"
  expected='REJECTED'
  assert_equals_helper 'Status "ReJeCtEd" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "ReJeCtEd"' "$LINENO" "$ret" 0

  output=$(check_valid_status 'REJECTED')
  ret="$?"
  expected='REJECTED'
  assert_equals_helper 'Status "REJECTED" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "REJECTED"' "$LINENO" "$ret" 0

  # MERGED
  output=$(check_valid_status 'm')
  ret="$?"
  expected='MERGED'
  assert_equals_helper 'Status "m" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "m"' "$LINENO" "$ret" 0

  output=$(check_valid_status 'merged')
  ret="$?"
  expected='MERGED'
  assert_equals_helper 'Status "merged" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "merged"' "$LINENO" "$ret" 0

  output=$(check_valid_status 'MeRgEd')
  ret="$?"
  expected='MERGED'
  assert_equals_helper 'Status "MeRgEd" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "MeRgEd"' "$LINENO" "$ret" 0

  output=$(check_valid_status 'MERGED')
  ret="$?"
  expected='MERGED'
  assert_equals_helper 'Status "MERGED" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "MERGED"' "$LINENO" "$ret" 0

  # REVIEWED
  output=$(check_valid_status 'rw')
  ret="$?"
  expected='REVIEWED'
  assert_equals_helper 'Status "rw" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "rw"' "$LINENO" "$ret" 0

  output=$(check_valid_status 'Rw')
  ret="$?"
  expected='REVIEWED'
  assert_equals_helper 'Status "Rw" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "Rw"' "$LINENO" "$ret" 0

  output=$(check_valid_status 'REVIEWED')
  ret="$?"
  expected='REVIEWED'
  assert_equals_helper 'Status "REVIEWED" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "REVIEWED"' "$LINENO" "$ret" 0

  output=$(check_valid_status 'ReViEwEd')
  ret="$?"
  expected='REVIEWED'
  assert_equals_helper 'Status "ReViEwEd" should be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error for "ReViEwEd"' "$LINENO" "$ret" 0

  #invalid values
  check_valid_status 'InVaLID'
  ret="$?"
  assert_equals_helper 'Expected no error for "ReViEwEd"' "$LINENO" "$ret" 22

}

invoke_shunit
